import hashlib
import importlib.machinery
import json
import os
import queue
import shutil
import stat
import pwd
import grp
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
import zipfile

HELPER_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "omafile-helper")

class Helper:
    def __init__(self, env=None, overrides=None):
        full_env = dict(os.environ)
        if env:
            full_env.update(env)
        self.proc = subprocess.Popen(
            [sys.executable, os.path.join(os.path.dirname(__file__), "helper_runner.py"),
             json.dumps(overrides or {})],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1, env=full_env,
        )
        self.q = queue.Queue()
        self.stash = {}
        self.stderr_lines = []
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()
        self.err_reader = threading.Thread(target=self._read_err_loop, daemon=True)
        self.err_reader.start()

    def _read_loop(self):
        try:
            for line in self.proc.stdout:
                line = line.rstrip("\n")
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                self.q.put(obj)
        except (ValueError, OSError):
            pass

    def _read_err_loop(self):
        try:
            for line in self.proc.stderr:
                self.stderr_lines.append(line)
        except (ValueError, OSError):
            pass

    def send(self, req):
        self.proc.stdin.write(json.dumps(req, ensure_ascii=True) + "\n")
        self.proc.stdin.flush()

    def send_raw(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def collect_until(self, req_id, timeout=8):
        msgs = self.stash.pop(req_id, [])
        if msgs and msgs[-1].get("t") in ("done", "error"):
            return msgs
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise AssertionError("timeout waiting for response id=%r, got so far=%r" % (req_id, msgs))
            try:
                obj = self.q.get(timeout=remaining)
            except queue.Empty:
                raise AssertionError("timeout waiting for response id=%r, got so far=%r" % (req_id, msgs))
            if obj.get("id") == req_id:
                msgs.append(obj)
                if obj.get("t") in ("done", "error"):
                    return msgs
            else:
                self.stash.setdefault(obj.get("id"), []).append(obj)

    def call(self, req, timeout=8):
        self.send(req)
        return self.collect_until(req["id"], timeout=timeout)

    def close(self):
        try:
            self.proc.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            self.proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=5)
        self.reader.join(timeout=5)
        self.err_reader.join(timeout=5)
        for stream in (self.proc.stdout, self.proc.stderr):
            try:
                stream.close()
            except (OSError, ValueError):
                pass

class HelperTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.helper = Helper()
        self._next_id = 1

    def tearDown(self):
        self.helper.close()
        self.tmp.cleanup()

    def next_id(self):
        i = self._next_id
        self._next_id += 1
        return i

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def terminal(self, msgs):
        return msgs[-1]

def is_root():
    return os.getuid() == 0

class ListTests(HelperTestCase):
    def test_list_known_tree(self):
        os.makedirs(self.path("sub"))
        with open(self.path("a.txt"), "w") as f:
            f.write("hello")
        with open(self.path("sub", "b.txt"), "w") as f:
            f.write("world")
        req_id = self.next_id()
        msgs = self.helper.call({"id": req_id, "op": "list", "path": self.root, "hidden": False})
        entries = []
        for m in msgs:
            if m["t"] == "entries":
                entries.extend(m["c"])
        names = sorted(e[0] for e in entries)
        self.assertEqual(names, ["a.txt", "sub"])
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["total"], 2)
        by_name = {e[0]: e for e in entries}
        self.assertEqual(by_name["a.txt"][1], "f")
        self.assertEqual(by_name["a.txt"][2], 5)
        self.assertEqual(by_name["sub"][1], "d")
        self.assertEqual(by_name["sub"][2], 0)

    def test_hidden_filtering(self):
        with open(self.path(".hidden"), "w") as f:
            f.write("x")
        with open(self.path("visible"), "w") as f:
            f.write("y")
        msgs = self.helper.call({"id": self.next_id(), "op": "list", "path": self.root, "hidden": False})
        entries = [e for m in msgs if m["t"] == "entries" for e in m["c"]]
        self.assertEqual([e[0] for e in entries], ["visible"])
        msgs2 = self.helper.call({"id": self.next_id(), "op": "list", "path": self.root, "hidden": True})
        entries2 = [e for m in msgs2 if m["t"] == "entries" for e in m["c"]]
        self.assertEqual(sorted(e[0] for e in entries2), [".hidden", "visible"])

    def test_chunking(self):
        for i in range(7):
            with open(self.path("f%02d" % i), "w") as f:
                f.write("x")
        req_id = self.next_id()
        msgs = self.helper.call({"id": req_id, "op": "list", "path": self.root, "hidden": False, "chunk": 3})
        chunk_msgs = [m for m in msgs if m["t"] == "entries"]
        self.assertEqual(len(chunk_msgs), 3)
        sizes = [len(m["c"]) for m in chunk_msgs]
        self.assertEqual(sizes, [3, 3, 1])
        total_entries = sum(sizes)
        self.assertEqual(total_entries, 7)
        done = self.terminal(msgs)
        self.assertEqual(done["total"], 7)

    def test_non_utf8_filename(self):
        bad_bytes = b"bad-\xff-name.txt"
        full = os.path.join(os.fsencode(self.root), bad_bytes)
        fd = os.open(full, os.O_CREAT | os.O_WRONLY, 0o644)
        os.close(fd)
        expected_name = os.fsdecode(bad_bytes)
        req_id = self.next_id()
        msgs = self.helper.call({"id": req_id, "op": "list", "path": self.root, "hidden": False})
        entries = [e for m in msgs if m["t"] == "entries" for e in m["c"]]
        names = [e[0] for e in entries]
        self.assertIn(expected_name, names)

    def test_enoent(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "list", "path": self.path("does-not-exist"), "hidden": False})
        err = self.terminal(msgs)
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "ENOENT")

    @unittest.skipIf(is_root(), "permission checks bypassed as root")
    def test_eacces(self):
        blocked = self.path("blocked")
        os.makedirs(blocked)
        with open(os.path.join(blocked, "secret.txt"), "w") as f:
            f.write("x")
        os.chmod(blocked, 0)
        try:
            msgs = self.helper.call({"id": self.next_id(), "op": "list", "path": blocked, "hidden": False})
            err = self.terminal(msgs)
            self.assertEqual(err["t"], "error")
            self.assertEqual(err["code"], "EACCES")
        finally:
            os.chmod(blocked, 0o700)

class StatTests(HelperTestCase):
    def test_stat_file_and_symlink(self):
        target = self.path("target.txt")
        with open(target, "w") as f:
            f.write("hello world")
        link = self.path("link.txt")
        os.symlink(target, link)
        msgs = self.helper.call({"id": self.next_id(), "op": "stat", "paths": [target, link]})
        stat_msg = [m for m in msgs if m["t"] == "stat"][0]
        items = stat_msg["items"]
        self.assertEqual(items[0]["kind"], "f")
        self.assertEqual(items[0]["size"], 11)
        self.assertEqual(items[1]["kind"], "l")
        self.assertEqual(items[1]["linkTarget"], target)

class PermissionTests(HelperTestCase):
    def test_chmod_sets_and_clears_bits(self):
        target = self.path("script.sh")
        with open(target, "w") as f:
            f.write("x")
        os.chmod(target, 0o644)
        msgs = self.helper.call({"id": self.next_id(), "op": "chmod", "path": target,
                                 "set": 0o111, "clear": 0o022})
        self.assertEqual(msgs[-1]["t"], "done")
        self.assertEqual(stat.S_IMODE(os.stat(target).st_mode), 0o755 & ~0o022 | 0o644 & 0o4)

    def test_chmod_recursive_keeps_other_bits(self):
        folder = self.path("tree")
        os.makedirs(os.path.join(folder, "sub"))
        inner = os.path.join(folder, "sub", "a.txt")
        with open(inner, "w") as f:
            f.write("x")
        os.chmod(inner, 0o640)
        self.helper.call({"id": self.next_id(), "op": "chmod", "path": folder,
                          "set": 0o004, "clear": 0, "recursive": True})
        self.assertEqual(stat.S_IMODE(os.stat(inner).st_mode), 0o644)

    def test_chmod_rejects_missing_masks(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "chmod", "path": self.path("x")})
        self.assertEqual(msgs[-1]["code"], "EINVAL")

    def test_chown_to_self_succeeds(self):
        target = self.path("mine.txt")
        with open(target, "w") as f:
            f.write("x")
        user = pwd.getpwuid(os.geteuid()).pw_name
        msgs = self.helper.call({"id": self.next_id(), "op": "chown", "path": target, "owner": user})
        self.assertEqual(msgs[-1]["t"], "done")

    def test_chown_unknown_user_fails(self):
        target = self.path("mine.txt")
        with open(target, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "chown", "path": target,
                                 "owner": "no-such-user-here"})
        self.assertEqual(msgs[-1]["code"], "EINVAL")

    def test_opener_reports_mime(self):
        target = self.path("notes.txt")
        with open(target, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "opener", "path": target})
        opener = [m for m in msgs if m["t"] == "opener"][0]
        self.assertEqual(opener["mime"], "text/plain")

    def test_setopener_rejects_bad_input(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "setopener",
                                 "mime": "text/plain", "handler": "../evil"})
        self.assertEqual(msgs[-1]["code"], "EINVAL")
        msgs = self.helper.call({"id": self.next_id(), "op": "setopener",
                                 "mime": "inode/directory", "handler": "other.desktop"})
        self.assertEqual(msgs[-1]["code"], "EINVAL", "the folder handler is never changed here")
        msgs = self.helper.call({"id": self.next_id(), "op": "setopener",
                                 "mime": "-x/y", "handler": "app.desktop"})
        self.assertEqual(msgs[-1]["code"], "EINVAL")

    @unittest.skipUnless(os.path.isfile("/usr/bin/gio"), "gio is not installed")
    def test_opener_uses_the_type_gio_open_uses(self):
        target = self.path("readme.md")
        with open(target, "w") as f:
            f.write("# title\n")
        msgs = self.helper.call({"id": self.next_id(), "op": "opener", "path": target})
        opener = [m for m in msgs if m["t"] == "opener"][0]
        self.assertEqual(opener["mime"], "text/markdown")

    @unittest.skipUnless(os.path.isfile("/usr/bin/gio"), "gio is not installed")
    def test_setopener_saves_the_default_where_gio_reads_it(self):
        config = self.path("config")
        apps = self.path("data", "applications")
        os.makedirs(config)
        os.makedirs(apps)
        with open(os.path.join(apps, "omafile-test-viewer.desktop"), "w") as f:
            f.write("[Desktop Entry]\nType=Application\nName=Viewer\nExec=true %f\nMimeType=text/markdown;\n")
        self.helper.close()
        self.helper = Helper(env={"XDG_CONFIG_HOME": config, "XDG_DATA_HOME": self.path("data")})
        msgs = self.helper.call({"id": self.next_id(), "op": "setopener",
                                 "mime": "text/markdown", "handler": "omafile-test-viewer.desktop"})
        self.assertEqual(msgs[-1]["t"], "done", msgs[-1])
        with open(os.path.join(config, "mimeapps.list")) as f:
            self.assertIn("text/markdown=omafile-test-viewer.desktop", f.read())
        target = self.path("readme.md")
        with open(target, "w") as f:
            f.write("# title\n")
        msgs = self.helper.call({"id": self.next_id(), "op": "opener", "path": target})
        self.assertEqual([m for m in msgs if m["t"] == "opener"][0]["handler"], "omafile-test-viewer.desktop")

    def test_recursive_chmod_never_follows_a_symlink(self):
        outside = self.path("outside.txt")
        with open(outside, "w") as f:
            f.write("x")
        os.chmod(outside, 0o600)
        os.makedirs(self.path("tree"))
        with open(self.path("tree", "inner.txt"), "w") as f:
            f.write("x")
        os.chmod(self.path("tree", "inner.txt"), 0o600)
        os.symlink(outside, self.path("tree", "link"))
        msgs = self.helper.call({"id": self.next_id(), "op": "chmod", "path": self.path("tree"),
                                 "set": 0o044, "clear": 0, "recursive": True})
        self.assertEqual(msgs[-1]["t"], "done")
        self.assertEqual(stat.S_IMODE(os.stat(self.path("tree", "inner.txt")).st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(os.stat(outside).st_mode), 0o600)

    def test_stat_reports_disk_usage(self):
        target = self.path("disk.txt")
        with open(target, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "stat", "paths": [target]})
        item = [m for m in msgs if m["t"] == "stat"][0]["items"][0]
        self.assertGreaterEqual(item["disk"], 1)

    def test_identity_lists_groups(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "identity"})
        ident = [m for m in msgs if m["t"] == "identity"][0]
        self.assertEqual(ident["uid"], os.geteuid())
        self.assertIn(grp.getgrgid(os.getegid()).gr_name, ident["groups"])

