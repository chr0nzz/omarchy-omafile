A lightweight, fast file manager plugin for Omarchy running in the shell.

![Omafile](preview.png)

## Features

* Real resizable window with tabs for multiple locations
* Dual pane layout with one-key copy and move between panes
* List and grid view modes
* Live directory watching: external changes appear immediately
* Background copy and move with persistent progress tracking
* Freedesktop trash integration, compatible with GNOME Files
* Recursive file search across directories
* Image previews in both list and grid view
* Recent files, and bookmarks for the folders you use most
* Connect to SMB, SFTP, WebDAV and other servers
* Settings inside the window, no config file editing
* Bar widget with places, drives, transfers, and trash overview
* Full keyboard control, following GNOME Files conventions
* Undo and redo for trash, rename, move, copy and new items

## Requirements

* Omarchy 4 (Quattro)
* Python 3 (included with Omarchy)
* util-linux `lsblk` and `findmnt` (included with Arch)
* Optional: `udisksctl` for ejecting removable drives
* Optional: `gvfs` and `gvfs-smb` for connecting to network servers
* Optional: PyGObject for Show in folder from other applications

## Install

```bash
omarchy plugin add https://github.com/chr0nzz/omarchy-omafile.git --enable --yes
```

Plugins run unsandboxed inside the shell process and have full access to your home directory.

