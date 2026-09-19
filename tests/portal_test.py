import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTAL_PATH = os.path.join(ROOT, "bin", "omafile-portal")
SETUP_PATH = os.path.join(ROOT, "bin", "omafile-portal-setup")


def load(name, path):
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


portal = load("omafile_portal", PORTAL_PATH)
setup = load("omafile_portal_setup", SETUP_PATH)


class RequestTests(unittest.TestCase):
    def test_open_defaults(self):
        req = portal.build_request("open", "", {}, "/run/x.json")
        self.assertEqual(req["mode"], "open")
        self.assertEqual(req["title"], "Open File")
        self.assertFalse(req["multiple"])
        self.assertFalse(req["directory"])
        self.assertEqual(req["filters"], [])
        self.assertEqual(req["currentFilter"], -1)
        self.assertEqual(req["result"], "/run/x.json")
        self.assertEqual(set(req), {
            "mode", "title", "acceptLabel", "multiple", "directory", "currentFolder",
            "currentName", "currentFile", "files", "filters", "currentFilter", "result"})
        json.dumps(req)

    def test_open_options(self):
        options = {
            "accept_label": "_Upload",
            "multiple": True,
            "directory": False,
            "current_folder": b"/home/me/Pictures\0",
            "filters": [
                ("Images", [(0, "*.png"), (0, "*.PNG"), (1, "image/jpeg")]),
                ("Weird", [(1, "application/x-omafile-nope")]),
            ],
            "current_filter": ("Weird", [(1, "application/x-omafile-nope")]),
        }
        req = portal.build_request("open", "Upload", options, "/r.json")
        self.assertEqual(req["title"], "Upload")
        self.assertEqual(req["acceptLabel"], "Upload")
        self.assertTrue(req["multiple"])
        self.assertEqual(req["currentFolder"], "/home/me/Pictures")
        images = req["filters"][0]
        self.assertEqual(images["name"], "Images")
        self.assertEqual(images["patterns"][:2], ["*.png", "*.PNG"])
        self.assertIn("*.jpg", images["patterns"])
        self.assertEqual(req["filters"][1]["patterns"], ["mime:application/x-omafile-nope"])
        self.assertEqual(req["currentFilter"], 1)

    def test_current_filter_not_in_list_is_appended(self):
        options = {"filters": [("Text", [(0, "*.txt")])],
                   "current_filter": ("PDF", [(1, "application/pdf")])}
        req = portal.build_request("open", "t", options, "/r")
        self.assertEqual(len(req["filters"]), 2)
        self.assertEqual(req["currentFilter"], 1)
        self.assertIn("*.pdf", req["filters"][1]["patterns"])

    def test_byte_lists_and_empty(self):
        self.assertEqual(portal.decode_bytes([47, 116, 109, 112, 0]), "/tmp")
        self.assertEqual(portal.decode_bytes(b""), "")
        self.assertEqual(portal.decode_bytes(None), "")
        self.assertEqual(portal.decode_bytes("/x\0"), "/x")
        self.assertEqual(portal.decode_bytes("/ü dir\0".encode()), "/ü dir")

    def test_unpack_options(self):
        GLib = portal.GLib
        variant = GLib.Variant("a{sv}", {
            "current_folder": GLib.Variant("ay", "/tmp/ü dir\0".encode()),
            "files": GLib.Variant("aay", [b"a.txt\0", b"b.txt\0"]),
            "multiple": GLib.Variant("b", True),
            "filters": GLib.Variant("a(sa(us))", [("T", [(0, "*.txt")])]),
        })
        options = portal.unpack_options(variant)
        req = portal.build_request("savefiles", "", options, "/r")
        self.assertEqual(req["currentFolder"], "/tmp/ü dir")
        self.assertEqual(req["files"], ["a.txt", "b.txt"])
        self.assertTrue(options["multiple"])
        self.assertEqual(portal.build_request("open", "", options, "/r")["filters"],
                         [{"name": "T", "patterns": ["*.txt"]}])

    def test_mnemonic(self):
        self.assertEqual(portal.strip_mnemonic("_Save"), "Save")
        self.assertEqual(portal.strip_mnemonic("my__file"), "my_file")
        self.assertEqual(portal.strip_mnemonic(None), "")

    def test_wildcard_mime(self):
        globs = portal.mime_globs("image/*")
        self.assertIn("*.png", globs)
        self.assertNotIn("*.txt", globs)
        self.assertEqual(portal.mime_globs("*/*"), ["*"])

    def test_save(self):
        options = {"current_name": "report.pdf", "current_folder": b"/home/me/Documents\0",
                   "multiple": True, "directory": True}
        req = portal.build_request("save", "Save", options, "/r")
        self.assertEqual(req["mode"], "save")
        self.assertEqual(req["currentName"], "report.pdf")
        self.assertEqual(req["currentFolder"], "/home/me/Documents")
        self.assertFalse(req["multiple"])
        self.assertFalse(req["directory"])

    def test_save_current_file(self):
        options = {"current_file": b"/home/me/notes.txt\0"}
        req = portal.build_request("save", "", options, "/r")
        self.assertEqual(req["title"], "Save File")
        self.assertEqual(req["currentFile"], "/home/me/notes.txt")
        self.assertEqual(req["currentFolder"], "/home/me")
        self.assertEqual(req["currentName"], "notes.txt")

    def test_savefiles(self):
        options = {"files": [b"a.txt\0", b"b c.png\0", b"\0"], "current_folder": b"/tmp\0"}
        req = portal.build_request("savefiles", "", options, "/r")
        self.assertEqual(req["mode"], "savefiles")
        self.assertEqual(req["files"], ["a.txt", "b c.png"])
        self.assertEqual(req["currentFolder"], "/tmp")
        self.assertTrue(req["directory"])
        self.assertEqual(req["currentName"], "")


