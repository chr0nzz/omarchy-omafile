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
| Tabs, bookmarks, hidden drives, server addresses | `~/.local/state/omarchy/omafile/state.json` | Plain text. Server addresses are stored, passwords are not |
| GTK bookmarks | `~/.config/gtk-3.0/bookmarks` (or `$XDG_CONFIG_HOME/gtk-3.0/bookmarks`) | Shared local paths and labels; remote entries preserved. Local backup and pending edits remain in `state.json`; migration is marked complete only after a confirmed write |
| Trashed files | `$XDG_DATA_HOME/Trash` and per volume `.Trash-$uid` | The freedesktop trash, shared with every other file manager |
| Desktop entry | `~/.local/share/applications/xyzlab.omafile.desktop` | Only while Default file manager is on |
| D-Bus service file | `~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service` | Only while Default file manager is on. Overrides the system file so Show in folder reaches Omafile |
| Default handler | `xdg-mime` for `inode/directory` | Only while Default file manager is on. Turning it off restores the previous handler |
| Portal backend file | `/usr/share/xdg-desktop-portal/portals/omafile.portal` | Installed once, with your password, when Pick files for other apps is turned on. Fixed contents. Left in place when it is turned off, where it does nothing on its own |
| Portal D-Bus service file | `~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.omafile.service` | Only while Pick files for other apps is on |
| Portal preference | `~/.config/xdg-desktop-portal/hyprland-portals.conf` | Only while Pick files for other apps is on. One `org.freedesktop.impl.portal.FileChooser=omafile` line, the rest of the file is kept |
| Clipboard | `wl-copy`, `wl-paste` | Written when you choose Copy path, or copy or cut files. Read when you paste files or images, and once per second while cut markers are active |
| Thumbnails | `~/.cache/thumbnails` (or `$XDG_CACHE_HOME/thumbnails`) | Shared PNG cache, including source URIs and timestamps; may remain after source files are moved or deleted |

## Processes Omafile runs

| Command | When |
| --- | --- |
| `bin/omafile-helper` | Always. One long lived Python process that does every filesystem operation |
| `bin/omafile-filemanager1` | Only while Default file manager is on. Started by D-Bus when another app asks to show a file, exits after two idle minutes |
| System thumbnailers | Automatically while browsing with thumbnails enabled. Root-owned definitions in `/usr/share/thumbnailers` and `/usr/local/share/thumbnailers` only; no user or XDG-supplied definitions |
| `lsblk`, `findmnt` | Listing drives, every 15 seconds while the shell runs |
| `gio open` | Opening a file with its default application |
| `gio mount` | Connecting to or disconnecting from a network server |
| `gio list network:///` | Looking for servers the network advertises |
| `xdg-mime`, `update-desktop-database` | Only when Default file manager is turned on or off |
| `bin/omafile-portal` | Only while Pick files for other apps is on. Started by D-Bus when another app asks for a file chooser |
| `bin/omafile-portal-setup` | Only when Pick files for other apps is turned on or off |
| `pkexec install`, or `sudo install` from a terminal | Once, when Pick files for other apps is turned on and `omafile.portal` is missing or different |
| `gdbus` `ReloadConfig`, `systemctl --user restart xdg-desktop-portal.service` | When Pick files for other apps is turned on or off, so the portal picks up the change |
| `udisksctl` | Only when you eject a removable drive |
| `wl-copy`, `wl-paste` | Copy path, copy/cut files, paste files or images, and clipboard checks while cut markers are active |
| `xdg-terminal-exec`, `omarchy-launch-editor` | Only when you choose Open in terminal or Open in editor |

Helper tools use argument lists. Thumbnailer arguments come from trusted system `.thumbnailer` `Exec` definitions, parsed without a shell; file paths and URIs remain individual argument values. Executables resolve through `trusted_program` and launch with `trusted_env`, ignoring user `PATH` entries and injected environment variables. Thumbnailer definitions and their parent directories must be root owned, not symlinks, and not writable by group or others. Thumbnailers run unsandboxed with your permissions, so enable previews only for files you trust the installed decoders to handle.

A configured terminal command is deliberately interpreted by a shell. The folder path is passed separately as an argument.

## Owning org.freedesktop.FileManager1

Turning on Default file manager installs a user D-Bus service file that claims `org.freedesktop.FileManager1`, the interface browsers and editors call for Show in folder. A user service file takes precedence over the system one, so the call reaches Omafile instead of the system file manager.

This is deliberate and reversible. Turning the setting off deletes the service file and the next call goes back to whatever owned the name before. The service only implements `ShowFolders`, `ShowItems`, and `ShowItemProperties`, does nothing but forward a path to `omarchy-shell omafile`, and exits on its own after two idle minutes.

## Credentials

Server passwords are written to the standard input of `gio mount`, never passed as arguments, so they do not appear in `ps` output or in any shell history. Omafile does not store passwords. Only the server address is remembered, so it can be offered again in the Network section.

## Trust model

- File and directory names, symlink targets, and everything else read from disk are attacker controlled on a shared, removable, or network filesystem. Every `Text` in Omafile sets `textFormat: Text.PlainText`, so none of it is parsed as rich text or can load a remote image. `tests/plain-text.test.js` fails on any `Text` without it.
- Paths are passed to the helper as JSON on standard input, never through a shell, and names that are not valid UTF-8 round trip as surrogate escapes.
- The helper runs with your permissions and never escalates.
- The only privileged step is installing `omafile.portal` when you turn on Pick files for other apps. `bin/omafile-portal-setup` runs `pkexec install -Dm644 /dev/stdin /usr/share/xdg-desktop-portal/portals/omafile.portal`, or `sudo` when run from a terminal without `pkexec`, as a fixed argument list with the fixed file contents on standard input. It is skipped when the file is already in place. Nothing else in Omafile uses `sudo`, `pkexec`, or polkit.
- The `omarchy-shell omafile` IPC commands are available to any process running as your user.
- Deleting permanently is irreversible. It is confirmed by default, and turning the confirmation off is a deliberate setting.
- A drive's trash is used only when `.Trash-$uid`, its `files` and its `info` are real folders owned by you. A symlink in their place is ignored, and emptying the trash never follows a symlink, so a crafted drive cannot point Empty trash at files outside it.

## Out of scope

- GVFS, `gio`, and the servers you connect to.
- The Omarchy shell, `lsblk`, `findmnt`, and `udisksctl`.
