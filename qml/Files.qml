// A Nautilus-shaped file manager for the Omarchy shell, with the two panes
// and commander keys of omarchomander. Everything is drawn with the shell
// theme tokens; the actual files live in backend/filesd.py.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Format.js" as Format

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "popkenr.files"
  readonly property string trashPath: ":trash:"
  readonly property string home: backend.home || Quickshell.env("HOME") || "/"

  readonly property color panelBg: Commons.Color.popups.background
  readonly property color ink: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color danger: Commons.Color.urgent
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property color line: Util.alpha(Commons.Color.popups.text, 0.12)
  readonly property color hoverBg: Util.alpha(Commons.Color.popups.text, 0.07)
  readonly property color chromeBg: Util.alpha(Commons.Color.popups.text, 0.035)
  readonly property color sidebarBg: Util.alpha(Commons.Color.popups.text, 0.02)
  readonly property color selectedBg: Util.alpha(Commons.Color.accent, 0.18)
  readonly property int headerHeight: Math.max(Style.space(46), Style.font.title + Style.space(30))
  readonly property int statusHeight: Style.space(26)
  readonly property int sidebarWidth: Style.space(188)
  readonly property int paneGap: 1

  property int activePane: 0
  property bool split: false
  property bool sidebarVisible: true
  property string viewMode: "grid"
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
  property bool dialogDanger: false
  property string pendingAction: ""
  property var pendingPaths: []
  property var props: ({})
  property var conflict: ({})

  property var job: ({})
  property var clipboard: ({ mode: "", paths: [] })
  property bool pendingCut: false

  property bool menuVisible: false
  property real menuX: 0
  property real menuY: 0
  property var menuItems: []
  readonly property int menuWidth: Style.space(252)

  property string toastText: ""
  property bool toastAngry: false
  property bool initialised: false

  function currentPane() { return activePane === 0 ? paneA : paneB }
  function otherPane() { return activePane === 0 ? paneB : paneA }

  function focusKeys() {
    if (!opened) return
    Qt.callLater(function() {
      if (!root.searchActive && !root.locationMode && root.dialog === "" && !root.menuVisible)
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
    opened = true
    searchActive = false
    searchText = ""
    locationMode = false
    dialog = ""
    menuVisible = false
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
    conflict = ({})
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
    if (index === activePane) return
    if (searchActive) finishSearch()
    activePane = index
  }

  function toggleSplit() {
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

  function toggleHidden() {
    showHidden = !showHidden
    if (searchActive) runSearch()
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
    backend.request("trash", { paths: paths })
  }

  function confirmDelete() {
    var paths = currentPane().selectionPaths()
    if (paths.length === 0) return
    pendingPaths = paths
    pendingAction = "delete"
    var count = paths.length
    openDialog("confirm", "Delete permanently?",
               count + (count === 1 ? " item" : " items") +
               " will be deleted permanently. This cannot be undone.",
               [{ label: "Cancel", action: "cancel" },
                { label: "Delete", action: "accept", danger: true }], true)
  }

  function confirmEmptyTrash() {
    pendingAction = "emptyTrash"
    openDialog("confirm", "Empty Trash?",
               "Every item in the Trash will be deleted permanently. This cannot be undone.",
               [{ label: "Cancel", action: "cancel" },
                { label: "Empty Trash", action: "accept", danger: true }], true)
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

  function openExternal(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-open", path])
  }

  // ---------------------------------------------------------------- dialogs

  function openDialog(kind, title, text, actions, danger) {
    dialog = kind
    dialogTitle = title
    dialogText = text
    dialogActions = actions
    dialogDanger = danger === true
    Qt.callLater(function() { card.forceActiveFocus() })
  }

  function openInput(kind, title, initial, confirmLabel) {
    dialog = kind
    dialogTitle = title
    dialogText = ""
    dialogDanger = false
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
    dialogDanger = false
    pendingAction = ""
    pendingPaths = []
    conflict = ({})
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
      if (pendingAction === "delete")
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
    menuItems = fileMenuItems(pane)
    showMenuAt(pane.mapToItem(card, x, y))
  }

  function sep() { return { sep: true } }

  function appMenuItems() {
    var pane = currentPane()
    var items = [
      { label: "New Folder", shortcut: "Ctrl+Shift+N", action: "mkdir" },
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
    if (pane.searchMode) return pane.items.length + " results"
    var label = pane.items.length + (pane.items.length === 1 ? " item" : " items")
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

  function handleKey(event) {
    var key = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var pane = currentPane()

    if (menuVisible) {
      if (key === Qt.Key_Escape) {
        menuVisible = false
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
          runDialogAction("cancel")
          event.accepted = true
        } else if (dialog === "conflict") {
          runDialogAction("skip")
          event.accepted = true
        } else if (dialog === "props") {
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
      return
    }

    if (ctrl && shift && key === Qt.Key_N) { openMkdir(); event.accepted = true; return }
    if (ctrl && shift && key === Qt.Key_D) { toggleSplit(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_F) { openSearch(""); event.accepted = true; return }
    if (ctrl && key === Qt.Key_L) { openLocation(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_H) { toggleHidden(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_A) { pane.selectAll(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_C) { copySelection("copy"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_X) { copySelection("cut"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_V) { pasteIntoActive(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_R) { refreshPanes(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_I) { showProperties(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_U) { swapPanes(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_W) { dismiss(); event.accepted = true; return }
    if (key === Qt.Key_F10) { dismiss(); event.accepted = true; return }
    if (key === Qt.Key_F5) {
      if (split) transferToOther(false)
      else refreshPanes()
      event.accepted = true
      return
    }
    if (key === Qt.Key_F6) {
      if (split) transferToOther(true)
      event.accepted = true
      return
    }
    if (key === Qt.Key_F2) { openRename(); event.accepted = true; return }
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
      root.currentPane().setSearchResults(data.entries || [], data.query || "")
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
        root.refreshPanes()
        if (root.searchActive) root.runSearch()
      }
    }

    onConflictAsked: function(data) {
      root.conflict = data
      var existing = Format.bytes(data.dstSize) + " · " + Format.date(data.dstMtime)
      var incoming = Format.bytes(data.srcSize) + " · " + Format.date(data.srcMtime)
      root.openDialog("conflict", "Replace existing file?",
                      "\"" + root.baseName(data.dst) + "\" already exists.\n" +
                      "Existing: " + existing + "\nNew: " + incoming,
                      [{ label: "Cancel", action: "cancel" },
                       { label: "Skip", action: "skip", primary: true },
                       { label: "Replace", action: "replace", danger: true }], false)
    }

    onPropsReady: function(data) {
      if (data.error) {
        root.showToast(String(data.error), true)
        return
      }
      root.props = data.props || ({})
      root.openDialog("props", "Properties", "",
                      [{ label: "Close", action: "close" }], false)
    }

    onBackendError: function(data) {
      root.showToast(String(data.message || "Files backend error"), true)
    }

    onBackendFailed: function(message) {
      root.job = ({})
      paneA.loading = false
      paneB.loading = false
      root.showToast(String(message || "Files backend stopped"), true)
    }
  }

  // ------------------------------------------------------------------ window

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "popkenr-files"

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
      radius: Math.max(Style.cornerRadius, Style.space(12))
      color: root.panelBg
      border.width: 1
      border.color: Util.alpha(root.ink, 0.22)
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
            glyph: "▤"
            active: root.sidebarVisible
            onClicked: root.sidebarVisible = !root.sidebarVisible
          }
          IconButton {
            glyph: "←"
            enabled: root.currentPane().canGoBack
            onClicked: root.currentPane().goBack()
          }
          IconButton {
            glyph: "→"
            enabled: root.currentPane().canGoForward
            onClicked: root.currentPane().goForward()
          }
          IconButton {
            glyph: "↑"
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
            glyph: "⌕"
            active: root.searchActive
            onClicked: root.searchActive ? root.finishSearch() : root.openSearch("")
          }
          IconButton {
            glyph: root.viewMode === "grid" ? "☰" : "▦"
            onClicked: root.viewMode = root.viewMode === "grid" ? "list" : "grid"
          }
          IconButton {
            glyph: "▥"
            active: root.split
            onClicked: root.toggleSplit()
          }
          IconButton {
            glyph: "⋮"
            active: root.menuVisible
            onClicked: root.menuVisible ? (root.menuVisible = false) : root.openAppMenu()
          }
          IconButton {
            glyph: "✕"
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
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
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
                    radius: Style.space(6)
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
                    font.family: "sans-serif"
                    font.pixelSize: Style.font.body
                    font.weight: crumb.modelData.last ? Font.DemiBold : Font.Normal
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !crumb.modelData.last
                    text: "›"
                    color: Util.alpha(root.ink, 0.4)
                    font.family: "sans-serif"
                    font.pixelSize: Style.font.body
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
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            radius: Style.space(7)
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
              clip: true
              selectByMouse: true
              onTextChanged: root.locationText = text
              onAccepted: root.acceptLocation()
            }
          }

          Rectangle {
            visible: root.searchActive
            anchors.fill: parent
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            radius: Style.space(7)
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
            }

            Text {
              id: searchClear
              anchors.right: parent.right
              anchors.rightMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: Util.alpha(root.ink, 0.55)
              font.family: "sans-serif"
              font.pixelSize: Style.font.caption

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
        anchors.bottom: status.top
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
          anchors.fill: parent
          anchors.margins: Style.space(8)
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }

            Repeater {
              model: backend.places

              delegate: Item {
                id: placeRow
                required property var modelData

                width: sidebarColumn.width
                height: Style.space(30)
                readonly property bool current: root.currentPane().path === modelData.path

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: 1
                  anchors.bottomMargin: 1
                  radius: Style.space(6)
                  color: placeRow.current ? root.selectedBg
                                         : (placeMouse.containsMouse ? root.hoverBg : "transparent")
                }

                Image {
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: Style.space(16)
                  source: Quickshell.iconPath(placeRow.modelData.icon, true)
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(32)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: placeRow.modelData.label
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: placeRow.current ? root.accent : root.ink
                  font.family: "sans-serif"
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: placeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.choosePath(placeRow.modelData.path)
                }
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }

            Repeater {
              model: backend.mounts

              delegate: Item {
                id: mountRow
                required property var modelData

                width: sidebarColumn.width
                height: Style.space(30)
                readonly property bool current: root.currentPane().path === modelData.path

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: 1
                  anchors.bottomMargin: 1
                  radius: Style.space(6)
                  color: mountRow.current ? root.selectedBg
                                          : (mountMouse.containsMouse ? root.hoverBg : "transparent")
                }

                Image {
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: Style.space(16)
                  source: Quickshell.iconPath(mountRow.modelData.icon, true)
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(32)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: mountRow.modelData.label
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: mountRow.current ? root.accent : root.ink
                  font.family: "sans-serif"
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: mountMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.choosePath(mountRow.modelData.path)
                }
              }
            }
          }
        }
      }

      // -------------------------------------------------------------- panes

      Item {
        id: content
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: status.top

        Pane {
          id: paneA
          objectName: "paneA"
          x: 0
          y: 0
          width: root.split ? Math.floor(content.width / 2) : content.width
          height: content.height
          service: backend
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
          visible: root.split
          x: paneA.width
          y: 0
          width: root.paneGap
          height: content.height
          color: root.line
        }

        Pane {
          id: paneB
          objectName: "paneB"
          visible: root.split
          x: paneA.width + root.paneGap
          y: 0
          width: Math.max(0, content.width - paneA.width - root.paneGap)
          height: content.height
          service: backend
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
          font.family: "sans-serif"
          font.pixelSize: Style.font.caption
        }

        Text {
          id: cancelStatus
          anchors.right: otherStatus.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.job.running === true
          text: "Cancel"
          color: root.danger
          font.family: "sans-serif"
          font.pixelSize: Style.font.caption

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
          font.family: "sans-serif"
          font.pixelSize: Style.font.caption
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
        radius: Style.space(9)
        color: Commons.Color.menu.background
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
                radius: Style.space(5)
                color: menuMouse.containsMouse ? root.hoverBg : "transparent"
              }

              Text {
                visible: menuRow.modelData.sep !== true
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: shortcutText.left
                anchors.verticalCenter: parent.verticalCenter
                text: (menuRow.modelData.check ? "✓ " : "   ") + (menuRow.modelData.label || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: menuRow.modelData.danger ? root.danger : root.ink
                font.family: "sans-serif"
                font.pixelSize: Style.font.body
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
                font.family: "sans-serif"
                font.pixelSize: Style.font.caption
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
        radius: Style.space(10)
        color: Commons.Color.popups.background
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
            font.family: "sans-serif"
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
          }

          Text {
            visible: root.dialogText !== "" && root.dialog !== "props"
            width: parent.width
            text: root.dialogText
            textFormat: Text.PlainText
            color: Util.alpha(root.ink, 0.78)
            font.family: "sans-serif"
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            lineHeight: 1.15
          }

          Rectangle {
            visible: root.dialog === "mkdir" || root.dialog === "rename"
            width: parent.width
            height: Style.space(34)
            radius: Style.space(7)
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
              font.family: "sans-serif"
              font.pixelSize: Style.font.body
              clip: true
              selectByMouse: true
              onAccepted: root.runDialogAction("accept")
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
                  font.family: "sans-serif"
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: propertyValue
                  x: Style.space(104)
                  width: parent.width - Style.space(104)
                  text: propertyRow.modelData.value
                  textFormat: Text.PlainText
                  color: root.ink
                  font.family: "sans-serif"
                  font.pixelSize: Style.font.body
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
                  onClicked: root.runDialogAction(modelData.action)
                }
              }
            }
          }
        }
      }

      // --------------------------------------------------------------- toast

      Rectangle {
        id: toast
        visible: root.toastText !== ""
        z: 120
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: status.top
        anchors.bottomMargin: Style.space(14)
        width: Math.min(toastLabel.implicitWidth + Style.space(28), card.width - Style.space(32))
        height: Style.space(32)
        radius: Style.space(8)
        color: root.toastAngry ? root.danger : root.accent

        Text {
          id: toastLabel
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          text: root.toastText
          textFormat: Text.PlainText
          color: root.toastAngry ? Commons.Color.foreground : root.panelBg
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
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
