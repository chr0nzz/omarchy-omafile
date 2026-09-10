import json
import os
import queue
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HELPER_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "omafile-helper")

class Helper:
    def __init__(self, env=None):
        full_env = dict(os.environ)
        if env:
            full_env.update(env)
        self.proc = subprocess.Popen(
            [sys.executable, HELPER_PATH],
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

if __name__ == "__main__":
    unittest.main()
