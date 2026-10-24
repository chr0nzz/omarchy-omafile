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
Every response echoes it. `op` names the operation. A cancellable request whose `id` is
already running is refused with `EBUSY`, and a request that cannot get a worker thread
fails with `EAGAIN`. Lines are read as raw bytes, so one bad line never stops the helper.

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
`EUNSUPPORTED`, `EINTERNAL`, `EFAIL`.

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
the original bytes before touching the filesystem. Qt's `JSON.stringify` writes a lone
surrogate raw, so the shell escapes them before sending a line; the helper also decodes
raw UTF-8 encoded surrogates with `surrogatepass`. A path is never passed through a
shell.

## Path safety

Every operation on a single item opens the parent folder one component at a time with
`O_PATH | O_NOFOLLOW` and then works relative to that handle. A symlinked folder on the
way is followed only when it is owned by the user or root and lives on a local
filesystem that is not a network or FUSE filesystem, not under `/mnt`, `/media` or
`/run/media`, and not in GVFS. Anything else fails with `ELOOP`. The last component must
be a plain name, never `.` or `..`.

## Operations

### list

```
{"id": N, "op": "list", "path": "/some/dir", "hidden": false, "chunk": 500}
```

Streams `{"t": "entries", "c": [...]}` in chunks of at most `chunk` entries, then
`{"t": "done", "total": <int>, "real": <path>}`. `real` is the folder's canonical path.
A folder with more than 200,000 entries stops there and adds `"truncated": true`.
Symlinks are not followed for the stat, and a symlink to anything other than a folder or
a regular file is reported as `o`. `hidden` defaults to `false` and controls dotfiles only.
Entries under the GVFS mount (`$XDG_RUNTIME_DIR/gvfs/…`, for example
`smb-share:server=…,share=…`) are listed from the directory entry alone: `size`
and `mtime` are `0` and the link target is `null`, because a per-entry stat would
cost a round trip per file on a network share. The shell stats items on demand.

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
unavailable. On GVFS paths the poll compares names only (no per-entry stat), so a
file modified in place does not emit an event until it is renamed or replaced.
`unwatch` ends the subscription and replies `done` on the watch's own id.

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

Adds the `set` bits and removes the `clear` bits from the permission bits of `path`, and of everything under it when `recursive`. Symlinks are skipped and never followed: the tree is walked with `os.fwalk` through folder handles, and each item is opened with `O_NOFOLLOW` and changed through that handle. Replies `done` with `changed`.

### chown

```
{"id": N, "op": "chown", "path": "/a", "owner": "name", "group": "name", "recursive": false}
```

`owner` and `group` are optional but one is required. Names or numeric ids. Symlinks are not followed, and the tree is walked through folder handles. Replies `done` with `changed`, or `EPERM` when the caller may not make the change.

### du

```
{"id": N, "op": "du", "path": "/some/dir"}
```

Streams `{"t": "du", "bytes": B, "files": F, "dirs": D, "partial": true}` at most four
times per second, then a final response with `"partial": false`, then `done`. Stays on
the starting filesystem, counts each folder once, and stops 256 levels deep. Cancellable;
the shell cancels it when Properties closes.

### copy, move

```
{"id": N, "op": "copy", "sources": ["/a/x"], "dest": "/b", "conflict": "ask"}
```

`conflict` is `ask`, `overwrite`, `skip` or `rename`. Streams
`{"t": "progress", "bytes": B, "total": T, "files": F, "filesTotal": FT, "current": "/a/x", "rate": R}`
at most ten times per second.

With `conflict: "ask"`, on a collision the helper emits
`{"t": "conflict", "source": "/a/x", "dest": "/b/x", "destKind": "f", "destSize": S, "destMtime": M, "seq": Q}`
and pauses that job until the caller sends:

```
{"id": N, "op": "resolve", "action": "overwrite", "applyAll": false, "seq": Q}
```

