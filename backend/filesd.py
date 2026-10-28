#!/usr/bin/env python3
"""filesd - filesystem backend for the popkenr.files Omarchy plugin.

The QML overlay talks one JSON object per line over stdin/stdout. Listing,
searching and metadata are answered on the main loop; mutating work runs on a
single worker thread so the UI keeps painting and can cancel it.

Standard library only. No shell is involved: every command is a list of
arguments, and paths are handled as paths.
"""

import configparser
import json
import mimetypes
import os
import pwd
import grp
import re
import shutil
import stat
import sys
import tempfile
import threading
import time
import urllib.parse

TRASH_PATH = ":trash:"
COPY_CHUNK = 1024 * 1024
SEARCH_LIMIT = 400
SEARCH_SECONDS = 20
READ_TEXT_LIMIT = 256 * 1024
READ_HEX_LIMIT = 8 * 1024
MUTATING = {"copy", "move", "trash", "delete", "restore", "emptyTrash", "mkdir", "rename"}

IMAGE_EXT = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "avif", "tif", "tiff", "heic", "heif", "ico"}
VIDEO_EXT = {"mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "wmv"}
AUDIO_EXT = {"mp3", "flac", "ogg", "oga", "wav", "m4a", "aac", "opus", "wma"}
ARCHIVE_EXT = {"zip", "tar", "gz", "bz2", "xz", "zst", "7z", "rar", "tgz", "txz", "deb", "rpm"}
DOC_EXT = {"txt", "md", "rst", "doc", "docx", "odt", "rtf", "epub", "org"}
SHEET_EXT = {"xls", "xlsx", "ods", "csv", "tsv"}
SLIDE_EXT = {"ppt", "pptx", "odp"}
CODE_EXT = {"py", "js", "mjs", "ts", "tsx", "jsx", "qml", "sh", "bash", "zsh", "c", "h", "cpp",
            "hpp", "rs", "go", "java", "rb", "php", "lua", "json", "yaml", "yml", "toml", "xml",
            "html", "css", "scss", "sql", "conf", "ini"}
FONT_EXT = {"ttf", "otf", "woff", "woff2"}


# --------------------------------------------------------------------- paths

def home_dir():
    return os.path.expanduser("~")


def data_home():
    value = os.environ.get("XDG_DATA_HOME", "")
    return value if value else os.path.join(home_dir(), ".local", "share")


def config_home():
    value = os.environ.get("XDG_CONFIG_HOME", "")
    return value if value else os.path.join(home_dir(), ".config")


def normalize(path):
    if not isinstance(path, str) or not path:
        raise ValueError("empty path")
    return os.path.abspath(os.path.expanduser(path))


def display_path(path, home=None):
    home = home or home_dir()
    if path == home:
        return "~"
    if path.startswith(home.rstrip("/") + "/"):
        return "~/" + path[len(home.rstrip("/")) + 1:]
    return path


def valid_name(name):
    if not isinstance(name, str):
        return False
    if name in ("", ".", "..") or "/" in name or "\x00" in name:
        return False
    return True


def natural_key(name):
    parts = re.split(r"(\d+)", name.casefold())
    return [(0, int(p)) if p.isdigit() else (1, p) for p in parts]


def kind_for(name, is_dir, path=""):
    if is_dir:
        return "folder"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in IMAGE_EXT:
        return "image"
    if ext in VIDEO_EXT:
        return "video"
    if ext in AUDIO_EXT:
        return "audio"
    if ext == "pdf":
        return "pdf"
    if ext in ARCHIVE_EXT:
        return "archive"
    if ext in DOC_EXT:
        return "document"
    if ext in SHEET_EXT:
        return "sheet"
    if ext in SLIDE_EXT:
        return "slide"
    if ext in CODE_EXT:
        return "code"
    if ext in FONT_EXT:
        return "font"
    if path and os.access(path, os.X_OK):
        return "exec"
    return "file"


def entry_for(full, name=None, parent_label=None):
    try:
        st = os.lstat(full)
    except OSError:
        return None
    is_link = stat.S_ISLNK(st.st_mode)
    try:
        is_dir = os.path.isdir(full)
    except OSError:
        is_dir = False

    item = {
        "name": name if name is not None else os.path.basename(full.rstrip("/")) or "/",
        "path": full,
        "dir": is_dir,
        "link": is_link,
        "hidden": item_hidden(name if name is not None else os.path.basename(full)),
        "size": int(st.st_size),
        "mtime": float(st.st_mtime),
        "kind": kind_for(name or os.path.basename(full), is_dir, full),
    }
    if is_link:
        try:
            item["target"] = os.readlink(full)
        except OSError:
            item["target"] = ""
    if parent_label is not None:
        item["parentLabel"] = parent_label
    return item


def item_hidden(name):
    return bool(name) and name.startswith(".")


def sort_entries(entries):
    entries.sort(key=lambda e: (not e["dir"], natural_key(e["name"])))
    return entries


def hex_dump(data):
    lines = []
    for offset in range(0, len(data), 16):
        chunk = data[offset:offset + 16]
        hex_part = " ".join("%02x" % byte for byte in chunk)
        hex_part = hex_part.ljust(16 * 3 - 1)
        ascii_part = "".join(chr(byte) if 32 <= byte < 127 else "." for byte in chunk)
        lines.append("%08x  %s  %s" % (offset, hex_part, ascii_part))
    return "\n".join(lines)


# --------------------------------------------------------------------- trash

class Trash:
    """Freedesktop home trash. shortcut: only the home trash, no per-volume
    trash; mount-local trashing would need .Trash-$uid on each volume."""

    def __init__(self):
        base = os.path.join(data_home(), "Trash")
        self.files = os.path.join(base, "files")
        self.info = os.path.join(base, "info")

    def ensure(self):
        os.makedirs(self.files, mode=0o700, exist_ok=True)
        os.makedirs(self.info, mode=0o700, exist_ok=True)

    def _unique(self, name):
        candidate = name
        index = 1
        while (os.path.lexists(os.path.join(self.files, candidate))
               or os.path.exists(os.path.join(self.info, candidate + ".trashinfo"))):
            index += 1
            candidate = "%s.%d" % (name, index)
        return candidate

    def put(self, path, progress=None):
        path = normalize(path)
        if path == "/" or path == os.path.abspath(home_dir()):
            raise ValueError("refusing to trash %s" % path)
        if path.startswith(self.files + os.sep) or path == self.files:
            raise ValueError("already in Trash")
        base = os.path.dirname(self.files)
        if path == base or base.startswith(path.rstrip("/") + os.sep):
            raise ValueError("refusing to trash a folder that contains the Trash")
        if not os.path.lexists(path):
            raise FileNotFoundError(path)
        self.ensure()
        name = self._unique(os.path.basename(path.rstrip("/")) or "item")
        info_path = os.path.join(self.info, name + ".trashinfo")
        target = os.path.join(self.files, name)
        quoted = urllib.parse.quote(path, safe="/")
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
        with open(info_path, "w", encoding="utf-8") as handle:
            handle.write("[Trash Info]\nPath=%s\nDeletionDate=%s\n" % (quoted, stamp))
        try:
            if os.stat(os.path.dirname(path)).st_dev == os.stat(self.files).st_dev:
                os.rename(path, target)
            else:
                copy_item(path, target, None, progress)
                remove_item(path)
        except Exception:
            try:
                os.remove(info_path)
            except OSError:
                pass
            raise
        return target

    def list(self):
        self.ensure()
        entries = []
        try:
            names = os.listdir(self.info)
        except OSError:
            return entries
        for info_name in names:
            if not info_name.endswith(".trashinfo"):
                continue
            name = info_name[: -len(".trashinfo")]
            full = os.path.join(self.files, name)
            info_path = os.path.join(self.info, info_name)
            parser = configparser.ConfigParser(interpolation=None)
            try:
                parser.read(info_path, encoding="utf-8")
                original = urllib.parse.unquote(parser.get("Trash Info", "Path"))
                deleted = parser.get("Trash Info", "DeletionDate", fallback="")
            except (OSError, configparser.Error):
                continue
            if not os.path.lexists(full):
                continue
            item = entry_for(full, name=os.path.basename(original.rstrip("/")), parent_label=os.path.dirname(original))
            if item is None:
                continue
            item["restoreTo"] = original
            item["deleted"] = deleted
            item["name"] = os.path.basename(original.rstrip("/")) or name
            entries.append(item)
        entries.sort(key=lambda e: e.get("deleted", ""), reverse=True)
        return entries

    def restore(self, paths):
        restored, errors = 0, []
        for path in paths:
            full = normalize(path)
            info_path = os.path.join(self.info, os.path.basename(full) + ".trashinfo")
            parser = configparser.ConfigParser(interpolation=None)
            try:
                parser.read(info_path, encoding="utf-8")
                original = urllib.parse.unquote(parser.get("Trash Info", "Path"))
                if not original.startswith("/"):
                    raise ValueError("bad original path")
            except Exception:
                errors.append("%s: no usable trash info" % os.path.basename(full))
                continue
            if os.path.lexists(original):
                errors.append("%s: already exists" % original)
                continue
            parent = os.path.dirname(original)
            if not os.path.isdir(parent):
                errors.append("%s: parent folder is gone" % original)
                continue
            try:
                if os.stat(full).st_dev == os.stat(parent).st_dev:
                    os.rename(full, original)
                else:
                    copy_item(full, original, None)
                    remove_item(full)
                os.remove(info_path)
                restored += 1
            except Exception as exc:
                errors.append("%s: %s" % (os.path.basename(full), exc))
        return restored, errors

    def empty(self):
        errors = []
        for directory in (self.files, self.info):
            try:
                for name in os.listdir(directory):
                    target = os.path.join(directory, name)
                    if os.path.isdir(target) and not os.path.islink(target):
                        shutil.rmtree(target)
                    else:
                        os.remove(target)
            except FileNotFoundError:
                pass
            except OSError as exc:
                errors.append(str(exc))
        self.ensure()
        return errors

    def forget(self, path):
        """Drop the .trashinfo beside a trashed item that is being purged."""
        if path.startswith(self.files + os.sep):
            name = os.path.basename(path.rstrip("/"))
            try:
                os.remove(os.path.join(self.info, name + ".trashinfo"))
            except OSError:
                pass


# ---------------------------------------------------------------- file copy

class Cancelled(Exception):
    pass


def remove_item(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.remove(path)


class Job:
    """One mutating operation: conflict prompts, progress, cancel."""

    def __init__(self, server, job_id, action):
        self.server = server
        self.id = job_id
        self.action = action
        self.errors = []
        self.done = 0
        self.last_emit = 0.0
        self.total = 0

    def check(self):
        if self.server.cancel_requested:
            raise Cancelled()

    def progress(self, current):
        self.done += 1
        now = time.monotonic()
        if now - self.last_emit > 0.1 or self.done == 1:
            self.last_emit = now
            self.server.emit({
                "event": "job", "id": self.id, "state": "progress", "action": self.action,
                "current": current, "done": self.done, "total": self.total,
            })

    def error(self, message):
        self.errors.append(message)
        self.server.emit({
            "event": "job", "id": self.id, "state": "error", "action": self.action,
            "message": message,
        })

    def conflict(self, src, dst):
        self.server.emit({
            "event": "conflict", "id": self.id, "src": src, "dst": dst,
            "srcSize": safe_size(src, follow=False), "dstSize": safe_size(dst, follow=False),
            "srcMtime": safe_mtime(src), "dstMtime": safe_mtime(dst),
        })
        choice = self.server.wait_conflict()
        return choice


def safe_size(path, follow=True):
    try:
        return int(os.stat(path).st_size if follow else os.lstat(path).st_size)
    except OSError:
        return 0


def safe_mtime(path):
    try:
        return float(os.lstat(path).st_mtime)
    except OSError:
        return 0.0


def unique_copy_target(directory, name):
    candidate = name
    index = 1
    while os.path.lexists(os.path.join(directory, candidate)):
        index += 1
        stem, dot, ext = name.rpartition(".")
        if dot and stem:
            candidate = "%s (%d).%s" % (stem, index, ext)
        else:
            candidate = "%s (%d)" % (name, index)
    return os.path.join(directory, candidate)


def copy_file(src, dst, job):
    job.check()
    handle, temp = tempfile.mkstemp(prefix=".filesd-", dir=os.path.dirname(dst) or ".")
    os.close(handle)
    try:
        with open(src, "rb") as source, open(temp, "wb") as target:
            while True:
                job.check()
                chunk = source.read(COPY_CHUNK)
                if not chunk:
                    break
                target.write(chunk)
        shutil.copystat(src, temp)
        if os.path.lexists(dst):
            remove_item(dst)
        os.replace(temp, dst)
    except Exception:
        try:
            os.remove(temp)
        except OSError:
            pass
        raise
    job.progress(os.path.basename(src))


def copy_item(src, dst, job, progress=None):
    """Copy one path. `job` may be None for internal copies (trash/restore)."""
    if job is not None:
        job.check()

    if os.path.islink(src):
        link_target = os.readlink(src)
        if os.path.lexists(dst):
            remove_item(dst)
        os.symlink(link_target, dst)
        if job is not None:
            job.progress(os.path.basename(src))
        elif progress:
            progress(os.path.basename(src))
        return

    if os.path.isdir(src):
        os.makedirs(dst, exist_ok=True)
        for name in sorted(os.listdir(src), key=natural_key):
            if job is not None:
                job.check()
            copy_item(os.path.join(src, name), os.path.join(dst, name), job, progress)
        shutil.copystat(src, dst)
        return

    if not os.path.isfile(src):
        raise ValueError("not a regular file: %s" % src)
    copy_file(src, dst, job if job is not None else _NullJob(progress))


class _NullJob:
    def __init__(self, progress):
        self.progress_cb = progress

    def check(self):
        return

    def progress(self, name):
        if self.progress_cb:
            self.progress_cb(name)


def copy_into(src, dest_dir, job, overwrite_never=False):
    name = os.path.basename(src.rstrip("/")) or "item"
    target = os.path.join(dest_dir, name)
    if os.path.abspath(src) == os.path.abspath(target):
        raise ValueError("source and target are the same")
    if os.path.isdir(src) and not os.path.islink(src) and target.startswith(os.path.abspath(src) + os.sep):
        raise ValueError("cannot copy a folder into itself")
    if os.path.lexists(target):
        if overwrite_never:
            target = unique_copy_target(dest_dir, name)
        elif os.path.isdir(src) and not os.path.islink(src) and os.path.isdir(target) and not os.path.islink(target):
            # Merge into the existing folder, prompting only on file clashes.
            for child in sorted(os.listdir(src), key=natural_key):
                copy_into(os.path.join(src, child), target, job)
            shutil.copystat(src, target)
            return True
        else:
            choice = job.conflict(src, target)
            if choice == "skip":
                return False
            if choice != "replace":
                raise Cancelled()
            remove_item(target)
    copy_item(src, target, job)
    return True


# -------------------------------------------------------------------- server

class Server:
    def __init__(self):
        self.write_lock = threading.Lock()
        self.busy = False
        self.cancel_requested = False
        self.closing = False
        self.conflict_event = threading.Event()
        self.conflict_choice = ""

    # io ---------------------------------------------------------------

    def emit(self, obj):
        line = json.dumps(obj, ensure_ascii=True)
        with self.write_lock:
            try:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, OSError):
                self.closing = True

    def wait_conflict(self):
        self.conflict_choice = ""
        self.conflict_event.clear()
        while not self.conflict_event.wait(0.2):
            if self.closing:
                return "abort"
        return self.conflict_choice or "abort"

    # dispatch ---------------------------------------------------------

    def handle(self, command):
        op = command.get("op")
        job_id = command.get("id", 0)

        if op == "ping":
            self.emit({"event": "pong", "id": job_id})
            return
        if op == "resolve":
            self.conflict_choice = str(command.get("choice", "abort"))
            self.conflict_event.set()
            return
        if op == "cancel":
            self.cancel_requested = True
            return
        if op == "quit":
            self.closing = True
            return

        try:
            if op == "places":
                self.emit(self.places_event(job_id))
            elif op == "list":
                self.emit(self.list_event(job_id, command.get("path"), bool(command.get("hidden"))))
            elif op == "search":
                self.emit(self.search_event(job_id, command.get("path"), command.get("query", ""),
                                            bool(command.get("hidden"))))
            elif op == "props":
                self.emit(self.props_event(job_id, command.get("path")))
            elif op == "read":
                self.emit(self.file_event(job_id, command.get("path")))
            elif op in MUTATING:
                if self.busy:
                    self.emit({"event": "error", "id": job_id, "message": "another file operation is running"})
                    return
                self.start_job(job_id, op, command)
            else:
                self.emit({"event": "error", "id": job_id, "message": "unknown command: %s" % op})
        except Exception as exc:
            self.emit({"event": "error", "id": job_id, "message": str(exc)})

    # read-only --------------------------------------------------------

    def places_event(self, job_id):
        home = home_dir()
        folders = [
            ("Home", home, "user-home", "place"),
            ("Desktop", xdg_user_dir("DESKTOP", "Desktop"), "folder-desktop", "place"),
            ("Documents", xdg_user_dir("DOCUMENTS", "Documents"), "folder-documents", "place"),
            ("Downloads", xdg_user_dir("DOWNLOADS", "Downloads"), "folder-download", "place"),
            ("Pictures", xdg_user_dir("PICTURES", "Pictures"), "folder-pictures", "place"),
            ("Music", xdg_user_dir("MUSIC", "Music"), "folder-music", "place"),
            ("Videos", xdg_user_dir("VIDEOS", "Videos"), "folder-videos", "place"),
        ]
        places = []
        for label, path, icon, kind in folders:
            if path and os.path.isdir(path) and (label == "Home" or path != home):
                places.append({"label": label, "path": path, "icon": icon, "kind": kind})
        places.append({"label": "Trash", "path": TRASH_PATH, "icon": "user-trash", "kind": "trash"})
        places.append({"label": "Computer", "path": "/", "icon": "drive-harddisk", "kind": "root"})

        mounts = []
        user = os.path.basename(home)
        for base in ("/run/media/" + user, "/media/" + user):
            try:
                names = sorted(os.listdir(base), key=natural_key)
            except OSError:
                continue
            for name in names:
                full = os.path.join(base, name)
                if os.path.isdir(full):
                    mounts.append({"label": name, "path": full, "icon": "drive-harddisk", "kind": "mount"})
        return {"event": "places", "id": job_id, "home": home, "places": places, "mounts": mounts}

    def list_event(self, job_id, path, hidden):
        if path == TRASH_PATH:
            return {
                "event": "listing", "id": job_id, "path": TRASH_PATH, "displayPath": "Trash",
                "parent": home_dir(), "entries": Trash().list(), "free": 0, "trash": True,
                "error": None, "writable": True,
            }
        try:
            full = normalize(path)
            if not os.path.isdir(full):
                raise NotADirectoryError(path)
            names = os.listdir(full)
            entries = []
            for name in names:
                if not hidden and name.startswith("."):
                    continue
                item = entry_for(os.path.join(full, name), name=name)
                if item is not None:
                    entries.append(item)
            sort_entries(entries)
            try:
                free = int(shutil.disk_usage(full).free)
            except OSError:
                free = 0
            parent = os.path.dirname(full.rstrip("/")) or "/"
            if full == "/":
                parent = "/"
            return {
                "event": "listing", "id": job_id, "path": full,
                "displayPath": display_path(full), "parent": parent,
                "entries": entries, "free": free, "trash": False,
                "error": None, "writable": os.access(full, os.W_OK),
            }
        except Exception as exc:
            return {
                "event": "listing", "id": job_id, "path": path, "displayPath": str(path),
                "parent": home_dir(), "entries": [], "free": 0, "trash": False,
                "error": friendly_error(exc), "writable": False,
            }

    def search_event(self, job_id, path, query, hidden):
        query = str(query or "").strip()
        result = {
            "event": "search", "id": job_id, "path": path, "query": query,
            "entries": [], "truncated": False, "error": None,
        }
        if not query:
            return result
        try:
            root = normalize(path)
            if root == TRASH_PATH:
                root = os.path.join(data_home(), "Trash", "files")
            needle = query.casefold()
            started = time.monotonic()
            entries = []
            for current, dirs, files in os.walk(root, followlinks=False):
                if not hidden:
                    dirs[:] = [d for d in dirs if not d.startswith(".")]
                dirs.sort(key=natural_key)
                for name in sorted(files + dirs, key=natural_key):
                    if not hidden and name.startswith("."):
                        continue
                    if needle not in name.casefold():
                        continue
                    full = os.path.join(current, name)
                    relative = os.path.relpath(current, root)
                    label = "" if relative == "." else display_path(current)
                    item = entry_for(full, name=name, parent_label=label)
                    if item is not None:
                        entries.append(item)
                    if len(entries) >= SEARCH_LIMIT:
                        result["truncated"] = True
                        break
                if result["truncated"] or time.monotonic() - started > SEARCH_SECONDS:
                    result["truncated"] = True
                    break
            result["entries"] = entries
        except Exception as exc:
            result["error"] = friendly_error(exc)
        return result

    def props_event(self, job_id, path):
        try:
            full = normalize(path)
            st = os.lstat(full)
            is_dir = os.path.isdir(full)
            item = {
                "name": os.path.basename(full.rstrip("/")) or "/",
                "path": full,
                "type": "Folder" if is_dir else (mimetypes.guess_type(full)[0] or "File"),
                "kind": kind_for(os.path.basename(full), is_dir, full),
                "size": int(st.st_size),
                "modified": time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime)),
                "permissions": stat.filemode(st.st_mode),
                "owner": owner_name(st.st_uid),
                "group": group_name(st.st_gid),
                "link": stat.S_ISLNK(st.st_mode),
                "target": os.readlink(full) if stat.S_ISLNK(st.st_mode) else "",
                "count": len(os.listdir(full)) if is_dir else -1,
            }
            return {"event": "props", "id": job_id, "props": item, "error": None}
        except Exception as exc:
            return {"event": "props", "id": job_id, "props": None, "error": friendly_error(exc)}

    def file_event(self, job_id, path):
        result = {"event": "file", "id": job_id, "path": path, "name": "", "size": 0,
                  "binary": False, "text": "", "hex": "", "truncated": False, "error": None}
        try:
            full = normalize(path)
            st = os.stat(full)
            if not stat.S_ISREG(st.st_mode):
                raise ValueError("not a regular file")
            with open(full, "rb") as handle:
                data = handle.read(READ_TEXT_LIMIT)
            result["path"] = full
            result["name"] = os.path.basename(full)
            result["size"] = int(st.st_size)
            result["truncated"] = st.st_size > len(data)
            if b"\x00" in data:
                result["binary"] = True
                result["hex"] = hex_dump(data[:READ_HEX_LIMIT])
                result["truncated"] = st.st_size > READ_HEX_LIMIT
            else:
                result["text"] = data.decode("utf-8", "replace")
        except Exception as exc:
            result["error"] = friendly_error(exc)
        return result

    # mutating ---------------------------------------------------------

    def start_job(self, job_id, op, command):
        self.busy = True
        self.cancel_requested = False
        thread = threading.Thread(target=self.run_job, args=(job_id, op, command), daemon=True)
        thread.start()

    def run_job(self, job_id, op, command):
        job = Job(self, job_id, op)
        message = ""
        ok = True
        try:
            self.emit({"event": "job", "id": job_id, "state": "start", "action": op,
                       "total": 0})
            if op == "mkdir":
                message = self.job_mkdir(job, command)
            elif op == "rename":
                message = self.job_rename(job, command)
            elif op == "copy":
                message = self.job_copy(job, command, move=False)
            elif op == "move":
                message = self.job_copy(job, command, move=True)
            elif op == "trash":
                message = self.job_trash(job, command)
            elif op == "delete":
                message = self.job_delete(job, command)
            elif op == "restore":
                message = self.job_restore(job, command)
            elif op == "emptyTrash":
                message = self.job_empty_trash(job)
        except Cancelled:
            ok = False
            message = "cancelled"
        except Exception as exc:
            ok = False
            message = friendly_error(exc)
        finally:
            ok = ok and not job.errors
            self.busy = False
            self.cancel_requested = False
            if self.closing:
                return
            self.emit({
                "event": "job", "id": job_id, "state": "done", "action": op, "ok": ok,
                "message": message if message else ("done" if ok else "failed"),
                "errors": job.errors[:50], "done": job.done,
            })

    def job_mkdir(self, job, command):
        parent = normalize(command.get("path"))
        name = str(command.get("name", ""))
        if not valid_name(name):
            raise ValueError("invalid folder name")
        target = os.path.join(parent, name)
        try:
            os.mkdir(target)
        except FileExistsError:
            raise ValueError("a file with that name already exists")
        return "Folder created"

    def job_rename(self, job, command):
        source = normalize(command.get("path"))
        name = str(command.get("name", ""))
        if not valid_name(name):
            raise ValueError("invalid name")
        target = os.path.join(os.path.dirname(source), name)
        if os.path.abspath(source) == os.path.abspath(target):
            return "Unchanged"
        if os.path.lexists(target):
            raise ValueError("a file with that name already exists")
        os.rename(source, target)
        return "Renamed"

    def job_copy(self, job, command, move):
        sources = [normalize(p) for p in command.get("sources", []) if p]
        dest = normalize(command.get("dest"))
        if not os.path.isdir(dest):
            raise NotADirectoryError(dest)
        if not sources:
            raise ValueError("nothing selected")
        job.total = len(sources)
        copied = 0
        for source in sources:
            if source == "/":
                job.error("refusing to move or copy /")
                continue
            try:
                if move:
                    did = move_into(source, dest, job)
                else:
                    did = copy_into(source, dest, job)
                if did:
                    copied += 1
            except Cancelled:
                raise
            except Exception as exc:
                job.error("%s: %s" % (os.path.basename(source), friendly_error(exc)))
        if job.errors:
            return "%d of %d %s" % (copied, len(sources), "moved" if move else "copied")
        return "%d %s" % (copied, "moved" if move else "copied")

    def job_trash(self, job, command):
        paths = [normalize(p) for p in command.get("paths", []) if p]
        if not paths:
            raise ValueError("nothing selected")
        job.total = len(paths)
        trash = Trash()
        moved = 0
        for path in paths:
            job.check()
            try:
                trash.put(path)
                job.progress(os.path.basename(path.rstrip("/")))
                moved += 1
            except Exception as exc:
                job.error("%s: %s" % (os.path.basename(path.rstrip("/")), friendly_error(exc)))
        if job.errors:
            return "%d of %d moved to Trash" % (moved, len(paths))
        return "%d moved to Trash" % moved

    def job_delete(self, job, command):
        paths = [normalize(p) for p in command.get("paths", []) if p]
        if not paths:
            raise ValueError("nothing selected")
        job.total = len(paths)
        for path in paths:
            job.check()
            if path == "/" or path == home_dir():
                job.error("refusing to delete %s" % path)
                continue
            try:
                remove_item(path)
                Trash().forget(path)
                job.progress(os.path.basename(path.rstrip("/")))
            except Exception as exc:
                job.error("%s: %s" % (os.path.basename(path.rstrip("/")), friendly_error(exc)))
        return "Deleted" if not job.errors else "Some items could not be deleted"

    def job_restore(self, job, command):
        paths = [normalize(p) for p in command.get("paths", []) if p]
        if not paths:
            raise ValueError("nothing selected")
        job.total = len(paths)
        restored, errors = Trash().restore(paths)
        for error in errors:
            job.error(error)
        job.done = restored
        return "Restored %d" % restored if restored else "Nothing restored"

    def job_empty_trash(self, job):
        errors = Trash().empty()
        for error in errors:
            job.error(error)
        return "Trash emptied" if not errors else "Trash not fully emptied"


