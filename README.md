# Files for Omarchy

A Nautilus-shaped file manager that runs as an Omarchy shell overlay. It has
the familiar places sidebar, header breadcrumbs, icon and list views, search,
trash, rename/copy/move, and a proper properties dialog. On top of that it has
the two-pane keyboard flow of
[OMARCHOMANDER](https://github.com/asfarsadewa/omarchy-omarchomander): two
independent folders, Tab to switch, F5/F6 to copy or move between them.

This is not a fork of GNOME Files and it does not embed GTK. The window is
drawn with the Omarchy shell theme tokens (colors, corner radius, font scale)
and the filesystem work happens in a small Python backend, so it follows the
active Omarchy theme and needs no extra packages.

## Install

On an Omarchy Quattro machine:

```bash
cp -r omarchy-files ~/.config/omarchy/plugins/popkenr.files
omarchy plugin validate ~/.config/omarchy/plugins/popkenr.files
omarchy plugin enable popkenr.files
```

Or publish the repo and install it the normal way:

```bash
omarchy plugin add https://github.com/<you>/omarchy-files.git
omarchy plugin enable popkenr.files
```

A folder icon appears in the bar. Click it to open Files. A hotkey is not
installed by default; add one to `~/.config/hypr/bindings.conf`:

```conf
bindd = SUPER SHIFT, N, Files, exec, omarchy-shell shell toggle popkenr.files '{}'
```

Then `hyprctl reload`. The same command works from a terminal.

## Keys

The clickable bar above the status line is the Total Commander function-key
bar:

| Key | Action |
|---|---|
| `F1` | Help |
| `F2` | Rename |
| `F3` | View the file: text, hex for binary files, or an image |
| `F4` | Edit in the Omarchy editor |
| `F5` | Copy the selection to the other pane |
| `F6` | Move the selection to the other pane |
| `F7` | New folder |
| `F8` | Move to Trash (in Trash: delete permanently) |
| `F9` | Open the menu |
| `F10` | Close Files |
| `Shift+F6` | Rename (the Total Commander alias) |
| `Shift+F8` | Delete permanently |
| `Alt+F4` | Close Files |

`F5` and `F6` need the second pane; the bar tells you so when it is off.
Total Commander itself uses `F2` to reread; this keeps `F2` for rename and
`Ctrl+R` for reload.

Other keys:

| Key | Action |
|---|---|
| `Enter` | Open the item / enter the folder |
| `Backspace`, `Alt+Up` | Parent folder, with the cursor on the folder you left |
| `Alt+Left` / `Alt+Right` | Back / forward |
| `Ctrl+L` | Type a location |
| `Ctrl+F` or just typing | Search this folder and below |
| `Esc` | Clear search/menu/dialog/viewer, otherwise close |
| `Ctrl+H` | Show hidden files |
| `Ctrl+D` | Add the current folder to Places |
| `Ctrl+R` | Reload |
| `Ctrl+A` | Select all |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / cut / paste |
| `Delete` | Move to Trash (asks first in Trash) |
| `Shift+Delete` | Delete permanently, after confirmation |
| `Ctrl+Shift+N` | New folder |
| `Ctrl+I` | Properties |
| `Ctrl+W` | Close Files |

Two-pane keys, from OMARCHOMANDER:

| Key | Action |
|---|---|
| `Ctrl+Shift+D` | Show or hide the second pane |
| `Tab` | Switch the active pane |
| `Ctrl+U` | Swap the two panes |

In a split view each pane shows its own path strip; the active one is
highlighted. The other pane can be driven with the mouse or with Tab first.

## What it does

- Sidebar with Home, XDG folders, Trash, Computer, and removable volumes under
  `/run/media/<user>` and `/media/<user>`.
- Add any folder to the sidebar with *Add This Folder to Places* (`Ctrl+D`) or
  by right-clicking a folder. Saved places persist between sessions; hover a
  saved place and click `✕` to remove it. They live in
  `$XDG_STATE_HOME/omarchy/files-places.json`.
- Nautilus layout: header bar, breadcrumbs that scroll to the deepest segment,
  icon grid with image thumbnails, list view with sortable columns, status bar
  with item/selection size and free space.
- Starts in dual-pane and list view. The `A−` / `A+` buttons at the top right
  scale the interface text from 80% to 160%.
- Search below the current folder, case-insensitive, capped at 400 results.
- Freedesktop home trash: move, list with original location, restore, empty.
  Items land in `$XDG_DATA_HOME/Trash`, so other file managers can restore them.
- Copy/move with per-file Replace/Skip/Cancel on conflicts, merge for folders,
  cross-filesystem moves, progress in the status bar, and Cancel.
- Rename, new folder, permanent delete, properties, `xdg-open`.
- Total Commander-style function-key bar and `F3` lister (text, hex, images).
- Hidden files, sorting by name/size/modified, grid/list toggle.
- Everything is keyboard operable; the mouse works too.

## Deliberate limits

Kept out to keep this one process, no extra dependencies, and no risky magic:

- No drag and drop, tabs, multiple windows, Recent/Starred, network or GVfs
  mounts, "Open With", compression, batch rename, permission editing, or undo.
- Trash support is the home trash only. Trashing to a separate mounted volume
  would need `.Trash-$uid` on that volume.
- Search is a bounded filesystem walk, not Tracker. Very large trees stop at
  400 results or 20 seconds.
- The lister shows text, a hex dump for binaries, and images. PDF, video,
  archives and office documents still go to `xdg-open`.
- Open folders last for the shell session; saved Places persist across restarts.

## Backend and tests

`backend/filesd.py` speaks one JSON object per line on stdin/stdout. Read-only
commands are answered on the main loop; one mutating operation at a time runs
on a worker thread, so the window keeps painting, can show progress, and can
cancel. Standard library only:

```bash
python3 -m unittest discover -s tests
```

QML check on an Omarchy machine:

```bash
qmllint -I "$OMARCHY_PATH/shell" qml/*.qml
```

## License

MIT. The two-pane key design and the name OMARCHOMANDER belong to Asfar
Sadewa; this plugin does not share its code.
