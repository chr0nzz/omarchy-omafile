# Omafile helper protocol

`bin/omafile-helper` is a long-running Python 3 process. The shell plugin spawns one
instance and speaks newline-delimited JSON over stdin and stdout. Every line is a
complete JSON object. The helper never writes a partial line and never writes anything
to stdout that is not a response. Diagnostics go to stderr.

## Framing

A request is one JSON object per line:

```
{"id": 17, "op": "list", "path": "/etc", "hidden": false}
```

`id` is a positive integer chosen by the caller and unique among in-flight requests.
Every response echoes it. `op` names the operation.

A response is one JSON object per line with `id` and `t` (type):

```
{"id": 17, "t": "entries", "c": [["hosts","f",221,1757400000,33188,null]]}
{"id": 17, "t": "done", "total": 184}
```

Response types: `entries`, `done`, `error`, `progress`, `conflict`, `changed`, `hit`,
`stat`, `du`, `space`, `drives`, `dirs`, `trash`, `thumb`, `thumbtypes`.

A streaming operation emits zero or more intermediate responses and exactly one
terminal response, which is either `done` or `error`. A non-streaming operation emits
exactly one `done` or `error`.

## Error shape

```
{"id": 17, "t": "error", "code": "EACCES", "message": "Permission denied", "path": "/root"}
```

`code` is the errno name where one applies, otherwise one of `EINVAL`, `ECANCELED`,
`EUNSUPPORTED`, `EINTERNAL`.

## Entry encoding

Directory entries are positional arrays, not objects, because a large directory sends
hundreds of thousands of them and object keys dominate both transfer size and parse
time.

```
[name, kind, size, mtime, mode, linkTarget]
```

| Field | Type | Notes |
|---|---|---|
| `name` | string | basename only, never a path |
| `kind` | string | `d` directory, `f` regular file, `L` symlink to directory, `l` symlink to file, `b` broken symlink, `o` other (fifo, socket, device) |
| `size` | int | bytes, `0` for directories, target size for a symlink |
| `mtime` | int | unix seconds |
| `mode` | int | st_mode as an integer |
| `linkTarget` | string or null | only set when kind is `L`, `l` or `b` |

Names that are not valid UTF-8 are decoded with `surrogateescape` and re-encoded for
JSON with `\udcXX` escapes. The helper accepts the same encoding on input and restores
the original bytes before touching the filesystem. A path is never passed through a
shell.

## Operations

### list

```
{"id": N, "op": "list", "path": "/some/dir", "hidden": false, "chunk": 500}
```

Streams `{"t": "entries", "c": [...]}` in chunks of at most `chunk` entries, then
`{"t": "done", "total": <int>}`. Symlinks are not followed for the stat. `hidden`
defaults to `false` and controls dotfiles only.

### watch, unwatch

```
{"id": N, "op": "watch", "path": "/some/dir"}
{"id": N, "op": "unwatch", "path": "/some/dir"}
```

`watch` is a long-lived subscription that emits
`{"t": "changed", "path": "/some/dir", "names": ["a", "b"]}` whenever the directory
content changes. Events are coalesced over a 120ms window so a large extraction does
not flood the shell. `names` may be empty, meaning the caller should relist. Watching
uses inotify through ctypes and falls back to a 2 second scandir poll when inotify is
unavailable. `unwatch` ends the subscription and replies `done` on the watch's own id.

### stat

```
{"id": N, "op": "stat", "paths": ["/a", "/b"]}
```

Replies `{"t": "stat", "items": [{...}]}` then `done`. Each item carries `path`,
`name`, `kind`, `size`, `mtime`, `atime`, `ctime`, `mode`, `uid`, `gid`, `owner`,
`group`, `nlink`, `disk`, `inode`, `dev`, `mime`, `linkTarget`. A path that cannot be stat'd
yields an item with `error` set instead of the metadata fields.

### identity

```
{"id": N, "op": "identity"}
```

Replies `{"t": "identity", "uid", "user", "groups": [...], "root"}` then `done`. `groups` are the groups the caller belongs to. When the helper runs as root, `users` lists every account and `groups` every group.

### opener

```
{"id": N, "op": "opener", "path": "/a"}
```

Replies `{"t": "opener", "mime", "handler"}` then `done`. `mime` is the type `gio info` reports, the same one `gio open` uses, and `handler` is the desktop file id `gio mime` reports as its default, or empty. `path` must be absolute.

### setopener

```
{"id": N, "op": "setopener", "mime": "text/plain", "handler": "app.desktop"}
```

