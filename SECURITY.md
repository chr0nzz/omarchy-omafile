# Security

## Reporting a vulnerability

Report privately through [GitHub private vulnerability reporting](https://github.com/chr0nzz/omarchy-omafile/security/advisories/new).
Do not open a public issue for anything that could be exploited.

Include what you found, how to reproduce it, and the Omafile and Omarchy versions.
You will get an acknowledgement within 7 days and a fix or a decision within 30 days.

## Supported versions

Only the latest release on `main` receives fixes.

## What Omafile touches

| Data | Where | Notes |
| --- | --- | --- |
| Settings | `~/.config/omarchy/shell.json` | Written by the settings dialog and `omarchy bar set` |
| Tabs, bookmarks, hidden drives, server addresses, per folder views, sidebar order | `~/.local/state/omarchy/omafile/state.json` | Plain text. Server addresses are stored, passwords are not |
| GTK bookmarks | `~/.config/gtk-3.0/bookmarks` (or `$XDG_CONFIG_HOME/gtk-3.0/bookmarks`) | Shared local paths and labels; remote entries preserved. Local backup and pending edits remain in `state.json`; migration is marked complete only after a confirmed write |
| Trashed files | `$XDG_DATA_HOME/Trash` and per volume `.Trash-$uid` | The freedesktop trash, shared with every other file manager |
| Desktop entry | `~/.local/share/applications/xyzlab.omafile.desktop` | Only while Default file manager is on |
| D-Bus service file | `~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service` | Only while Default file manager is on. Overrides the system file so Show in folder reaches Omafile |
| Default handler | `gio mime` for `inode/directory` in `mimeapps.list` | Only while Default file manager is on. Claimed again at shell start if something else took it. Turning it off restores the previous handler |
| Default apps | `~/.config/mimeapps.list` (or `$XDG_CONFIG_HOME/mimeapps.list`) through `gio mime` | Only when you change Opens with in Properties. Never for `inode/directory` |
| Permissions, owner and group | The file or folder you edit in Properties | Only when you press Apply. Recursive changes skip symlinks and never follow them. Changing the owner only works when the helper runs as root, which Omafile never arranges |
| Portal backend file | `/usr/share/xdg-desktop-portal/portals/omafile.portal` | Installed once, with your password, when Pick files for other apps is turned on. Fixed contents. Left in place when it is turned off, where it does nothing on its own |
| Portal D-Bus service file | `~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.omafile.service` | Only while Pick files for other apps is on |
| Portal preference | `~/.config/xdg-desktop-portal/hyprland-portals.conf` | Only while Pick files for other apps is on. One `org.freedesktop.impl.portal.FileChooser=omafile` line, the rest of the file is kept |
| Clipboard | `wl-copy`, `wl-paste` | Written when you choose Copy path, or copy or cut files. Read when you paste files, images, or text into a text field, and once per second while cut markers are active. Every read goes through the helper with a time limit and a size cap (1 MB of file list and 20,000 paths, 64 KB of text), never through Qt |
| Text you edit | The file you open with Edit, or with Open in editor when Omafile's editor is the default | Only when you save, or a second after you stop typing when Auto save is on. Replaced through a new temporary file in the same folder, or written in place when it has other hard links. Never through a link, and never when it changed on disk since you opened it unless you choose Overwrite |
| Thumbnails | `~/.cache/thumbnails` (or `$XDG_CACHE_HOME/thumbnails`) | Shared PNG cache, including source URIs and timestamps; may remain after source files are moved or deleted |
| Large image previews | `~/.cache/omafile/previews/<size>` (or under `$XDG_CACHE_HOME`) | 2048, 4096 or 7680 px PNG previews, when Image preview size asks for more than 1024 px. Private to you, with the same pixel-only checks as thumbnails. The oldest are removed beyond 2 GB or 500 files in all |
| Audio preview copies | `~/.cache/omafile/preview` (or `$XDG_CACHE_HOME/omafile/preview`) | The audio stream of the last one or two previewed songs, without cover art or tags. Private to you and replaced as you preview more |

## Processes Omafile runs

| Command | When |
| --- | --- |
| `bin/omafile-helper` | Always. One long lived Python process that does every filesystem operation |
| `bin/omafile-filemanager1` | Only while Default file manager is on. Started by D-Bus when another app asks to show a file, exits after two idle minutes |
| System thumbnailers | Automatically while browsing with thumbnails enabled, including for images and the image preview. Root-owned definitions in `/usr/share/thumbnailers` and `/usr/local/share/thumbnailers` only; no user or XDG-supplied definitions |
| `ffprobe`, `ffmpeg` | Only when you preview an audio file, to read its title, artist and album and to copy its audio stream without anything else |
| `magick`, `ffmpeg`, `cjxl` | Only when you choose Transcode. `cjxl` only runs for a JPEG XL lossless repack, and only on a file whose first bytes are a JPEG. A selected link is only followed when Omafile trusts it (yours or root's, on a local disk, not on a network share or removable drive), and its ownership is checked and its target read through one handle on the link itself, so it cannot be replaced between the two. The file it points to is then opened without following any further link, so a link swapped in after you chose the file cannot hand a private picture to the encoder. The helper opens each file as a handle and checks its first bytes, so only real pictures and videos are passed on, whatever their name. ImageMagick is told the exact picture format, so it never runs its script, text or vector readers on a file, and has memory, size and time limits. `ffmpeg` may only read local files and only through plain video container demuxers (`mov`, `matroska`, `avi`, `mpegts`, `flv`, `mpeg`), never playlists or concat lists that could pull other files into the result. Both write to a new temporary file that is linked into place without replacing anything, and metadata is removed |
| `lsblk`, `findmnt` | Listing drives, every 15 seconds while the shell runs |
| `gio open` | Opening a file with its default application |
| `gio mount` | Connecting to or disconnecting from a network server |
| `gio list network:///` | Looking for servers the network advertises |
| `gio info`, `gio mime` | Reading a file's type and its default app when Properties opens, saving a new default when you change Opens with, and checking or setting the folder handler for Default file manager |
| `update-desktop-database` | Only when Default file manager is turned on or off |
| `bin/omafile-portal` | Only while Pick files for other apps is on. Started by D-Bus when another app asks for a file chooser |
| `bin/omafile-portal-setup` | Only when Pick files for other apps is turned on or off |
| `/usr/bin/pkexec /usr/bin/install`, or `/usr/bin/sudo` from a terminal | Once, when Pick files for other apps is turned on and `omafile.portal` is missing or different. Fixed paths, never looked up on your `PATH` |
| `gdbus` `ReloadConfig`, `systemctl --user restart xdg-desktop-portal.service` | When Pick files for other apps is turned on or off, so the portal picks up the change |
| `udisksctl` | Only when you mount, unlock, unmount or eject a drive |
| `bsdtar` | Only when you extract or compress. Extracting reads the archive from an open file handle, refuses absolute paths and `..` entries, and goes into a private temporary folder handed over as an open folder handle, which is moved into place only when it succeeds. Compressing works inside the folder through an open handle, reads item names from standard input, writes to a new file on standard output, never follows symlinks, and never replaces an existing file |
| `wl-copy`, `wl-paste` | Copy path, copy/cut files, paste files or images, and clipboard checks while cut markers are active |
| `xdg-terminal-exec`, `omarchy-launch-editor`, `omarchy-launch-tui` | Only when you choose Open in terminal, Open in editor, or the agent item such as Open Claude Code here |
| `omarchy-default-editor` | Only when you turn on Also make it Omarchy's default editor while picking an editor. It is given one name from a fixed list of editors Omarchy supports |

Helper tools use argument lists. Thumbnailer arguments come from trusted system `.thumbnailer` `Exec` definitions, parsed without a shell; file paths and URIs remain individual argument values. Executables resolve through `trusted_program` and launch with `trusted_env`, ignoring user `PATH` entries and injected environment variables. Thumbnailer definitions and their parent directories must be root owned, not symlinks, and not writable by group or others. Thumbnailers run unsandboxed with your permissions, so enable previews only for files you trust the installed decoders to handle.

A configured terminal, editor or agent command is deliberately interpreted by a shell. The path is passed separately as an argument. Before a saved editor command runs, the helper checks that its program exists, so a broken setting asks for an editor instead.

Omafile reads Omarchy's default editor from `~/.local/state/omarchy/defaults/editor` and default agent from `~/.config/omarchy/defaults/agent`. Only the first line is used, only when it is a plain program name of letters, digits, `.`, `_`, `+` and `-`, so the agent file cannot smuggle a shell command into the agent item. Omafile never writes either file itself.

## Owning org.freedesktop.FileManager1

Turning on Default file manager installs a user D-Bus service file that claims `org.freedesktop.FileManager1`, the interface browsers and editors call for Show in folder. A user service file takes precedence over the system one, so the call reaches Omafile instead of the system file manager.

This is deliberate and reversible. Turning the setting off deletes the service file and the next call goes back to whatever owned the name before. The service only implements `ShowFolders`, `ShowItems`, and `ShowItemProperties`, does nothing but forward a path to `omarchy-shell omafile`, and exits on its own after two idle minutes.

## Credentials

Server passwords are written to the standard input of `gio mount`, never passed as arguments, so they do not appear in `ps` output or in any shell history. Omafile does not store passwords. Only the server address is remembered, so it can be offered again in the Network section.

A drive passphrase takes the same route: it reaches the helper as JSON on standard input, and the helper writes it to the standard input of `udisksctl unlock --key-file /dev/stdin`. It is never an argument, never written to a file, and never stored. The field and its undo history are cleared when the dialog closes, when another dialog replaces it, and after a wrong passphrase. A server connection that fails in the background while the dialog is open reports in the status bar instead of opening the Connect dialog over it, so typing cannot carry on into a server password field. udisks and polkit decide who may unlock a drive, the same as for mounting one.

## Trust model

- File and directory names, symlink targets, and everything else read from disk are attacker controlled on a shared, removable, or network filesystem. Every `Text` in Omafile sets `textFormat: Text.PlainText`, so none of it is parsed as rich text or can load a remote image. `tests/plain-text.test.js` fails on any `Text` without it.
- Paths are passed to the helper as JSON on standard input, never through a shell. Names that are not valid UTF-8 round trip as surrogate escapes; the shell escapes lone surrogates before writing a request, because Qt's `JSON.stringify` leaves them raw and they would otherwise turn into a different name.
- The helper runs with your permissions and never escalates.
- The only privileged step is installing `omafile.portal` when you turn on Pick files for other apps. `bin/omafile-portal-setup` runs `pkexec install -Dm644 /dev/stdin /usr/share/xdg-desktop-portal/portals/omafile.portal`, or `sudo` when run from a terminal without `pkexec`, as a fixed argument list with the fixed file contents on standard input. It is skipped when the file is already in place. Nothing else in Omafile uses `sudo`, `pkexec`, or polkit.
- The `omarchy-shell omafile` IPC commands are available to any process running as your user.
- Deleting permanently is irreversible. It is confirmed by default, and turning the confirmation off is a deliberate setting.
- File picks for other apps only grant access inside the folder you chose. When an app asks to save several files, every name it supplies must be a plain file name: an empty name, `.`, `..`, or a name with a slash or NUL refuses the whole request, and duplicate names are refused too. A name that already exists in the chosen folder is never handed out: `bin/omafile-portal` numbers it instead, the way other file choosers do. A suggested Save as name that is not plain is ignored, and a name you type is checked the same way. Saving over an existing name always asks first, checked with the helper rather than the visible list, so hidden or filtered files are covered. A symlink is never returned: a linked file or folder is refused in the chooser and again in the portal. Before answering, the portal checks that every returned path is absolute and normalised.
- Only one app can use the file chooser at a time. A second request is refused instead of cancelling or replacing the open one, and the chooser shows the requesting app's id. While it is open, trash, delete, paste, drop, rename, restore, extract, compress, Properties, undo, redo, new file, the terminal, the editor and the agent are unavailable, thumbnails are not made, and folders are not added to Recent, so an app cannot steer keystrokes or system thumbnailers at files in a folder it chose. Omafile focuses its own windows by its process id and the window address, never by title alone.
- An app decides when the chooser opens, and the chooser takes keyboard focus, so it could catch typing meant for another window, such as a password. For 600 ms after it opens, every key is ignored, and each ignored key restarts the wait. Accepting is refused during that time, whether by Enter, a double click or the Save or Select button. If any key was ignored, the save name field does not take focus on its own and needs a click, so text typed for something else never becomes the file name sent to the app.
- Copies and moves on a shared or network folder cannot be redirected by someone who changes the folder mid copy. Folders are walked through open directory handles rather than paths, every source is opened without following symlinks and checked to be the same file that was looked at, and destination files are created with `O_EXCL` and `O_NOFOLLOW`, so a symlink that appears is never written through and an existing file is never truncated. Replacing a file writes a temporary file first and renames it over the old one, so a failed or cancelled copy keeps the original. Permissions and times are set on the open file. A move across drives only removes the source after every item copied. A source named `.` or `..` is refused.
- Every single item operation (rename, trash, delete, restore, new file or folder, permissions, owner, copy, move, extract, compress) opens the folder path one step at a time without following symlinks. A symlink on the way is followed only when it is owned by you or root and sits on a local filesystem, never on a network or FUSE filesystem, under `/mnt`, `/media` or `/run/media`, or in GVFS, so a server or another user of a share cannot point the operation at your own files. Recursive permission and owner changes walk the tree through open folder handles.
- Rename, restoring from the trash, and undo or redo never replace an existing file. Both use `renameat2` with `RENAME_NOREPLACE`. Restoring refuses a `.trashinfo` path with `..`, and a drive's trash only restores inside that drive. Undo and redo act on the exact paths the helper reports it created, so undoing a Keep both copy, a merged folder or a skipped item never touches the original.
- A drive's trash is used only when `.Trash-$uid`, its `files` and its `info` are real folders owned by you, opened one step at a time without following symlinks. A symlink in their place is ignored, and emptying the trash never follows a symlink, so a crafted drive cannot point Empty trash at files outside it.
- Trash metadata is read only from a regular `.trashinfo` file of at most 64 KB, opened without following symlinks and without waiting on a pipe. Anything else is skipped, so a crafted drive cannot stall the trash count or exhaust memory with oversized metadata. The trash count sent to the shell is a summary without the item list. `tests/trash_security_test.py` covers this.
- Untrusted folders cannot flood or stall the shell. A listing stops at 200,000 entries and says so, disk usage stays on one drive, never revisits a folder and stops when Properties closes, each drive is polled at most once at a time with a time limit, and the helper refuses a request id that is already running. Previews only read regular files: a pipe, socket or device named like a song or a picture is never opened, images over 1 GB are not previewed, pictures are only ever decoded by the system thumbnailer in its own process with a time limit, and audio on a network folder is not played inside the shell.
- The shell never decodes a file you browse. Qt keeps every text chunk a PNG carries, so a small PNG with many compressed text chunks could make the shell hold gigabytes of metadata, and Qt Multimedia decodes a song's embedded cover art the same way when it loads the song. Thumbnails and the image preview are made by system thumbnailers in separate processes, and the helper writes them back with only pixel chunks and the `Thumb::` fields, at most 1024 px on a side. Cached thumbnails from other apps with anything more are made again. Audio is previewed from a copy the helper makes with `ffmpeg`, holding only the audio stream; the title, artist and album come from `ffprobe`, cut to 256 characters. Reported in the marketplace review of 1.4.0 (omarchy-plugin-marketplace#11604). `tests/media-sources.test.js` fails on any QML that loads an original file into an image or a player.
- No Qt text field ever reads the clipboard. Released Qt 6.11 and 6.12 read the whole clipboard text, with no size or time limit, into every editable text field each time another app copies something, on the thread that draws the desktop. Every Omafile text field is permanently read only to Qt and edits its text itself: typing, delete, cut, undo and redo work as usual, and paste asks the helper for at most 64 KB of text. The shell's own search dropdown is not used; Opens with has its own search built on the same field. `tests/text-inputs.test.js` fails on any text field that is not read only, and `tests/browser-flows.qml` checks typing and paste.
- Dragging over an Omafile window only looks at which formats the other app offers. The dragged data is read only when you drop.
- A transfer conflict prompt only appears in the window that started the transfer, waits for any open dialog to close, ignores keys for the first 600 ms, and its answer carries the conflict's number, so a stray keystroke cannot pick Replace for a different prompt.
- Opens with substitutes the file path as a separate argument. When an application's command is a `sh -c` style script, the path is shell quoted inside the script, so a file name cannot add commands. Portal filter patterns are matched without regular expressions, in linear time, and are capped in count and length.

## Out of scope

- GVFS, `gio`, and the servers you connect to.
- The Omarchy shell, `lsblk`, `findmnt`, and `udisksctl`.
