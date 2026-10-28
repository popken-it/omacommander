// One Nautilus-style pane: icon grid or list, selection, history and its own
// directory. The Files overlay owns two of these; every filesystem call goes
// through the shared Service.
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Format.js" as Format

Item {
  id: root

  property var service: null
  property bool active: false
  property bool splitMode: false
  property string viewMode: "list"
  property string sortMode: "name"
  property bool sortAsc: true
  property bool showHidden: false
  property string homePath: "/"
  property var cutPaths: []

  property real fontScale: 1.0
  readonly property int fCaption: Math.max(1, Math.round(Style.font.caption * fontScale))
  readonly property int fBody: Math.max(1, Math.round(Style.font.body * fontScale))
  readonly property int fTitle: Math.max(1, Math.round(Style.font.title * fontScale))

  readonly property string trashPath: ":trash:"
  readonly property int rowHeight: Math.max(Style.space(30), fBody + Style.space(16))
  readonly property int stripHeight: splitMode ? Math.max(Style.space(26), fCaption + Style.space(10)) : 0
  readonly property int sizeWidth: Style.space(88)
  readonly property int dateWidth: Style.space(124)
  readonly property int nameWidth: Math.max(Style.space(60), body.width - Style.space(38) - sizeWidth - dateWidth - Style.space(24))

  property string path: ""
  property string displayPath: ""
  property string parentPath: ""
  property var entries: []
  property var items: []
  property int cursor: 0
  property var selected: ({})
  property int anchor: -1
  property int selectedCount: 0
  property real selectedBytes: 0
  property int reqId: 0
  property bool loading: false
  property string error: ""
  property bool trash: false
  property bool writable: true
  property real freeBytes: 0
  property var history: []
  property int histIndex: -1
  property bool searchMode: false
  property string searchQuery: ""
  property var searchEntries: []
  property string revealPath: ""
  property int columns: 1

  property color ink: Commons.Color.popups.text
  property color accent: Commons.Color.accent
  property color line: Util.alpha(Commons.Color.popups.text, 0.12)
  property color hoverBg: Util.alpha(Commons.Color.popups.text, 0.07)
  property color selectedBg: Util.alpha(Commons.Color.accent, 0.22)

  signal paneActivated()
  signal openPath(string path)
  signal contextRequested(int index, real x, real y)
  signal searchCleared()

  clip: true

  onShowHiddenChanged: if (path !== "") refresh()
  onSortModeChanged: rebuild()
  onSortAscChanged: rebuild()
  onViewModeChanged: Qt.callLater(ensureVisible)
  onServiceChanged: if (service && path !== "" && entries.length === 0) refresh()

  // ------------------------------------------------------------- navigation

  function ensure(startPath) {
    if (path === "") navigate(startPath)
  }

  function childToward(target, from) {
    if (!target || !from || target === from) return ""
    var root = target === "/" ? "/" : String(target).replace(/\/+$/, "") + "/"
    if (from.indexOf(root) !== 0) return ""
    var rest = from.slice(root.length)
    var first = rest.split("/")[0]
    if (!first) return ""
    return target === "/" ? "/" + first : String(target).replace(/\/+$/, "") + "/" + first
  }

  function navigate(target, push) {
    var next = String(target || "")
    if (next === "") return
    if (next === path) {
      refresh()
      return
    }
    revealPath = childToward(next, path)
    if (push !== false) {
      var nextHistory = history.slice(0, histIndex + 1)
      nextHistory.push(next)
      history = nextHistory
      histIndex = nextHistory.length - 1
    }
    path = next
    displayPath = next === trashPath ? "Trash" : next
    entries = []
    items = []
    cursor = 0
    selected = ({})
    anchor = -1
    selectedCount = 0
    selectedBytes = 0
    error = ""
    loading = true
    trash = next === trashPath
    searchMode = false
    searchQuery = ""
    searchEntries = []
    refresh()
  }

  function refresh() {
    if (!service || path === "") return
    loading = true
    reqId = service.request("list", { path: path, hidden: showHidden })
  }

  function receive(data) {
    if (!data || data.id !== reqId) return
    loading = false
    var reveal = revealPath
    revealPath = ""
    if (data.error) {
      error = String(data.error)
      entries = []
      items = []
      updateStats()
      return
    }
    var previous = cursorEntry()
    path = String(data.path || path)
    displayPath = String(data.displayPath || path)
    parentPath = String(data.parent || homePath)
    entries = data.entries || []
    freeBytes = Number(data.free || 0)
    trash = data.trash === true
    writable = data.writable !== false
    error = ""
    rebuild()
    if (reveal !== "") {
      var revealed = indexOfPath(reveal)
      if (revealed >= 0) selectOnly(revealed)
    } else if (previous) {
      var index = indexOfPath(previous.path)
      if (index >= 0) cursor = index
    }
    pruneSelection()
    if (searchMode) rebuild()
    updateStats()
    Qt.callLater(ensureVisible)
  }

  function goUp() {
    if (searchMode) {
      clearSearch()
      return
    }
    if (trash) {
      navigate(homePath)
      return
    }
    navigate(parentPath || path)
  }

  function goBack() {
    if (histIndex > 0) {
      histIndex -= 1
      navigate(history[histIndex], false)
    }
  }

  function goForward() {
    if (histIndex < history.length - 1) {
      histIndex += 1
      navigate(history[histIndex], false)
    }
  }

  readonly property bool canGoBack: histIndex > 0
  readonly property bool canGoForward: histIndex < history.length - 1

  // -------------------------------------------------------------- selection

  function cursorEntry() {
    return items.length > 0 && cursor >= 0 && cursor < items.length ? items[cursor] : null
  }

  function indexOfPath(target) {
    for (var i = 0; i < items.length; i++)
      if (items[i].path === target) return i
    return -1
  }

  function isSelected(target) {
    return selected[target] === true
  }

  function isCut(target) {
    return cutPaths.indexOf(target) >= 0
  }

  function selectOnly(index) {
    var entry = items[index]
    var map = ({})
    if (entry) map[entry.path] = true
    selected = map
    anchor = index
    cursor = index
    updateStats()
  }

  function toggleAt(index) {
    var entry = items[index]
    if (!entry) return
    var map = ({})
    for (var key in selected) map[key] = selected[key]
    if (map[entry.path]) delete map[entry.path]
    else map[entry.path] = true
    selected = map
    anchor = index
    cursor = index
    updateStats()
  }

  function rangeTo(index) {
    var from = anchor >= 0 ? anchor : cursor
    var to = index
    if (from > to) {
      var swap = from
      from = to
      to = swap
    }
    var map = ({})
    for (var i = from; i <= to && i < items.length; i++) map[items[i].path] = true
    selected = map
    cursor = index
    updateStats()
  }

  function selectAll() {
    var map = ({})
    for (var i = 0; i < items.length; i++) map[items[i].path] = true
    selected = map
    anchor = 0
    updateStats()
  }

  function clearSelection() {
    selected = ({})
    anchor = -1
    updateStats()
  }

  function cutSelection(paths) {
    cutPaths = paths || []
  }

  function selectedItems() {
    var out = []
    for (var i = 0; i < items.length; i++)
      if (selected[items[i].path]) out.push(items[i])
    return out
  }

  function selectionPaths() {
    var chosen = selectedItems()
    if (chosen.length > 0) {
      var out = []
      for (var i = 0; i < chosen.length; i++) out.push(chosen[i].path)
      return out
    }
    var entry = cursorEntry()
    return entry ? [entry.path] : []
  }

  function updateStats() {
    var count = 0
    var bytes = 0
    for (var i = 0; i < items.length; i++) {
      var entry = items[i]
      if (selected[entry.path]) {
        count += 1
        if (!entry.dir) bytes += Number(entry.size || 0)
      }
    }
    selectedCount = count
    selectedBytes = bytes
  }

  function pruneSelection() {
    var map = ({})
    var changed = false
    for (var i = 0; i < items.length; i++) {
      if (selected[items[i].path]) map[items[i].path] = true
    }
    for (var key in selected)
      if (!map[key]) changed = true
    selected = map
    if (changed) updateStats()
  }

  // ---------------------------------------------------------------- cursor

  function click(index, modifiers) {
    paneActivated()
    var entry = items[index]
    if (!entry) return
    if (modifiers & Qt.ShiftModifier) rangeTo(index)
    else if (modifiers & Qt.ControlModifier) toggleAt(index)
    else selectOnly(index)
    ensureVisible()
  }

  function move(dx, dy) {
    if (items.length === 0) return
    if (viewMode === "list" && dy === 0) return
    var step = viewMode === "grid" ? columns : 1
    var next = cursor
    if (dy !== 0) next = cursor + dy * step
    else next = cursor + dx
    setCursor(next)
  }

  function movePage(delta) {
    if (items.length === 0) return
    var rows = viewMode === "grid"
      ? Math.max(1, Math.floor(grid.height / grid.cellHeight))
      : Math.max(1, Math.floor(list.height / rowHeight))
    var step = viewMode === "grid" ? columns * rows : rows
    setCursor(cursor + delta * step)
  }

  function setCursor(index) {
    if (items.length === 0) return
    var next = Math.max(0, Math.min(items.length - 1, Number(index)))
    selectOnly(next)
    ensureVisible()
  }

  function edge(last) {
    if (items.length === 0) return
    setCursor(last ? items.length - 1 : 0)
  }

  function ensureVisible() {
    if (items.length === 0) return
    var index = Math.max(0, Math.min(items.length - 1, cursor))
    if (viewMode === "grid") grid.positionViewAtIndex(index, GridView.Contain)
    else listView.positionViewAtIndex(index, ListView.Contain)
  }

  function activate() {
    var entry = items[cursor]
    if (!entry) return
    var wasSearch = searchMode
    if (wasSearch) {
      searchMode = false
      searchQuery = ""
      searchEntries = []
      searchCleared()
    }
    if (entry.dir) {
      navigate(entry.path)
      return
    }
    if (wasSearch) {
      rebuild()
      updateStats()
    }
    openPath(entry.path)
  }

  // ---------------------------------------------------------------- search

  function setSearchResults(list, query) {
    searchMode = true
    searchQuery = String(query || "")
    searchEntries = list || []
    cursor = 0
    selected = ({})
    anchor = -1
    rebuild()
    updateStats()
    Qt.callLater(ensureVisible)
  }

  function clearSearch() {
    if (!searchMode && searchEntries.length === 0) return
    searchMode = false
    searchQuery = ""
    searchEntries = []
    rebuild()
    updateStats()
  }

  // ------------------------------------------------------------------ sort

  function compareEntries(a, b) {
    if (a.dir !== b.dir) return a.dir ? -1 : 1
    var cmp = 0
    if (sortMode === "size") cmp = Number(a.size || 0) - Number(b.size || 0)
    else if (sortMode === "modified") cmp = Number(a.mtime || 0) - Number(b.mtime || 0)
    if (cmp === 0) {
      var left = a._sortKey || Format.naturalKey(a.name)
      var right = b._sortKey || Format.naturalKey(b.name)
      cmp = left < right ? -1 : (left > right ? 1 : 0)
    }
    return sortAsc ? cmp : -cmp
  }

  function rebuild() {
    var base = searchMode ? searchEntries : entries
    var out = []
    for (var i = 0; i < base.length; i++) {
      out.push(base[i])
      base[i]._sortKey = Format.naturalKey(base[i].name)
    }
    out.sort(compareEntries)
    items = out
    if (cursor >= items.length) cursor = Math.max(0, items.length - 1)
    updateStats()
    Qt.callLater(ensureVisible)
  }

  function setSort(mode) {
    if (sortMode === mode) sortAsc = !sortAsc
    else {
      sortMode = mode
      sortAsc = mode === "name"
    }
  }

  // ------------------------------------------------------------------ icons

  function iconName(entry) {
    if (!entry) return "text-x-generic"
    if (entry.dir) return "folder"
    switch (String(entry.kind)) {
    case "image": return "image-x-generic"
    case "video": return "video-x-generic"
    case "audio": return "audio-x-generic"
    case "pdf": return "application-pdf"
    case "archive": return "package-x-generic"
    case "document": return "x-office-document"
    case "sheet": return "x-office-spreadsheet"
    case "slide": return "x-office-presentation"
    case "code": return "text-x-script"
    case "font": return "font-x-generic"
    case "exec": return "application-x-executable"
    default: return "text-x-generic"
    }
  }

  function iconSource(entry) {
    var found = Quickshell.iconPath(iconName(entry), true)
    if (!found) found = Quickshell.iconPath("text-x-generic", true)
    return found
  }

  function thumbSource(entry) {
    if (!entry || entry.dir || entry.kind !== "image") return ""
    return Util.fileUrl(entry.path)
  }

  function dateLabel(entry) {
    return Format.date(entry ? entry.mtime : 0)
  }

  function sizeLabel(entry) {
    if (!entry || entry.dir) return ""
    return Format.bytes(entry.size)
  }

  function updateColumns() {
    if (grid.width <= 0) return
    var next = Math.max(1, Math.floor(grid.width / Style.space(122)))
    if (next !== columns) columns = next
  }

  // ------------------------------------------------------------------- view

  Rectangle {
    id: strip
    visible: root.splitMode
    width: parent.width
    height: root.stripHeight
    color: root.active ? Util.alpha(root.accent, 0.10) : "transparent"

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: root.line
    }

    Image {
      id: stripIcon
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(14)
      height: Style.space(14)
      source: root.iconSource({ dir: true })
      fillMode: Image.PreserveAspectFit
    }

    Text {
      anchors.left: stripIcon.right
      anchors.leftMargin: Style.space(7)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: root.searchMode ? ("Search: " + root.searchQuery) : root.displayPath
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: root.active ? root.accent : Util.alpha(root.ink, 0.75)
      font.family: "sans-serif"
      font.pixelSize: root.fCaption
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.paneActivated()
    }
  }

  Item {
    id: body
    anchors.top: strip.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    GridView {
      id: grid
      anchors.fill: parent
      anchors.margins: Style.space(6)
      visible: root.viewMode === "grid"
      model: root.items
      cellWidth: root.columns > 0 ? width / root.columns : width
      cellHeight: Math.max(Style.space(112), Style.space(76) + 3 * root.fBody)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      onWidthChanged: root.updateColumns()

      delegate: Item {
        id: gridCell
        required property int index
        required property var modelData

        readonly property bool isSelected: root.isSelected(gridCell.modelData.path)
        readonly property bool isCut: root.isCut(gridCell.modelData.path)

        width: grid.cellWidth
        height: grid.cellHeight
        opacity: isCut ? 0.55 : 1

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(3)
          radius: Style.space(8)
          color: gridCell.isSelected ? root.selectedBg
                                     : (gridMouse.containsMouse ? root.hoverBg : "transparent")
          border.width: gridCell.isSelected ? 1 : 0
          border.color: Util.alpha(root.accent, 0.55)
        }

        Column {
          anchors.top: parent.top
          anchors.topMargin: Style.space(9)
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - Style.space(14)
          spacing: Style.space(3)

          Item {
            width: Style.space(52)
            height: Style.space(52)
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
              id: thumb
              anchors.fill: parent
              asynchronous: true
              cache: true
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: Style.space(104)
              sourceSize.height: Style.space(104)
              source: root.thumbSource(gridCell.modelData)
              visible: source !== "" && status === Image.Ready
            }

            Image {
              anchors.centerIn: parent
              width: Style.space(46)
              height: Style.space(46)
              source: root.iconSource(gridCell.modelData)
              fillMode: Image.PreserveAspectFit
              visible: !thumb.visible
            }
          }

          Text {
            width: parent.width
            text: gridCell.modelData.name
            textFormat: Text.PlainText
            color: root.ink
            font.family: "sans-serif"
            font.pixelSize: root.fBody
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideMiddle
            lineHeight: 0.95
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: gridCell.modelData.parentLabel || ""
            textFormat: Text.PlainText
            color: Util.alpha(root.ink, 0.55)
            font.family: "sans-serif"
            font.pixelSize: root.fCaption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
        }

        MouseArea {
          id: gridMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            root.paneActivated()
            if (mouse.button === Qt.RightButton) {
              root.click(gridCell.index, mouse.modifiers)
              var point = gridMouse.mapToItem(root, mouse.x, mouse.y)
              root.contextRequested(gridCell.index, point.x, point.y)
            } else {
              root.click(gridCell.index, mouse.modifiers)
            }
          }
          onDoubleClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton) return
            root.click(gridCell.index, mouse.modifiers)
            root.activate()
          }
        }
      }
    }

    Item {
      id: list
      anchors.fill: parent
      visible: root.viewMode === "list"

      Rectangle {
        id: listHeader
        width: parent.width
        height: root.rowHeight - Style.space(2)
        color: "transparent"

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: root.line
        }

        Text {
          x: Style.space(38)
          width: root.nameWidth
          anchors.verticalCenter: parent.verticalCenter
          text: "Name"
          color: Util.alpha(root.ink, 0.7)
          font.family: "sans-serif"
          font.pixelSize: root.fCaption
          elide: Text.ElideRight

          MouseArea {
            anchors.fill: parent
            onClicked: root.setSort("name")
          }
        }

        Text {
          x: Style.space(38) + root.nameWidth + Style.space(8)
          width: root.sizeWidth - Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: (root.sortMode === "size" ? (root.sortAsc ? "Size ↑" : "Size ↓") : "Size")
          color: Util.alpha(root.ink, 0.7)
          font.family: "sans-serif"
          font.pixelSize: root.fCaption
          horizontalAlignment: Text.AlignRight

          MouseArea {
            anchors.fill: parent
            onClicked: root.setSort("size")
          }
        }

        Text {
          x: Style.space(38) + root.nameWidth + root.sizeWidth + Style.space(14)
          width: root.dateWidth
          anchors.verticalCenter: parent.verticalCenter
          text: (root.sortMode === "modified" ? (root.sortAsc ? "Modified ↑" : "Modified ↓") : "Modified")
          color: Util.alpha(root.ink, 0.7)
          font.family: "sans-serif"
          font.pixelSize: root.fCaption
          horizontalAlignment: Text.AlignRight

          MouseArea {
            anchors.fill: parent
            onClicked: root.setSort("modified")
          }
        }
      }

      ListView {
        id: listView
        anchors.top: listHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        model: root.items
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          id: listRow
          required property int index
          required property var modelData

          readonly property bool isSelected: root.isSelected(listRow.modelData.path)
          readonly property bool isCut: root.isCut(listRow.modelData.path)

          width: listView.width
          height: root.rowHeight
          opacity: isCut ? 0.55 : 1

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: Style.space(6)
            color: listRow.isSelected ? root.selectedBg
                                      : (listMouse.containsMouse ? root.hoverBg : "transparent")
          }

          Image {
            id: rowIcon
            x: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: Style.space(18)
            source: root.iconSource(listRow.modelData)
            fillMode: Image.PreserveAspectFit
          }

          Text {
            x: Style.space(38)
            width: root.nameWidth
            anchors.verticalCenter: parent.verticalCenter
            text: listRow.modelData.name
            textFormat: Text.PlainText
            color: root.ink
            font.family: "sans-serif"
            font.pixelSize: root.fBody
            elide: Text.ElideMiddle
          }

          Text {
            x: Style.space(38) + root.nameWidth + Style.space(8)
            width: root.sizeWidth - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.sizeLabel(listRow.modelData)
            color: Util.alpha(root.ink, 0.65)
            font.family: "sans-serif"
            font.pixelSize: root.fCaption
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }

          Text {
            x: Style.space(38) + root.nameWidth + root.sizeWidth + Style.space(14)
            width: root.dateWidth
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateLabel(listRow.modelData)
            color: Util.alpha(root.ink, 0.65)
            font.family: "sans-serif"
            font.pixelSize: root.fCaption
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }

          MouseArea {
            id: listMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              root.paneActivated()
              if (mouse.button === Qt.RightButton) {
                root.click(listRow.index, mouse.modifiers)
                var point = listMouse.mapToItem(root, mouse.x, mouse.y)
                root.contextRequested(listRow.index, point.x, point.y)
              } else {
                root.click(listRow.index, mouse.modifiers)
              }
            }
            onDoubleClicked: function(mouse) {
              if (mouse.button !== Qt.LeftButton) return
              root.click(listRow.index, mouse.modifiers)
              root.activate()
            }
          }
        }
      }
    }

    // Empty and error states sit above the views but only while they show.
    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(40)
      visible: !root.loading && root.error === "" && root.items.length === 0
      text: root.searchMode ? "No results" : (root.trash ? "Trash is empty" : "Folder is empty")
      textFormat: Text.PlainText
      color: Util.alpha(root.ink, 0.55)
      font.family: "sans-serif"
      font.pixelSize: root.fTitle
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(40)
      visible: root.error !== ""
      text: root.error
      textFormat: Text.PlainText
      color: Commons.Color.urgent
      font.family: "sans-serif"
      font.pixelSize: root.fBody
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(10)
      visible: root.loading && root.items.length === 0
      text: "Loading…"
      textFormat: Text.PlainText
      color: Util.alpha(root.ink, 0.55)
      font.family: "sans-serif"
      font.pixelSize: root.fCaption
    }
  }
}