`action` is `overwrite`, `skip`, `rename` or `cancel`; anything else is treated as
`cancel`. A `resolve` without the matching `seq`, or a second answer to the same
conflict, is ignored. Terminal response is
`{"t": "done", "copied": C, "skipped": S, "errors": [{"path": P, "message": M}], "created": [{"source": S, "path": P}]}`.
`created` lists each top-level item the job actually placed and where, after any
renaming. Merged folders and skipped items are left out, so undo can act on exactly
what the job made.

Overwriting a file writes a `.omafile-part-*` temporary file next to it and renames it
over the old one only when the copy is complete. Without overwrite, names are placed
with `renameat2(RENAME_NOREPLACE)`, so an existing file is never replaced. The
destination folder is opened safely and checked to be the folder that was looked at,
and a source whose name is `.` or `..` is refused.

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
Every read has a 3 second limit. A file list over 1 MB or 20,000 paths fails with `E2BIG`.

### cliptext

```
{"id": N, "op": "cliptext"}
```

Replies `done` with `text`, the clipboard's plain text, for pasting into a text field.
At most 64 KB, or `limit` bytes up to 1 MB when given, which the text editor uses; more
fails with `E2BIG`. Text fields never read the clipboard through
Qt, so this is the only path clipboard text takes into the shell.

### readtext, writetext

```
{"id": N, "op": "readtext", "path": "/home/me/.bashrc"}
{"id": N, "op": "writetext", "path": P, "text": T, "expect": {"ino", "dev", "mtimeNs", "size"}, "force": false, "crlf": false, "bom": false}
```

`readtext` follows links to the real file, opens it with `O_NOFOLLOW` through a safe parent
handle, and replies `{"t": "text", "text", "path", "crlf", "bom", "writable", "ino", "dev",
"mtimeNs", "size"}` then `done`. `path` is the real file. Windows line endings become `\n`, with
`crlf` true when most lines had them, and a UTF-8 byte order mark is removed and reported in `bom`.
`ino`, `dev` and `mtimeNs` are strings. Errors: `EINVAL` for anything but a regular file,
`EFBIG` over 1 MB, `ELONGLINE` for a line over 20,000 characters, and `EBINARY` for a file with a NUL
byte, that is not UTF-8, or that has a carriage return outside a Windows line ending.

`writetext` saves `text` as UTF-8 to `path`, turning `\n` back into `\r\n` when `crlf` is set and
adding the byte order mark when `bom` is set. Unless `force` is set, the file must still be the
one `expect` describes, or it fails with `ECONFLICT` and `message` `changed` or `deleted`. A file
you own with one link is replaced: the text goes to a new temporary file in the same folder with
the old permissions and group, is synced, and is renamed over the old one. A file with more links, or one you
do not own, is overwritten in place. A link or anything else that is not a regular file is
refused with `EINVAL`, even with `force`. Replies `done` with the new `ino`, `dev`, `mtimeNs` and
`size`. Text over 8 MB, or text that cannot be UTF-8, fails with `EFBIG` or `EINVAL`.

### duplicates

```
{"id": N, "op": "duplicates", "root": "/home/me", "path": "/home/me/photo.jpg", "hidden": false}
```

Cancellable. Walks `root` without following links or leaving its drive, skipping the trash, and
hidden files and folders unless `hidden` is set. With `path`, it finds copies of that file;
without it, every group of identical files. Files are compared by size, then by a BLAKE2 hash of
their first and last 64 KB, then by a hash of every byte, each read with `O_NOFOLLOW`. Empty files
never match, and hard links to one file count once. Emits `{"t": "progress", "phase", "files",
"current", "done", "total"}` with `phase` `looking` or `comparing` about three times a second.
Replies `done` with `groups`, each `{"size", "items": [{"path", "mtime", "size"}]}`, the picked
file first or else oldest first, groups with the most space to free first, plus `scanned` and
`truncated`, which is set after 300,000 candidate files or 2,000 groups. Errors: `EINVAL`, for
example for an empty `path`, `ENOTDIR`, and `ECANCELED`.

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

