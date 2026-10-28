"""End-to-end tests for backend/filesd.py over its JSON-lines protocol.

Run with: python3 -m unittest discover -s tests
"""

import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

BACKEND = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend", "filesd.py")
TRASH = ":trash:"


class Client:
    def __init__(self, env):
        self.proc = subprocess.Popen(
            [sys.executable, BACKEND],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        self.buffer = b""
        self.fd = self.proc.stdout.fileno()
        self.events = []

    def send(self, **command):
        self.proc.stdin.write((json.dumps(command) + "\n").encode("utf-8"))
        self.proc.stdin.flush()

    def read(self, timeout=8):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("timeout waiting for event; log=%r; stderr=%r"
                                     % (self.events[-5:], self.stderr()))
            ready, _, _ = select.select([self.fd], [], [], remaining)
            if not ready:
                continue
            chunk = os.read(self.fd, 65536)
            if not chunk:
                raise AssertionError("backend exited; stderr=%r" % self.stderr())
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        event = json.loads(line.decode("utf-8", "replace"))
        self.events.append(event)
        return event

    def wait(self, event_name, ident=None, timeout=8):
        deadline = time.monotonic() + timeout
        while True:
            event = self.read(max(0.1, deadline - time.monotonic()))
            if event.get("event") == event_name and (ident is None or event.get("id") == ident):
                if event_name == "job" and event.get("state") != "done":
                    continue
                return event
            if event.get("event") == "error":
                raise AssertionError("backend error: %r" % event)

    def run_job(self, **command):
        ident = command["id"]
        self.send(**command)
        conflict = None
        while True:
            event = self.read()
            if event.get("event") == "conflict" and event.get("id") == ident:
                conflict = event
                return event
            if event.get("event") == "job" and event.get("id") == ident and event.get("state") == "done":
                return event

    def resolve(self, choice):
        self.send(op="resolve", choice=choice)

    def stderr(self):
        try:
            self.proc.stderr.flush()
        except Exception:
            pass
        try:
            os.set_blocking(self.proc.stderr.fileno(), False)
            return self.proc.stderr.read() or b""
        except Exception:
            return b""

    def close(self):
        try:
            self.send(op="quit")
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()
        for stream in (self.proc.stdin, self.proc.stdout, self.proc.stderr):
            try:
                stream.close()
            except Exception:
                pass


class FilesdTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="filesd-test-")
        self.home = os.path.join(self.tmp, "home")
        self.data = os.path.join(self.tmp, "data")
        self.config = os.path.join(self.tmp, "config")
        os.makedirs(self.home)
        os.makedirs(self.data)
        os.makedirs(self.config)
        self.env = dict(os.environ)
        self.env.update({"HOME": self.home, "XDG_DATA_HOME": self.data,
                         "XDG_CONFIG_HOME": self.config,
                         "XDG_STATE_HOME": os.path.join(self.tmp, "state"),
                         "PYTHONUNBUFFERED": "1"})
        self.make("Documents", dir=True)
        self.make("note.txt", "hello")
        self.make("pic.png", "png")
        self.make("archive.zip", "zip")
        self.make("tool.sh", "#!/bin/sh\n", mode=0o755)
        self.make(".hidden", "secret")
        self.client = Client(self.env)
        ready = self.client.read()
        self.assertEqual(ready["event"], "ready")
        self.assertEqual(ready["home"], self.home)
        self.ident = 0

    def tearDown(self):
        self.client.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def make(self, relative, content="", dir=False, mode=None):
        full = os.path.join(self.home, relative)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        if dir:
            os.makedirs(full, exist_ok=True)
        else:
            with open(full, "w", encoding="utf-8") as handle:
                handle.write(content)
            if mode is not None:
                os.chmod(full, mode)
        return full

    def next_id(self):
        self.ident += 1
        return self.ident

    def listing(self, path=None, hidden=False):
        ident = self.next_id()
        self.client.send(op="list", id=ident, path=path or self.home, hidden=hidden)
        event = self.client.wait("listing", ident)
        self.assertIsNone(event["error"])
        return event

    def test_places(self):
        ident = self.next_id()
        self.client.send(op="places", id=ident)
        event = self.client.wait("places", ident)
        labels = [p["label"] for p in event["places"]]
        self.assertIn("Home", labels)
        self.assertIn("Documents", labels)
        self.assertIn("Trash", labels)
        self.assertEqual(event["places"][0]["path"], self.home)
        self.assertEqual(event["bookmarks"], [])

    def test_bookmark_add_persist_and_remove(self):
        target = self.make("Projects", dir=True)
        ident = self.next_id()
        self.client.send(op="bookmarkAdd", id=ident, path=target)
        event = self.client.wait("bookmarks", ident)
        self.assertTrue(event["ok"], event)
        self.assertEqual([b["path"] for b in event["bookmarks"]], [target])
        self.assertEqual(event["bookmarks"][0]["label"], "Projects")

        ident = self.next_id()
        self.client.send(op="bookmarkAdd", id=ident, path=target)
        event = self.client.wait("bookmarks", ident)
        self.assertFalse(event["ok"])

        stored = os.path.join(self.tmp, "state", "omarchy", "files-places.json")
        with open(stored, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), [target])

        ident = self.next_id()
        self.client.send(op="places", id=ident)
        event = self.client.wait("places", ident)
        self.assertEqual([b["path"] for b in event["bookmarks"]], [target])

        ident = self.next_id()
        self.client.send(op="bookmarkRemove", id=ident, path=target)
        event = self.client.wait("bookmarks", ident)
        self.assertTrue(event["ok"], event)
        self.assertEqual(event["bookmarks"], [])
        with open(stored, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), [])

    def test_bookmark_rejects_files_and_standard_places(self):
        ident = self.next_id()
        self.client.send(op="bookmarkAdd", id=ident, path=os.path.join(self.home, "note.txt"))
        event = self.client.wait("bookmarks", ident)
        self.assertFalse(event["ok"])

        ident = self.next_id()
        self.client.send(op="bookmarkAdd", id=ident, path=self.home)
        event = self.client.wait("bookmarks", ident)
        self.assertFalse(event["ok"])

    def test_listing_kinds_hidden_and_parent(self):
        event = self.listing()
        names = [e["name"] for e in event["entries"]]
        self.assertIn("note.txt", names)
        self.assertNotIn(".hidden", names)
        self.assertEqual(event["entries"][0]["name"], "Documents")  # folders first
        by_name = {e["name"]: e for e in event["entries"]}
        self.assertEqual(by_name["Documents"]["kind"], "folder")
        self.assertEqual(by_name["pic.png"]["kind"], "image")
        self.assertEqual(by_name["archive.zip"]["kind"], "archive")
        self.assertEqual(by_name["tool.sh"]["kind"], "code")
        self.assertTrue(by_name["note.txt"]["dir"] is False)
        self.assertGreater(event["free"], 0)
        self.assertEqual(event["parent"], os.path.dirname(self.home))

        event = self.listing(hidden=True)
        self.assertIn(".hidden", [e["name"] for e in event["entries"]])

    def test_symlink_listing(self):
        os.symlink(os.path.join(self.home, "Documents"), os.path.join(self.home, "docs-link"))
        event = self.listing()
        link = next(e for e in event["entries"] if e["name"] == "docs-link")
        self.assertTrue(link["link"])
        self.assertTrue(link["dir"])
        self.assertEqual(link["target"], os.path.join(self.home, "Documents"))

    def test_listing_caps_huge_directories(self):
        folder = os.path.join(self.home, "huge")
        os.makedirs(folder)
        for index in range(10001):
            open(os.path.join(folder, "f%05d" % index), "a").close()
        event = self.listing(folder)
        self.assertEqual(len(event["entries"]), 10000)
        self.assertTrue(event["truncated"])

    def test_move_symlink_dir_does_not_merge_target(self):
        real = self.make("real", dir=True)
        self.make("real/keep.txt", "keep")
        link = os.path.join(self.home, "link")
        os.symlink(real, link)
        dest = self.make("dest", dir=True)
        os.makedirs(os.path.join(dest, "link"))
        self.make("dest/link/existing.txt", "old")

        ident = self.next_id()
        conflict = self.client.run_job(op="move", id=ident, sources=[link], dest=dest)
        self.assertEqual(conflict["event"], "conflict")
        self.client.resolve("skip")
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertTrue(os.path.islink(link))
        self.assertTrue(os.path.isfile(os.path.join(real, "keep.txt")))
        self.assertFalse(os.path.exists(os.path.join(dest, "link", "keep.txt")))
        self.assertTrue(os.path.isfile(os.path.join(dest, "link", "existing.txt")))

    def test_copy_refuses_symlinked_destination_inside_source(self):
        source = self.make("src/sub", dir=True)
        self.make("src/file.txt", "x")
        out = os.path.join(self.home, "out")
        os.symlink(source, out)

        ident = self.next_id()
        self.client.send(op="copy", id=ident, sources=[os.path.join(self.home, "src")], dest=out)
        done = self.client.wait("job", ident)
        self.assertFalse(done["ok"])
        self.assertFalse(os.path.exists(os.path.join(source, "src")))

    def test_trash_refuses_cross_filesystem(self):
        shm = "/dev/shm"
        if not os.path.isdir(shm) or os.stat(shm).st_dev == os.stat(self.data).st_dev:
            self.skipTest("no second filesystem available")
        folder = tempfile.mkdtemp(prefix="filesd-shm-", dir=shm)
        self.addCleanup(shutil.rmtree, folder, True)
        source = os.path.join(folder, "big.txt")
        with open(source, "w", encoding="utf-8") as handle:
            handle.write("data")

        ident = self.next_id()
        self.client.send(op="trash", id=ident, paths=[source])
        done = self.client.wait("job", ident)
        self.assertFalse(done["ok"])
        self.assertTrue(os.path.exists(source))
        self.assertEqual(self.listing(TRASH)["entries"], [])

    def test_mkdir_and_rename(self):
        ident = self.next_id()
        self.client.send(op="mkdir", id=ident, path=self.home, name="New Folder")
        done = self.client.wait("job", ident)
        self.assertEqual(done["state"], "done")
        self.assertTrue(done["ok"])
        self.assertTrue(os.path.isdir(os.path.join(self.home, "New Folder")))

        ident = self.next_id()
        self.client.send(op="mkdir", id=ident, path=self.home, name="New Folder")
        done = self.client.wait("job", ident)
        self.assertFalse(done["ok"])

        ident = self.next_id()
        self.client.send(op="rename", id=ident, path=os.path.join(self.home, "note.txt"), name="renamed.txt")
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"])
        self.assertTrue(os.path.isfile(os.path.join(self.home, "renamed.txt")))
        self.assertFalse(os.path.exists(os.path.join(self.home, "note.txt")))

    def test_search(self):
        self.make("Documents/deep/notes.md", "x")
        ident = self.next_id()
        self.client.send(op="search", id=ident, path=self.home, query="note", hidden=False)
        event = self.client.wait("search", ident)
        self.assertIsNone(event["error"])
        names = sorted(e["name"] for e in event["entries"])
        self.assertEqual(names, ["note.txt", "notes.md"])
        deep = next(e for e in event["entries"] if e["name"] == "notes.md")
        self.assertTrue(deep["parentLabel"].endswith("deep"))

    def test_trash_round_trip(self):
        ident = self.next_id()
        self.client.send(op="trash", id=ident, paths=[os.path.join(self.home, "note.txt")])
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertFalse(os.path.exists(os.path.join(self.home, "note.txt")))

        event = self.listing(TRASH)
        self.assertTrue(event["trash"])
        item = next(e for e in event["entries"] if e["name"] == "note.txt")
        self.assertEqual(item["restoreTo"], os.path.join(self.home, "note.txt"))

        ident = self.next_id()
        self.client.send(op="restore", id=ident, paths=[item["path"]])
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertTrue(os.path.isfile(os.path.join(self.home, "note.txt")))
        self.assertEqual(self.listing(TRASH)["entries"], [])

    def test_trash_empty(self):
        ident = self.next_id()
        self.client.send(op="trash", id=ident, paths=[os.path.join(self.home, "pic.png")])
        self.assertTrue(self.client.wait("job", ident)["ok"])
        ident = self.next_id()
        self.client.send(op="emptyTrash", id=ident)
        self.assertTrue(self.client.wait("job", ident)["ok"])
        self.assertEqual(self.listing(TRASH)["entries"], [])

    def test_delete_from_trash_drops_trashinfo(self):
        ident = self.next_id()
        self.client.send(op="trash", id=ident, paths=[os.path.join(self.home, "pic.png")])
        self.assertTrue(self.client.wait("job", ident)["ok"])
        item = self.listing(TRASH)["entries"][0]
        ident = self.next_id()
        self.client.send(op="delete", id=ident, paths=[item["path"]])
        self.assertTrue(self.client.wait("job", ident)["ok"])
        self.assertEqual(self.listing(TRASH)["entries"], [])
        info = os.path.join(self.data, "Trash", "info", os.path.basename(item["path"]) + ".trashinfo")
        self.assertFalse(os.path.exists(info))

    def test_move_folder_merge_skip_keeps_source(self):
        self.make("merge/a.txt", "new-a")
        self.make("merge/b.txt", "new-b")
        self.make("Documents/merge/a.txt", "old-a")
        ident = self.next_id()
        conflict = self.client.run_job(op="move", id=ident,
                                       sources=[os.path.join(self.home, "merge")],
                                       dest=os.path.join(self.home, "Documents"))
        self.assertEqual(conflict["event"], "conflict")
        self.client.resolve("skip")
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertEqual(os.listdir(os.path.join(self.home, "merge")), ["a.txt"])
        with open(os.path.join(self.home, "Documents", "merge", "a.txt")) as handle:
            self.assertEqual(handle.read(), "old-a")
        with open(os.path.join(self.home, "Documents", "merge", "b.txt")) as handle:
            self.assertEqual(handle.read(), "new-b")

    def test_copy_skip_then_replace_conflict(self):
        src = self.make("src.txt", "new")
        dest_dir = os.path.join(self.home, "Documents")
        self.make("Documents/src.txt", "old")
        ident = self.next_id()
        conflict = self.client.run_job(op="copy", id=ident, sources=[src], dest=dest_dir)
        self.assertEqual(conflict["event"], "conflict")
        self.client.resolve("skip")
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        with open(os.path.join(dest_dir, "src.txt")) as handle:
            self.assertEqual(handle.read(), "old")

        ident = self.next_id()
        conflict = self.client.run_job(op="copy", id=ident, sources=[src], dest=dest_dir)
        self.assertEqual(conflict["event"], "conflict")
        self.client.resolve("replace")
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        with open(os.path.join(dest_dir, "src.txt")) as handle:
            self.assertEqual(handle.read(), "new")

    def test_copy_folder_merges(self):
        self.make("folder/one.txt", "1")
        self.make("Documents/folder/two.txt", "2")
        self.make("Documents/folder/one.txt", "old")
        ident = self.next_id()
        conflict = self.client.run_job(op="copy", id=ident, sources=[os.path.join(self.home, "folder")],
                                       dest=os.path.join(self.home, "Documents"))
        self.assertEqual(conflict["event"], "conflict")
        self.client.resolve("replace")
        self.assertTrue(self.client.wait("job", ident)["ok"])
        merged = os.path.join(self.home, "Documents", "folder")
        self.assertEqual(sorted(os.listdir(merged)), ["one.txt", "two.txt"])
        with open(os.path.join(merged, "one.txt")) as handle:
            self.assertEqual(handle.read(), "1")
        with open(os.path.join(merged, "two.txt")) as handle:
            self.assertEqual(handle.read(), "2")

    def test_move_broken_symlink(self):
        link = os.path.join(self.home, "broken")
        os.symlink(os.path.join(self.home, "missing-target"), link)
        dest = os.path.join(self.home, "Documents")
        ident = self.next_id()
        self.client.send(op="move", id=ident, sources=[link], dest=dest)
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        moved = os.path.join(dest, "broken")
        self.assertTrue(os.path.islink(moved))
        self.assertEqual(os.readlink(moved), os.path.join(self.home, "missing-target"))
        self.assertFalse(os.path.lexists(link))

    def test_restore_broken_symlink(self):
        link = os.path.join(self.home, "broken-restore")
        os.symlink(os.path.join(self.home, "missing-target"), link)
        ident = self.next_id()
        self.client.send(op="trash", id=ident, paths=[link])
        self.assertTrue(self.client.wait("job", ident)["ok"])
        item = next(e for e in self.listing(TRASH)["entries"] if e["name"] == "broken-restore")
        ident = self.next_id()
        self.client.send(op="restore", id=ident, paths=[item["path"]])
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertTrue(os.path.islink(link))
        self.assertEqual(os.readlink(link), os.path.join(self.home, "missing-target"))

    def test_move_and_delete(self):
        src = os.path.join(self.home, "note.txt")
        dest = os.path.join(self.home, "Documents")
        ident = self.next_id()
        self.client.send(op="move", id=ident, sources=[src], dest=dest)
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertTrue(os.path.isfile(os.path.join(dest, "note.txt")))
        self.assertFalse(os.path.exists(src))

        ident = self.next_id()
        self.client.send(op="delete", id=ident, paths=[os.path.join(dest, "note.txt")])
        done = self.client.wait("job", ident)
        self.assertTrue(done["ok"], done)
        self.assertFalse(os.path.exists(os.path.join(dest, "note.txt")))

    def test_props(self):
        ident = self.next_id()
        self.client.send(op="props", id=ident, path=os.path.join(self.home, "note.txt"))
        event = self.client.wait("props", ident)
        self.assertIsNone(event["error"])
        self.assertEqual(event["props"]["name"], "note.txt")
        self.assertEqual(event["props"]["size"], 5)
        self.assertIn("rw", event["props"]["permissions"])

    def test_read_text_and_binary(self):
        ident = self.next_id()
        self.client.send(op="read", id=ident, path=os.path.join(self.home, "note.txt"))
        event = self.client.wait("file", ident)
        self.assertIsNone(event["error"])
        self.assertEqual(event["text"], "hello")
        self.assertFalse(event["binary"])

        binary = os.path.join(self.home, "data.bin")
        with open(binary, "wb") as handle:
            handle.write(b"\x00\x01binary\xff")
        ident = self.next_id()
        self.client.send(op="read", id=ident, path=binary)
        event = self.client.wait("file", ident)
        self.assertIsNone(event["error"])
        self.assertTrue(event["binary"])
        self.assertIn("00000000", event["hex"])
        self.assertEqual(event["text"], "")

        ident = self.next_id()
        self.client.send(op="read", id=ident, path=self.home)
        event = self.client.wait("file", ident)
        self.assertIsNotNone(event["error"])

    def test_refuses_dangerous_delete(self):
        ident = self.next_id()
        self.client.send(op="delete", id=ident, paths=["/"])
        done = self.client.wait("job", ident)
        self.assertFalse(done["ok"])
        self.assertTrue(os.path.isdir("/"))


if __name__ == "__main__":
    unittest.main()