class PeekTests(HelperTestCase):
    def peek(self, path, limit=None):
        req = {"id": self.next_id(), "op": "peek", "path": path}
        if limit:
            req["limit"] = limit
        return self.helper.call(req)

    def test_peek_text(self):
        target = self.path("config.yml")
        with open(target, "w") as f:
            f.write("name: omafile\nlist:\n  - one\n")
        msgs = self.peek(target)
        peek = [m for m in msgs if m["t"] == "peek"][0]
        self.assertFalse(peek["binary"])
        self.assertFalse(peek["truncated"])
        self.assertEqual(peek["text"], "name: omafile\nlist:\n  - one\n")

    def test_peek_truncates(self):
        target = self.path("long.txt")
        with open(target, "w") as f:
            f.write("x" * 100)
        peek = [m for m in self.peek(target, 10) if m["t"] == "peek"][0]
        self.assertTrue(peek["truncated"])
        self.assertEqual(peek["text"], "x" * 10)

    def test_peek_binary(self):
        target = self.path("blob.bin")
        with open(target, "wb") as f:
            f.write(b"\x7fELF\x00\x01\x02")
        peek = [m for m in self.peek(target) if m["t"] == "peek"][0]
        self.assertTrue(peek["binary"])
        self.assertEqual(peek["text"], "")

    def test_peek_directory_errors(self):
        msgs = self.peek(self.root)
        self.assertEqual([m for m in msgs if m["t"] == "error"][0]["code"], "EISDIR")

FAKE_THUMBNAILER = """#!/usr/bin/env python3
import struct, sys, zlib
with open(sys.argv[3], "a") as log:
    log.write(sys.argv[1] + "\\n")
if sys.argv[4] == "fail":
    sys.exit(1)
if sys.argv[4] == "slow":
    import time
    time.sleep(30)
def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
data = b"\\x89PNG\\r\\n\\x1a\\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
data += chunk(b"IDAT", zlib.compress(b"\\x00\\x00\\x00\\x00\\x00")) + chunk(b"IEND", b"")
with open(sys.argv[2], "wb") as out:
    out.write(data)
"""

def png_meta(path):
    with open(path, "rb") as f:
        data = f.read()[8:]
    meta = {}
    while data:
        length = int.from_bytes(data[:4], "big")
        kind = data[4:8]
        body = data[8:8 + length]
        if kind == b"tEXt":
            key, value = body.split(b"\0", 1)
            meta[key.decode("latin-1")] = value.decode("latin-1")
        data = data[12 + length:]
        if kind == b"IEND":
            break
    return meta

FAKE_WL_PASTE = """#!/usr/bin/env python3
import os, sys
root = os.environ["FAKE_CLIP_DIR"]
args = sys.argv[1:]
if "--list-types" in args:
    sys.stdout.write("\\n".join(sorted(n.replace("%", "/") for n in os.listdir(root))) + "\\n")
    sys.exit(0)
mime = args[args.index("--type") + 1]
path = os.path.join(root, mime.replace("/", "%"))
if not os.path.exists(path):
    sys.exit(1)
sys.stdout.buffer.write(open(path, "rb").read())
"""

class ClipboardImageTests(HelperTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "files")
        os.makedirs(self.root)
        self.clip = os.path.join(self.tmp.name, "clip")
        os.makedirs(self.clip)
        bindir = os.path.join(self.tmp.name, "bin")
        os.makedirs(bindir)
        tool = os.path.join(bindir, "wl-paste")
        with open(tool, "w") as f:
            f.write(FAKE_WL_PASTE.replace('os.environ["FAKE_CLIP_DIR"]', repr(self.clip)))
        os.chmod(tool, 0o755)
        self.helper = Helper(overrides={"programs": {"wl-paste": tool}})
        self._next_id = 1

    def offer(self, mime, data):
        with open(os.path.join(self.clip, mime.replace("/", "%")), "wb") as f:
            f.write(data)

    def read(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "clipget"})
        self.assertEqual(msgs[-1]["t"], "done", msgs)
        return [m for m in msgs if m["t"] == "done"][0]

    def test_gnome_cut_list(self):
        self.offer("x-special/gnome-copied-files", b"cut\nfile:///tmp/a%20b.txt\nfile:///tmp/c")
        self.offer("text/uri-list", b"file:///tmp/ignored\r\n")
        clip = self.read()
        self.assertEqual(clip["mode"], "cut")
        self.assertEqual(clip["paths"], ["/tmp/a b.txt", "/tmp/c"])

    def test_plain_uri_list_is_a_copy(self):
        self.offer("text/uri-list", b"file://localhost/tmp/one\r\nfile://elsewhere/tmp/two\r\n")
        clip = self.read()
        self.assertEqual(clip["mode"], "copy")
        self.assertEqual(clip["paths"], ["/tmp/one"])

    def test_image_is_offered_and_saved_with_a_unique_name(self):
        self.offer("image/png", b"\\x89PNG fake")
        self.offer("text/plain", b"hello")
        clip = self.read()
        self.assertEqual(clip["paths"], [])
        self.assertEqual(clip["image"], "image/png")
        open(os.path.join(self.root, "Pasted image.png"), "w").close()
        msgs = self.helper.call({"id": self.next_id(), "op": "clipimage", "dest": self.root, "type": "image/png"})
        saved = [m for m in msgs if m["t"] == "clipimage"][0]["path"]
        self.assertEqual(saved, os.path.join(self.root, "Pasted image 2.png"))
        with open(saved, "rb") as f:
            self.assertEqual(f.read(), b"\\x89PNG fake")

    def test_empty_clipboard(self):
        clip = self.read()
        self.assertEqual(clip["paths"], [])
        self.assertEqual(clip["image"], "")

