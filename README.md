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
* Bar widget with places, drives, transfers, and trash overview
* Keyboard-first workflow with standard shortcuts

## Requirements

* Omarchy 4 (Quattro)
* Python 3 (included with Omarchy)
* util-linux `lsblk` and `findmnt` (included with Arch)
* Optional: `bsdtar` for archive operations, `udisksctl` for drive ejection

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

Copy items between panes with F5 or move them with F6. Drag and drop is also supported.

Press F7 to create a new folder. Press F2 to rename a file or folder.

Press Delete to move items to trash or Shift+Delete to delete permanently. Cut with Ctrl+X, copy with Ctrl+C, and paste with Ctrl+V. Select all files with Ctrl+A.

Press Ctrl+H to toggle hidden files and Ctrl+F to search recursively from the current directory.

Press Escape to close the window.

## Settings

Configure these keys through the Omarchy bar widget settings:

| Key | Purpose |
|-----|---------|
| `homePath` | Default directory when opening Omafile |
| `showHidden` | Show hidden files and folders by default |
| `sortBy` | Sort files by name, size, or date |
| `sortDirsFirst` | List directories before files |
| `confirmDelete` | Prompt before deleting items |
| `useTrash` | Send deleted items to trash (vs. permanent deletion) |
| `defaultView` | Start in list or grid view |
| `terminal` | Terminal command to open in the current directory |
| `editor` | Text editor command to open selected files |
| `showTransferBadge` | Show active transfers on the window title |
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

Check the status of background transfers:

```bash
omarchy-shell omafile status
```

## Removal

```bash
omarchy plugin remove xyzlab.omafile
```

State is stored at `~/.local/state/omarchy/omafile/state.json` and the thumbnail cache at `~/.cache/omarchy/omafile/`.

## License

MIT, Copyright (c) 2026 chr0nzz
