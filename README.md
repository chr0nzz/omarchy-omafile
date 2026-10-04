A lightweight, fast file manager plugin for Omarchy running in the shell.

![Omafile](preview.png)

## Features

* Real resizable window with tabs for multiple locations
* Dual pane layout with one-key copy and move between panes
* List, compact, grid and gallery views, with zoom from Ctrl+Scroll or the View menu
* Sort from the View menu in any view: A to Z, Z to A, last modified, size or type
* Quick preview with Space: images full size, text files such as `.yml` as plain text
* Mouse back and forward buttons move through folder history
* Can stand in for the GTK file chooser, so browser uploads and downloads open Omafile
* Live directory watching: external changes appear immediately
* Background copy and move with persistent progress tracking
* Freedesktop trash integration, compatible with GNOME Files, with Empty trash and Restore in the trash view
* Recursive file search across directories
* Image previews in list, compact, grid and gallery view, plus thumbnails for videos, PDFs, office files and anything else your system has a thumbnailer for
* Recent files, and bookmarks for the folders you use most
* Connect to SMB, SFTP, WebDAV and other servers
* Settings inside the window, no config file editing
* Bar widget with places, drives, transfers, and trash overview
* Optional standalone trash can in the bar, placeable anywhere, with a live count
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
o.window({ class = "^org.quickshell$", title = "^Omafile( [0-9]+)?$" }, { float = true, size = { 1100, 720 }, center = true })
```

Omarchy makes every window slightly transparent, so your wallpaper shows faintly through Omafile the same way it does through every other app. If you would rather Omafile were solid, opt it out of that rule:

```lua
o.window({ class = "^org.quickshell$", title = "^Omafile( [0-9]+)?$" }, { tag = "-default-opacity", opacity = "1 1" })
```

## Usage

Super+E toggles the window. If it is already open it comes to the front. Ctrl+Q closes it, and Escape closes the popup.

To open another window each time instead, bind `omarchy-shell omafile newwindow`. Extra windows are titled `Omafile 2`, `Omafile 3` and so on, and each opens a little down and to the right of the first. Escape closes only the window you are in.

```lua
hl.unbind("SUPER + E")
o.bind("SUPER + E", "Omafile (new window)", "omarchy-shell omafile newwindow")
```

Moving around is covered in [Keyboard](#keyboard); F1 shows the same list inside the window.

### Finding things

Click any part of the address bar to type a path, or press Ctrl+L. Click a breadcrumb to jump to that folder.

The magnifier at the end of the address bar filters the folder you are in. Ctrl+F searches that folder and everything inside it instead. Escape clears the text, then leaves the results.

### Sorting

The Sort by section of the View menu sorts by A to Z, Z to A, last modified, first modified, largest, smallest or type, in every view. In list view you can also click Name, Size, Type or Modified. Click the same column again to reverse its order.

### Views

The View button in the toolbar opens one menu for the layout, zoom, sorting and hidden files. It switches between list, compact, grid and gallery. Compact packs names into columns. Gallery shows large image previews. Ctrl+1 to Ctrl+4 pick them from the keyboard.

Grid view can show captions under each name, like GNOME Files: pick up to three from Size (item count for folders), Type, Modified and Permissions under Settings, View, or with Grid captions in the View menu. The first shows at any size, the second from 90 percent zoom and the third from 130 percent.

Zoom scales rows, icons and grid cells from 50 to 300 percent. Use the minus and plus buttons in the View menu, Ctrl with the scroll wheel over a pane, or Ctrl+Plus, Ctrl+Minus and Ctrl+0. Click the percentage to go back to 100 percent.

### Preview

Press Space on a file to preview it without opening another app. Images are shown full size. Text files such as `.yml`, `.json`, `.md` or scripts are shown as text, up to the first 256 KB. Arrow keys move to the next file while the preview stays open. Enter opens the file, and Space or Escape closes the preview. Preview is also in the right click menu.

### Transfers

Copies and moves run in the background. Quick ones finish silently. Anything still running after about a second opens a small Transfers panel in the bottom right with progress, speed and time left. Click a transfer to see where it goes, how many files are done and any errors. Minimize the panel into the status bar and it stays there, with a progress bar, until you click it again. Finished transfers stay in the list so you can check them later: clear them one by one, or all at once with Clear completed.

### Thumbnails

Videos, PDFs, office documents and other files get a thumbnail from the thumbnailers your system already has, the same ones GNOME Files uses. Omarchy ships ffmpegthumbnailer for video and Evince for PDF. Thumbnails are stored in `~/.cache/thumbnails` and shared with GNOME Files, so anything it has already thumbnailed shows up straight away. The cache only holds copies you can read yourself, but it keeps them after the original moves, so clear it if a folder is private. Only root-owned, non-writable-by-others definitions in `/usr/share/thumbnailers` and `/usr/local/share/thumbnailers` are used. User thumbnailers and definitions supplied through XDG data directories are ignored. Turn thumbnails off with the `thumbnails` setting.

### The sidebar

Places, then your bookmarks, then drives, then Network, then Trash.

Bookmarks are shared with GNOME Files and the GTK file chooser: Omafile reads and writes `~/.config/gtk-3.0/bookmarks`, so a bookmark added in either place shows up in the other straight away. To add one, right click a folder and choose Bookmark this folder, press Ctrl+D, or drag folders onto the Bookmarks heading in the sidebar. An empty bookmark list shows a drop spot. Right click a bookmark to rename it or remove it, or use the cross beside it. Bookmarks from earlier Omafile versions are merged in once. A local backup stays in `state.json`; migration completes only after the GTK write succeeds. Read or write errors appear in the status bar, and pending edits retry after a helper restart or another bookmark change.

Right click places, bookmarks and network entries for a menu: open here or in another tab or pane, copy the path, show properties, remove a bookmark, connect or disconnect a network share, or empty Trash. Drive controls remain provided by the upstream implementation.

Recent lists the files you opened most recently, newest first, from the same history the rest of the desktop uses. Opening one goes straight to the file. There is no folder above it, so leave by picking a place or a bookmark.

Hover a drive and click the eye to hide it. Hidden drives come back from Settings.

### Network drives

Connect to a server mounts an SMB share, an SFTP host, FTP or WebDAV. Servers you have used before are listed so one click reconnects, and any server the network advertises appears alongside them. Each server shows once under Network, dimmed while it is not connected. Click a server you used before to connect straight away with the address, user name, domain and anonymous choice you used last time. Passwords are never stored: SSH keys and your keyring cover most servers, and if the server still wants a password the Connect dialog opens filled in. Right click a server for Connect, Edit to change its details, or Forget this server. Right click a connected share, or use the eject button beside it, to disconnect.

This uses GVFS and needs no root. Install `gvfs-smb` for Windows shares if it is missing.

### Terminal

Right click a folder, or empty space for the folder you are in, and choose Open in terminal, or press Ctrl+.. With [Claude Code](https://claude.com/claude-code) installed, Open Claude Code here starts it in that folder and leaves a shell open when it exits.

### Settings

Ctrl+Comma, or Settings in the menu at the right end of the toolbar. Hidden files, folders-first ordering, image previews, trash behaviour, the drive list, and the trash can in the bar.

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

### Picking files for other apps

Turn on Pick files for other apps in Settings, under Opening. When a browser or another app asks you to choose a file, for example Upload file in Chrome or Firefox, Omafile opens instead of the GTK file chooser. The same goes for Save as and download locations. A bar along the bottom of the window shows what the app asked for, with a name box when saving and the app's file type filters. Pick a file and press Enter or the Select button, or press `Escape` to cancel.

It works through the desktop portal, the same route every app uses to ask for a file. Omafile registers a small D-Bus service in your home directory and tells the portal to send file chooser requests to it. Other portals, such as screen sharing, are left alone.

The portal only reads its list of backends from `/usr/share/xdg-desktop-portal/portals`, so enabling asks for your password once to install one file there, `omafile.portal`. Nothing else outside your home directory changes.

Turning it off sends file chooser requests back to the GTK portal. The file in `/usr/share` stays behind. It does nothing on its own, and you can remove it with `sudo rm /usr/share/xdg-desktop-portal/portals/omafile.portal`.

This needs PyGObject, which Omarchy ships. Apps that are already open may keep the old file chooser until you restart them.

The same from a terminal:

```bash
~/.config/omarchy/plugins/xyzlab.omafile/bin/omafile-portal-setup enable
~/.config/omarchy/plugins/xyzlab.omafile/bin/omafile-portal-setup status
~/.config/omarchy/plugins/xyzlab.omafile/bin/omafile-portal-setup disable
```

`enable` adds `org.freedesktop.impl.portal.FileChooser=omafile` to `~/.config/xdg-desktop-portal/hyprland-portals.conf` and keeps anything else you have in that file. `disable` removes only that line.

### Clipboard and drag and drop

Copy, cut and paste use the system clipboard, so files copied in GNOME Files, a browser or a chat app paste into Omafile, and files copied in Omafile paste into them. A cut offers GNOME's format, so pasting it in GNOME Files moves the files. Paste an image from the clipboard to save it as a new file. Cut files show dimmed icons and a scissors marker until the clipboard changes or the files are pasted.

Drag files onto a folder, a sidebar place or the pane background to move them there, or out of the window into another app. Dropping on another drive copies instead of moving, as in GNOME Files. Dropping on Trash moves them to the trash. Drag from the space beside a name to draw a selection box instead of dragging the item. Files can also be dropped on the path bar or a breadcrumb folder, using the same move or copy rules as pane and sidebar drops.

### Copying over something that exists

Omafile asks what to do. Choose with the mouse, or with the keys under [Keyboard](#when-a-file-already-exists).

## Keyboard

Omafile follows GNOME Files conventions, so shortcuts you already know work here.

### Navigation

| Keys | Action |
|------|--------|
| `Enter` / `Ctrl+O` / `Alt+Down` | Open the selected items, folders in new tabs when several are selected. Asks first for more than five |
| `Backspace` / `Alt+Up` | Go to the parent folder |
| `Alt+Left` / `Alt+Right` | Back and forward |
| Mouse back / forward | Back and forward |
| `Alt+Home` | Go to your home folder |
| `Ctrl+L` | Type a path |
| `/` or `~` | Type a path, starting from root or home |
| `Home` / `End` | First and last item |
| `F5` / `Ctrl+R` | Refresh |
| `Ctrl+.` | Open a terminal in this folder |

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
| `F10` | Open the menu for the folder itself |

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
| `Delete` | Move to trash, or delete permanently when already in the trash |
| `Shift+Delete` | Delete permanently |
| `Ctrl+I` / `Alt+Enter` | Properties |
| `Ctrl+D` | Bookmark this folder |

Inside the trash, a bar above the files shows how many items it holds and has an **Empty trash** button, which asks before deleting everything for good. The right click menu there offers **Restore**, which puts items back where they came from, and **Delete permanently** in place of Move to trash.

Undo covers trash, rename, move, copy and new file or folder. Undoing a trash puts the items back where they were, and undoing a copy trashes what the copy created.

### Panes and tabs

| Keys | Action |
|------|--------|
| `Ctrl+T` | New tab with the same view, sort and hidden files setting |
| `Ctrl+W` | Close the tab, or the window when it is the last one |
| `Ctrl+Shift+T` | Reopen the last closed tab |
| `Ctrl+PageUp` / `Ctrl+PageDown` | Previous and next tab |
| `Ctrl+Shift+PageUp` / `Ctrl+Shift+PageDown` | Move the tab left or right |
| `Alt+1` to `Alt+9` | Go to that tab |
| `Ctrl+Enter` / middle click | Open a folder in a new tab |
| `F6` | Split into two panes |
| `Tab` | Switch the active pane, while split |
| `Ctrl+Shift+C` / `Ctrl+Shift+M` | Copy and move to the other pane |

### View

| Keys | Action |
|------|--------|
| `Ctrl+1` / `Ctrl+2` / `Ctrl+3` / `Ctrl+4` | List, grid, compact and gallery |
| `Ctrl+Plus` / `Ctrl+Minus`, or `Ctrl` + scroll | Zoom in and out |
| `Ctrl+0` | Reset the zoom to 100 percent |
| `Space` | Preview the item under the cursor |
| `Ctrl+H` | Show hidden files |
| `F9` / `Ctrl+B` | Show or hide the sidebar |
| `Ctrl+F`, or just type | Search in this folder |
| `Ctrl+Shift+F` | Search your whole home folder |
| `Ctrl+Comma` | Settings |
| `F1` / `Ctrl+?` | The shortcut list |
| `Ctrl+Q` | Close the window |

Typing an ordinary character opens the search box with that character already typed, the way GNOME Files does.

### When a file already exists

| Keys | Action |
|------|--------|
| `R` / `K` / `S` / `A` | Replace, keep both, skip, skip all |

Escape skips the file.

Super+C, Super+V and Super+X are Omarchy's universal clipboard shortcuts. Omarchy translates them to Ctrl+C, Ctrl+V and Ctrl+X before they reach the window, so they copy, paste and cut files in Omafile too.

## Trash in the Bar

Turn on **Trash can in the bar** in Settings. Omafile adds a trash can to your bar as its own widget, so you can drag it anywhere from the Omarchy bar settings, including the other side of the bar from the file manager icon. Turning the setting off removes it again.

The icon is outlined when the trash is empty and solid when it is not, with the number of items beside it. The count updates on its own as things are deleted or restored from anywhere, not only from Omafile, and it covers every trash directory on the system, so a removable drive with its own trash is included.

Left click opens the trash. Right click empties it: the first right click turns it red for four seconds, and a second right click within that window empties it, so a stray click cannot wipe anything. Turn off **Ask before emptying** if you want the first right click to empty it outright.

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
| `defaultView` | Start in `list`, `compact`, `grid` or `gallery` view |
| `terminal` | Terminal command to open in the current directory |
| `editor` | Text editor command to open selected files |
| `showTransferBadge` | Show a progress ring on the bar icon while a transfer runs |
| `showDrives` | Show the Drives section in the sidebar |
| `thumbnails` | Show image previews and thumbnails |
| `glyph` | Custom icon for the bar widget |
| `mode` | `files` for the file manager icon, `trash` for a trash can |
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

Add or remove the trash can in the bar:

```bash
omarchy-shell omafile trashicon on
omarchy-shell omafile trashicon off
omarchy-shell omafile trashicon status
```

Toggle the window from a keybinding or script:

```bash
omarchy-shell omafile toggle
```

Open an additional window:

```bash
omarchy-shell omafile newwindow
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