## Keybinding and Window Rule

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + E", "Omafile", "omarchy-shell shell toggle xyzlab.omafile '{}'")
```

Add to `~/.config/hypr/windows.lua`:

```lua
o.window({ class = "^org.quickshell$", title = "^Omafile$" }, { float = true, size = { 1100, 720 }, center = true })
```

Omarchy makes every window slightly transparent, so your wallpaper shows faintly through Omafile the same way it does through every other app. If you would rather Omafile were solid, opt it out of that rule:

```lua
o.window({ class = "^org.quickshell$", title = "^Omafile$" }, { tag = "-default-opacity", opacity = "1 1" })
```

## Usage

Press Super+E to toggle the Omafile window. Opening it again while it is already open brings it to the front rather than doing nothing.

Navigate directories with Enter or double-click. Backspace or Alt+Up go to the parent folder; Alt+Left and Alt+Right go back and forward.

Click any part of the address bar to type a path, or press Ctrl+L. Click a breadcrumb to jump to that folder. Typing `/` or `~` opens the address bar with that character already in it.

The magnifier at the end of the address bar filters the current folder. Press Ctrl+F instead to search the folder and everything inside it. Escape clears the text, then closes the filter.

Everything Omafile does is reachable from the keyboard. Press F1, or the last toolbar button, for the list inside the window; the same list is in the Keyboard section below.

Open Settings from the toolbar or with Ctrl+Comma to turn hidden files, folders-first ordering, image previews, trash behaviour and the sidebar drive list on or off.

The Network section of the sidebar holds everything remote. Choose Connect to a server to mount an SMB share, an SFTP host, FTP or WebDAV. Servers you have used before are listed there so one click reconnects, and any server the network advertises appears alongside them. Right click a connected share to disconnect it. Connections use GVFS and need no root; install `gvfs-smb` for Windows shares if it is missing.

Hover a drive in the sidebar and click the eye to hide it. Hidden drives come back from Settings.

Settings also chooses whether Omafile opens as a normal window or as a popup panel centred over the desktop that closes when you click away. The change applies straight away, even while Omafile is open.

Turn on Default file manager in Settings to have folders opened from other applications land in Omafile. This covers two separate mechanisms: it points `inode/directory` at a desktop entry in `~/.local/share/applications/`, which is what `xdg-open` and `gio open` use, and it claims `org.freedesktop.FileManager1` through a user D-Bus service file, which is what browsers and editors use for Show in folder. Show in folder opens the containing folder with the file selected. Turning the setting off removes both and restores the handler you had before.

The D-Bus half needs PyGObject, which Omarchy already ships. Without it the desktop entry still works and Show in folder keeps going to your previous file manager. To do the same from a terminal:

```bash
xdg-mime default xyzlab.omafile.desktop inode/directory
xdg-mime query default inode/directory
```

Right click a folder and choose Bookmark this folder to pin it to the sidebar. Remove a bookmark with the cross beside it.

Recent in Places lists the files you opened most recently, newest first, drawn from the same history the rest of the desktop uses. Opening one takes you straight to the file; there is no folder to go up to, so use a place or a bookmark to leave.

When a copy or move finds a file of the same name, Omafile asks what to do. Choose with the mouse, or with the keys listed under Keyboard.

Press Escape to close the window.

## Keyboard

Omafile follows GNOME Files conventions, so shortcuts you already know work here.

### Navigation

| Keys | Action |
|------|--------|
| `Enter` | Open the selected item |
| `Backspace` / `Alt+Up` | Go to the parent folder |
| `Alt+Left` / `Alt+Right` | Back and forward |
| `Alt+Home` | Go to your home folder |
| `Ctrl+L` | Type a path |
| `/` or `~` | Type a path, starting from root or home |
| `Home` / `End` | First and last item |
| `F5` / `Ctrl+R` | Refresh |

### Moving around without a mouse

Focus starts in the file list. Tab moves it to the sidebar, or to the other pane when the window is split. Escape or Right returns focus to the file list.

| Keys | Action |
|------|--------|
| `Tab` | Sidebar, or the other pane when split |
| `Shift+Tab` | Jump to the sidebar |
| `Arrows`, `Enter` | Move and open, once in the sidebar |
| `Ctrl+Enter` | Open a sidebar place in a new tab |
| `Delete` | Remove a bookmark or hide a drive, in the sidebar |
| `Escape` | Leave the sidebar |
| `Shift+F10` / `Menu` | Open the context menu on the current item |

The context menu is a real focus target: arrows move through it, Enter or Space runs the highlighted entry, Escape closes it. Anything Omafile can do to a file is in there, so no action needs the mouse.

### Selection

| Keys | Action |
|------|--------|
| `Ctrl+Click` | Add one item to the selection |
| `Ctrl+Space` | Add the item under the cursor |
| `Shift+Click`, `Shift+Arrows` | Select a range |
| `Ctrl+A` | Select everything |
| `Ctrl+Shift+I` | Invert the selection |
| `Escape` | Clear the selection |

### Files

| Keys | Action |
|------|--------|
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy, cut and paste |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo and redo |
| `F2` | Rename |
| `Ctrl+Shift+N` | New folder |
| `Ctrl+N` | New file |
| `Delete` | Move to trash |
| `Shift+Delete` | Delete permanently |
| `Ctrl+I` / `Alt+Enter` | Properties |
| `Ctrl+D` | Bookmark this folder |

Undo covers trash, rename, move, copy and new file or folder. Undoing a trash puts the items back where they were, and undoing a copy trashes what the copy created.

### Panes and tabs

| Keys | Action |
|------|--------|
| `Ctrl+T` / `Ctrl+W` | New tab and close tab |
| `Ctrl+PageUp` / `Ctrl+PageDown` | Previous and next tab |
| `Ctrl+Enter` | Open the folder under the cursor in a new tab |
| `F6` | Split into two panes |
| `Tab` | Switch the active pane, while split |
| `Ctrl+Shift+C` / `Ctrl+Shift+M` | Copy and move to the other pane |

### View

| Keys | Action |
|------|--------|
| `Ctrl+1` / `Ctrl+2` | List and grid |
| `Ctrl+H` | Show hidden files |
| `Ctrl+B` | Show or hide the sidebar |
| `Ctrl+F`, or just type | Search in this folder |
| `Ctrl+Comma` | Settings |
| `F1` | The shortcut list |
| `Ctrl+Q` / `Escape` | Close the window |

Typing an ordinary character opens the search box with that character already typed, the way GNOME Files does.

### When a file already exists

| Keys | Action |
|------|--------|
| `R` / `K` / `S` / `A` | Replace, keep both, skip, skip all |

Escape skips the file.

Super+C, Super+V and Super+X are Omarchy's universal clipboard shortcuts. Omarchy translates them to Ctrl+C, Ctrl+V and Ctrl+X before they reach the window, so they copy, paste and cut files in Omafile too.

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

Switch between a window and a popup:

```bash
omarchy-shell omafile windowmode window
omarchy-shell omafile windowmode popup
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
