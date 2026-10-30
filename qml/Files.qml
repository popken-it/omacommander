// A Nautilus-shaped file manager for the Omarchy shell, with the two panes
// and commander keys of omarchomander. Everything is drawn with the shell
// theme tokens; the actual files live in backend/filesd.py.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "Format.js" as Format

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "popkenr.omancommander"
  readonly property string trashPath: ":trash:"
  readonly property string home: backend.home || Quickshell.env("HOME") || "/"

  property bool retro: false
  property bool ultraRetro: false
  FontLoader {
    id: vgaFont
    source: Qt.resolvedUrl("../fonts/Px437_IBM_VGA_9x16.ttf")
  }
  readonly property bool vgaReady: vgaFont.status === FontLoader.Ready
  readonly property string uiFont: ultraRetro && vgaReady ? vgaFont.name : "sans-serif"
  readonly property string monoFont: ultraRetro && vgaReady ? vgaFont.name : "monospace"

  readonly property color panelBg: retro ? "#0000a8" : Commons.Color.popups.background
  readonly property color ink: retro ? "#c0c0c0" : Commons.Color.popups.text
  readonly property color accent: retro ? "#ffff55" : Commons.Color.accent
  readonly property color danger: retro ? "#ff5555" : Commons.Color.urgent
  readonly property color scrim: retro ? "#8000002a" : Commons.Color.menu.scrim
  readonly property color line: retro ? "#00aaaa" : Util.alpha(Commons.Color.popups.text, 0.12)
  readonly property color hoverBg: retro ? "#3300aaaa" : Util.alpha(Commons.Color.popups.text, 0.07)
  readonly property color chromeBg: retro ? "#000080" : Util.alpha(Commons.Color.popups.text, 0.035)
  readonly property color sidebarBg: retro ? "#000080" : Util.alpha(Commons.Color.popups.text, 0.02)
  readonly property color selectedBg: ultraRetro ? "#00aaaa" : (retro ? "#005f5f" : Util.alpha(Commons.Color.accent, 0.18))
  readonly property real defaultFontScale: 1.2
  property real fontScale: defaultFontScale
  readonly property int fCaption: ultraRetro ? 16 : Math.max(1, Math.round(Style.font.caption * fontScale))
  readonly property int fBodySmall: ultraRetro ? 16 : Math.max(1, Math.round(Style.font.bodySmall * fontScale))
  readonly property int fBody: ultraRetro ? 16 : Math.max(1, Math.round(Style.font.body * fontScale))
  readonly property int fTitle: ultraRetro ? 16 : Math.max(1, Math.round(Style.font.title * fontScale))
  readonly property int fHeading: ultraRetro ? 16 : Math.max(1, Math.round(Style.font.heading * fontScale))

  readonly property int headerHeight: ultraRetro ? Style.space(30) : Math.max(Style.space(46), fTitle + Style.space(30))
  readonly property int statusHeight: ultraRetro ? Style.space(20) : Math.max(Style.space(26), fCaption + Style.space(12))
  readonly property int fkeyHeight: ultraRetro ? Style.space(20) : Math.max(Style.space(34), 2 * fCaption + Style.space(14))
  readonly property int sidebarWidth: ultraRetro ? Style.space(148) : Style.space(188)
  // Boomer-mode panels sit in from the window and each other, so the blue
  // background shows on both sides of their vertical borders.
  readonly property int paneGap: ultraRetro ? Style.space(8) : 1
  readonly property int paneInset: ultraRetro ? Style.space(8) : 0

  readonly property var fkeys: [
    { key: "F1", label: "Help", action: "help" },
    { key: "F2", label: "Rename", action: "rename" },
    { key: "F3", label: "View", action: "view" },
    { key: "F4", label: "Edit", action: "edit" },
    { key: "F5", label: "Copy", action: "copyOther" },
    { key: "F6", label: "Move", action: "moveOther" },
    { key: "F7", label: "New", action: "mkdir" },
    { key: "F8", label: "Delete", action: "trash" },
    { key: "F9", label: "Menu", action: "menu" },
    { key: "F10", label: "Quit", action: "quit" }
  ]

  property bool viewerOpen: false
  property string viewerTitle: ""
  property string viewerText: ""
  property string viewerImage: ""
  property string viewerInfo: ""
  property bool viewerWrap: true
  property int viewerReq: 0

  property int activePane: 0
  property bool split: true
  property bool sidebarVisible: true
  property string viewMode: "list"
  property string sortMode: "name"
  property bool sortAsc: true
  property bool showHidden: false

  property bool searchActive: false
  property string searchText: ""
  property int searchReq: 0
  property bool locationMode: false
  property string locationText: ""

  property string dialog: ""
  property string dialogTitle: ""
  property string dialogText: ""
  property var dialogActions: []
  property string pendingAction: ""
  property var pendingPaths: []
  property var props: ({})

  property var job: ({})
  property var clipboard: ({ mode: "", paths: [] })
  property bool pendingCut: false

  property bool menuVisible: false
  property real menuX: 0
  property real menuY: 0
  property var menuItems: []
  property string menuEntryPath: ""
  readonly property int menuWidth: Style.space(252)

  property string toastText: ""
  property bool toastAngry: false
  property bool initialised: false
  property bool recovering: false

  function currentPane() { return activePane === 0 ? paneA : paneB }
  function otherPane() { return activePane === 0 ? paneB : paneA }

  function focusKeys() {
    if (!opened) return
    Qt.callLater(function() {
      if (root.searchActive) {
        searchField.forceActiveFocus()
        return
      }
      if (root.locationMode) {
        locationField.forceActiveFocus()
        return
      }
      if (root.dialog === "" && !root.menuVisible)
        card.forceActiveFocus()
    })
  }

  function showToast(message, angry) {
    if (!message) return
    toastText = String(message)
    toastAngry = angry === true
    toastTimer.restart()
  }

  function baseName(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut >= 0 ? text.slice(cut + 1) : text
  }

  function parentOf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut > 0 ? text.slice(0, cut) : "/"
  }

  // ------------------------------------------------------------- open/close

  function open(payloadJson) {
    if (dialog === "conflict" && backend.ready)
      backend.send({ op: "resolve", choice: "abort" })
    opened = true
    searchActive = false
    searchText = ""
    locationMode = false
    dialog = ""
    menuVisible = false
    viewerOpen = false
    viewerReq = 0
    paneA.clearSearch()
    paneB.clearSearch()
    backend.open(payloadJson)

    if (!initialised) {
      paneA.ensure(home)
      paneB.ensure(home)
      initialised = true
    } else {
      if (paneA.path !== "") paneA.refresh()
      if (paneB.path !== "") paneB.refresh()
    }
    if (backend.places.length === 0) backend.request("places", {})
    Qt.callLater(function() { card.forceActiveFocus() })
  }

  function close() {
    if (dialog === "conflict" && backend.ready)
      backend.send({ op: "resolve", choice: "abort" })
    opened = false
    searchActive = false
    searchText = ""
    locationMode = false
    menuVisible = false
    dialog = ""
    dialogActions = []
    pendingAction = ""
    pendingPaths = []
    viewerOpen = false
    viewerReq = 0
    paneA.clearSearch()
    paneB.clearSearch()
    backend.close()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else Quickshell.execDetached(["omarchy-shell", "shell", "hide", pluginId])
  }

  // ---------------------------------------------------------------- places

  function choosePath(target) {
    if (!target) return
    if (searchActive) finishSearch()
    currentPane().navigate(target)
  }

  // ----------------------------------------------------------------- panes

  function setActive(index) {
    if (index !== 0 && index !== 1) return
    if (searchActive) finishSearch()
    activePane = index
    focusKeys()
  }

  function toggleSplit() {
    if (ultraRetro) return
    if (searchActive) finishSearch()
    split = !split
    if (!split) {
      activePane = 0
      paneB.clearSearch()
    } else if (paneB.path === "") {
      paneB.ensure(home)
    }
    focusKeys()
  }

  function swapPanes() {
    var left = paneA.path
    var right = paneB.path
    paneA.navigate(right)
    paneB.navigate(left)
    split = true
    focusKeys()
  }

  function refreshPanes() {
    if (paneA.path !== "") paneA.refresh()
    if (paneB.path !== "") paneB.refresh()
  }

  function pathIsUnder(child, parent) {
    return child === parent || child.indexOf(parent.replace(/\/+$/, "") + "/") === 0
  }

  function recoverPanes(removed) {
    if (!removed || removed.length === 0) return
    var panes = [paneA, paneB]
    for (var i = 0; i < panes.length; i++) {
      var pane = panes[i]
      if (!pane.path) continue
      var target = ""
      for (var j = 0; j < removed.length; j++) {
        if (!removed[j] || !pathIsUnder(pane.path, removed[j])) continue
        target = parentOf(removed[j])
        var guard = 0
        while (target !== "/" && guard < removed.length + 1) {
          var nested = false
          for (var k = 0; k < removed.length; k++)
            if (pathIsUnder(target, removed[k])) nested = true
          if (!nested) break
          target = parentOf(target)
          guard++
        }
        break
      }
      if (target && target !== pane.path) pane.navigate(target)
    }
  }

  function toggleHidden() {
    showHidden = !showHidden
    if (searchActive) runSearch()
  }

  function changeFontSize(delta) {
    if (ultraRetro) return
    var next = Math.round((fontScale + delta) * 10) / 10
    fontScale = Math.max(0.8, Math.min(1.6, next))
  }

  onRetroChanged: if (!retro) ultraRetro = false
  onUltraRetroChanged: {
    if (ultraRetro && !retro) {
      ultraRetro = false
      return
    }
    if (ultraRetro) {
      sidebarVisible = true
      split = true
      viewMode = "list"
    }
  }

  // ----------------------------------------------------------------- search

  function openSearch(initial) {
    locationMode = false
    searchActive = true
    searchText = String(initial || "")
    paneA.clearSearch()
    paneB.clearSearch()
    Qt.callLater(function() {
      searchField.text = root.searchText
      searchField.forceActiveFocus()
      searchField.cursorPosition = searchField.text.length
      root.runSearch()
    })
  }

  function finishSearch() {
    searchActive = false
    searchText = ""
    searchReq = 0
    paneA.clearSearch()
    paneB.clearSearch()
    focusKeys()
  }

  function runSearch() {
    if (!searchActive) return
    var query = String(searchText || "").trim()
    var pane = currentPane()
    if (query === "" || pane.path === "") {
      pane.clearSearch()
      searchReq = 0
      return
    }
    searchReq = backend.request("search", { path: pane.path, query: query, hidden: showHidden })
  }

  // -------------------------------------------------------------- location

  function openLocation() {
    searchActive = false
    searchText = ""
    paneA.clearSearch()
    paneB.clearSearch()
    locationMode = true
    Qt.callLater(function() {
      var start = root.currentPane().trash ? "" : root.currentPane().path
      root.locationText = start
      locationField.text = start
      locationField.forceActiveFocus()
      locationField.selectAll()
    })
  }

  function cancelLocation() {
    locationMode = false
    locationText = ""
    focusKeys()
  }

  function acceptLocation() {
    var target = String(locationText || "").trim()
    if (target === "") return
    locationMode = false
    currentPane().navigate(target)
    focusKeys()
  }

  // ---------------------------------------------------------------- clipboard

  function copySelection(mode) {
    var pane = currentPane()
    var paths = pane.selectionPaths()
    if (paths.length === 0) return
    if (mode === "cut" && pane.trash) {
      showToast("Use Restore to move items out of Trash", true)
      return
    }
    clipboard = { mode: mode, paths: paths }
    pendingCut = false
    showToast((mode === "cut" ? "Cut " : "Copied ") + paths.length +
              (paths.length === 1 ? " item" : " items"))
  }

  function pasteIntoActive() {
    var pane = currentPane()
    if (clipboard.paths.length === 0) return
    if (pane.trash || !pane.writable) {
      showToast("Cannot paste in this folder", true)
      return
    }
    pendingCut = clipboard.mode === "cut"
    backend.request(pendingCut ? "move" : "copy", { sources: clipboard.paths, dest: pane.path })
  }

  function transferToOther(move) {
    if (!split) {
      showToast("Turn on dual pane first (Ctrl+Shift+D)", true)
      return
    }
    var target = otherPane()
    if (target.trash || !target.writable) {
      showToast("The other pane cannot receive files", true)
      return
    }
    var paths = currentPane().selectionPaths()
    if (paths.length === 0) return
    backend.request(move ? "move" : "copy", { sources: paths, dest: target.path })
  }

  function openInOtherPane() {
    if (!split) {
      showToast("Turn on dual pane first (Ctrl+Shift+D)", true)
      return
    }
    var entry = currentPane().cursorEntry()
    if (!entry) return
    otherPane().navigate(entry.dir ? entry.path : parentOf(entry.path))
  }

  // ------------------------------------------------------------- operations

  function openMkdir() {
    var pane = currentPane()
    if (pane.trash || !pane.writable) {
      showToast("Cannot create a folder here", true)
      return
    }
    openInput("mkdir", "New Folder", "Untitled Folder", "Create")
  }

  function openRename() {
    var pane = currentPane()
    var entry = pane.cursorEntry()
    if (!entry) return
    if (pane.trash) {
      showToast("Restore the item before renaming it", true)
      return
    }
    pendingPaths = [entry.path]
    openInput("rename", "Rename", entry.name, "Rename")
  }

  function trashSelection() {
    var pane = currentPane()
    if (pane.trash) {
      confirmDelete()
      return
    }
    var paths = pane.selectionPaths()
    if (paths.length === 0) return
    pendingPaths = paths
    pendingAction = "trash"
    var count = paths.length
    openDialog("confirm", "Are you sure?",
               count + (count === 1 ? " item" : " items") + " will be moved to Trash.",
               [{ label: "No", action: "cancel" },
                { label: "Yes", action: "accept", primary: true }])
  }

  function confirmDelete() {
    var paths = currentPane().selectionPaths()
    if (paths.length === 0) return
    pendingPaths = paths
    pendingAction = "delete"
    var count = paths.length
    openDialog("confirm", "Are you sure?",
               count + (count === 1 ? " item" : " items") +
               " will be deleted permanently. This cannot be undone.",
               [{ label: "No", action: "cancel" },
                { label: "Yes", action: "accept", primary: true, danger: true }])
  }

  function confirmEmptyTrash() {
    pendingAction = "emptyTrash"
    openDialog("confirm", "Are you sure?",
               "Every item in the Trash will be deleted permanently. This cannot be undone.",
               [{ label: "No", action: "cancel" },
                { label: "Yes", action: "accept", primary: true, danger: true }])
  }

  function restoreSelection() {
    if (!currentPane().trash) return
    var paths = currentPane().selectionPaths()
    if (paths.length === 0) return
    backend.request("restore", { paths: paths })
  }

  function showProperties() {
    var entry = currentPane().cursorEntry()
    if (!entry) return
    backend.request("props", { path: entry.path })
  }

  function addToPlaces(path) {
    var target = String(path || currentPane().path)
    if (target === trashPath) {
      showToast("Trash cannot be added to Places", true)
      return
    }
    backend.request("bookmarkAdd", { path: target })
  }

  function removeBookmark(path) {
    backend.request("bookmarkRemove", { path: path })
  }

  function openHelp() {
    openDialog("help", "Function keys — Total Commander style", "",
               [{ label: "Close", action: "close" }])
  }

  function helpLines() {
    return [
      { key: "F1", text: "Help" },
      { key: "F2", text: "Rename the item under the cursor" },
      { key: "F3", text: "View: text, hex for binary files, images" },
      { key: "F4", text: "Edit the item in the Omarchy editor" },
      { key: "F5", text: "Copy the selection to the other pane" },
      { key: "F6", text: "Move the selection to the other pane" },
      { key: "F7", text: "New folder" },
      { key: "F8", text: "Move to Trash (in Trash: delete permanently)" },
      { key: "F9", text: "Open the menu" },
      { key: "F10", text: "Close OmaNCommander" },
      { key: "Shift+F6", text: "Rename (Total Commander alias)" },
      { key: "Shift+F8", text: "Delete permanently" },
      { key: "Alt+F4", text: "Close OmaNCommander" },
      { key: "Tab", text: "Switch pane (dual pane)" },
      { key: "Ctrl+Shift+D", text: "Show or hide the second pane" },
      { key: "Ctrl+L", text: "Type a location" },
      { key: "Ctrl+F", text: "Search this folder and below" },
      { key: "Ctrl+H", text: "Show hidden files" },
      { key: "Ctrl+D", text: "Add this folder to Places" },
      { key: "A− / A+", text: "Smaller or larger text (top right)" },
      { key: "Ctrl+- / Ctrl+=", text: "Smaller or larger text" },
      { key: "Ctrl+0", text: "Reset text to 120%" },
      { key: "Ctrl+Shift+R", text: "Toggle Retro Norton Commander colours" },
      { key: "Ctrl+Shift+U", text: "Toggle Boomer-mode 9x16 text mode (Retro only)" },
      { key: "Ctrl+R", text: "Reload" },
      { key: "Delete", text: "Move to Trash" },
      { key: "Shift+Delete", text: "Delete permanently" }
    ]
  }

  function viewCursor() {
    var entry = currentPane().cursorEntry()
    if (!entry) return
    if (entry.dir) {
      showToast("Select a file to view", true)
      return
    }
    viewerOpen = true
    viewerTitle = entry.name
    viewerText = ""
    viewerImage = ""
    viewerInfo = ""
    viewerWrap = true
    viewerReq = 0
    if (entry.kind === "image") {
      viewerImage = entry.path
      viewerInfo = Format.bytes(entry.size)
      return
    }
    viewerText = "Loading…"
    viewerReq = backend.request("read", { path: entry.path })
  }

  function closeViewer() {
    viewerOpen = false
    viewerReq = 0
    viewerText = ""
    viewerImage = ""
    viewerInfo = ""
    focusKeys()
  }

  function editCursor() {
    var entry = currentPane().cursorEntry()
    if (!entry) return
    if (entry.dir) {
      showToast("Select a file to edit", true)
      return
    }
    Quickshell.execDetached(["omarchy-launch-editor", entry.path])
  }

  function runFunction(action) {
    switch (action) {
    case "help": openHelp(); break
    case "rename": openRename(); break
    case "view": viewCursor(); break
    case "edit": editCursor(); break
    case "copyOther": transferToOther(false); break
    case "moveOther": transferToOther(true); break
    case "mkdir": openMkdir(); break
    case "trash": trashSelection(); break
    case "menu": openAppMenu(); break
    case "quit": dismiss(); break
    }
  }

  function openExternal(path) {
    if (!path) return
    Util.execArgv(["gio", "open", path])
  }

  // ---------------------------------------------------------------- dialogs

  function openDialog(kind, title, text, actions) {
    dialog = kind
    dialogTitle = title
    dialogText = text
    dialogActions = actions
    Qt.callLater(function() { card.forceActiveFocus() })
  }

  function openInput(kind, title, initial, confirmLabel) {
    dialog = kind
    dialogTitle = title
    dialogText = ""
    dialogActions = [{ label: "Cancel", action: "cancel" },
                     { label: confirmLabel, action: "accept", primary: true }]
    Qt.callLater(function() {
      dialogField.text = initial
      dialogField.forceActiveFocus()
      dialogField.selectAll()
    })
  }

  function closeDialog() {
    dialog = ""
    dialogActions = []
    dialogText = ""
    pendingAction = ""
    pendingPaths = []
    if (dialogField) dialogField.text = ""
    focusKeys()
  }

  function invalidName(name) {
    return name === "" || name === "." || name === ".." || name.indexOf("/") >= 0
  }

  function runDialogAction(action) {
    if (action === "cancel") {
      if (dialog === "conflict") backend.send({ op: "resolve", choice: "abort" })
      closeDialog()
      return
    }
    if (action === "close") {
      closeDialog()
      return
    }
    if (action === "skip") {
      backend.send({ op: "resolve", choice: "skip" })
      closeDialog()
      return
    }
    if (action === "replace") {
      backend.send({ op: "resolve", choice: "replace" })
      closeDialog()
      return
    }
    if (action !== "accept") return

    if (dialog === "mkdir" || dialog === "rename") {
      var kind = dialog
      var name = String(dialogField.text || "").trim()
      if (invalidName(name)) {
        showToast("Enter a name without /", true)
        return
      }
      if (kind === "mkdir") {
        backend.request("mkdir", { path: currentPane().path, name: name })
      } else {
        backend.request("rename", { path: pendingPaths[0], name: name })
      }
      closeDialog()
      return
    }

    if (dialog === "confirm") {
      if (pendingAction === "trash")
        backend.request("trash", { paths: pendingPaths })
      else if (pendingAction === "delete")
        backend.request("delete", { paths: pendingPaths })
      else if (pendingAction === "emptyTrash")
        backend.request("emptyTrash", {})
      closeDialog()
    }
  }

  // ------------------------------------------------------------------ menus

  function showMenuAt(point) {
    menuX = point.x + Style.space(4)
    menuY = point.y + Style.space(4)
    menuVisible = true
  }

  function openAppMenu() {
    menuEntryPath = ""
    menuItems = appMenuItems()
    menuX = Math.max(Style.space(8), card.width - menuWidth - Style.space(8))
    menuY = headerHeight + Style.space(4)
    menuVisible = true
  }

  function openFileMenu(pane, index, x, y) {
    setActive(pane === paneA ? 0 : 1)
    var entry = pane.items[index]
    if (!entry) return
    if (!pane.isSelected(entry.path)) pane.selectOnly(index)
    menuEntryPath = entry.dir ? entry.path : ""
    menuItems = fileMenuItems(pane)
    showMenuAt(pane.mapToItem(card, x, y))
  }

  function sep() { return { sep: true } }

  function appMenuItems() {
    var pane = currentPane()
    var items = [
      { label: "New Folder", shortcut: "Ctrl+Shift+N", action: "mkdir" },
      { label: "Add This Folder to Places", shortcut: "Ctrl+D", action: "addPlace" },
      { label: "Paste", shortcut: "Ctrl+V", action: "paste" },
      sep(),
      { label: "Select All", shortcut: "Ctrl+A", action: "selectAll" },
      { label: "Show Hidden Files", shortcut: "Ctrl+H", action: "hidden", check: showHidden },
      { label: "Reload", shortcut: "Ctrl+R", action: "refresh" },
      sep(),
      { label: "Sort by Name", action: "sortName", check: sortMode === "name" },
      { label: "Sort by Size", action: "sortSize", check: sortMode === "size" },
      { label: "Sort by Modified", action: "sortModified", check: sortMode === "modified" },
      sep(),
      { label: "Dual Pane", shortcut: "Ctrl+Shift+D", action: "split", check: split }
    ]
    if (pane.trash) {
      items.push(sep())
      items.push({ label: "Empty Trash", action: "emptyTrash", danger: true })
    }
    items.push(sep())
    items.push({ label: "Close", shortcut: "Esc", action: "close" })
    return items
  }

  function fileMenuItems(pane) {
    var entry = pane.cursorEntry()
    if (!entry) return appMenuItems()
    var items = [{ label: "Open", shortcut: "Enter", action: "open" }]
    if (entry.dir && !pane.trash)
      items.push({ label: "Add to Places", shortcut: "Ctrl+D", action: "addPlace" })
    if (pane.trash) {
      items.push({ label: "Restore", action: "restore" })
    }
    items.push(sep())
    items.push({ label: "Copy", shortcut: "Ctrl+C", action: "copy" })
    items.push({ label: "Cut", shortcut: "Ctrl+X", action: "cut" })
    if (split) {
      items.push({ label: "Copy to Other Pane", shortcut: "F5", action: "copyOther" })
      items.push({ label: "Move to Other Pane", shortcut: "F6", action: "moveOther" })
      items.push({ label: "Open Folder in Other Pane", action: "openOther" })
    }
    if (!pane.trash) {
      items.push(sep())
      items.push({ label: "Rename", shortcut: "F2", action: "rename" })
      items.push({ label: "Move to Trash", shortcut: "Delete", action: "trash" })
    } else {
      items.push(sep())
      items.push({ label: "Delete Permanently", shortcut: "Shift+Delete", action: "delete", danger: true })
    }
    items.push(sep())
    items.push({ label: "Properties", shortcut: "Ctrl+I", action: "props" })
    return items
  }

  function runMenuAction(action) {
    menuVisible = false
    switch (action) {
    case "open": currentPane().activate(); break
    case "copy": copySelection("copy"); break
    case "cut": copySelection("cut"); break
    case "paste": pasteIntoActive(); break
    case "copyOther": transferToOther(false); break
    case "moveOther": transferToOther(true); break
    case "openOther": openInOtherPane(); break
    case "restore": restoreSelection(); break
    case "mkdir": openMkdir(); break
    case "addPlace": addToPlaces(menuEntryPath || currentPane().path); break
    case "rename": openRename(); break
    case "trash": trashSelection(); break
    case "delete": confirmDelete(); break
    case "emptyTrash": confirmEmptyTrash(); break
    case "props": showProperties(); break
    case "selectAll": currentPane().selectAll(); break
    case "hidden": toggleHidden(); break
    case "refresh": refreshPanes(); break
    case "split": toggleSplit(); break
    case "sortName": currentPane().setSort("name"); break
    case "sortSize": currentPane().setSort("size"); break
    case "sortModified": currentPane().setSort("modified"); break
    case "close": dismiss(); break
    }
  }

  // ------------------------------------------------------------------ props

  function propertyLines() {
    var p = props
    if (!p || !p.name) return []
    var lines = [
      { key: "Name", value: p.name },
      { key: "Type", value: p.type },
      { key: "Size", value: p.count >= 0 ? p.count + (p.count === 1 ? " item" : " items") : Format.bytes(p.size) },
      { key: "Modified", value: p.modified },
      { key: "Permissions", value: p.permissions },
      { key: "Owner", value: p.owner + " · " + p.group },
      { key: "Location", value: p.path }
    ]
    if (p.link) lines.push({ key: "Link target", value: p.target })
    return lines
  }

  // ------------------------------------------------------------------ crumbs

  function crumbs() {
    var pane = currentPane()
    var full = pane.path || home
    if (full === trashPath) return [{ label: "Trash", path: trashPath, last: true }]
    if (full === "/") return [{ label: "Computer", path: "/", last: true }]
    var out = []
    var homeRoot = String(home || "/").replace(/\/+$/, "")
    var prefix = ""
    var parts = []
    if (homeRoot !== "" && (full === homeRoot || full.indexOf(homeRoot + "/") === 0)) {
      out.push({ label: "Home", path: homeRoot })
      parts = full.slice(homeRoot.length).split("/")
      prefix = homeRoot
    } else {
      out.push({ label: "/", path: "/" })
      parts = full.split("/")
    }
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i]) continue
      prefix = prefix + "/" + parts[i]
      out.push({ label: parts[i], path: prefix })
    }
    for (var j = 0; j < out.length; j++) out[j].last = j === out.length - 1
    return out
  }

  function statusLabel() {
    if (job.running) {
      var verbs = { copy: "Copying", move: "Moving", trash: "Moving to Trash",
                    delete: "Deleting", restore: "Restoring", emptyTrash: "Emptying Trash",
                    mkdir: "Creating folder", rename: "Renaming" }
      var text = (verbs[String(job.action)] || "Working")
      if (job.current) text += " " + job.current
      if (Number(job.done || 0) > 0) text += "  ·  " + job.done
      return text
    }
    var pane = currentPane()
    if (pane.searchMode)
      return pane.items.length + (pane.searchTruncated ? "+" : "") + " results"
    var label = pane.items.length + (pane.items.length === 1 ? " item" : " items")
    if (pane.truncated) label += "  ·  more items not shown"
    if (pane.selectedCount > 0)
      label += "  ·  " + pane.selectedCount + " selected" +
               (pane.selectedBytes > 0 ? " (" + Format.bytes(pane.selectedBytes) + ")" : "")
    return label
  }

  function otherLabel() {
    if (split) return "Other: " + otherPane().displayPath
    var pane = currentPane()
    return pane.trash ? "" : Format.bytes(pane.freeBytes) + " free"
  }

  // -------------------------------------------------------------- key input

  function handleFunctionKey(key, shift, alt) {
    if (key === Qt.Key_F1) { openHelp(); return true }
    if (key === Qt.Key_F2) { openRename(); return true }
    if (key === Qt.Key_F3) { viewCursor(); return true }
    if (key === Qt.Key_F4) { editCursor(); return true }
    if (shift && key === Qt.Key_F6) { openRename(); return true }
    if (key === Qt.Key_F5) { transferToOther(false); return true }
    if (key === Qt.Key_F6) { transferToOther(true); return true }
    if (key === Qt.Key_F7) { openMkdir(); return true }
    if (shift && key === Qt.Key_F8) { confirmDelete(); return true }
    if (key === Qt.Key_F8) { trashSelection(); return true }
    if (key === Qt.Key_F9) { openAppMenu(); return true }
    if (key === Qt.Key_F10) { dismiss(); return true }
    if (alt && key === Qt.Key_F4) { dismiss(); return true }
    return false
  }

  function handleKey(event) {
    var key = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var pane = currentPane()

    if (viewerOpen) {
      if (key === Qt.Key_Escape || key === Qt.Key_F3 || key === Qt.Key_F10
          || (alt && key === Qt.Key_F4)) {
        closeViewer()
        event.accepted = true
      }
      return
    }

    if (menuVisible) {
      if (key === Qt.Key_Escape) {
        menuVisible = false
        focusKeys()
        event.accepted = true
      }
      return
    }

    if (dialog !== "") {
      if (key === Qt.Key_Escape) {
        runDialogAction("cancel")
        event.accepted = true
      } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        if (dialog === "confirm") {
          runDialogAction("accept")
          event.accepted = true
        } else if (dialog === "conflict") {
          runDialogAction("skip")
          event.accepted = true
        } else if (dialog === "props" || dialog === "help") {
          closeDialog()
          event.accepted = true
        }
      }
      return
    }

    if (locationMode) {
      if (key === Qt.Key_Escape) {
        cancelLocation()
        event.accepted = true
      } else if (handleFunctionKey(key, shift, alt)) {
        event.accepted = true
      }
      return
    }

    if (searchActive) {
      if (key === Qt.Key_Escape) {
        finishSearch()
        event.accepted = true
      } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        pane.activate()
        event.accepted = true
      } else if (key === Qt.Key_Down) {
        pane.move(0, 1)
        event.accepted = true
      } else if (key === Qt.Key_Up) {
        pane.move(0, -1)
        event.accepted = true
      } else if (key === Qt.Key_PageDown) {
        pane.movePage(1)
        event.accepted = true
      } else if (key === Qt.Key_PageUp) {
        pane.movePage(-1)
        event.accepted = true
      }
      if (handleFunctionKey(key, shift, alt)) {
        event.accepted = true
        return
      }
      return
    }

    if (ctrl && shift && key === Qt.Key_N) { openMkdir(); event.accepted = true; return }
    if (ctrl && shift && key === Qt.Key_D) { toggleSplit(); event.accepted = true; return }
    if (ctrl && shift && key === Qt.Key_R) { retro = !retro; event.accepted = true; return }
    if (ctrl && shift && key === Qt.Key_U) { if (retro) ultraRetro = !ultraRetro; event.accepted = true; return }
    if (ctrl && key === Qt.Key_F) { openSearch(""); event.accepted = true; return }
    if (ctrl && key === Qt.Key_L) { openLocation(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_H) { toggleHidden(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_D) { addToPlaces(currentPane().path); event.accepted = true; return }
    if (ctrl && (key === Qt.Key_Plus || key === Qt.Key_Equal)) { changeFontSize(0.1); event.accepted = true; return }
    if (ctrl && (key === Qt.Key_Minus || key === Qt.Key_Underscore)) { changeFontSize(-0.1); event.accepted = true; return }
    if (ctrl && key === Qt.Key_0) { fontScale = defaultFontScale; event.accepted = true; return }
    if (ctrl && key === Qt.Key_A) { pane.selectAll(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_C) { copySelection("copy"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_X) { copySelection("cut"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_V) { pasteIntoActive(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_R) { refreshPanes(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_I) { showProperties(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_U) { swapPanes(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_W) { dismiss(); event.accepted = true; return }
    if (handleFunctionKey(key, shift, alt)) { event.accepted = true; return }
    if (key === Qt.Key_Tab) {
      if (split) setActive(1 - activePane)
      event.accepted = true
      return
    }
    if (key === Qt.Key_Backtab) {
      if (split) setActive(1 - activePane)
      event.accepted = true
      return
    }
    if (alt && key === Qt.Key_Left) { pane.goBack(); event.accepted = true; return }
    if (alt && key === Qt.Key_Right) { pane.goForward(); event.accepted = true; return }
    if (alt && key === Qt.Key_Up) { pane.goUp(); event.accepted = true; return }
    if (alt && key === Qt.Key_Home) { pane.navigate(home); event.accepted = true; return }
    if (key === Qt.Key_Backspace) { pane.goUp(); event.accepted = true; return }
    if (key === Qt.Key_Delete) {
      if (shift) confirmDelete()
      else trashSelection()
      event.accepted = true
      return
    }
    if (key === Qt.Key_Return || key === Qt.Key_Enter) { pane.activate(); event.accepted = true; return }
    if (key === Qt.Key_Escape) { dismiss(); event.accepted = true; return }

    if (key === Qt.Key_Up) { pane.move(0, -1); event.accepted = true; return }
    if (key === Qt.Key_Down) { pane.move(0, 1); event.accepted = true; return }
    if (key === Qt.Key_Left) { pane.move(-1, 0); event.accepted = true; return }
    if (key === Qt.Key_Right) { pane.move(1, 0); event.accepted = true; return }
    if (key === Qt.Key_Home) { pane.edge(false); event.accepted = true; return }
    if (key === Qt.Key_End) { pane.edge(true); event.accepted = true; return }
    if (key === Qt.Key_PageUp) { pane.movePage(-1); event.accepted = true; return }
    if (key === Qt.Key_PageDown) { pane.movePage(1); event.accepted = true; return }

    if (!ctrl && !alt && event.text && event.text.length === 1 &&
        event.text !== " " && event.text.charCodeAt(0) >= 32) {
      openSearch(event.text)
      event.accepted = true
    }
  }

  // ------------------------------------------------------------------ backend

  Service {
    id: backend
    objectName: "backend"

    onPlacesReady: function(data) {
      if (paneA.path === "") paneA.ensure(data.home || root.home)
      if (paneB.path === "") paneB.ensure(data.home || root.home)
    }

    onBookmarksReady: function(data) {
      if (data.message) root.showToast(String(data.message), data.ok === false)
    }

    onListing: function(data) {
      if (data.id === paneA.reqId) paneA.receive(data)
      else if (data.id === paneB.reqId) paneB.receive(data)
    }

    onSearchFinished: function(data) {
      if (data.id !== root.searchReq) return
      if (data.error) {
        root.showToast(String(data.error), true)
        return
      }
      root.currentPane().setSearchResults(data.entries || [], data.query || "",
                                          data.truncated === true)
    }

    onJobEvent: function(data) {
      if (data.state === "start") {
        root.job = { running: true, action: data.action, current: "", done: 0 }
      } else if (data.state === "progress") {
        root.job = { running: true, action: data.action, current: data.current || "",
                     done: Number(data.done || 0) }
      } else if (data.state === "done") {
        var ok = data.ok === true
        root.job = ({})
        if (ok) {
          root.showToast(String(data.message || "Done"))
          if (root.pendingCut) {
            root.clipboard = { mode: "", paths: [] }
            root.pendingCut = false
          }
        } else if (data.message === "cancelled") {
          root.pendingCut = false
          root.showToast("Cancelled")
        } else {
          root.pendingCut = false
          var message = String(data.message || "Operation failed")
          if (data.errors && data.errors.length > 0)
            message += " — " + data.errors[0]
          root.showToast(message, true)
        }
        root.recoverPanes(data.removed || [])
        root.refreshPanes()
        if (root.searchActive) root.runSearch()
      }
    }

    onConflictAsked: function(data) {
      var target = data.dstDir ? "folder" : "file"
      var existing = data.dstDir ? "folder" : Format.bytes(data.dstSize) + " · " + Format.date(data.dstMtime)
      var incoming = data.srcDir ? "folder" : Format.bytes(data.srcSize) + " · " + Format.date(data.srcMtime)
      root.openDialog("conflict", "Replace existing " + target + "?",
                      "\"" + root.baseName(data.dst) + "\" already exists.\n" +
                      "Existing: " + existing + "\nNew: " + incoming,
                      [{ label: "Cancel", action: "cancel" },
                       { label: "Skip", action: "skip", primary: true },
                       { label: "Replace", action: "replace", danger: true }])
    }

    onPropsReady: function(data) {
      if (data.error) {
        root.showToast(String(data.error), true)
        return
      }
      root.props = data.props || ({})
      root.openDialog("props", "Properties", "",
                      [{ label: "Close", action: "close" }])
    }

    onFileReady: function(data) {
      if (data.id !== root.viewerReq) return
      if (data.error) {
        root.viewerOpen = false
        root.showToast(String(data.error), true)
        return
      }
      if (!root.viewerOpen) return
      root.viewerTitle = String(data.name || root.viewerTitle)
      if (data.binary) {
        root.viewerText = String(data.hex || "")
        root.viewerWrap = false
        root.viewerInfo = "Binary · hex" + (data.truncated ? " · first 8 kB" : "")
      } else {
        root.viewerText = String(data.text || "")
        root.viewerWrap = true
        root.viewerInfo = "Text · " + Format.bytes(data.size) +
                          (data.truncated ? " · first 256 kB" : "")
      }
    }

    onBackendError: function(data) {
      root.showToast(String(data.message || "OmaNCommander backend error"), true)
    }

    onBackendReady: function() {
      if (!root.recovering) return
      root.recovering = false
      backend.request("places", {})
      root.refreshPanes()
    }

    onBackendFailed: function(message) {
      root.job = ({})
      paneA.loading = false
      paneB.loading = false
      root.recovering = root.opened
      root.showToast(String(message || "OmaNCommander backend stopped"), true)
    }
  }

  // ------------------------------------------------------------------ window

  // Own fullscreen layer shell window instead of qs.Ui.OverlayWindow: that
  // type only exists in shell 4.5, and Omarchy stable 4.0.6 has no replacement.
  PanelWindow {
    id: window
    visible: root.opened
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "popkenr-omancommander"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.max(Style.space(360), Math.min(parent.width - Style.gapsOut * 4, Style.space(1460)))
      height: Math.max(Style.space(280), Math.min(parent.height - Style.gapsOut * 4, Style.space(980)))
      radius: root.ultraRetro ? 0 : Math.max(Style.cornerRadius, Style.space(12))
      color: root.panelBg
      border.width: root.ultraRetro ? 2 : 1
      border.color: root.ultraRetro ? "#00aaaa" : Util.alpha(root.ink, 0.22)
      clip: true
      focus: root.opened

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      // Swallow clicks meant for the window chrome.
      MouseArea { anchors.fill: parent; onClicked: {} }

      // ------------------------------------------------------------- header

      Rectangle {
        id: header
        width: parent.width
        height: root.headerHeight
        color: root.chromeBg

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.line
        }

        Row {
          id: leftControls
          anchors.left: parent.left
          anchors.leftMargin: Style.space(7)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            visible: !root.ultraRetro
            glyph: "▤"
            active: root.sidebarVisible
            onClicked: root.sidebarVisible = !root.sidebarVisible
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? "<" : "←"
            enabled: root.currentPane().canGoBack
            onClicked: root.currentPane().goBack()
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? ">" : "→"
            enabled: root.currentPane().canGoForward
            onClicked: root.currentPane().goForward()
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? "^" : "↑"
            enabled: !root.currentPane().trash
            onClicked: root.currentPane().goUp()
          }
        }

        Row {
          id: rightControls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(7)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            visible: !root.ultraRetro
            enabled: !root.ultraRetro
            glyph: "A−"
            onClicked: root.changeFontSize(-0.1)
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            visible: !root.ultraRetro
            enabled: !root.ultraRetro
            glyph: "A+"
            onClicked: root.changeFontSize(0.1)
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? "S" : "⌕"
            active: root.searchActive
            onClicked: root.searchActive ? root.finishSearch() : root.openSearch("")
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            visible: !root.ultraRetro
            glyph: root.viewMode === "grid" ? "☰" : "▦"
            onClicked: root.viewMode = root.viewMode === "grid" ? "list" : "grid"
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            visible: !root.ultraRetro
            glyph: "▥"
            active: root.split
            onClicked: root.toggleSplit()
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? "=" : "⋮"
            active: root.menuVisible
            onClicked: root.menuVisible ? (root.menuVisible = false) : root.openAppMenu()
          }
          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            glyph: root.ultraRetro ? "X" : "✕"
            onClicked: root.dismiss()
          }
        }

        Item {
          id: centerZone
          anchors.left: leftControls.right
          anchors.right: rightControls.left
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          Flickable {
            id: crumbFlick
            anchors.fill: parent
            anchors.topMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            anchors.bottomMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            visible: !root.searchActive && !root.locationMode
            clip: true
            contentWidth: crumbRow.width
            contentHeight: height
            contentX: Math.max(0, contentWidth - width)
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            Row {
              id: crumbRow
              height: crumbFlick.height
              spacing: 1

              Repeater {
                model: root.crumbs()

                delegate: Item {
                  id: crumb
                  required property var modelData

                  width: crumbLabel.implicitWidth + Style.space(16)
                  height: crumbRow.height

                  Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Style.space(2)
                    anchors.bottomMargin: Style.space(2)
                    radius: root.ultraRetro ? 0 : Style.space(6)
                    color: crumbMouse.containsMouse && !crumb.modelData.last
                           ? root.hoverBg : "transparent"
                  }

                  Text {
                    id: crumbLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: crumb.modelData.label
                    textFormat: Text.PlainText
                    color: crumb.modelData.last ? root.ink : Util.alpha(root.ink, 0.68)
                    font.family: root.uiFont
                    font.pixelSize: root.fBody
                    font.weight: crumb.modelData.last ? Font.DemiBold : Font.Normal
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !crumb.modelData.last
                    text: root.ultraRetro ? ">" : "›"
                    color: Util.alpha(root.ink, 0.4)
                    font.family: root.uiFont
                    font.pixelSize: root.fBody
                  }

                  MouseArea {
                    id: crumbMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !crumb.modelData.last
                    onClicked: root.currentPane().navigate(crumb.modelData.path)
                  }
                }
              }
            }
          }

          Rectangle {
            visible: root.locationMode
            anchors.fill: parent
            anchors.topMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            anchors.bottomMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            radius: root.ultraRetro ? 0 : Style.space(7)
            color: Util.alpha(root.ink, 0.06)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.5)

            TextInput {
              id: locationField
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              verticalAlignment: TextInput.AlignVCenter
              color: root.ink
              selectionColor: root.accent
              selectedTextColor: root.panelBg
              font.family: root.uiFont
              font.pixelSize: root.fBody
              clip: true
              selectByMouse: true
              onTextChanged: root.locationText = text
              onAccepted: root.acceptLocation()
            }
          }

          Rectangle {
            visible: root.searchActive
            anchors.fill: parent
            anchors.topMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            anchors.bottomMargin: root.ultraRetro ? Style.space(2) : Style.space(8)
            radius: root.ultraRetro ? 0 : Style.space(7)
            color: Util.alpha(root.ink, 0.06)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.5)

            Text {
              id: searchGlyph
              anchors.left: parent.left
              anchors.leftMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: "⌕"
              color: Util.alpha(root.ink, 0.65)
              font.family: root.uiFont
              font.pixelSize: root.fBody
            }

            TextInput {
              id: searchField
              anchors.left: searchGlyph.right
              anchors.leftMargin: Style.space(6)
              anchors.right: searchClear.left
              anchors.rightMargin: Style.space(6)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              verticalAlignment: TextInput.AlignVCenter
              color: root.ink
              selectionColor: root.accent
              selectedTextColor: root.panelBg
              font.family: root.uiFont
              font.pixelSize: root.fBody
              clip: true
              selectByMouse: true
              onTextChanged: {
                root.searchText = text
                if (root.searchActive) searchDebounce.restart()
              }
            }

            Text {
              visible: searchField.text === ""
              anchors.left: searchField.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Search files…"
              color: Util.alpha(root.ink, 0.45)
              font.family: root.uiFont
              font.pixelSize: root.fBody
            }

            Text {
              id: searchClear
              anchors.right: parent.right
              anchors.rightMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: Util.alpha(root.ink, 0.55)
              font.family: root.uiFont
              font.pixelSize: root.fCaption

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(5)
                onClicked: {
                  searchField.text = ""
                  root.searchText = ""
                  searchField.forceActiveFocus()
                  root.runSearch()
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ sidebar

      Rectangle {
        id: sidebar
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.bottom: fbar.top
        width: root.sidebarVisible ? root.sidebarWidth : 0
        clip: true
        color: root.sidebarBg

        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: root.line
        }

        Flickable {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: versionLabel.top
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(4)
          contentWidth: width
          contentHeight: sidebarColumn.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: sidebarColumn
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              height: Style.space(26)
              leftPadding: Style.space(8)
              verticalAlignment: Text.AlignVCenter
              text: "Places"
              color: Util.alpha(root.ink, 0.5)
              font.family: root.uiFont
              font.pixelSize: root.fCaption
              font.weight: Font.DemiBold
            }

            Repeater {
              model: backend.places

              delegate: PlaceRow {
                required property var modelData

                width: sidebarColumn.width
                fontScale: root.fontScale
                retro: root.retro
                ultraRetro: root.ultraRetro
                fontFamily: root.uiFont
                label: modelData.label
                icon: modelData.icon
                current: root.currentPane().path === modelData.path
                onClicked: root.choosePath(modelData.path)
              }
            }

            Text {
              width: parent.width
              height: backend.bookmarks.length > 0 ? Style.space(30) : 0
              visible: backend.bookmarks.length > 0
              leftPadding: Style.space(8)
              topPadding: Style.space(8)
              text: "Saved"
              color: Util.alpha(root.ink, 0.5)
              font.family: root.uiFont
              font.pixelSize: root.fCaption
              font.weight: Font.DemiBold
            }

            Repeater {
              model: backend.bookmarks

              delegate: PlaceRow {
                required property var modelData

                width: sidebarColumn.width
                fontScale: root.fontScale
                retro: root.retro
                ultraRetro: root.ultraRetro
                fontFamily: root.uiFont
                label: modelData.label
                icon: modelData.icon
                current: root.currentPane().path === modelData.path
                removable: true
                onClicked: root.choosePath(modelData.path)
                onRemoveClicked: root.removeBookmark(modelData.path)
              }
            }

            Text {
              width: parent.width
              height: backend.mounts.length > 0 ? Style.space(30) : 0
              visible: backend.mounts.length > 0
              leftPadding: Style.space(8)
              topPadding: Style.space(8)
              text: "Devices"
              color: Util.alpha(root.ink, 0.5)
              font.family: root.uiFont
              font.pixelSize: root.fCaption
              font.weight: Font.DemiBold
            }

            Repeater {
              model: backend.mounts

              delegate: PlaceRow {
                required property var modelData

                width: sidebarColumn.width
                fontScale: root.fontScale
                retro: root.retro
                ultraRetro: root.ultraRetro
                fontFamily: root.uiFont
                label: modelData.label
                icon: modelData.icon
                current: root.currentPane().path === modelData.path
                onClicked: root.choosePath(modelData.path)
              }
            }

            Item {
              width: parent.width
              height: Style.space(34)

              RetroToggle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                checked: root.retro
                fontScale: root.fontScale
                fontFamily: root.uiFont
                ultraRetro: root.ultraRetro
                ink: root.ink
                accent: root.accent
                panelBg: root.panelBg
                onToggled: root.retro = !root.retro
              }
            }

            Item {
              width: parent.width
              height: Style.space(28)

              RetroToggle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "Boomer-mode"
                checkbox: true
                checked: root.ultraRetro
                enabled: root.retro
                fontScale: root.fontScale
                fontFamily: root.uiFont
                ultraRetro: root.ultraRetro
                ink: root.ink
                accent: root.accent
                panelBg: root.panelBg
                onToggled: if (root.retro) root.ultraRetro = !root.ultraRetro
              }
            }

          }
        }

        Text {
          id: versionLabel
          objectName: "versionLabel"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          anchors.bottomMargin: Style.space(6)
          text: root.manifest && root.manifest.version ? "v" + root.manifest.version : ""
          textFormat: Text.PlainText
          visible: text !== ""
          color: Util.alpha(root.ink, 0.45)
          font.family: root.uiFont
          font.pixelSize: root.fCaption
          elide: Text.ElideRight
        }
      }

      // -------------------------------------------------------------- panes

      Item {
        id: content
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: fbar.top

        Pane {
          id: paneA
          objectName: "paneA"
          x: root.paneInset
          y: 0
          width: Math.max(0, root.split
                             ? Math.floor((content.width - 2 * root.paneInset - root.paneGap) / 2)
                             : content.width - 2 * root.paneInset)
          height: content.height
          service: backend
          fontScale: root.fontScale
          retro: root.retro
          ultraRetro: root.ultraRetro
          fontFamily: root.uiFont
          active: root.activePane === 0
          splitMode: root.split
          viewMode: root.viewMode
          sortMode: root.sortMode
          sortAsc: root.sortAsc
          showHidden: root.showHidden
          homePath: root.home
          cutPaths: root.clipboard.mode === "cut" ? root.clipboard.paths : []

          onPaneActivated: root.setActive(0)
          onOpenPath: function(path) { root.openExternal(path) }
          onContextRequested: function(index, x, y) { root.openFileMenu(paneA, index, x, y) }
          onSearchCleared: root.finishSearch()
          onPathChanged: if (root.searchActive) root.finishSearch()
        }

        Rectangle {
          visible: root.split && !root.ultraRetro
          x: paneA.x + paneA.width
          y: 0
          width: root.paneGap
          height: content.height
          color: root.line
        }

        Pane {
          id: paneB
          objectName: "paneB"
          visible: root.split
          x: paneA.x + paneA.width + root.paneGap
          y: 0
          width: Math.max(0, content.width - paneA.x - paneA.width - root.paneGap - root.paneInset)
          height: content.height
          service: backend
          fontScale: root.fontScale
          retro: root.retro
          ultraRetro: root.ultraRetro
          fontFamily: root.uiFont
          active: root.activePane === 1
          splitMode: root.split
          viewMode: root.viewMode
          sortMode: root.sortMode
          sortAsc: root.sortAsc
          showHidden: root.showHidden
          homePath: root.home
          cutPaths: root.clipboard.mode === "cut" ? root.clipboard.paths : []

          onPaneActivated: root.setActive(1)
          onOpenPath: function(path) { root.openExternal(path) }
          onContextRequested: function(index, x, y) { root.openFileMenu(paneB, index, x, y) }
          onSearchCleared: root.finishSearch()
          onPathChanged: if (root.searchActive) root.finishSearch()
        }
      }

      // ------------------------------------------------------- function keys

      Rectangle {
        id: fbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: status.top
        height: root.fkeyHeight
        color: root.chromeBg

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.line
        }

        Row {
          id: fkeyRow
          anchors.fill: parent
          spacing: 0

          Repeater {
            model: root.fkeys

            delegate: Rectangle {
              id: fkey
              required property var modelData
              required property int index

              width: fkeyRow.width / root.fkeys.length
              height: fkeyRow.height
              color: fkeyMouse.containsMouse ? root.hoverBg : "transparent"

              Rectangle {
                visible: fkey.index < root.fkeys.length - 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: root.line
              }

              Text {
                visible: root.ultraRetro
                anchors.centerIn: parent
                text: fkey.modelData.key + " " + fkey.modelData.label
                textFormat: Text.PlainText
                color: root.ink
                font.family: root.uiFont
                font.pixelSize: root.fCaption
              }

              Column {
                visible: !root.ultraRetro
                anchors.centerIn: parent
                width: parent.width
                spacing: 0

                Text {
                  width: parent.width
                  text: fkey.modelData.key
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: root.uiFont
                  font.pixelSize: root.fCaption
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: fkey.modelData.label
                  textFormat: Text.PlainText
                  color: Util.alpha(root.ink, 0.8)
                  font.family: root.uiFont
                  font.pixelSize: root.fCaption
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: fkeyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runFunction(fkey.modelData.action)
              }
            }
          }
        }
      }

      // ------------------------------------------------------------- status

      Rectangle {
        id: status
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.statusHeight
        color: root.chromeBg

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.line
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - otherStatus.width - cancelStatus.width - Style.space(36))
          text: root.statusLabel()
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(root.ink, 0.7)
          font.family: root.uiFont
          font.pixelSize: root.fCaption
        }

        Text {
          id: cancelStatus
          anchors.right: otherStatus.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.job.running === true
          text: "Cancel"
          color: root.danger
          font.family: root.uiFont
          font.pixelSize: root.fCaption

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            onClicked: backend.send({ op: "cancel" })
          }
        }

        Text {
          id: otherStatus
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.45)
          text: root.otherLabel()
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          horizontalAlignment: Text.AlignRight
          color: Util.alpha(root.ink, 0.55)
          font.family: root.uiFont
          font.pixelSize: root.fCaption
        }
      }

      // --------------------------------------------------------------- menu

      MouseArea {
        anchors.fill: parent
        visible: root.menuVisible
        z: 40
        onClicked: root.menuVisible = false
        onWheel: function(wheel) { wheel.accepted = true }
      }

      Rectangle {
        id: menuCard
        visible: root.menuVisible
        z: 41
        width: root.menuWidth
        height: menuColumn.implicitHeight + Style.space(8)
        x: Math.max(Style.space(8), Math.min(root.menuX, card.width - width - Style.space(8)))
        y: Math.max(Style.space(8), Math.min(root.menuY, card.height - height - Style.space(8)))
        radius: root.ultraRetro ? 0 : Style.space(9)
        color: root.panelBg
        border.width: 1
        border.color: Util.alpha(root.ink, 0.22)

        Column {
          id: menuColumn
          x: Style.space(4)
          y: Style.space(4)
          width: parent.width - Style.space(8)

          Repeater {
            model: root.menuItems

            delegate: Item {
              id: menuRow
              required property var modelData

              width: menuColumn.width
              height: modelData.sep ? Style.space(7) : Style.space(30)

              Rectangle {
                visible: menuRow.modelData.sep === true
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(8)
                x: Style.space(4)
                height: 1
                color: root.line
              }

              Rectangle {
                visible: menuRow.modelData.sep !== true
                anchors.fill: parent
                anchors.margins: 1
                radius: root.ultraRetro ? 0 : Style.space(5)
                color: menuMouse.containsMouse ? root.hoverBg : "transparent"
              }

              Text {
                visible: menuRow.modelData.sep !== true
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: shortcutText.left
                anchors.verticalCenter: parent.verticalCenter
                text: ((menuRow.modelData.check ? (root.ultraRetro ? "* " : "✓ ") : "   ")) + (menuRow.modelData.label || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: menuRow.modelData.danger ? root.danger : root.ink
                font.family: root.uiFont
                font.pixelSize: root.fBody
              }

              Text {
                id: shortcutText
                visible: menuRow.modelData.sep !== true && !!menuRow.modelData.shortcut
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: menuRow.modelData.shortcut || ""
                textFormat: Text.PlainText
                color: Util.alpha(root.ink, 0.42)
                font.family: root.uiFont
                font.pixelSize: root.fCaption
              }

              MouseArea {
                id: menuMouse
                anchors.fill: parent
                enabled: menuRow.modelData.sep !== true
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runMenuAction(menuRow.modelData.action)
              }
            }
          }
        }
      }

      // ------------------------------------------------------------- dialogs

      Rectangle {
        anchors.fill: parent
        visible: root.dialog !== ""
        z: 90
        color: Util.alpha("#000000", 0.35)

        MouseArea { anchors.fill: parent; onClicked: {} }
      }

      Rectangle {
        id: dialogCard
        visible: root.dialog !== ""
        z: 91
        anchors.centerIn: parent
        width: Math.min(Style.space(500), card.width - Style.space(48))
        height: Math.min(card.height - Style.space(48),
                         dialogColumn.implicitHeight + Style.space(40))
        radius: root.ultraRetro ? 0 : Style.space(10)
        color: root.panelBg
        border.width: 1
        border.color: Util.alpha(root.ink, 0.25)

        Column {
          id: dialogColumn
          x: Style.space(20)
          y: Style.space(20)
          width: parent.width - Style.space(40)
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: root.dialogTitle
            textFormat: Text.PlainText
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: root.fHeading
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
          }

          Text {
            visible: root.dialogText !== "" && root.dialog !== "props"
            width: parent.width
            text: root.dialogText
            textFormat: Text.PlainText
            color: Util.alpha(root.ink, 0.78)
            font.family: root.uiFont
            font.pixelSize: root.fBody
            wrapMode: Text.Wrap
            lineHeight: 1.15
          }

          Rectangle {
            visible: root.dialog === "mkdir" || root.dialog === "rename"
            width: parent.width
            height: Style.space(34)
            radius: root.ultraRetro ? 0 : Style.space(7)
            color: Util.alpha(root.ink, 0.06)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.5)

            TextInput {
              id: dialogField
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              verticalAlignment: TextInput.AlignVCenter
              color: root.ink
              selectionColor: root.accent
              selectedTextColor: root.panelBg
              font.family: root.uiFont
              font.pixelSize: root.fBody
              clip: true
              selectByMouse: true
              onAccepted: root.runDialogAction("accept")
            }
          }

          Column {
            visible: root.dialog === "help"
            width: parent.width
            spacing: Style.space(3)

            Repeater {
              model: root.helpLines()

              delegate: Item {
                id: helpRow
                required property var modelData

                width: dialogColumn.width
                height: Math.max(helpKey.implicitHeight, helpText.implicitHeight)

                Text {
                  id: helpKey
                  width: Style.space(104)
                  text: helpRow.modelData.key
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: root.uiFont
                  font.pixelSize: root.fBody
                  font.weight: Font.DemiBold
                }

                Text {
                  id: helpText
                  x: Style.space(110)
                  width: parent.width - Style.space(110)
                  text: helpRow.modelData.text
                  textFormat: Text.PlainText
                  color: root.ink
                  font.family: root.uiFont
                  font.pixelSize: root.fBody
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          Column {
            visible: root.dialog === "props"
            width: parent.width
            spacing: Style.space(7)

            Repeater {
              model: root.propertyLines()

              delegate: Item {
                id: propertyRow
                required property var modelData

                width: dialogColumn.width
                height: Math.max(propertyKey.implicitHeight, propertyValue.implicitHeight)

                Text {
                  id: propertyKey
                  width: Style.space(96)
                  text: propertyRow.modelData.key
                  textFormat: Text.PlainText
                  color: Util.alpha(root.ink, 0.55)
                  font.family: root.uiFont
                  font.pixelSize: root.fBody
                  elide: Text.ElideRight
                }

                Text {
                  id: propertyValue
                  x: Style.space(104)
                  width: parent.width - Style.space(104)
                  text: propertyRow.modelData.value
                  textFormat: Text.PlainText
                  color: root.ink
                  font.family: root.uiFont
                  font.pixelSize: root.fBody
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          Item {
            width: parent.width
            height: dialogButtons.height

            Row {
              id: dialogButtons
              anchors.right: parent.right
              spacing: Style.space(8)

              Repeater {
                model: root.dialogActions

                delegate: ActionButton {
                  required property var modelData

                  label: modelData.label
                  primary: modelData.primary === true
                  danger: modelData.danger === true
                  fontScale: root.fontScale
                  retro: root.retro
                  ultraRetro: root.ultraRetro
                  fontFamily: root.uiFont
                  onClicked: root.runDialogAction(modelData.action)
                }
              }
            }
          }
        }
      }

      // --------------------------------------------------------------- viewer

      Rectangle {
        anchors.fill: parent
        visible: root.viewerOpen
        z: 92
        color: Util.alpha("#000000", 0.45)

        MouseArea {
          anchors.fill: parent
          onClicked: root.closeViewer()
        }
      }

      Rectangle {
        id: viewerCard
        visible: root.viewerOpen
        z: 93
        anchors.centerIn: parent
        width: Math.min(card.width - Style.space(56), Style.space(960))
        height: Math.min(card.height - Style.space(56), Style.space(720))
        radius: root.ultraRetro ? 0 : Style.space(10)
        color: root.panelBg
        border.width: 1
        border.color: Util.alpha(root.ink, 0.25)
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
          id: viewerHeader
          width: parent.width
          height: Style.space(40)
          color: root.chromeBg

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: root.line
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.right: viewerInfoText.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.viewerTitle
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: root.fBody
            font.weight: Font.DemiBold
          }

          Text {
            id: viewerInfoText
            anchors.right: viewerClose.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.viewerInfo
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Util.alpha(root.ink, 0.55)
            font.family: root.uiFont
            font.pixelSize: root.fCaption
          }

          IconButton {
            retro: root.retro
            ultraRetro: root.ultraRetro
            fontFamily: root.uiFont
            id: viewerClose
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.ultraRetro ? "X" : "✕"
            onClicked: root.closeViewer()
          }
        }

        Item {
          id: viewerBody
          anchors.top: viewerHeader.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(12)

          Image {
            anchors.fill: parent
            visible: root.viewerImage !== ""
            source: root.viewerImage !== "" ? Util.fileUrl(root.viewerImage) : ""
            sourceSize.width: 4096
            sourceSize.height: 4096
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
          }

          Flickable {
            id: viewerFlick
            anchors.fill: parent
            visible: root.viewerImage === ""
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width, viewerTextItem.width)
            contentHeight: Math.max(height, viewerTextItem.height)

            Text {
              id: viewerTextItem
              width: root.viewerWrap ? viewerFlick.width : implicitWidth
              text: root.viewerText
              textFormat: Text.PlainText
              color: root.ink
              font.family: root.monoFont
              font.pixelSize: root.fBodySmall
              wrapMode: root.viewerWrap ? Text.Wrap : Text.NoWrap
              lineHeight: 1.15
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.viewerImage === "" && root.viewerText === ""
            text: "Empty file"
            textFormat: Text.PlainText
            color: Util.alpha(root.ink, 0.5)
            font.family: root.uiFont
            font.pixelSize: root.fBody
          }
        }
      }

      // --------------------------------------------------------------- toast

      Rectangle {
        id: toast
        visible: root.toastText !== ""
        z: 120
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: fbar.top
        anchors.bottomMargin: Style.space(14)
        width: Math.min(toastLabel.implicitWidth + Style.space(28), card.width - Style.space(32))
        height: Style.space(32)
        radius: root.ultraRetro ? 0 : Style.space(8)
        color: root.toastAngry ? root.danger : root.accent

        Text {
          id: toastLabel
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          text: root.toastText
          textFormat: Text.PlainText
          color: root.toastAngry ? (root.retro ? "#ffffff" : Commons.Color.foreground) : root.panelBg
          font.family: root.uiFont
          font.pixelSize: root.fBody
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }

      Timer {
        id: toastTimer
        interval: 2600
        onTriggered: root.toastText = ""
      }

      Timer {
        id: searchDebounce
        interval: 220
        onTriggered: root.runSearch()
      }
    }
  }
}