`trash`, `delete` and `restore` open folders as described in Path safety.
`trash` implements the freedesktop trash specification directly: `$XDG_DATA_HOME/Trash`
with `files/` and `info/`, a `DeletionDate` in local time, `%`-encoded paths in
`Path=`, and de-duplicated names. Files on another filesystem go to that volume's
`.Trash-$uid/`. `delete` is permanent and the plugin only sends it after an explicit
confirmation. Deleting an item that sits directly in a trash `files/` directory also removes
its `.trashinfo`, so the trash count stays right. Both reply `{"t": "done", "results": [{"path": P, "ok": true}]}`. A successful `trash`
result also carries `trashinfo`, the name of the `.trashinfo` entry it created, so the
caller can hand that exact name back to `restore` and undo the deletion. `restore`
never replaces a file that is back at the original path (`EEXIST`), recreates missing
parent folders safely, and refuses a `Path=` with `..`, or one outside the drive for a
drive's trash, as `invalid trashinfo`. Its results carry the restored path.

### trashinfo, emptytrash

```
{"id": N, "op": "trashinfo"}
{"id": N, "op": "emptytrash"}
```

`trashinfo` replies `{"t": "trash", "count": C, "bytes": B, "infoDirs": [...]}`. With
`"items": true` it also sends `items`, at most 5,000, where each item is
`{"name", "original", "deleted", "size", "kind"}`; the shell does not ask for them. The count comes from
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
that is not a plain name (`EINVAL`) and never replaces an existing item (`EEXIST`).

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
empty `text`. A directory fails with `EISDIR`, and anything that is not a regular file,
such as a pipe or a device, fails with `EINVAL` without being read.

### thumb

```
{"id": N, "op": "thumb", "path": "/home/me/Videos/clip.mp4", "size": "large"}
```

Replies `{"t": "thumb", "thumb": "/home/me/.cache/thumbnails/large/<md5>.png"}` then
`done`. Cancellable. `size` is one of `large` (256 px, the default), `x-large` (512),
`xx-large` (1024), `preview-2048`, `preview-4096` or `preview-7680`. The `preview-` sizes are not part
of the standard: they are made by the same thumbnailer with up to 90 seconds instead of 20,
checked the same way with their own size limit, and kept in
`$XDG_CACHE_HOME/omafile/previews/<size>`. That cache keeps the newest 2 GB or 500 files across all
sizes, a hit counts as new, and it is never thumbnailed itself. Thumbnails are read and copied a
chunk at a time, so the helper never holds a whole large preview in memory. The cache follows the freedesktop Thumbnail Managing Standard, so
thumbnails made by GNOME Files and other file managers are reused and theirs reuse ours.
A cached thumbnail counts only when its `Thumb::URI` and `Thumb::MTime` match the file,
it is no larger than 1024 px on either side, and it holds nothing but pixel chunks
(`IHDR`, `PLTE`, `tRNS`, `IDAT`, `IEND`, `gAMA`, `sRGB`, `cHRM`, `sBIT`) plus at most 16 KB of
`tEXt`; the requested size and every larger one are tried. Thumbnails the helper writes
keep only those pixel chunks from the thumbnailer's output and add the `Thumb::` fields, so
the shell never decodes metadata from a file it was shown. The shell shows images, including
the full preview, only through this operation.

On a miss the helper runs the system thumbnailer registered for the file's MIME type in
`thumbnailers/*.thumbnailer` under `$XDG_DATA_HOME` and `$XDG_DATA_DIRS`, such as
ffmpegthumbnailer for video or evince-thumbnailer for PDF. At most two run at once, each
at a lower priority and for at most 20 seconds, never through a shell. A thumbnailer
that fails leaves a marker in `fail/omafile-<version>/`, and a failure recorded there by
any app is not retried until the file changes. Files without a thumbnailer, earlier
failures and files inside the thumbnail cache fail with `EUNSUPPORTED`. A relative path
fails with `EINVAL`.

### audiopreview

```
{"id": N, "op": "audiopreview", "path": "/home/me/Music/song.mp3"}
```

