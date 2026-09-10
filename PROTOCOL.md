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
`stat`, `du`, `space`, `drives`, `dirs`, `trash`.

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
`group`, `nlink`, `inode`, `dev`, `mime`, `linkTarget`. A path that cannot be stat'd
yields an item with `error` set instead of the metadata fields.

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
confirmation. Both reply `{"t": "done", "results": [{"path": P, "ok": true}]}`.

### trashinfo, emptytrash

```
{"id": N, "op": "trashinfo"}
{"id": N, "op": "emptytrash"}
```

`trashinfo` replies `{"t": "trash", "count": C, "bytes": B, "items": [...]}` where each
item is `{"name", "original", "deleted", "size", "kind"}`. `emptytrash` clears every
trash directory it knows about and replies `done`.

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

### freespace

```
{"id": N, "op": "freespace", "path": "/home"}
```

Replies `{"t": "space", "total": T, "free": F, "used": U, "mount": M}` then `done`.

### drives

```
{"id": N, "op": "drives"}
```

Replies `{"t": "drives", "drives": [{"name", "path", "label", "size", "fstype", "mount", "removable", "free", "total"}]}`
then `done`. Sourced from `lsblk -J -b -o ...` and `findmnt -J -b`. Both tools are part
of util-linux and are always present. A missing tool yields an empty list, never an
error.

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

Replies `{"t": "done", "version": "0.1.0", "pid": <int>, "inotify": true}`.

## Concurrency

The helper serves requests concurrently on worker threads. Listing, searching, du and
transfers each run on their own thread so a slow network mount never blocks the bar.
Writes to stdout are serialized behind a single lock so lines never interleave.

## Safety

The helper runs with the invoking user's permissions and never escalates. It contains
no `sudo`, no `pkexec`, no shell invocation, no network access and no third-party
imports. Every subprocess it does spawn is a fixed argv list of a util-linux tool.