Makes `handler` the default for `mime` through `gio mime`. `inode/directory` is refused, so Omafile's own folder handler is only changed by Default file manager.

### chmod

```
{"id": N, "op": "chmod", "path": "/a", "set": 420, "clear": 18, "recursive": false}
```

Adds the `set` bits and removes the `clear` bits from the permission bits of `path`, and of everything under it when `recursive`. Symlinks are skipped and never followed: each item is opened with `O_NOFOLLOW` and changed through that handle. Replies `done` with `changed`.

### chown

```
{"id": N, "op": "chown", "path": "/a", "owner": "name", "group": "name", "recursive": false}
```

`owner` and `group` are optional but one is required. Names or numeric ids. Symlinks are not followed. Replies `done` with `changed`, or `EPERM` when the caller may not make the change.

### du

```
{"id": N, "op": "du", "path": "/some/dir"}
```

Streams `{"t": "du", "bytes": B, "files": F, "dirs": D, "partial": true}` at most four
times per second, then a final response with `"partial": false`, then `done`.

### copy, move

```
{"id": N, "op": "copy", "sources": ["/a/x"], "dest": "/b", "conflict": "ask"}
```

`conflict` is `ask`, `overwrite`, `skip` or `rename`. Streams
`{"t": "progress", "bytes": B, "total": T, "files": F, "filesTotal": FT, "current": "/a/x", "rate": R}`
at most ten times per second.

With `conflict: "ask"`, on a collision the helper emits
`{"t": "conflict", "source": "/a/x", "dest": "/b/x", "destKind": "f", "destSize": S, "destMtime": M}`
and pauses that job until the caller sends:

```
{"id": N, "op": "resolve", "action": "overwrite", "applyAll": false}
```

`action` is `overwrite`, `skip`, `rename` or `cancel`. Terminal response is
`{"t": "done", "copied": C, "skipped": S, "errors": [{"path": P, "message": M}]}`.

`move` renames within a filesystem and falls back to copy then unlink across
filesystems. It never calls `os.rename` blindly across devices. Copy preserves mode and
timestamps and uses `os.copy_file_range` with a `shutil.copyfileobj` fallback.

A source that is the destination itself, such as a paste back into the same folder,
never goes through `conflict`: `copy` writes a renamed copy beside it and `move` skips it.

### clipset, clipget, clipclear

```
{"id": N, "op": "clipset", "mode": "copy", "paths": ["/a/x"]}
{"id": N, "op": "clipget"}
{"id": N, "op": "clipclear"}
```

The system clipboard, through `wl-copy` and `wl-paste`. `clipset` with `mode: "copy"`
offers `text/uri-list`; `mode: "cut"` offers `x-special/gnome-copied-files`, which GNOME
Files reads as a move. `clipget` replies `done` with `mode` (`copy` or `cut`) and `paths`,
read from either type, and an empty `paths` when the clipboard holds no files.
The `image` field names an available image MIME type when there are no files, or is empty.
`clipclear` always replies `done`. A missing `wl-copy` or `wl-paste` is `EUNSUPPORTED`.

### samedev

```
{"id": N, "op": "samedev", "path": "/a/x", "dest": "/b"}
```

Replies `done` with `same`, whether both are on one filesystem. A drop moves when they
are and copies when they are not.

### trash, delete, restore

```
{"id": N, "op": "trash", "paths": ["/a/x"]}
{"id": N, "op": "delete", "paths": ["/a/x"]}
{"id": N, "op": "restore", "items": ["x.trashinfo"]}
```

`trash` implements the freedesktop trash specification directly: `$XDG_DATA_HOME/Trash`
with `files/` and `info/`, a `DeletionDate` in local time, `%`-encoded paths in
`Path=`, and de-duplicated names. Files on another filesystem go to that volume's
`.Trash-$uid/`. `delete` is permanent and the plugin only sends it after an explicit
confirmation. Deleting an item that sits directly in a trash `files/` directory also removes
its `.trashinfo`, so the trash count stays right. Both reply `{"t": "done", "results": [{"path": P, "ok": true}]}`. A successful `trash`
result also carries `trashinfo`, the name of the `.trashinfo` entry it created, so the
caller can hand that exact name back to `restore` and undo the deletion.

### trashinfo, emptytrash

```
{"id": N, "op": "trashinfo"}
{"id": N, "op": "emptytrash"}
```

`trashinfo` replies `{"t": "trash", "count": C, "bytes": B, "items": [...], "infoDirs": [...]}`
where each item is `{"name", "original", "deleted", "size", "kind"}`. The count comes from
the `.trashinfo` entries, not the files, so `infoDirs` lists the directories to `watch` to
be told when the trash changes. There is one per trash root, so a removable drive with its
own trash adds an entry and the list changes when that drive is mounted or unmounted.
`emptytrash` clears every trash directory it knows about and replies `done`.