Cancellable. Makes a copy of the first audio stream for the shell to play, so the shell's
media player never parses the original file. Runs `ffprobe` for the `title`, `artist`,
`album_artist` and `album` tags, each cut to 256 characters, and `ffmpeg -map 0:a:0 -c copy
-map_metadata -1 -map_chapters -1` into a Matroska file in `$XDG_CACHE_HOME/omafile/preview`,
mode 0600, with the source passed as an open handle. Cover art, other streams, chapters and
tags are dropped. Replies `done` with `path`, `title`, `artist` and `album`. Only the two most
recent copies are kept. Errors: `EINVAL` for anything that is not a regular file, `EFBIG` over
1 GB, `EUNSUPPORTED` without ffmpeg, `ETIMEDOUT` after 90 seconds, `ECANCELED`, and `EFAIL`.

### thumbtypes

```
{"id": N, "op": "thumbtypes"}
```

Replies `{"t": "thumbtypes", "exts": ["avi", "mkv", "mp4", "pdf", ...]}` then `done`:
the lowercase file extensions some installed thumbnailer can handle.

### defaults

```
{"id": N, "op": "defaults", "names": ["code", "nvim", "~/.local/bin/omp"]}
```

Replies `{"t": "defaults", "editor": E, "agent": A, "agentFound": B, "found": {name: B}}` then `done`.
`editor` is Omarchy's default editor from `~/.local/state/omarchy/defaults/editor`, or `nvim`
like `omarchy default editor`. `agent` is Omarchy's default agent from
`~/.config/omarchy/defaults/agent`, or empty. Either is used only when its first line is a plain
program name. `found` says, for each of up to 64 `names`, whether that program exists: a plain
name is looked up on the helper's `PATH`, an absolute or `~/` path must be an executable regular
file, and anything else is not found. Nothing is run. Errors: `EINVAL` for a bad `names`.

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

Replies `{"t": "drives", "drives": [{"name", "path", "label", "size", "fstype", "mount", "removable", "free", "total", "mountable", "locked"}]}`
then `done`. Sourced from `lsblk -J -b -o ...` and `findmnt -J -b`. Both tools are part
of util-linux and are always present. A missing tool yields an empty list, never an
error. `mountable` is true for an unmounted partition with a filesystem udisks can mount.
Swap, LUKS, LVM and RAID members, and EFI, BIOS boot, Microsoft reserved and Windows
recovery partitions are never mountable. `locked` is true for a LUKS container that is
not unlocked, one with no device inside it. Unlock it with `unlockdev`. The filesystem
inside an unlocked container takes `removable` from the container. Free space is read for every mount at once with
a 1.5 second limit; a mount that does not answer is left without `free` and `total`, and
keeps at most one waiting thread no matter how often drives are polled.

### mountdev, unmountdev

```
{"id": N, "op": "mountdev", "device": "/dev/sdb1"}
{"id": N, "op": "unmountdev", "device": "/dev/sdb1", "powerOff": false}
```

Runs `udisksctl mount -b` or `udisksctl unmount -b`. `device` must be a path under `/dev/`.
`mountdev` replies `done` with `path`, the new mount point. When the unmounted device is
the filesystem inside a LUKS container, `unmountdev` then locks the container with
`udisksctl lock -b`. With `powerOff: true` it then runs `udisksctl power-off -b` on the
container, or on the device itself. It replies `done` with `locked`. Errors: `EINVAL` for
a bad device, `EUNSUPPORTED` without udisksctl, `ETIMEDOUT`, `EMOUNT` with udisks'
message, and `ELOCK` when the unmount worked but the lock did not.

### unlockdev

```
{"id": N, "op": "unlockdev", "device": "/dev/sda3", "passphrase": "..."}
```

Runs `udisksctl unlock -b <device> --key-file /dev/stdin` with the passphrase on standard
input, never in argv, then mounts the unlocked device as `mountdev` does. A container
that is already unlocked is mounted as it is. Replies `done` with `device`, the unlocked
device, and `path`, the mount point. When the mount fails, `path` is empty and `message`
says why. The container stays unlocked. Errors: `EINVAL` for a bad device or an empty
passphrase, `EPASSPHRASE` for a wrong passphrase, `EUNLOCK` with udisks' message,
`EUNSUPPORTED` without udisksctl, and `ETIMEDOUT` after two minutes, which leaves time
for a polkit prompt.

