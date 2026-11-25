import errno
import importlib.machinery
import importlib.util
import os
import shutil
import stat
import tempfile
import threading
import unittest

HELPER_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "omafile-helper")


def load_helper():
    spec = importlib.util.spec_from_loader(
        "omafile_helper_copy_security", importlib.machinery.SourceFileLoader("omafile_helper_copy_security", HELPER_PATH))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CopyFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.helper = load_helper()
        self.out = []
        self.helper.emit = self.out.append
        os.makedirs(self.path("shared"))
        os.makedirs(self.path("dest"))
        os.makedirs(self.path("private"))
        with open(self.path("private", "secret.txt"), "w") as f:
            f.write("secret")
        with open(self.path("private", "victim.txt"), "w") as f:
            f.write("keep me")

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def run_op(self, sources, dest, is_move=False):
        self.helper.op_copy_move({"id": 1, "sources": sources, "dest": dest, "conflict": "rename"},
                                 threading.Event(), is_move)
        return self.out[-1]

    def swap_before_open(self, name, replacement):
        real = self.helper.open_checked

        def swapping(dir_fd, entry, lst, flags):
            if os.fsdecode(entry) == name and not swapping.done:
                swapping.done = True
                target = self.path("shared", name)
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target)
                else:
                    os.unlink(target)
                os.symlink(replacement, target)
            return real(dir_fd, entry, lst, flags)

        swapping.done = False
        self.helper.open_checked = swapping


class CopySecurityTests(CopyFixture):
    def test_a_file_swapped_for_a_symlink_after_the_check_is_not_read(self):
        with open(self.path("shared", "report.txt"), "w") as f:
            f.write("report")
        self.swap_before_open("report.txt", self.path("private", "secret.txt"))
        done = self.run_op([self.path("shared", "report.txt")], self.path("dest"))
        self.assertEqual(done["t"], "done")
        self.assertEqual(len(done["errors"]), 1)
        self.assertFalse(os.path.exists(self.path("dest", "report.txt")))

    def test_a_folder_swapped_for_a_symlink_after_the_check_is_not_walked(self):
        os.makedirs(self.path("shared", "photos"))
        with open(self.path("shared", "photos", "a.jpg"), "w") as f:
            f.write("a")
        self.swap_before_open("photos", self.path("private"))
        done = self.run_op([self.path("shared", "photos")], self.path("dest"))
        self.assertEqual(len(done["errors"]), 1)
        self.assertFalse(os.path.exists(self.path("dest", "photos", "secret.txt")))

    def test_a_destination_symlink_that_appears_after_the_check_is_never_truncated(self):
        with open(self.path("shared", "notes.txt"), "w") as f:
            f.write("new")
        real = self.helper.lstat_at

        def planted(dir_fd, name):
            result = real(dir_fd, name)
            if os.fsdecode(name) == "notes.txt" and result is None:
                os.symlink(self.path("private", "victim.txt"), self.path("dest", "notes.txt"))
            return result

        self.helper.lstat_at = planted
        done = self.run_op([self.path("shared", "notes.txt")], self.path("dest"))
        self.assertEqual(len(done["errors"]), 1)
        with open(self.path("private", "victim.txt")) as f:
            self.assertEqual(f.read(), "keep me")

    def test_symlinks_inside_a_copied_folder_are_copied_as_links(self):
        os.makedirs(self.path("shared", "box"))
        os.symlink(self.path("private", "secret.txt"), self.path("shared", "box", "link"))
        done = self.run_op([self.path("shared", "box")], self.path("dest"))
        self.assertEqual(done["errors"], [])
        self.assertTrue(os.path.islink(self.path("dest", "box", "link")))

    def test_a_cross_drive_move_keeps_the_source_when_part_of_the_copy_fails(self):
        if os.geteuid() == 0:
            self.skipTest("root can read anything")
        os.makedirs(self.path("shared", "album"))
        with open(self.path("shared", "album", "ok.jpg"), "w") as f:
            f.write("ok")
        with open(self.path("shared", "album", "locked.jpg"), "w") as f:
            f.write("locked")
        os.chmod(self.path("shared", "album", "locked.jpg"), 0)
        real_rename = self.helper.os.rename

        def cross_drive(*args, **kwargs):
            if os.fsencode(args[0]).startswith(b".omafile-part-"):
                return (real_noreplace if len(args) == 4 else real_rename)(*args, **kwargs)
            raise OSError(errno.EXDEV, "Invalid cross-device link")

        real_noreplace = self.helper.rename_noreplace
        self.helper.os.rename = cross_drive
        self.helper.rename_noreplace = cross_drive
        try:
            done = self.run_op([self.path("shared", "album")], self.path("dest"), is_move=True)
        finally:
            self.helper.os.rename = real_rename
            self.helper.rename_noreplace = real_noreplace
            os.chmod(self.path("shared", "album", "locked.jpg"), stat.S_IRUSR | stat.S_IWUSR)
        self.assertEqual(len(done["errors"]), 1)
        self.assertTrue(os.path.exists(self.path("shared", "album", "locked.jpg")), "nothing is lost")
        self.assertTrue(os.path.exists(self.path("shared", "album", "ok.jpg")))

    def test_special_files_are_skipped_instead_of_hanging(self):
        os.mkfifo(self.path("shared", "pipe"))
        done = self.run_op([self.path("shared", "pipe")], self.path("dest"))
        self.assertEqual(len(done["errors"]), 1)
        self.assertFalse(os.path.exists(self.path("dest", "pipe")))