class ThumbnailTests(HelperTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "files")
        os.makedirs(self.root)
        self.cache = os.path.join(self.tmp.name, "cache")
        data = os.path.join(self.tmp.name, "data")
        os.makedirs(os.path.join(data, "thumbnailers"))
        self.log = os.path.join(self.tmp.name, "runs.log")
        script = os.path.join(self.tmp.name, "fake-thumbnailer")
        with open(script, "w") as f:
            f.write(FAKE_THUMBNAILER)
        os.chmod(script, 0o755)
        for name, mime, mode in (("ok", "video/mp4", "ok"), ("bad", "video/x-msvideo", "fail"),
                                ("slow", "video/webm", "slow")):
            with open(os.path.join(data, "thumbnailers", name + ".thumbnailer"), "w") as f:
                f.write("[Thumbnailer Entry]\nTryExec=%s\nExec=%s %%i %%o %s %s\nMimeType=%s;\n"
                        % (script, script, self.log, mode, mime))
        self.helper = Helper(env={"XDG_CACHE_HOME": self.cache, "XDG_DATA_HOME": data,
                                  "XDG_DATA_DIRS": os.path.join(self.tmp.name, "none")},
                             overrides={"thumbnailers": os.path.join(data, "thumbnailers"),
                                        "programs": {"fake-thumbnailer": script}})
        self._next_id = 1

    def runs(self):
        try:
            with open(self.log) as f:
                return len(f.read().splitlines())
        except FileNotFoundError:
            return 0

    def thumb(self, path, size="large"):
        return self.helper.call({"id": self.next_id(), "op": "thumb", "path": path, "size": size})

    def make(self, name):
        target = self.path(name)
        with open(target, "wb") as f:
            f.write(b"not really a video")
        return target

    def uri(self, path):
        return "file://" + urllib.parse.quote(path, safe="/!$&'()*+,;=:@")

    def test_thumbtypes_lists_supported_extensions(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "thumbtypes"})
        exts = [m for m in msgs if m["t"] == "thumbtypes"][0]["exts"]
        self.assertIn("mp4", exts)
        self.assertIn("avi", exts)
        self.assertNotIn("txt", exts)

    def test_generates_once_and_caches(self):
        target = self.make("my clip #1.mp4")
        msgs = self.thumb(target)
        self.assertEqual(msgs[-1]["t"], "done", msgs)
        out = [m for m in msgs if m["t"] == "thumb"][0]["thumb"]
        uri = self.uri(target)
        self.assertEqual(out, os.path.join(self.cache, "thumbnails", "large",
                                           hashlib.md5(uri.encode()).hexdigest() + ".png"))
        meta = png_meta(out)
        self.assertEqual(meta["Thumb::URI"], uri)
        self.assertIn("%20clip%20%231.mp4", uri)
        self.assertEqual(meta["Thumb::MTime"], str(int(os.stat(target).st_mtime)))
        self.assertEqual(stat.S_IMODE(os.stat(out).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.cache, "thumbnails")).st_mode), 0o700)
        self.assertEqual([m for m in self.thumb(target) if m["t"] == "thumb"][0]["thumb"], out)
        self.assertEqual(self.runs(), 1)

    def test_reuses_larger_thumbnail_from_other_apps(self):
        target = self.make("clip.mp4")
        first = [m for m in self.thumb(target, "x-large") if m["t"] == "thumb"][0]["thumb"]
        self.assertIn("/x-large/", first)
        again = [m for m in self.thumb(target, "large") if m["t"] == "thumb"][0]["thumb"]
        self.assertEqual(again, first)
        self.assertEqual(self.runs(), 1)

    def test_changed_file_is_thumbnailed_again(self):
        target = self.make("clip.mp4")
        self.thumb(target)
        os.utime(target, (1000000000, 1000000000))
        out = [m for m in self.thumb(target) if m["t"] == "thumb"][0]["thumb"]
        self.assertEqual(png_meta(out)["Thumb::MTime"], "1000000000")
        self.assertEqual(self.runs(), 2)

    def test_failure_is_remembered(self):
        target = self.make("broken.avi")
        msgs = self.thumb(target)
        self.assertEqual(msgs[-1]["code"], "EUNSUPPORTED")
        self.assertEqual(self.thumb(target)[-1]["code"], "EUNSUPPORTED")
        self.assertEqual(self.runs(), 1)
        fail_dir = os.path.join(self.cache, "thumbnails", "fail")
        self.assertEqual(len(os.listdir(fail_dir)), 1)

    def test_unknown_type_is_unsupported(self):
        target = self.make("notes.xyz123")
        self.assertEqual(self.thumb(target)[-1]["code"], "EUNSUPPORTED")
        self.assertEqual(self.runs(), 0)

    def test_cancel_stops_the_thumbnailer(self):
        target = self.make("long.webm")
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "thumb", "path": target, "size": "large"})
        deadline = time.time() + 5
        while self.runs() == 0 and time.time() < deadline:
            time.sleep(0.05)
        self.helper.send({"id": self.next_id(), "op": "cancel", "target": req_id})
        start = time.time()
        msgs = self.helper.collect_until(req_id, timeout=5)
        self.assertEqual(msgs[-1]["code"], "ECANCELED")
        self.assertLess(time.time() - start, 3)
        self.assertFalse(os.path.exists(os.path.join(self.cache, "thumbnails", "fail")))

    def test_relative_path_is_rejected(self):
        self.assertEqual(self.thumb("clip.mp4")[-1]["code"], "EINVAL")

class PollWatchTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        self.helper.close()
        self.helper = Helper(overrides={"force_poll": True})

    def test_poll_watch_names_what_changed(self):
        keep = self.path("keep.txt")
        grow = self.path("grow.bin")
        for p in (keep, grow):
            with open(p, "w") as f:
                f.write("x")
        req = self.next_id()
        self.helper.send({"id": req, "op": "watch", "path": self.root})
        time.sleep(2.3)
        with open(grow, "a") as f:
            f.write("more data")
        with open(self.path("new.txt"), "w") as f:
            f.write("n")
        deadline = time.time() + 6
        changed = None
        while time.time() < deadline and changed is None:
            try:
                obj = self.helper.q.get(timeout=0.5)
            except queue.Empty:
                continue
            if obj.get("id") == req and obj.get("t") == "changed":
                changed = obj
        self.assertIsNotNone(changed, "poll watch reported a change")
        self.assertEqual(changed["names"], ["grow.bin", "new.txt"])
        self.helper.send({"id": self.next_id(), "op": "unwatch", "path": self.root})

class BookmarkTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        self.helper.close()
        self.config = tempfile.mkdtemp()
        self.helper = Helper(env={"XDG_CONFIG_HOME": self.config})
        self.file = os.path.join(self.config, "gtk-3.0", "bookmarks")

    def tearDown(self):
        super().tearDown()
        shutil.rmtree(self.config, ignore_errors=True)

    def read(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "bookmarks"})
        return [m for m in msgs if m["t"] == "bookmarks"][0]

    def test_reads_gtk_bookmarks_and_keeps_other_lines(self):
        os.makedirs(os.path.dirname(self.file))
        with open(self.file, "w") as f:
            f.write("file:///home/me/Projects Projects\nsftp://laptop/home/me Laptop\nfile:///tmp/my%20docs\n")
        items = self.read()["items"]
        self.assertEqual(items, [{"path": "/home/me/Projects", "label": "Projects"},
                                 {"path": "/tmp/my docs", "label": ""}])
        msgs = self.helper.call({"id": self.next_id(), "op": "setbookmarks", "items": [
            {"path": "/tmp/my docs", "label": "Docs"}, {"path": "/srv/a b#c", "label": ""}]})
        self.assertEqual(msgs[-1]["t"], "done", msgs)
        with open(self.file) as f:
            self.assertEqual(f.read(), "file:///tmp/my%20docs Docs\nfile:///srv/a%20b%23c\nsftp://laptop/home/me Laptop\n")

    def test_missing_file_is_empty_and_folder_is_created(self):
        info = self.read()
        self.assertEqual(info["items"], [])
        self.assertTrue(os.path.isdir(info["dir"]))

def load_helper_module():
    loader = importlib.machinery.SourceFileLoader("omafile_helper_module", HELPER_PATH)
    module = type(sys)("omafile_helper_module")
    module.__file__ = HELPER_PATH
    loader.exec_module(module)
    return module

class MountTargetTests(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper_module()
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "home", "menno"))
        with open(os.path.join(self.tmp, "home", "menno", "notes.txt"), "w") as f:
            f.write("x")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def fake_gio(self, local):
        class Result:
            returncode = 0
            stdout = "type: directory\nuri: sftp://laptop/x\nlocal path: %s\nattributes:\n" % local
            stderr = ""
        self.helper.run_trusted = lambda name, args, **kw: Result()

    def test_opens_the_folder_in_the_address(self):
        self.fake_gio(os.path.join(self.tmp, "home", "menno"))
        self.assertEqual(self.helper.gio_local_folder("ssh://laptop/home/menno"), os.path.join(self.tmp, "home", "menno"))

    def test_an_address_to_a_file_opens_its_folder(self):
        self.fake_gio(os.path.join(self.tmp, "home", "menno", "notes.txt"))
        self.assertEqual(self.helper.gio_local_folder("ssh://laptop/home/menno/notes.txt"), os.path.join(self.tmp, "home", "menno"))

    def test_unknown_paths_fall_back(self):
        self.fake_gio(os.path.join(self.tmp, "missing"))
        self.assertEqual(self.helper.gio_local_folder("ssh://laptop/missing"), "")

class CountTests(HelperTestCase):
    def test_counts_folder_items(self):
        full = self.path("full")
        os.makedirs(full)
        for name in ("a", "b", ".hidden"):
            open(os.path.join(full, name), "w").close()
        empty = self.path("empty")
        os.makedirs(empty)
        missing = self.path("missing")
        msgs = self.helper.call({"id": self.next_id(), "op": "counts", "paths": [full, empty, missing]})
        counts = [m for m in msgs if m["t"] == "counts"][0]["counts"]
        self.assertEqual(counts, {full: 2, empty: 0, missing: -1})
        msgs = self.helper.call({"id": self.next_id(), "op": "counts", "paths": [full], "hidden": True})
        self.assertEqual([m for m in msgs if m["t"] == "counts"][0]["counts"][full], 3)

class SymlinkTests(HelperTestCase):
    def test_symlink_kinds(self):
        target_dir = self.path("realdir")
        os.makedirs(target_dir)
        target_file = self.path("realfile")
        with open(target_file, "w") as f:
            f.write("x")
        dir_link = self.path("dirlink")
        file_link = self.path("filelink")
        broken_link = self.path("brokenlink")
        os.symlink(target_dir, dir_link)
        os.symlink(target_file, file_link)
        os.symlink(self.path("nowhere"), broken_link)
        msgs = self.helper.call({"id": self.next_id(), "op": "list", "path": self.root, "hidden": False})
        entries = {e[0]: e for m in msgs if m["t"] == "entries" for e in m["c"]}
        self.assertEqual(entries["dirlink"][1], "L")
        self.assertEqual(entries["filelink"][1], "l")
        self.assertEqual(entries["brokenlink"][1], "b")