### baricon, barsettings

```
{"id": N, "op": "baricon", "action": "status" | "add" | "remove"}
{"id": N, "op": "barsettings", "settings": {"showHidden": true}}
```

Both edit `~/.config/omarchy/shell.json`, which the shell reloads on its own.

`baricon` replies `{"t": "baricon", "present": P, "trashIcon": T, "count": C}`, plus
`"changed"` for `add` and `remove`. `add` inserts `{"id": "xyzlab.omafile", "mode":
"trash", "trashConfirm": true}` directly after the existing Omafile entry, or at the end
of the last bar section when there is none. `remove` deletes every Omafile entry whose
mode is `trash`. Both are idempotent.

`barsettings` merges `settings` into the Omafile bar entries and replies
`{"t": "barsettings", "changed": B}`. It never writes `id` or `mode`, so a trash entry
cannot be turned back into a file manager entry by a settings change. Entries in trash
mode only accept the keys in `TRASH_ENTRY_KEYS`, currently `trashConfirm`; everything else
lands on the file manager entry alone. This exists because the shell's own
`updateEntryInline` rewrites every entry sharing a plugin id with the same object, which
erases the trash entry's mode.

Writes go to a temporary file in the same directory and are renamed into place, so a
partial write cannot leave the shell without a config.

### mkdir, mkfile, rename, symlink

```
{"id": N, "op": "mkdir", "path": "/a/new"}
{"id": N, "op": "mkfile", "path": "/a/new.txt"}
{"id": N, "op": "rename", "path": "/a/old", "newName": "new"}
{"id": N, "op": "symlink", "target": "/a/x", "path": "/b/x"}
```

Each replies `done` with the resulting `path`, or `error`. `rename` refuses a `newName`
containing a path separator.

### search

```
{"id": N, "op": "search", "root": "/home/u", "query": "report",
 "mode": "substring", "maxResults": 2000, "maxDepth": 12, "hidden": false}
```

`mode` is `substring`, `glob` or `regex`. Streams
`{"t": "hit", "path": P, "name": N, "dir": D, "kind": K, "size": S, "mtime": M}` and
ends with `{"t": "done", "truncated": bool, "scanned": int}`. Skips `.git`, and does not
cross filesystem boundaries or follow symlinked directories.

### peek

```
{"id": N, "op": "peek", "path": "/a/config.yml", "limit": 262144}
```

Replies `{"t": "peek", "text": S, "binary": B, "truncated": T, "size": N}` then `done`.
Reads at most `limit` bytes, capped at 256 KB, for the preview. A file with a NUL byte
in its first 8 KB, or one that is mostly not UTF-8, comes back with `binary: true` and
empty `text`. A directory fails with `EISDIR`.

### thumb

```
{"id": N, "op": "thumb", "path": "/home/me/Videos/clip.mp4", "size": "large"}
```

Replies `{"t": "thumb", "thumb": "/home/me/.cache/thumbnails/large/<md5>.png"}` then
`done`. Cancellable. `size` is one of `large` (256 px, the default), `x-large` (512) or
`xx-large` (1024). The cache follows the freedesktop Thumbnail Managing Standard, so
thumbnails made by GNOME Files and other file managers are reused and theirs reuse ours.
A cached thumbnail counts only when its `Thumb::URI` and `Thumb::MTime` match the file;
the requested size and every larger one are tried.

On a miss the helper runs the system thumbnailer registered for the file's MIME type in
`thumbnailers/*.thumbnailer` under `$XDG_DATA_HOME` and `$XDG_DATA_DIRS`, such as
ffmpegthumbnailer for video or evince-thumbnailer for PDF. At most two run at once, each
at a lower priority and for at most 20 seconds, never through a shell. A thumbnailer
that fails leaves a marker in `fail/omafile-<version>/`, and a failure recorded there by
any app is not retried until the file changes. Files without a thumbnailer, earlier
failures and files inside the thumbnail cache fail with `EUNSUPPORTED`. A relative path
fails with `EINVAL`.

### thumbtypes

```
{"id": N, "op": "thumbtypes"}
```

Replies `{"t": "thumbtypes", "exts": ["avi", "mkv", "mp4", "pdf", ...]}` then `done`:
the lowercase file extensions some installed thumbnailer can handle.

### bookmarks, setbookmarks