class CopyTreeTests(CopyFixture):
    def make_tree(self):
        base = self.path("shared", "project")
        os.makedirs(os.path.join(base, "src", "deep"))
        with open(os.path.join(base, "src", "deep", "main.py"), "w") as f:
            f.write("print(1)")
        os.chmod(os.path.join(base, "src", "deep", "main.py"), 0o750)
        os.utime(os.path.join(base, "src", "deep", "main.py"), ns=(1_000_000_000, 2_000_000_000))
        odd = os.path.join(os.fsencode(base), b"caf\xe9.txt")
        with open(odd, "wb") as f:
            f.write(b"latin1 name")
        os.symlink("src/deep/main.py", os.path.join(base, "shortcut"))
        return base

    def check_tree(self, root):
        with open(os.path.join(root, "src", "deep", "main.py")) as f:
            self.assertEqual(f.read(), "print(1)")
        st = os.stat(os.path.join(root, "src", "deep", "main.py"))
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o750)
        self.assertEqual(st.st_mtime_ns, 2_000_000_000)
        with open(os.path.join(os.fsencode(root), b"caf\xe9.txt"), "rb") as f:
            self.assertEqual(f.read(), b"latin1 name")
        self.assertEqual(os.readlink(os.path.join(root, "shortcut")), "src/deep/main.py")

    def test_a_folder_copies_with_contents_modes_times_odd_names_and_links(self):
        base = self.make_tree()
        done = self.run_op([base], self.path("dest"))
        self.assertEqual(done["errors"], [])
        self.check_tree(self.path("dest", "project"))
        self.check_tree(base)

    def test_copying_into_the_same_folder_makes_a_numbered_copy(self):
        base = self.make_tree()
        done = self.run_op([base], self.path("shared"))
        self.assertEqual(done["errors"], [])
        self.check_tree(self.path("shared", "project (1)"))

    def test_overwrite_merges_a_folder_into_an_existing_one(self):
        base = self.make_tree()
        os.makedirs(self.path("dest", "project"))
        with open(self.path("dest", "project", "extra.txt"), "w") as f:
            f.write("stays")
        self.helper.op_copy_move({"id": 1, "sources": [base], "dest": self.path("dest"), "conflict": "overwrite"},
                                 threading.Event(), False)
        self.assertEqual(self.out[-1]["errors"], [])
        self.check_tree(self.path("dest", "project"))
        self.assertTrue(os.path.exists(self.path("dest", "project", "extra.txt")))

    def test_a_cross_drive_move_copies_then_removes_the_source(self):
        base = self.make_tree()
        real_rename = self.helper.os.rename

        def cross_drive(*args, **kwargs):
            raise OSError(errno.EXDEV, "Invalid cross-device link")

        self.helper.os.rename = cross_drive
        try:
            done = self.run_op([base], self.path("dest"), is_move=True)
        finally:
            self.helper.os.rename = real_rename
        self.assertEqual(done["errors"], [])
        self.check_tree(self.path("dest", "project"))
        self.assertFalse(os.path.exists(base))