class DuTests(HelperTestCase):
    def test_du_totals(self):
        os.makedirs(self.path("a", "b"))
        with open(self.path("f1"), "wb") as f:
            f.write(b"x" * 100)
        with open(self.path("a", "f2"), "wb") as f:
            f.write(b"y" * 250)
        with open(self.path("a", "b", "f3"), "wb") as f:
            f.write(b"z" * 50)
        msgs = self.helper.call({"id": self.next_id(), "op": "du", "path": self.root})
        du_msgs = [m for m in msgs if m["t"] == "du"]
        self.assertTrue(du_msgs)
        final = du_msgs[-1]
        self.assertFalse(final["partial"])
        self.assertEqual(final["bytes"], 400)
        self.assertEqual(final["files"], 3)
        self.assertEqual(final["dirs"], 2)
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")

class FreespaceTests(HelperTestCase):
    def test_freespace(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "freespace", "path": self.root})
        space = [m for m in msgs if m["t"] == "space"][0]
        self.assertGreaterEqual(space["total"], space["free"])
        self.assertGreaterEqual(space["free"], 0)
        self.assertIsInstance(space["mount"], str)

class MkdirMkfileRenameTests(HelperTestCase):
    def test_mkdir(self):
        newdir = self.path("newdir")
        msgs = self.helper.call({"id": self.next_id(), "op": "mkdir", "path": newdir})
        self.assertEqual(self.terminal(msgs)["t"], "done")
        self.assertTrue(os.path.isdir(newdir))

    def test_mkfile(self):
        newfile = self.path("newfile.txt")
        msgs = self.helper.call({"id": self.next_id(), "op": "mkfile", "path": newfile})
        self.assertEqual(self.terminal(msgs)["t"], "done")
        self.assertTrue(os.path.isfile(newfile))

    def test_mkfile_exists_errors(self):
        newfile = self.path("dup.txt")
        with open(newfile, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "mkfile", "path": newfile})
        err = self.terminal(msgs)
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "EEXIST")

    def test_rename(self):
        old = self.path("old.txt")
        with open(old, "w") as f:
            f.write("content")
        msgs = self.helper.call({"id": self.next_id(), "op": "rename", "path": old, "newName": "new.txt"})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        self.assertTrue(os.path.isfile(self.path("new.txt")))
        self.assertFalse(os.path.exists(old))

    def test_rename_rejects_separator(self):
        old = self.path("old2.txt")
        with open(old, "w") as f:
            f.write("content")
        msgs = self.helper.call({"id": self.next_id(), "op": "rename", "path": old, "newName": "a/b"})
        err = self.terminal(msgs)
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "EINVAL")
        self.assertTrue(os.path.isfile(old))

class DeleteTests(HelperTestCase):
    def test_delete_file_and_dir(self):
        f1 = self.path("f1.txt")
        with open(f1, "w") as f:
            f.write("x")
        d1 = self.path("d1")
        os.makedirs(d1)
        with open(os.path.join(d1, "inner.txt"), "w") as f:
            f.write("y")
        msgs = self.helper.call({"id": self.next_id(), "op": "delete", "paths": [f1, d1]})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        for r in done["results"]:
            self.assertTrue(r["ok"])
        self.assertFalse(os.path.exists(f1))
        self.assertFalse(os.path.exists(d1))

class CopyTests(HelperTestCase):
    def test_copy_with_progress(self):
        src = self.path("src.bin")
        with open(src, "wb") as f:
            f.write(os.urandom(4096))
        dest_dir = self.path("dest")
        os.makedirs(dest_dir)
        req_id = self.next_id()
        msgs = self.helper.call({"id": req_id, "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "overwrite"})
        progress_msgs = [m for m in msgs if m["t"] == "progress"]
        self.assertTrue(progress_msgs)
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["copied"], 1)
        self.assertEqual(done["skipped"], 0)
        self.assertEqual(done["errors"], [])
        with open(src, "rb") as f:
            src_data = f.read()
        with open(os.path.join(dest_dir, "src.bin"), "rb") as f:
            dst_data = f.read()
        self.assertEqual(src_data, dst_data)

    def _make_conflict(self):
        src = self.path("file.txt")
        with open(src, "w") as f:
            f.write("new content")
        dest_dir = self.path("dest")
        os.makedirs(dest_dir)
        existing = os.path.join(dest_dir, "file.txt")
        with open(existing, "w") as f:
            f.write("old content")
        return src, dest_dir, existing

    def test_copy_conflict_overwrite(self):
        src, dest_dir, existing = self._make_conflict()
        msgs = self.helper.call({"id": self.next_id(), "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "overwrite"})
        done = self.terminal(msgs)
        self.assertEqual(done["copied"], 1)
        with open(existing) as f:
            self.assertEqual(f.read(), "new content")

    def test_copy_conflict_skip(self):
        src, dest_dir, existing = self._make_conflict()
        msgs = self.helper.call({"id": self.next_id(), "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "skip"})
        done = self.terminal(msgs)
        self.assertEqual(done["copied"], 0)
        self.assertEqual(done["skipped"], 1)
        with open(existing) as f:
            self.assertEqual(f.read(), "old content")

    def test_copy_conflict_rename(self):
        src, dest_dir, existing = self._make_conflict()
        msgs = self.helper.call({"id": self.next_id(), "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "rename"})
        done = self.terminal(msgs)
        self.assertEqual(done["copied"], 1)
        renamed = os.path.join(dest_dir, "file (1).txt")
        self.assertTrue(os.path.isfile(renamed))
        with open(renamed) as f:
            self.assertEqual(f.read(), "new content")
        with open(existing) as f:
            self.assertEqual(f.read(), "old content")

    def test_copy_onto_itself_makes_a_copy_even_when_overwriting(self):
        folder = self.path("same")
        os.makedirs(folder)
        src = os.path.join(folder, "file.txt")
        with open(src, "w") as f:
            f.write("keep me")
        msgs = self.helper.call({"id": self.next_id(), "op": "copy", "sources": [src], "dest": folder, "conflict": "overwrite"})
        self.assertEqual(self.terminal(msgs)["copied"], 1)
        with open(src) as f:
            self.assertEqual(f.read(), "keep me")
        self.assertTrue(os.path.isfile(os.path.join(folder, "file (1).txt")))

    def test_move_onto_itself_is_skipped(self):
        folder = self.path("stay")
        os.makedirs(folder)
        src = os.path.join(folder, "file.txt")
        with open(src, "w") as f:
            f.write("keep me")
        msgs = self.helper.call({"id": self.next_id(), "op": "move", "sources": [src], "dest": folder, "conflict": "overwrite"})
        self.assertEqual(self.terminal(msgs)["t"], "done")
        with open(src) as f:
            self.assertEqual(f.read(), "keep me")
        self.assertEqual(os.listdir(folder), ["file.txt"])

    def test_copy_conflict_ask_resolve_overwrite(self):
        src, dest_dir, existing = self._make_conflict()
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "ask"})
        msgs = []
        conflict_msg = None
        deadline = time.time() + 8
        while time.time() < deadline:
            obj = self.helper.q.get(timeout=8)
            msgs.append(obj)
            if obj.get("t") == "conflict":
                conflict_msg = obj
                break
        self.assertIsNotNone(conflict_msg)
        self.assertEqual(conflict_msg["source"], src)
        self.helper.send({"id": req_id, "op": "resolve", "action": "overwrite", "applyAll": False})
        rest = self.helper.collect_until(req_id)
        done = rest[-1]
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["copied"], 1)
        with open(existing) as f:
            self.assertEqual(f.read(), "new content")

    def test_copy_conflict_ask_cancel(self):
        src, dest_dir, existing = self._make_conflict()
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "ask"})
        conflict_msg = None
        deadline = time.time() + 8
        while time.time() < deadline:
            obj = self.helper.q.get(timeout=8)
            if obj.get("t") == "conflict":
                conflict_msg = obj
                break
        self.assertIsNotNone(conflict_msg)
        self.helper.send({"id": req_id, "op": "resolve", "action": "cancel", "applyAll": False})
        rest = self.helper.collect_until(req_id)
        err = rest[-1]
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "ECANCELED")

class MoveTests(HelperTestCase):
    def _cross_device_pair(self):
        candidates = []
        for base in ("/dev/shm", os.path.expanduser("~"), "/var/tmp", "/tmp", tempfile.gettempdir()):
            if os.path.isdir(base) and os.access(base, os.W_OK):
                candidates.append(base)
        devs = {}
        for c in candidates:
            try:
                d = os.stat(c).st_dev
            except OSError:
                continue
            devs.setdefault(d, c)
        if len(devs) < 2:
            return None
        vals = list(devs.values())
        return vals[0], vals[1]

    def test_cross_device_move_fallback(self):
        pair = self._cross_device_pair()
        if pair is None:
            self.skipTest("no two distinct filesystems available for a cross-device move test")
        base_a, base_b = pair
        src_root = tempfile.mkdtemp(dir=base_a)
        dest_root = tempfile.mkdtemp(dir=base_b)
        try:
            src_file = os.path.join(src_root, "moveme.txt")
            with open(src_file, "w") as f:
                f.write("cross device payload")
            msgs = self.helper.call({"id": self.next_id(), "op": "move", "sources": [src_file], "dest": dest_root, "conflict": "overwrite"})
            done = self.terminal(msgs)
            self.assertEqual(done["t"], "done")
            self.assertEqual(done["copied"], 1)
            self.assertFalse(os.path.exists(src_file))
            moved = os.path.join(dest_root, "moveme.txt")
            self.assertTrue(os.path.isfile(moved))
            with open(moved) as f:
                self.assertEqual(f.read(), "cross device payload")
        finally:
            shutil.rmtree(src_root, ignore_errors=True)
            shutil.rmtree(dest_root, ignore_errors=True)

@unittest.skipUnless(os.path.isfile("/usr/bin/bsdtar"), "bsdtar is not installed")
class ExtractTests(HelperTestCase):
    def make_zip(self, name, members):
        path = self.path(name)
        with zipfile.ZipFile(path, "w") as z:
            for member, data in members.items():
                z.writestr(member, data)
        return path

    def extract(self, path):
        return self.terminal(self.helper.call({"id": self.next_id(), "op": "extract", "path": path}, timeout=20))

    def leftovers(self):
        return [n for n in os.listdir(self.root) if n.startswith(".omafile-extract-")]

    def test_single_top_level_item_lands_next_to_the_archive(self):
        archive = self.make_zip("one.zip", {"photos/a.txt": "a", "photos/b.txt": "b"})
        done = self.extract(archive)
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["path"], self.path("photos"))
        self.assertEqual(sorted(os.listdir(self.path("photos"))), ["a.txt", "b.txt"])
        self.assertEqual(self.leftovers(), [])

    def test_several_items_go_into_a_folder_named_after_the_archive(self):
        archive = self.make_zip("Holiday.ZIP", {"a.txt": "a", "b.txt": "b"})
        done = self.extract(archive)
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["path"], self.path("Holiday"))
        self.assertEqual(sorted(os.listdir(self.path("Holiday"))), ["a.txt", "b.txt"])

    def test_existing_names_are_kept(self):
        archive = self.make_zip("notes.zip", {"notes.txt": "new"})
        with open(self.path("notes.txt"), "w") as f:
            f.write("old")
        done = self.extract(archive)
        self.assertEqual(done["path"], self.path("notes (1).txt"))
        with open(self.path("notes.txt")) as f:
            self.assertEqual(f.read(), "old")
        with open(self.path("notes (1).txt")) as f:
            self.assertEqual(f.read(), "new")

    def test_a_broken_archive_errors_and_cleans_up(self):
        with open(self.path("broken.zip"), "w") as f:
            f.write("not an archive")
        err = self.extract(self.path("broken.zip"))
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "EFAIL")
        self.assertEqual(self.leftovers(), [])

    def test_entries_cannot_escape_the_folder(self):
        os.makedirs(self.path("inside"))
        archive = os.path.join(self.path("inside"), "evil.zip")
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("../escaped.txt", "x")
            z.writestr("/tmp/omafile-absolute-test.txt", "x")
        self.extract(archive)
        self.assertFalse(os.path.exists(self.path("escaped.txt")))
        self.assertFalse(os.path.exists("/tmp/omafile-absolute-test.txt"))

    def test_a_folder_is_rejected(self):
        os.makedirs(self.path("folder.zip"))
        err = self.extract(self.path("folder.zip"))
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "EINVAL")