```
{"id": N, "op": "bookmarks"}
{"id": N, "op": "setbookmarks", "items": [{"path": "/home/me/Projects", "label": "Work"}]}
```

`bookmarks` replies `{"t": "bookmarks", "items": [{"path": P, "label": L}], "file": F, "dir": D}`
then `done`, reading the GTK bookmarks file `$XDG_CONFIG_HOME/gtk-3.0/bookmarks` that GNOME Files
and the file chooser share. Only local `file://` entries are returned. `setbookmarks` rewrites the
file atomically with the given folders in order, and keeps every line it does not manage, such as
`sftp://` bookmarks, after them.

### counts

```
{"id": N, "op": "counts", "paths": ["/home/me/Music", "/home/me/Videos"], "hidden": false}
```

Cancellable. Replies `{"t": "counts", "counts": {"/home/me/Music": 12, ...}, "limit": 100000}` then
`done`: how many entries each folder holds, for grid captions. Dotfiles count only when `hidden`
is true, a folder that cannot be read counts as `-1`, and counting stops at `limit`. At most 500
paths are counted per request.

### freespace

```
{"id": N, "op": "freespace", "path": "/home"}
```

Replies `{"t": "space", "total": T, "free": F, "used": U, "mount": M}` then `done`.

### drives

```
{"id": N, "op": "drives"}
```

Replies `{"t": "drives", "drives": [{"name", "path", "label", "size", "fstype", "mount", "removable", "free", "total", "mountable"}]}`
then `done`. Sourced from `lsblk -J -b -o ...` and `findmnt -J -b`. Both tools are part
of util-linux and are always present. A missing tool yields an empty list, never an
error. `mountable` is true for an unmounted partition with a filesystem udisks can mount.
Swap, LUKS, LVM and RAID members, and EFI, BIOS boot, Microsoft reserved and Windows
recovery partitions are never mountable.

### mountdev, unmountdev

```
{"id": N, "op": "mountdev", "device": "/dev/sdb1"}
{"id": N, "op": "unmountdev", "device": "/dev/sdb1"}
```

Runs `udisksctl mount -b` or `udisksctl unmount -b`. `device` must be a path under `/dev/`.
`mountdev` replies `done` with `path`, the new mount point. Errors: `EINVAL` for a bad
device, `EUNSUPPORTED` without udisksctl, `ETIMEDOUT`, and `EMOUNT` with udisks' message.

### extract

```
{"id": N, "op": "extract", "path": "/home/me/Downloads/photos.zip"}
```

Cancellable. Extracts the archive into a temporary folder next to it with `bsdtar -xf`,
then moves the result into place. A single
top-level item lands next to the archive as is; several go into a new folder named after
the archive without its suffix. Clashing names get ` (1)`, ` (2)` and so on. Replies `done`
with `path`, the extracted item or folder. bsdtar keeps entries inside the folder: absolute
paths and `..` are refused. Errors: `EINVAL` when `path` is not a file, `EUNSUPPORTED`
without bsdtar, `ECANCELED`, and `EFAIL` with the tool's message. The temporary folder is
removed on failure.

### dirs

```
{"id": N, "op": "dirs"}
```

Replies `{"t": "dirs", "dirs": {"desktop": P, "documents": P, "downloads": P, "music": P, "pictures": P, "videos": P, "templates": P, "publicshare": P}}`
then `done`. Parsed from `~/.config/user-dirs.dirs`, falling back to the XDG defaults.
A directory that does not exist is omitted.

### cancel

```
{"id": N, "op": "cancel", "target": M}
```

Cancels in-flight request `M`. The cancelled request terminates with
`{"t": "error", "code": "ECANCELED"}`. Replies `done` on its own id.

### ping

```
{"id": N, "op": "ping"}
```

Replies `{"t": "done", "version": "1.0.0", "pid": <int>, "inotify": true}`.

## Concurrency

The helper serves requests concurrently on worker threads. Listing, searching, du and
transfers each run on their own thread so a slow network mount never blocks the bar.
Writes to stdout are serialized behind a single lock so lines never interleave.

## Safety

The helper runs with the invoking user's permissions and never escalates. It contains
no `sudo`, no `pkexec`, no shell invocation, no network access and no third-party
imports. Every subprocess it does spawn is a fixed argv list of a trusted system tool, such as util-linux, udisksctl or bsdtar.

### clipimage

```
{"id": N, "op": "clipimage", "dest": "/a", "type": "image/png"}
```

Saves clipboard image bytes under a unique `Pasted image` name in `dest`. Replies
`clipimage` with `path`, then `done`. Accepts PNG, JPEG, WebP, GIF and BMP MIME types.