def move_into(source, dest_dir, job):
    name = os.path.basename(source.rstrip("/")) or "item"
    target = os.path.join(dest_dir, name)
    if os.path.abspath(source) == os.path.abspath(target):
        raise ValueError("source and target are the same")
    if os.path.isdir(source) and not os.path.islink(source) and target.startswith(os.path.abspath(source) + os.sep):
        raise ValueError("cannot move a folder into itself")

    if os.path.lexists(target):
        # Merge folders, prompt for everything else.
        if os.path.isdir(source) and os.path.isdir(target) and not os.path.islink(target):
            for name in sorted(os.listdir(source), key=natural_key):
                move_into(os.path.join(source, name), target, job)
            try:
                os.rmdir(source)
            except OSError:
                # A skipped conflict leaves its source behind; that is the
                # outcome the user asked for, not a failed move.
                pass
            return not os.path.lexists(source)
        choice = job.conflict(source, target)
        if choice == "skip":
            return False
        if choice != "replace":
            raise Cancelled()
        remove_item(target)

    try:
        if os.stat(source).st_dev == os.stat(dest_dir).st_dev:
            os.rename(source, target)
        else:
            copy_item(source, target, job)
            remove_item(source)
        job.progress(os.path.basename(source.rstrip("/")))
    except OSError as exc:
        if exc.errno == 18:  # EXDEV, different filesystem despite the check
            copy_item(source, target, job)
            remove_item(source)
            job.progress(os.path.basename(source.rstrip("/")))
        else:
            raise
    return True