FAKE_BSDTAR = """#!/usr/bin/env python3
import os, sys, time
archive, work = sys.argv[2], sys.argv[4]
with open(archive, "rb", buffering=0) as f:
    f.read(os.path.getsize(archive) // 2)
    sys.stderr.write("x first.txt\\n")
    sys.stderr.flush()
    time.sleep(30 if "slow" in archive else 0.8)
    f.read()
open(os.path.join(work, "first.txt"), "w").close()
sys.stderr.write("x second.txt\\n")
"""


class ExtractProgressTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        script = self.path("fake-bsdtar")
        with open(script, "w") as f:
            f.write(FAKE_BSDTAR)
        os.chmod(script, 0o755)
        self.helper.close()
        self.helper = Helper(overrides={"programs": {"bsdtar": script}})

    def archive(self, name):
        target = self.path(name)
        with open(target, "wb") as f:
            f.write(b"x" * 4096)
        return target

    def test_extraction_reports_how_far_it_has_read(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "extract", "path": self.archive("pack.zip")}, timeout=10)
        progress = [m for m in msgs if m["t"] == "progress"]
        self.assertTrue(progress, "progress is reported while extracting")
        halfway = [m for m in progress if m["bytes"] == 2048]
        self.assertTrue(halfway, "bytes read so far in the archive")
        self.assertEqual(halfway[-1]["total"], 4096)
        self.assertEqual(halfway[-1]["files"], 1)
        self.assertEqual(halfway[-1]["current"], "first.txt")
        self.assertTrue(all(m["bytes"] <= 4096 for m in progress))
        self.assertEqual(msgs[-1]["t"], "done")
        self.assertEqual(msgs[-1]["path"], self.path("first.txt"))

    def test_cancel_stops_the_extraction_and_leaves_nothing(self):
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "extract", "path": self.archive("slow.zip")})
        deadline = time.time() + 5
        while time.time() < deadline:
            obj = self.helper.q.get(timeout=5)
            if obj.get("t") == "progress":
                break
        self.helper.send({"id": self.next_id(), "op": "cancel", "target": req_id})
        start = time.time()
        msgs = self.helper.collect_until(req_id, timeout=5)
        self.assertEqual(msgs[-1]["code"], "ECANCELED")
        self.assertLess(time.time() - start, 3)
        self.assertEqual([n for n in os.listdir(self.root) if n.startswith(".omafile-extract-")], [])
        self.assertFalse(os.path.exists(self.path("first.txt")))


@unittest.skipUnless(os.path.isfile("/usr/bin/bsdtar"), "bsdtar is not installed")
class CompressTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        os.makedirs(self.path("photos", "trip"))
        with open(self.path("photos", "trip", "a.txt"), "w") as f:
            f.write("a" * 100)
        with open(self.path("notes.txt"), "w") as f:
            f.write("n" * 50)
        with open(self.path("-rf"), "w") as f:
            f.write("dash")

    def compress(self, paths, name):
        return self.helper.call({"id": self.next_id(), "op": "compress", "paths": paths, "name": name}, timeout=20)

    def listing(self, archive):
        out = subprocess.run(["/usr/bin/bsdtar", "-tf", archive], capture_output=True, text=True, check=True)
        return sorted(line.rstrip("/") for line in out.stdout.splitlines())

    def test_items_go_into_an_archive_next_to_them(self):
        for name in ["Archive.zip", "Archive.tar.xz", "Archive.tar.gz", "Archive.7z"]:
            msgs = self.compress([self.path("photos"), self.path("notes.txt"), self.path("-rf")], name)
            self.assertEqual(msgs[-1]["t"], "done", msgs[-1])
            self.assertEqual(msgs[-1]["path"], self.path(name))
            self.assertEqual(self.listing(self.path(name)),
                             ["-rf", "notes.txt", "photos", "photos/trip", "photos/trip/a.txt"])
        self.assertEqual([n for n in os.listdir(self.root) if n.startswith(".omafile-compress-")], [])

    def test_progress_counts_the_bytes_written(self):
        msgs = self.compress([self.path("photos"), self.path("notes.txt")], "Archive.zip")
        progress = [m for m in msgs if m["t"] == "progress"]
        for m in progress:
            self.assertEqual(m["total"], 150)
            self.assertLessEqual(m["bytes"], 150)

    def test_existing_archives_are_never_replaced(self):
        with open(self.path("Archive.tar.xz"), "w") as f:
            f.write("old")
        msgs = self.compress([self.path("notes.txt")], "Archive.tar.xz")
        self.assertEqual(msgs[-1]["path"], self.path("Archive (1).tar.xz"))
        with open(self.path("Archive.tar.xz")) as f:
            self.assertEqual(f.read(), "old")

    def test_round_trip_through_extract(self):
        self.compress([self.path("photos")], "photos.zip")
        shutil.rmtree(self.path("photos"))
        msgs = self.helper.call({"id": self.next_id(), "op": "extract", "path": self.path("photos.zip")}, timeout=20)
        self.assertEqual(msgs[-1]["path"], self.path("photos"))
        with open(self.path("photos", "trip", "a.txt")) as f:
            self.assertEqual(f.read(), "a" * 100)

    def test_bad_requests_are_rejected(self):
        os.makedirs(self.path("other"))
        with open(self.path("other", "x.txt"), "w") as f:
            f.write("x")
        cases = [
            ([self.path("notes.txt"), self.path("other", "x.txt")], "Archive.zip"),
            ([self.path("notes.txt")], "Archive.rar"),
            ([self.path("notes.txt")], "../Archive.zip"),
            ([self.path("notes.txt")], ".zip"),
            (["notes.txt"], "Archive.zip"),
            ([], "Archive.zip"),
        ]
        for paths, name in cases:
            self.assertEqual(self.compress(paths, name)[-1]["code"], "EINVAL", (paths, name))
        self.assertEqual(self.compress([self.path("missing")], "Archive.zip")[-1]["code"], "ENOENT")


FAKE_SLOW_BSDTAR = """#!/usr/bin/env python3
import sys, time
sys.stdin.buffer.read()
sys.stderr.write("a big.bin\\n")
sys.stderr.flush()
time.sleep(30)
"""


class CompressCancelTests(HelperTestCase):
    def test_cancel_stops_compressing_and_leaves_nothing(self):
        script = self.path("fake-bsdtar")
        with open(script, "w") as f:
            f.write(FAKE_SLOW_BSDTAR)
        os.chmod(script, 0o755)
        self.helper.close()
        self.helper = Helper(overrides={"programs": {"bsdtar": script}})
        with open(self.path("big.bin"), "wb") as f:
            f.write(b"x" * 1000)
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "compress", "paths": [self.path("big.bin")], "name": "big.zip"})
        deadline = time.time() + 5
        progress = None
        while time.time() < deadline:
            obj = self.helper.q.get(timeout=5)
            if obj.get("t") == "progress" and obj.get("files"):
                progress = obj
                break
        self.assertEqual(progress["bytes"], 1000)
        self.helper.send({"id": self.next_id(), "op": "cancel", "target": req_id})
        msgs = self.helper.collect_until(req_id, timeout=5)
        self.assertEqual(msgs[-1]["code"], "ECANCELED")
        self.assertEqual(sorted(n for n in os.listdir(self.root) if n != "fake-bsdtar"), ["big.bin"])


class TrashTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        self.helper.close()
        self.data_home = tempfile.mkdtemp()
        self.helper = Helper(env={"XDG_DATA_HOME": self.data_home})

    def tearDown(self):
        super().tearDown()
        shutil.rmtree(self.data_home, ignore_errors=True)

    def test_trash_round_trip(self):
        target = self.path("throwaway.txt")
        with open(target, "w") as f:
            f.write("goodbye")
        msgs = self.helper.call({"id": self.next_id(), "op": "trash", "paths": [target]})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        self.assertTrue(done["results"][0]["ok"])
        self.assertFalse(os.path.exists(target))
        files_dir = os.path.join(self.data_home, "Trash", "files")
        info_dir = os.path.join(self.data_home, "Trash", "info")
        trashed = os.path.join(files_dir, "throwaway.txt")
        info_file = os.path.join(info_dir, "throwaway.txt.trashinfo")
        self.assertTrue(os.path.isfile(trashed))
        self.assertTrue(os.path.isfile(info_file))
        with open(info_file) as f:
            content = f.read()
        self.assertIn("[Trash Info]", content)
        self.assertIn("Path=%s" % target, content)
        self.assertRegex(content, r"DeletionDate=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
        restore_msgs = self.helper.call({"id": self.next_id(), "op": "restore", "items": ["throwaway.txt.trashinfo"]})
        rdone = self.terminal(restore_msgs)
        self.assertEqual(rdone["t"], "done")
        self.assertTrue(rdone["results"][0]["ok"])
        self.assertTrue(os.path.isfile(target))
        with open(target) as f:
            self.assertEqual(f.read(), "goodbye")
        self.assertFalse(os.path.exists(trashed))
        self.assertFalse(os.path.exists(info_file))

    def test_deleting_a_trashed_item_removes_its_trashinfo(self):
        target = self.path("gone.txt")
        with open(target, "w") as f:
            f.write("bye")
        self.helper.call({"id": self.next_id(), "op": "trash", "paths": [target]})
        files_dir = os.path.join(self.data_home, "Trash", "files")
        info_file = os.path.join(self.data_home, "Trash", "info", "gone.txt.trashinfo")
        trashed = os.path.join(files_dir, "gone.txt")
        self.assertTrue(os.path.isfile(info_file))
        loose = os.path.join(self.root, "files")
        os.makedirs(loose)
        other = os.path.join(loose, "keep.txt")
        with open(other, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "delete", "paths": [trashed, other]})
        done = self.terminal(msgs)
        self.assertTrue(all(r["ok"] for r in done["results"]))
        self.assertFalse(os.path.exists(trashed))
        self.assertFalse(os.path.exists(info_file))
        info_msgs = self.helper.call({"id": self.next_id(), "op": "trashinfo"})
        names = [item["name"] for item in [m for m in info_msgs if m["t"] == "trash"][0]["items"]]
        self.assertNotIn("gone.txt", names)

    def test_trash_percent_encoding(self):
        weird = self.path("weird name 100% done.txt")
        with open(weird, "w") as f:
            f.write("x")
        msgs = self.helper.call({"id": self.next_id(), "op": "trash", "paths": [weird]})
        done = self.terminal(msgs)
        self.assertTrue(done["results"][0]["ok"])
        info_dir = os.path.join(self.data_home, "Trash", "info")
        info_file = os.path.join(info_dir, "weird name 100% done.txt.trashinfo")
        with open(info_file) as f:
            content = f.read()
        path_line = [l for l in content.splitlines() if l.startswith("Path=")][0]
        encoded = path_line[len("Path="):]
        self.assertIn("%20", encoded)
        self.assertIn("%25", encoded)
        self.assertNotIn(" ", encoded)
        self.assertTrue(encoded.startswith("/"))
        self.assertIn("/", encoded)

    def test_trashinfo_and_emptytrash(self):
        f1 = self.path("t1.txt")
        f2 = self.path("t2.txt")
        for p in (f1, f2):
            with open(p, "w") as f:
                f.write("data")
        self.helper.call({"id": self.next_id(), "op": "trash", "paths": [f1, f2]})
        msgs = self.helper.call({"id": self.next_id(), "op": "trashinfo"})
        info_msg = [m for m in msgs if m["t"] == "trash"][0]
        self.assertGreaterEqual(info_msg["count"], 2)
        names = set(item["name"] for item in info_msg["items"])
        self.assertIn("t1.txt", names)
        self.assertIn("t2.txt", names)
        empty_msgs = self.helper.call({"id": self.next_id(), "op": "emptytrash"})
        self.assertEqual(self.terminal(empty_msgs)["t"], "done")
        after_msgs = self.helper.call({"id": self.next_id(), "op": "trashinfo"})
        after_info = [m for m in after_msgs if m["t"] == "trash"][0]
        after_names = set(item["name"] for item in after_info["items"])
        self.assertNotIn("t1.txt", after_names)
        self.assertNotIn("t2.txt", after_names)

    def test_emptytrash_only_touches_listed_mounts(self):
        volume = tempfile.mkdtemp()
        try:
            trash = os.path.join(volume, ".Trash-%d" % os.getuid())
            os.makedirs(os.path.join(trash, "files"))
            os.makedirs(os.path.join(trash, "info"))
            victim = os.path.join(trash, "files", "old.txt")
            with open(victim, "w") as f:
                f.write("x")
            self.helper.call({"id": self.next_id(), "op": "emptytrash"})
            self.assertTrue(os.path.exists(victim), "unlisted drives are never emptied")
            mounts = os.path.join(volume, "mounts")
            with open(mounts, "w") as f:
                f.write("tmpfs %s tmpfs rw 0 0\n" % volume)
            self.helper.close()
            self.helper = Helper(env={"XDG_DATA_HOME": self.data_home}, overrides={"mounts_file": mounts})
            self.helper.call({"id": self.next_id(), "op": "emptytrash"})
            self.assertFalse(os.path.exists(victim), "listed drives are emptied")
        finally:
            shutil.rmtree(volume, ignore_errors=True)

    def symlinked_volume_trash(self, link_whole_trash):
        volume = tempfile.mkdtemp()
        outside = tempfile.mkdtemp()
        os.makedirs(os.path.join(outside, "files"))
        os.makedirs(os.path.join(outside, "info"))
        private = os.path.join(outside, "files", "private.txt")
        with open(private, "w") as f:
            f.write("keep")
        with open(os.path.join(outside, "info", "private.txt.trashinfo"), "w") as f:
            f.write("[Trash Info]\nPath=private.txt\nDeletionDate=2026-10-01T00:00:00\n")
        trash = os.path.join(volume, ".Trash-%d" % os.getuid())
        if link_whole_trash:
            os.symlink(outside, trash)
        else:
            os.makedirs(trash)
            os.symlink(os.path.join(outside, "files"), os.path.join(trash, "files"))
            os.symlink(os.path.join(outside, "info"), os.path.join(trash, "info"))
        mounts = os.path.join(volume, "mounts")
        with open(mounts, "w") as f:
            f.write("tmpfs %s tmpfs rw 0 0\n" % volume)
        self.helper.close()
        self.helper = Helper(env={"XDG_DATA_HOME": self.data_home}, overrides={"mounts_file": mounts})
        return volume, outside, private

    def check_symlinked_volume_trash_is_ignored(self, link_whole_trash):
        volume, outside, private = self.symlinked_volume_trash(link_whole_trash)
        try:
            msgs = self.helper.call({"id": self.next_id(), "op": "trashinfo"})
            info = [m for m in msgs if m["t"] == "trash"][0]
            self.assertNotIn("private.txt", [item["name"] for item in info["items"]])
            self.assertEqual(self.terminal(self.helper.call({"id": self.next_id(), "op": "emptytrash"}))["t"], "done")
            self.assertTrue(os.path.exists(private), "emptying the trash never follows a symlinked drive trash")
            msgs = self.helper.call({"id": self.next_id(), "op": "restore", "items": ["private.txt"]})
            self.assertFalse(self.terminal(msgs)["results"][0]["ok"])
            self.assertTrue(os.path.exists(private))
        finally:
            shutil.rmtree(volume, ignore_errors=True)
            shutil.rmtree(outside, ignore_errors=True)

    def test_emptytrash_ignores_a_symlinked_files_folder_on_a_drive(self):
        self.check_symlinked_volume_trash_is_ignored(False)

    def test_emptytrash_ignores_a_symlinked_trash_folder_on_a_drive(self):
        self.check_symlinked_volume_trash_is_ignored(True)

    def test_emptytrash_removes_symlinks_inside_the_trash_without_following_them(self):
        outside = tempfile.mkdtemp()
        try:
            private = os.path.join(outside, "private.txt")
            with open(private, "w") as f:
                f.write("keep")
            files_dir = os.path.join(self.data_home, "Trash", "files")
            os.makedirs(files_dir, exist_ok=True)
            link = os.path.join(files_dir, "link")
            os.symlink(outside, link)
            self.helper.call({"id": self.next_id(), "op": "emptytrash"})
            self.assertFalse(os.path.lexists(link))
            self.assertTrue(os.path.exists(private))
        finally:
            shutil.rmtree(outside, ignore_errors=True)

class TrashInfoDirsTests(HelperTestCase):
    def test_trashinfo_reports_the_directories_to_watch(self):
        req = self.next_id()
        self.helper.send({"id": req, "op": "trashinfo"})
        msgs = self.helper.collect_until(req)
        trash = [m for m in msgs if m["t"] == "trash"][0]
        self.assertIn("infoDirs", trash)
        self.assertIsInstance(trash["infoDirs"], list)
        self.assertTrue(trash["infoDirs"])
        for d in trash["infoDirs"]:
            self.assertIsInstance(d, str)
            self.assertTrue(d.endswith("info"), d)

