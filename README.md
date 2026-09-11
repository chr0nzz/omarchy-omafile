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
* Optional trash can in the bar, with a live count
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

Super+E toggles the window. If it is already open it comes to the front. Escape closes it.

Moving around is covered in [Keyboard](#keyboard); F1 shows the same list inside the window.

### Finding things

Click any part of the address bar to type a path, or press Ctrl+L. Click a breadcrumb to jump to that folder.

The magnifier at the end of the address bar filters the folder you are in. Ctrl+F searches that folder and everything inside it instead. Escape clears the text, then leaves the results.

### The sidebar

Places, then your bookmarks, then drives, then Network, then Trash.

Right click a folder and choose Bookmark this folder to pin it. Remove a bookmark with the cross beside it.

Recent lists the files you opened most recently, newest first, from the same history the rest of the desktop uses. Opening one goes straight to the file. There is no folder above it, so leave by picking a place or a bookmark.

Hover a drive and click the eye to hide it. Hidden drives come back from Settings.

### Network drives

Connect to a server mounts an SMB share, an SFTP host, FTP or WebDAV. Servers you have used before are listed so one click reconnects, and any server the network advertises appears alongside them. Right click a connected share to disconnect it.

This uses GVFS and needs no root. Install `gvfs-smb` for Windows shares if it is missing.

### Settings

Ctrl+Comma, or the gear in the toolbar. Hidden files, folders-first ordering, image previews, trash behaviour, the drive list, and the trash can in the bar.

Settings also picks whether Omafile is a normal window or a popup panel centred over the desktop that closes when you click away. The change applies immediately, even while Omafile is open.

### Opening folders from other apps

Turn on Default file manager in Settings. Folders opened from anywhere else then land in Omafile, and Show in folder opens the containing folder with the file selected. It also puts Omafile in your application launcher, using the same folder icon as the bar widget. Turning it off restores the handler you had before.

Two separate mechanisms are involved, which is why some apps can follow it and others not:

| Mechanism | Used by |
|-----------|---------|
| `inode/directory` pointed at a desktop entry in `~/.local/share/applications/` | `xdg-open`, `gio open`, most desktop apps |
| `org.freedesktop.FileManager1` claimed through a user D-Bus service file | browsers and editors, for Show in folder |

The D-Bus half needs PyGObject, which Omarchy ships. Without it the desktop entry still works and Show in folder keeps going to your previous file manager.

The desktop entry half from a terminal:

```bash
xdg-mime default xyzlab.omafile.desktop inode/directory
xdg-mime query default inode/directory
```

### Copying over something that exists

Omafile asks what to do. Choose with the mouse, or with the keys under [Keyboard](#when-a-file-already-exists).

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

## Trash in the Bar

Turn on **Trash can in the bar** in Settings. A trash can appears beside the Omafile icon, outlined when the trash is empty and solid when it is not, with the number of items next to it. The count updates on its own as things are deleted or restored, from anywhere, not just from Omafile.

Left click opens the trash. Right click empties it: the first right click turns it red for four seconds and a second right click within that window empties it, so a stray click cannot wipe anything. Turn off **Ask before emptying** if you want the first right click to empty it outright.

The count comes from every trash directory on the system, so a removable drive with its own trash is included, and Omafile notices when that drive is mounted or unmounted.

## Settings

Ctrl+Comma, or the gear in the toolbar. Hidden files, folders-first ordering, image previews, trash behaviour, the drive list, and the trash can in the bar.

Settings also picks whether Omafile is a normal window or a popup panel centred over the desktop that closes when you click away. The change applies immediately, even while Omafile is open.

### Opening folders from other apps

Turn on Default file manager in Settings. Folders opened from anywhere else then land in Omafile, and Show in folder opens the containing folder with the file selected. It also puts Omafile in your application launcher, using the same folder icon as the bar widget. Turning it off restores the handler you had before.

Two separate mechanisms are involved, which is why some apps can follow it and others not:

| Mechanism | Used by |
|-----------|---------|
| `inode/directory` pointed at a desktop entry in `~/.local/share/applications/` | `xdg-open`, `gio open`, most desktop apps |
| `org.freedesktop.FileManager1` claimed through a user D-Bus service file | browsers and editors, for Show in folder |

The D-Bus half needs PyGObject, which Omarchy ships. Without it the desktop entry still works and Show in folder keeps going to your previous file manager.

The desktop entry half from a terminal:

```bash
xdg-mime default xyzlab.omafile.desktop inode/directory
xdg-mime query default inode/directory
```

### Copying over something that exists

Omafile asks what to do. Choose with the mouse, or with the keys under [Keyboard](#when-a-file-already-exists).

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

## Trash in the Bar

Omafile can also sit in the bar as a standalone trash can. The icon is the outlined bin when the trash is empty and the solid one when it is not, with the number of items beside it. Left click opens the trash, right click empties it.

Add it from the Omarchy bar settings: place a second Omafile widget wherever you want it, then set that instance's mode to `trash`. It is a separate bar entry, so it moves and sits apart from the main Omafile icon, on the other side of the bar if you like.

By default the first right click arms the widget and turns it red for four seconds; a second right click in that window empties the trash. Turn off `trashConfirm` on that instance if you would rather the first right click empty it outright.

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
| `showTrash` | Show a trash can beside the bar icon |
| `trashConfirm` | Ask before a right click empties the trash |

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