# --------------------------------------------------------------------- misc

def xdg_user_dir(key, fallback):
    path = os.path.join(config_home(), "user-dirs.dirs")
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line.startswith("XDG_" + key + "_DIR="):
                    continue
                value = line.split("=", 1)[1].strip().strip('"')
                value = value.replace("$HOME", home_dir())
                return os.path.abspath(value)
    except OSError:
        pass
    return os.path.join(home_dir(), fallback)


def owner_name(uid):
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def group_name(gid):
    try:
        return grp.getgrgid(gid).gr_name
    except KeyError:
        return str(gid)


def friendly_error(exc):
    if isinstance(exc, PermissionError):
        return "Permission denied"
    if isinstance(exc, FileNotFoundError):
        return "No such file or folder"
    if isinstance(exc, FileExistsError):
        return "Already exists"
    text = str(exc)
    if isinstance(exc, OSError) and exc.strerror:
        text = exc.strerror
    return text or exc.__class__.__name__


def main():
    server = Server()
    server.emit({"event": "ready", "version": 1, "home": home_dir(), "trash": TRASH_PATH})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                command = json.loads(line)
            except ValueError:
                server.emit({"event": "error", "id": 0, "message": "invalid JSON"})
                continue
            if not isinstance(command, dict):
                server.emit({"event": "error", "id": 0, "message": "invalid command"})
                continue
            try:
                server.handle(command)
            except Exception as exc:
                server.emit({"event": "error", "id": command.get("id", 0), "message": str(exc)})
            if server.closing:
                break
    except KeyboardInterrupt:
        pass
    finally:
        server.closing = True
        server.conflict_event.set()


if __name__ == "__main__":
    main()
