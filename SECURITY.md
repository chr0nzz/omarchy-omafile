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
| Trashed files | `$XDG_DATA_HOME/Trash` and per volume `.Trash-$uid` | The freedesktop trash, shared with every other file manager |
| Desktop entry | `~/.local/share/applications/xyzlab.omafile.desktop` | Only while Default file manager is on |
| Default handler | `xdg-mime` for `inode/directory` | Only while Default file manager is on. Turning it off restores the previous handler |
| Clipboard | `wl-copy` | Only when you choose Copy path |

## Processes Omafile runs

| Command | When |
| --- | --- |
| `bin/omafile-helper` | Always. One long lived Python process that does every filesystem operation |
| `lsblk`, `findmnt` | Listing drives, every 15 seconds while the shell runs |
| `gio open` | Opening a file with its default application |
| `gio mount` | Connecting to or disconnecting from a network server |
| `gio list network:///` | Looking for servers the network advertises |
| `xdg-mime`, `update-desktop-database` | Only when Default file manager is turned on or off |
| `udisksctl` | Only when you eject a removable drive |
| `wl-copy` | Only when you choose Copy path |
| `xdg-terminal-exec`, `omarchy-launch-editor` | Only when you choose Open in terminal or Open in editor |

Every one of these is spawned as a fixed argument list. No command Omafile runs is ever assembled into a shell string, so a file name cannot become part of a command.

## Credentials

Server passwords are written to the standard input of `gio mount`, never passed as arguments, so they do not appear in `ps` output or in any shell history. Omafile does not store passwords. Only the server address is remembered, so it can be offered again in the Network section.

## Trust model

- File and directory names are attacker controlled on a shared or network filesystem. They are rendered as plain text and never interpreted.
- Paths are passed to the helper as JSON on standard input, never through a shell, and names that are not valid UTF-8 round trip as surrogate escapes.
- The helper runs with your permissions and never escalates. There is no `sudo`, no `pkexec`, and no polkit action anywhere in Omafile.
- The `omarchy-shell omafile` IPC commands are available to any process running as your user.
- Deleting permanently is irreversible. It is confirmed by default, and turning the confirmation off is a deliberate setting.

## Out of scope

- GVFS, `gio`, and the servers you connect to.
- The Omarchy shell, `lsblk`, `findmnt`, and `udisksctl`.