class BarIconTests(unittest.TestCase):
    def helper_with_config(self, tmp, config):
        import importlib.util
        cfg_dir = os.path.join(tmp, "omarchy")
        os.makedirs(cfg_dir, exist_ok=True)
        with open(os.path.join(cfg_dir, "shell.json"), "w", encoding="utf-8") as f:
            json.dump(config, f)
        saved = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = tmp
        try:
            spec = importlib.util.spec_from_loader(
                "omafile_helper_bar",
                importlib.machinery.SourceFileLoader("omafile_helper_bar", HELPER_PATH))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
        finally:
            if saved is None:
                os.environ.pop("XDG_CONFIG_HOME", None)
            else:
                os.environ["XDG_CONFIG_HOME"] = saved

    def base_config(self):
        return {"version": 1, "bar": {"layout": {
            "left": [], "center": [],
            "right": [{"id": "omarchy.tray"},
                      {"id": "xyzlab.omafile", "windowMode": "window"},
                      {"id": "omarchy.clock"}]}}}

    def test_add_places_the_trash_entry_after_the_files_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            h = self.helper_with_config(tmp, self.base_config())
            config = h.read_shell_config()
            self.assertFalse(h.bar_state(config)["trashIcon"])
            entries = h.omafile_entries(config)
            arr = entries[0][1]
            arr.insert(entries[0][2] + 1,
                       {"id": "xyzlab.omafile", "mode": "trash", "trashConfirm": True})
            ids = [e.get("id") for e in config["bar"]["layout"]["right"]]
            self.assertEqual(ids, ["omarchy.tray", "xyzlab.omafile", "xyzlab.omafile", "omarchy.clock"])
            self.assertTrue(h.bar_state(config)["trashIcon"])

    def test_settings_never_touch_the_trash_entry_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = self.base_config()
            config["bar"]["layout"]["right"].insert(
                2, {"id": "xyzlab.omafile", "mode": "trash", "trashConfirm": True})
            h = self.helper_with_config(tmp, config)
            loaded = h.read_shell_config()
            for name, arr, index, entry in h.omafile_entries(loaded):
                trash = h.is_trash_entry(entry)
                merged = dict(entry)
                for key, value in {"showHidden": True, "trashConfirm": False}.items():
                    if key in ("id", "mode"):
                        continue
                    if trash and key not in h.TRASH_ENTRY_KEYS:
                        continue
                    merged[key] = value
                arr[index] = merged
            found = h.omafile_entries(loaded)
            files_entry = [e for _, _, _, e in found if not h.is_trash_entry(e)][0]
            trash_entry = [e for _, _, _, e in found if h.is_trash_entry(e)][0]
            self.assertTrue(files_entry["showHidden"])
            self.assertEqual(trash_entry["mode"], "trash")
            self.assertNotIn("showHidden", trash_entry)
            self.assertFalse(trash_entry["trashConfirm"])

    def test_write_is_atomic_and_reloadable(self):
        with tempfile.TemporaryDirectory() as tmp:
            h = self.helper_with_config(tmp, self.base_config())
            config = h.read_shell_config()
            config["bar"]["layout"]["right"].append({"id": "xyzlab.omafile", "mode": "trash"})
            h.write_shell_config(config)
            again = h.read_shell_config()
            self.assertTrue(h.bar_state(again)["trashIcon"])
            self.assertEqual(h.bar_state(again)["count"], 2)

class SearchTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        os.makedirs(self.path("sub", "deep"))
        with open(self.path("report_final.txt"), "w") as f:
            f.write("x")
        with open(self.path("sub", "report_draft.txt"), "w") as f:
            f.write("x")
        with open(self.path("sub", "deep", "notes.md"), "w") as f:
            f.write("x")
        with open(self.path("other.log"), "w") as f:
            f.write("x")

    def test_search_substring(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "search", "root": self.root, "query": "report", "mode": "substring"})
        hits = [m for m in msgs if m["t"] == "hit"]
        names = sorted(h["name"] for h in hits)
        self.assertEqual(names, ["report_draft.txt", "report_final.txt"])
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")

    def test_search_glob(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "search", "root": self.root, "query": "*.md", "mode": "glob"})
        hits = [m for m in msgs if m["t"] == "hit"]
        self.assertEqual([h["name"] for h in hits], ["notes.md"])

    def test_search_regex(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "search", "root": self.root, "query": r"^report_\w+\.txt$", "mode": "regex"})
        hits = [m for m in msgs if m["t"] == "hit"]
        names = sorted(h["name"] for h in hits)
        self.assertEqual(names, ["report_draft.txt", "report_final.txt"])

class CancelTests(HelperTestCase):
    def test_cancel_in_flight_copy_during_conflict(self):
        src = self.path("cancel_src.txt")
        with open(src, "w") as f:
            f.write("new")
        dest_dir = self.path("cancel_dest")
        os.makedirs(dest_dir)
        existing = os.path.join(dest_dir, "cancel_src.txt")
        with open(existing, "w") as f:
            f.write("old")
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "copy", "sources": [src], "dest": dest_dir, "conflict": "ask"})
        conflict_msg = None
        deadline = time.time() + 8
        while time.time() < deadline:
            obj = self.helper.q.get(timeout=8)
            if obj.get("t") == "conflict":
                conflict_msg = obj
                break
        self.assertIsNotNone(conflict_msg)
        cancel_id = self.next_id()
        cancel_msgs = self.helper.call({"id": cancel_id, "op": "cancel", "target": req_id})
        self.assertEqual(self.terminal(cancel_msgs)["t"], "done")
        rest = self.helper.collect_until(req_id)
        err = rest[-1]
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "ECANCELED")

    def test_cancel_in_flight_search(self):
        for i in range(40):
            d = self.path("d%03d" % i)
            os.makedirs(d)
            for j in range(60):
                with open(os.path.join(d, "f%03d.txt" % j), "w") as f:
                    f.write("x")
        req_id = self.next_id()
        self.helper.send({"id": req_id, "op": "search", "root": self.root, "query": "zzz_never_matches", "mode": "substring"})
        cancel_id = self.next_id()
        self.helper.send({"id": cancel_id, "op": "cancel", "target": req_id})
        search_msgs = self.helper.collect_until(req_id)
        final = search_msgs[-1]
        self.assertIn(final["t"], ("error", "done"))
        if final["t"] == "error":
            self.assertEqual(final["code"], "ECANCELED")
        cancel_msgs = self.helper.collect_until(cancel_id)
        self.assertEqual(self.terminal(cancel_msgs)["t"], "done")

class PingTests(HelperTestCase):
    def test_ping(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "ping"})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["version"], "1.0.0")
        self.assertIsInstance(done["pid"], int)
        self.assertIn(done["inotify"], (True, False))

class RobustnessTests(HelperTestCase):
    def test_malformed_line_does_not_crash(self):
        self.helper.send_raw("not valid json {{{")
        msgs = self.helper.call({"id": self.next_id(), "op": "ping"})
        self.assertEqual(self.terminal(msgs)["t"], "done")

    def test_unknown_op(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "not_a_real_op"})
        err = self.terminal(msgs)
        self.assertEqual(err["t"], "error")
        self.assertEqual(err["code"], "EUNSUPPORTED")

class DirsDrivesTests(HelperTestCase):
    def test_dirs_no_crash(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "dirs"})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        dirs_msg = [m for m in msgs if m["t"] == "dirs"][0]
        self.assertIsInstance(dirs_msg["dirs"], dict)

    def test_drives_no_crash(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "drives"})
        done = self.terminal(msgs)
        self.assertEqual(done["t"], "done")
        drives_msg = [m for m in msgs if m["t"] == "drives"][0]
        self.assertIsInstance(drives_msg["drives"], list)

    def test_mountdev_rejects_paths_outside_dev(self):
        for device in ["/etc/passwd", "/dev/../etc/passwd", "", 7]:
            for op in ["mountdev", "unmountdev"]:
                msgs = self.helper.call({"id": self.next_id(), "op": op, "device": device})
                err = self.terminal(msgs)
                self.assertEqual(err["t"], "error")
                self.assertEqual(err["code"], "EINVAL")