### extract

```
{"id": N, "op": "extract", "path": "/home/me/Downloads/photos.zip"}
```

Cancellable. Opens the archive and a new private temporary folder next to it as handles,
runs `bsdtar -xvf - -C /proc/self/fd/<folder>` with the archive on standard input, then
moves the result into place without replacing anything. While it runs it emits
`{"t": "progress", "bytes", "total", "files", "filesTotal": 0, "current", "rate"}` about four
times a second: `bytes` is how far bsdtar has read into the archive, from its file position in
`/proc/<pid>/fdinfo`, `total` is the archive size, and `files` counts entries extracted so far. A single
top-level item lands next to the archive as is; several go into a new folder named after
the archive without its suffix. Clashing names get ` (1)`, ` (2)` and so on. Replies `done`
with `path`, the extracted item or folder. bsdtar keeps entries inside the folder: absolute
paths and `..` are refused. Errors: `EINVAL` when `path` is not a file, `EUNSUPPORTED`
without bsdtar, `ECANCELED`, and `EFAIL` with the tool's message. The temporary folder is
removed on failure.

### compress

```
{"id": N, "op": "compress", "paths": ["/home/me/photos", "/home/me/notes.txt"], "name": "Archive.zip"}
```

Cancellable. Every path must be absolute and in the same folder. `name` must end in `.zip`,
`.tar.xz`, `.tar.gz` or `.7z`, which picks the format, and must be a plain name. Runs
`bsdtar -cv --format <format> -f - -C /proc/self/fd/<folder> --null -T -`, with the folder
as an open handle, the archive written to a new temporary file on standard output, and
the item names on standard input,
NUL separated, so no name is ever read as an option. Symlinks are stored as links, never
followed. The finished archive is linked into place under `name`, or `name (1)`, `name (2)` and so
on, without replacing anything. Emits `progress` like `extract`, where `bytes` and
`total` count the regular file bytes added so far and in all. Replies `done` with `path`.
Errors: `EINVAL`, `ENOENT`, `EUNSUPPORTED` without bsdtar, `ECANCELED`, and `EFAIL` with the
tool's message. The temporary file is removed on failure.

### transcode

```
{"id": N, "op": "transcode", "paths": ["/home/me/Pictures/a.heic"], "format": "jpg", "resolution": "medium"}
```

Cancellable. Every path must be absolute. `format` is `jpg`, `png`, `webp`, `avif` or `jxl` for pictures and `mp4` or
`gif` for videos. `resolution` is `high`, `medium`, `low`, `original` or `lossless` for pictures and `4k`, `1080p`,
`720p` or `original` for videos. `original` does not resize, except that video sizes are rounded
down to even numbers. `lossless` is only for a JPEG made into `jxl`: it runs
`cjxl --lossless_jpeg=1` on the handles, which keeps the JPEG's metadata so `djxl` can rebuild it
byte for byte. Each file is opened as a handle and recognised by its first bytes;
anything that is not a PNG, JPEG, GIF, WebP, TIFF, BMP, HEIC, AVIF or JPEG XL picture or an MP4, MOV,
Matroska, AVI, MPEG or FLV video is refused without running a tool. Pictures go through
`magick` with the input format pinned (`PNG:/proc/self/fd/<n>[0]`), `-auto-orient`, `-strip` and
resource limits. Videos go through `ffmpeg -nostdin -protocol_whitelist file -format_whitelist
mov,matroska,avi,mpegts,flv,mpeg` with metadata and chapters removed. Output goes to a new
temporary file in the same folder, linked into place as `<name>-<resolution>.<format>`, or
`(1)`, `(2)` and so on, without replacing anything. Emits `{"t": "progress", "files",
"filesTotal", "current"}` before each file. Replies `done` with `outputs`, the files made, and
`failures`, `[{"path", "message"}]` for files that could not be. A file that fails does not
stop the rest. Errors: `EINVAL`, `ECANCELED`, and `EFAIL` when nothing could be made.

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