class ResultTests(unittest.TestCase):
    def test_cancel_and_errors(self):
        self.assertEqual(portal.parse_result({"ok": False}, "open", {}), (1, {}))
        self.assertEqual(portal.parse_result({"ok": True, "paths": []}, "open", {}), (1, {}))
        self.assertEqual(portal.parse_result([], "open", {})[0], 2)
        self.assertEqual(portal.parse_result({"ok": True}, "open", {})[0], 2)
        self.assertEqual(portal.parse_result({"ok": True, "paths": ["rel.txt"]}, "open", {})[0], 2)

    def test_uri_encoding(self):
        data = {"ok": True, "paths": ["/tmp/a b/ü#1.txt", "/tmp/x%y"]}
        response, results = portal.parse_result(data, "open", {"multiple": True})
        self.assertEqual(response, 0)
        self.assertEqual(results["uris"], [
            "file:///tmp/a%20b/%C3%BC%231.txt", "file:///tmp/x%25y"])
        self.assertEqual(results["choices"], [])
        self.assertNotIn("current_filter", results)

    def test_single_open_truncates(self):
        data = {"ok": True, "paths": ["/a", "/b"]}
        self.assertEqual(portal.parse_result(data, "open", {})[1]["uris"], ["file:///a"])

    def test_filter_echo(self):
        options = {"filters": [("Text", [(0, "*.txt")]), ("Images", [(1, "image/png")])]}
        data = {"ok": True, "paths": ["/a.png"], "filter": 1}
        response, results = portal.parse_result(data, "open", options)
        self.assertEqual(results["current_filter"], ("Images", [(1, "image/png")]))
        data["filter"] = 5
        self.assertNotIn("current_filter", portal.parse_result(data, "open", options)[1])
        data["filter"] = -1
        self.assertNotIn("current_filter", portal.parse_result(data, "open", options)[1])

    def test_save_path(self):
        data = {"ok": True, "paths": ["/home/me/new name.pdf"]}
        response, results = portal.parse_result(data, "save", {})
        self.assertEqual(results["uris"], ["file:///home/me/new%20name.pdf"])

    def test_savefiles_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            options = {"files": [b"a.txt\0", b"b c.txt\0"]}
            response, results = portal.parse_result({"ok": True, "paths": [tmp]}, "savefiles", options)
            self.assertEqual(response, 0)
            self.assertEqual(results["uris"], [
                portal.GLib.filename_to_uri(os.path.join(tmp, "a.txt"), None),
                portal.GLib.filename_to_uri(os.path.join(tmp, "b c.txt"), None)])
            one = {"files": [b"a.txt\0"]}
            response, results = portal.parse_result({"ok": True, "paths": [tmp]}, "savefiles", one)
            self.assertTrue(results["uris"][0].endswith("/a.txt"))
            full = [os.path.join(tmp, "x"), os.path.join(tmp, "y")]
            response, results = portal.parse_result({"ok": True, "paths": full}, "savefiles", options)
            self.assertEqual(len(results["uris"]), 2)
            self.assertTrue(results["uris"][1].endswith("/y"))

    def test_variant(self):
        results = portal.parse_result(
            {"ok": True, "paths": ["/a"], "filter": 0}, "open",
            {"filters": [("All", [(0, "*")])]})[1]
        variants = portal.results_variant(results)
        self.assertEqual(variants["uris"].get_type_string(), "as")
        self.assertEqual(variants["current_filter"].get_type_string(), "(sa(us))")
        self.assertEqual(variants["choices"].get_type_string(), "a(ss)")