class MountableDeviceTests(unittest.TestCase):
    def load_helper(self):
        import importlib.util
        spec = importlib.util.spec_from_loader(
            "omafile_helper_mountable",
            importlib.machinery.SourceFileLoader("omafile_helper_mountable", HELPER_PATH))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_filesystems_are_offered_and_system_partitions_are_not(self):
        helper = self.load_helper()
        self.assertTrue(helper.mountable_device({"path": "/dev/sdb1", "fstype": "ntfs"}))
        self.assertTrue(helper.mountable_device({"path": "/dev/sdc1", "fstype": "ext4", "parttype": None}))
        self.assertFalse(helper.mountable_device({"path": "/dev/sda2", "fstype": "swap"}))
        self.assertFalse(helper.mountable_device({"path": "/dev/sda3", "fstype": "crypto_LUKS"}))
        self.assertFalse(helper.mountable_device({"path": "/dev/sdd", "fstype": None}))
        self.assertFalse(helper.mountable_device({
            "path": "/dev/nvme0n1p1", "fstype": "vfat",
            "parttype": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"}))
        self.assertFalse(helper.mountable_device({"path": "sdb1", "fstype": "ext4"}))

class ClipboardFormatTests(unittest.TestCase):
    def load_helper(self):
        import importlib.util
        spec = importlib.util.spec_from_loader(
            "omafile_helper_clipboard",
            importlib.machinery.SourceFileLoader("omafile_helper_clipboard", HELPER_PATH))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_copy_offers_a_uri_list_and_cut_the_gnome_format(self):
        helper = self.load_helper()
        mime, data = helper.clipboard_payload("copy", ["/tmp/a b.txt", "/tmp/c#d"])
        self.assertEqual(mime, "text/uri-list")
        self.assertEqual(data, "file:///tmp/a%20b.txt\r\nfile:///tmp/c%23d\r\n")
        mime, data = helper.clipboard_payload("cut", ["/tmp/a b.txt"])
        self.assertEqual(mime, "x-special/gnome-copied-files")
        self.assertEqual(data, "cut\nfile:///tmp/a%20b.txt")

    def test_gnome_format_round_trips(self):
        helper = self.load_helper()
        paths = ["/home/u/Some file.png", "/home/u/100% done", "/home/u/ünï"]
        mode, parsed = helper.parse_gnome_copied_files(helper.clipboard_payload("cut", paths)[1])
        self.assertEqual(mode, "cut")
        self.assertEqual(parsed, paths)

    def test_non_file_uris_are_ignored(self):
        helper = self.load_helper()
        self.assertIsNone(helper.uri_to_path("https://example.com/x"))
        self.assertIsNone(helper.uri_to_path("file://otherhost/x"))
        self.assertIsNone(helper.uri_to_path("# comment"))
        self.assertEqual(helper.uri_to_path("file://localhost/tmp/x"), "/tmp/x")

class SameDeviceTests(HelperTestCase):
    def test_same_folder_is_same_device(self):
        folder = self.path("dev")
        os.makedirs(folder)
        msgs = self.helper.call({"id": self.next_id(), "op": "samedev", "path": folder, "dest": self.path()})
        self.assertEqual(self.terminal(msgs)["same"], True)

    def test_missing_path_is_an_error(self):
        msgs = self.helper.call({"id": self.next_id(), "op": "samedev", "path": self.path("nope"), "dest": self.path()})
        self.assertEqual(self.terminal(msgs)["t"], "error")

class WatchTests(HelperTestCase):
    def test_watch_reports_change_and_unwatch_completes(self):
        watch_dir = self.path("watched")
        os.makedirs(watch_dir)
        watch_id = self.next_id()
        self.helper.send({"id": watch_id, "op": "watch", "path": watch_dir})
        time.sleep(0.3)
        with open(os.path.join(watch_dir, "newfile.txt"), "w") as f:
            f.write("x")
        changed = None
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                obj = self.helper.q.get(timeout=deadline - time.time())
            except queue.Empty:
                break
            if obj.get("id") == watch_id and obj.get("t") == "changed":
                changed = obj
                break
        self.assertIsNotNone(changed)
        unwatch_id = self.next_id()
        self.helper.send({"id": unwatch_id, "op": "unwatch", "path": watch_dir})
        final = self.helper.collect_until(watch_id)
        self.assertEqual(final[-1]["t"], "done")

class DesktopEntryTests(unittest.TestCase):
    def load_helper(self, data_home):
        import importlib.util
        env_keys = ("XDG_DATA_HOME",)
        saved = {k: os.environ.get(k) for k in env_keys}
        os.environ["XDG_DATA_HOME"] = data_home
        try:
            spec = importlib.util.spec_from_loader(
                "omafile_helper_under_test",
                importlib.machinery.SourceFileLoader(
                    "omafile_helper_under_test", HELPER_PATH))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

    def test_exec_line_uses_the_launcher_shim(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper = self.load_helper(tmp)
            body = helper.desktop_body()
            exec_line = [l for l in body.splitlines() if l.startswith("Exec=")][0]
            self.assertTrue(exec_line.endswith(" %f"), exec_line)
            shim = exec_line[len("Exec="):-len(" %f")]
            self.assertTrue(shim.endswith(os.path.join("bin", "omafile-open")), shim)
            self.assertTrue(os.access(shim, os.X_OK), shim)

    def test_icon_points_at_the_plugin_glyph(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper = self.load_helper(tmp)
            body = helper.desktop_body()
            icon_line = [l for l in body.splitlines() if l.startswith("Icon=")][0]
            icon = icon_line[len("Icon="):]
            self.assertTrue(icon.endswith("icon.png"), icon)
            self.assertTrue(os.path.exists(icon), icon)

    def test_a_stale_entry_is_rewritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper = self.load_helper(tmp)
            os.makedirs(helper.DESKTOP_DIR, exist_ok=True)
            path = os.path.join(helper.DESKTOP_DIR, helper.DESKTOP_ID)
            with open(path, "w", encoding="utf-8") as f:
                f.write("[Desktop Entry]\nExec=omarchy-shell omafile open %f\n")
            helper.refresh_stale_desktop_entry()
            with open(path, "r", encoding="utf-8") as f:
                self.assertEqual(f.read(), helper.desktop_body())

    def test_a_missing_entry_is_not_created(self):
        with tempfile.TemporaryDirectory() as tmp:
            helper = self.load_helper(tmp)
            helper.refresh_stale_desktop_entry()
            self.assertFalse(
                os.path.exists(os.path.join(helper.DESKTOP_DIR, helper.DESKTOP_ID)))

class TrustedRunTests(unittest.TestCase):
    def load_helper(self):
        import importlib.util
        spec = importlib.util.spec_from_loader(
            "omafile_helper_trusted_run",
            importlib.machinery.SourceFileLoader(
                "omafile_helper_trusted_run", HELPER_PATH))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_output_and_exit_code_are_captured(self):
        helper = self.load_helper()
        result = helper.run_trusted("echo", ["hello"], timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "hello\n")

    def test_stdin_is_delivered(self):
        helper = self.load_helper()
        result = helper.run_trusted("cat", [], stdin_text="answer\n", timeout=10)
        self.assertEqual(result.stdout, "answer\n")

    def test_a_nonzero_exit_is_reported(self):
        helper = self.load_helper()
        result = helper.run_trusted("bash", ["-c", "exit 4"], timeout=10)
        self.assertEqual(result.returncode, 4)

    def test_capture_stops_at_the_limit(self):
        helper = self.load_helper()
        result = helper.run_trusted(
            "bash", ["-c", "yes abcdefgh | head -c 200000"], timeout=20, limit=4096)
        self.assertEqual(len(result.stdout), 4096)

    def test_an_endless_writer_times_out_instead_of_growing(self):
        helper = self.load_helper()
        with self.assertRaises(subprocess.TimeoutExpired):
            helper.run_trusted("cat", ["/dev/zero"], timeout=2, limit=4096)

    def test_a_timeout_kills_the_whole_process_group(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            marker = os.path.join(tmp, "pid")
            script = "sleep 47 & echo $! > " + marker + "; wait"
            with self.assertRaises(subprocess.TimeoutExpired):
                helper.run_trusted("bash", ["-c", script], timeout=2)
            time.sleep(0.5)
            with open(marker, "r", encoding="utf-8") as f:
                grandchild = int(f.read().strip())
            with self.assertRaises(ProcessLookupError):
                os.kill(grandchild, 0)

    def test_a_shadowed_binary_on_path_is_ignored(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            shadow = os.path.join(tmp, "echo")
            with open(shadow, "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\nexit 0\n")
            os.chmod(shadow, 0o755)
            saved = os.environ.get("PATH")
            os.environ["PATH"] = tmp + os.pathsep + (saved or "")
            try:
                resolved = helper.trusted_program("echo")
            finally:
                if saved is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = saved
            self.assertNotEqual(resolved, shadow)
            self.assertIn(os.path.dirname(resolved), helper.TRUSTED_BIN_DIRS)

    def test_a_program_outside_trusted_directories_is_refused(self):
        helper = self.load_helper()
        with self.assertRaises(FileNotFoundError):
            helper.trusted_program("omafile-definitely-not-installed")

    def test_the_child_environment_is_minimal(self):
        helper = self.load_helper()
        os.environ["OMAFILE_LEAK_CHECK"] = "leaked"
        try:
            env = helper.trusted_env()
        finally:
            os.environ.pop("OMAFILE_LEAK_CHECK", None)
        self.assertEqual(env["PATH"], "/usr/bin:/bin")
        self.assertNotIn("OMAFILE_LEAK_CHECK", env)

class TrustedProgramTests(unittest.TestCase):
    def load_helper(self):
        import importlib.util
        spec = importlib.util.spec_from_loader(
            "omafile_helper_trusted_program",
            importlib.machinery.SourceFileLoader(
                "omafile_helper_trusted_program", HELPER_PATH))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def make_executable(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(path, 0o755)
        return path

    @unittest.skipUnless(os.path.exists("/usr/bin/env"), "needs /usr/bin/env")
    def test_resolves_a_real_system_binary(self):
        helper = self.load_helper()
        self.assertEqual(helper.trusted_program("env"), "/usr/bin/env")

    def test_refuses_a_symlink_to_a_user_owned_executable(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            target = self.make_executable(os.path.join(tmp, "payload"))
            fake_bin = os.path.join(tmp, "bin")
            os.makedirs(fake_bin)
            os.symlink(target, os.path.join(fake_bin, "gio"))
            helper.TRUSTED_BIN_DIRS = (fake_bin,)
            with self.assertRaises(FileNotFoundError):
                helper.trusted_program("gio")

    @unittest.skipUnless(os.path.exists("/usr/bin/env"), "needs /usr/bin/env")
    def test_refuses_a_symlink_even_when_the_target_is_trusted(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            os.symlink("/usr/bin/env", os.path.join(tmp, "gio"))
            helper.TRUSTED_BIN_DIRS = (tmp,)
            with self.assertRaises(FileNotFoundError):
                helper.trusted_program("gio")

    def test_refuses_a_plain_user_owned_executable(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            self.make_executable(os.path.join(tmp, "gio"))
            helper.TRUSTED_BIN_DIRS = (tmp,)
            with self.assertRaises(FileNotFoundError):
                helper.trusted_program("gio")

    def test_refuses_a_name_containing_a_separator(self):
        helper = self.load_helper()
        for bad in ("../etc/passwd", "/bin/sh", "", "."):
            with self.assertRaises(FileNotFoundError):
                helper.trusted_program(bad)

    def test_trusted_node_rejects_a_non_root_owner(self):
        helper = self.load_helper()
        if is_root():
            self.skipTest("running as root")
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_executable(os.path.join(tmp, "gio"))
            self.assertFalse(helper.trusted_node(os.lstat(path)))

    def test_trusted_directory_chain_rejects_a_user_owned_directory(self):
        helper = self.load_helper()
        if is_root():
            self.skipTest("running as root")
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(helper.trusted_directory_chain(tmp))

    @unittest.skipUnless(os.path.isdir("/usr/bin"), "needs /usr/bin")
    def test_trusted_directory_chain_accepts_usr_bin(self):
        helper = self.load_helper()
        self.assertTrue(helper.trusted_directory_chain("/usr/bin"))

if __name__ == "__main__":
    unittest.main()