class SymlinkDestinationTests(CopyFixture):
    def setUp(self):
        super().setUp()
        with open(self.path("shared", "report.txt"), "w") as f:
            f.write("report")

    def test_a_copy_into_a_linked_folder_lands_in_the_folder(self):
        os.symlink(self.path("dest"), self.path("linked"))
        done = self.run_op([self.path("shared", "report.txt")], self.path("linked"))
        self.assertEqual(done["t"], "done")
        self.assertEqual(done["errors"], [])
        with open(self.path("dest", "report.txt")) as f:
            self.assertEqual(f.read(), "report")

    def test_a_move_into_a_linked_folder_lands_and_removes_the_source(self):
        os.symlink("dest", self.path("linked"))
        done = self.run_op([self.path("shared", "report.txt")], self.path("linked"), is_move=True)
        self.assertEqual(done["errors"], [])
        self.assertTrue(os.path.exists(self.path("dest", "report.txt")))
        self.assertFalse(os.path.exists(self.path("shared", "report.txt")))

    def test_a_link_to_a_file_is_not_a_destination(self):
        os.symlink(self.path("private", "victim.txt"), self.path("linked"))
        done = self.run_op([self.path("shared", "report.txt")], self.path("linked"))
        self.assertEqual(done["t"], "error")
        self.assertEqual(done["code"], "EINVAL")
        with open(self.path("private", "victim.txt")) as f:
            self.assertEqual(f.read(), "keep me")

    def test_a_link_omafile_does_not_trust_is_still_refused(self):
        os.symlink(self.path("dest"), self.path("linked"))
        self.helper.link_trusted = lambda *args: False
        done = self.run_op([self.path("shared", "report.txt")], self.path("linked"))
        self.assertEqual(done["t"], "error")
        self.assertEqual(done["code"], "ELOOP")
        self.assertEqual(os.listdir(self.path("dest")), [])

    def test_a_linked_folder_swapped_after_the_check_is_not_written(self):
        os.symlink(self.path("dest"), self.path("linked"))
        real = self.helper.open_dir_safely

        def swapping(path_bytes, *args, **kwargs):
            if path_bytes == os.fsencode(self.path("linked")) and not swapping.done:
                swapping.done = True
                os.unlink(self.path("linked"))
                os.symlink(self.path("private"), self.path("linked"))
            return real(path_bytes, *args, **kwargs)

        swapping.done = False
        self.helper.open_dir_safely = swapping
        done = self.run_op([self.path("shared", "report.txt")], self.path("linked"))
        self.assertEqual(done["t"], "error")
        self.assertEqual(done["code"], "ESTALE")
        self.assertEqual(os.listdir(self.path("dest")), [])
        self.assertFalse(os.path.exists(self.path("private", "report.txt")))


class PlainCopyOs:
    def __init__(self, real, write_size):
        self.real = real
        self.write_size = write_size

    def __getattr__(self, name):
        return getattr(self.real, name)

    def copy_file_range(self, *args, **kwargs):
        raise OSError(errno.EXDEV, "Invalid cross-device link")

    def write(self, fd, data):
        return self.real.write(fd, bytes(data)[:self.write_size(len(data))])


class ShortWriteTests(CopyFixture):
    def big_file(self, name):
        data = os.urandom(3 * 1024 * 1024 + 123)
        with open(self.path("shared", name), "wb") as f:
            f.write(data)
        return data

    def test_short_writes_still_copy_every_byte(self):
        data = self.big_file("movie.bin")
        self.helper.os = PlainCopyOs(os, lambda wanted: min(wanted, 4096))
        try:
            done = self.run_op([self.path("shared", "movie.bin")], self.path("dest"))
        finally:
            self.helper.os = os
        self.assertEqual(done["errors"], [])
        with open(self.path("dest", "movie.bin"), "rb") as f:
            self.assertEqual(f.read(), data)

    def test_a_write_that_stops_keeps_the_source_of_a_cross_drive_move(self):
        data = self.big_file("movie.bin")
        budget = [1024 * 1024 + 7]

        def stalling(wanted):
            allowed = min(wanted, budget[0])
            budget[0] -= allowed
            return allowed

        real_noreplace = self.helper.rename_noreplace

        def cross_drive(*args, **kwargs):
            if os.fsencode(args[0]).startswith(b".omafile-part-"):
                return real_noreplace(*args, **kwargs)
            raise OSError(errno.EXDEV, "Invalid cross-device link")

        self.helper.os = PlainCopyOs(os, stalling)
        self.helper.rename_noreplace = cross_drive
        try:
            done = self.run_op([self.path("shared", "movie.bin")], self.path("dest"), is_move=True)
        finally:
            self.helper.os = os
            self.helper.rename_noreplace = real_noreplace
        self.assertEqual(len(done["errors"]), 1)
        with open(self.path("shared", "movie.bin"), "rb") as f:
            self.assertEqual(f.read(), data, "the source is kept whole")
        self.assertFalse(os.path.exists(self.path("dest", "movie.bin")), "no truncated copy is published")
        self.assertEqual([n for n in os.listdir(self.path("dest")) if n.startswith(".omafile-part-")], [],
                         "and the partial file is cleaned up")


if __name__ == "__main__":
    unittest.main()
