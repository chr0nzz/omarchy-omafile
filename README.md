A lightweight, fast file manager plugin for Omarchy running in the shell.

![Omafile](preview.png)

## Features

* Real resizable window with tabs for multiple locations
* Dual pane layout with F5 copy and F6 move between panes
* List and grid view modes
* Live directory watching: external changes appear immediately
* Background copy and move with persistent progress tracking
* Freedesktop trash integration, compatible with GNOME Files
* Recursive file search across directories
* Image previews in grid view
* Bookmarks for the folders you use most
* Bar widget with places, drives, transfers, and trash overview
* Keyboard-first workflow with standard shortcuts

## Requirements

* Omarchy 4 (Quattro)
* Python 3 (included with Omarchy)
* util-linux `lsblk` and `findmnt` (included with Arch)
* Optional: `udisksctl` for ejecting removable drives

## Install

```bash
omarchy plugin add https://github.com/chr0nzz/omarchy-omafile.git --enable --yes
```

Plugins run unsandboxed inside the shell process and have full access to your home directory.

## Keybinding and Window Rule

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind({ "SUPER", "E" }, "Omafile", "exec", "omarchy-shell shell toggle xyzlab.omafile '{}'")
```

Add to `~/.config/hypr/windows.lua`:

```lua
o.window({ class = "^org.quickshell$", title = "^Omafile$" }, { float = true, size = { 1100, 720 }, center = true })
```

## Usage

Press Super+E to toggle the Omafile window.

Navigate directories with Enter or double-click. Backspace or Alt+Left go up or back; Alt+Right goes forward. Press Ctrl+L to type a path directly.

Use Ctrl+T to open a new tab and Ctrl+W to close it. Press Tab to switch between the left and right panes.

Copy items between panes with F5 or move them with F6.

Press F7 to create a new folder. Press F2 to rename a file or folder.

Press Delete to move items to trash or Shift+Delete to delete permanently. Cut with Ctrl+X, copy with Ctrl+C, and paste with Ctrl+V. Select all files with Ctrl+A.

Press Ctrl+H to toggle hidden files. Press Ctrl+F to search recursively from the current directory, and Escape to leave the results and return to the folder.

Press Ctrl+D to split the window into two panes and Ctrl+B to hide the sidebar. The toolbar has the same split toggle, next to the view and hidden-file buttons.

Press F1, or the last toolbar button, for the full list of keyboard shortcuts.

Right click a folder and choose Bookmark this folder to pin it to the sidebar. Remove a bookmark with the cross beside it.

When a copy or move finds a file of the same name, Omafile asks what to do. Choose with the mouse, or press R to replace, K to keep both, S to skip and A to skip every remaining conflict. Escape skips the file.

Press Escape to close the window.

## Settings

Configure these keys through the Omarchy bar widget settings:

| Key | Purpose |
|-----|---------|
| `homePath` | Default directory when opening Omafile |
| `showHidden` | Show hidden files and folders by default |
| `sortBy` | Sort by `name`, `size`, `modified` or `type` |
| `sortDirsFirst` | List directories before files |
| `confirmDelete` | Prompt before deleting items |
| `useTrash` | Send deleted items to trash (vs. permanent deletion) |
| `defaultView` | Start in `list` or `grid` view |
| `terminal` | Terminal command to open in the current directory |
| `editor` | Text editor command to open selected files |
| `showTransferBadge` | Show a progress ring on the bar icon while a transfer runs |
| `showDrives` | Show the Drives section in the sidebar |
| `thumbnails` | Show image previews in grid view |
| `glyph` | Custom icon for the bar widget |

## Command Line

Open a specific directory or reveal a file:

```bash
omarchy-shell omafile open /path/to/directory
omarchy-shell omafile reveal /path/to/file
```

Move a file or folder to trash:

```bash
omarchy-shell omafile trash /path/to/item
```

Open the keyboard shortcut list:

```bash
omarchy-shell omafile shortcuts
```

Toggle the window from a keybinding or script:

```bash
omarchy-shell omafile toggle
```

Check the helper, running transfers, drives and trash:

```bash
omarchy-shell omafile status
```

## Removal

```bash
omarchy plugin remove xyzlab.omafile
```

Removal leaves one file behind, `~/.local/state/omarchy/omafile/state.json`, which remembers open tabs and recent folders. Delete it if you do not want to keep it.

## License

MIT, Copyright (c) 2026 chr0nzz