class ConfTests(unittest.TestCase):
    LINE = "org.freedesktop.impl.portal.FileChooser=omafile"

    def test_fresh(self):
        text = setup.merge_conf(None)
        self.assertEqual(text, "[preferred]\ndefault=hyprland;gtk\n" + self.LINE + "\n")
        self.assertTrue(setup.conf_enabled(text))
        self.assertIsNone(setup.unmerge_conf(text))

    def test_preserves_other_keys(self):
        original = ("# mine\n[preferred]\ndefault=hyprland;gtk\n"
                    "org.freedesktop.impl.portal.Settings=darkman\n\n[other]\nx=1\n")
        merged = setup.merge_conf(original)
        self.assertIn("org.freedesktop.impl.portal.Settings=darkman\n" + self.LINE + "\n\n[other]", merged)
        self.assertIn("# mine", merged)
        self.assertEqual(setup.merge_conf(merged), merged)
        self.assertEqual(setup.unmerge_conf(merged), original)

    def test_replaces_existing_filechooser(self):
        original = "[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=gtk\n"
        merged = setup.merge_conf(original)
        self.assertEqual(merged.count("FileChooser"), 1)
        self.assertTrue(setup.conf_enabled(merged))
        self.assertFalse(setup.conf_enabled(original))

    def test_unmerge_leaves_foreign_value(self):
        text = "[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=kde\n"
        self.assertEqual(setup.unmerge_conf(text), text)

    def test_no_preferred_section(self):
        merged = setup.merge_conf("[other]\nx=1\n")
        self.assertEqual(merged, "[other]\nx=1\n\n[preferred]\n" + self.LINE + "\n")
        self.assertTrue(setup.conf_enabled(merged))


class SetupCommandTests(unittest.TestCase):
    def run_setup(self, home, *args):
        env = dict(os.environ)
        env.update({"HOME": home, "OMAFILE_PORTAL_SKIP_SYSTEM": "1",
                    "PATH": "/nonexistent"})
        env.pop("XDG_CONFIG_HOME", None)
        env.pop("XDG_DATA_HOME", None)
        return subprocess.run([sys.executable, SETUP_PATH] + list(args),
                              capture_output=True, text=True, env=env, timeout=30)

    def test_enable_status_disable(self):
        with tempfile.TemporaryDirectory() as home:
            conf = os.path.join(home, ".config", "xdg-desktop-portal", "hyprland-portals.conf")
            service = os.path.join(home, ".local", "share", "dbus-1", "services",
                                   "org.freedesktop.impl.portal.desktop.omafile.service")
            status = json.loads(self.run_setup(home, "status").stdout)
            self.assertFalse(status["enabled"])
            result = self.run_setup(home, "enable")
            self.assertEqual(result.returncode, 0, result.stderr)
            with open(service, encoding="utf-8") as f:
                body = f.read()
            self.assertIn("Exec=" + os.path.realpath(PORTAL_PATH) + "\n", body)
            with open(conf, encoding="utf-8") as f:
                self.assertIn("FileChooser=omafile", f.read())
            status = json.loads(self.run_setup(home, "status").stdout)
            self.assertTrue(status["enabled"])
            self.assertIn("systemFile", status)
            self.assertIn("available", status)
            result = self.run_setup(home, "disable")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(os.path.exists(conf))
            self.assertFalse(os.path.exists(service))
            self.assertFalse(json.loads(self.run_setup(home, "status").stdout)["enabled"])

    def test_disable_keeps_user_conf(self):
        with tempfile.TemporaryDirectory() as home:
            conf = os.path.join(home, ".config", "xdg-desktop-portal", "hyprland-portals.conf")
            os.makedirs(os.path.dirname(conf))
            original = "[preferred]\ndefault=hyprland;gtk\norg.freedesktop.impl.portal.Settings=darkman\n"
            with open(conf, "w", encoding="utf-8") as f:
                f.write(original)
            self.assertEqual(self.run_setup(home, "enable").returncode, 0)
            self.assertEqual(self.run_setup(home, "disable").returncode, 0)
            with open(conf, encoding="utf-8") as f:
                self.assertEqual(f.read(), original)

    def test_bad_command(self):
        with tempfile.TemporaryDirectory() as home:
            result = self.run_setup(home, "bogus")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
