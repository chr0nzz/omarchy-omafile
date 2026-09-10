import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: pane

  property var service: null
  property string path: ""
  property bool showHidden: false
  property string sortBy: "name"
  property bool descending: false
  property bool dirsFirst: true
  property string view: "list"
  property bool thumbnails: true
  property bool active: false
  property string filter: ""

  property var entries: []
  property var rows: []
  property var selection: ({})
  property int cursorIndex: -1
  property int anchorIndex: -1
  property bool loading: false
  property string errorMessage: ""
  property int total: 0

  property var history: []
  property int historyIndex: -1

  property bool searching: false
  property string searchQuery: ""
  property bool searchTruncated: false
  property int _searchId: 0
  property int _listId: 0
  property int _watchId: 0
  property string _watchPath: ""
  property var _pendingChunks: []

  readonly property bool canGoBack: historyIndex > 0
  readonly property bool canGoForward: historyIndex >= 0 && historyIndex < history.length - 1
  readonly property int selectedCount: countSelection()
  readonly property var selectedEntries: collectSelected()

  signal activated()
  signal navigated(string newPath)
  signal openRequested(var entry)
  signal contextRequested(var entry, real sceneX, real sceneY)
  signal statusChanged()

  function countSelection() {
    var n = 0
    for (var k in selection) if (selection[k]) n++
    return n
  }

  function collectSelected() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (selection[rows[i][0]]) out.push(Model.decodeEntry(rows[i], pane.path))
    return out
  }

  function selectedPaths() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (selection[rows[i][0]]) out.push(Model.decodeEntry(rows[i], pane.path).path)
    return out
  }

  function cursorEntry() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return null
    return Model.decodeEntry(rows[cursorIndex], pane.path)
  }

  function navigate(target, recordHistory) {
    var next = Model.normalizePath(Model.expandTilde(String(target || ""), Quickshell.env("HOME") || ""))
    if (!next) return
    if (pane.searching) {
      if (_searchId && service) service.cancel(_searchId)
      _searchId = 0
      pane.searching = false
      pane.searchQuery = ""
    }
    if (recordHistory !== false) pushHistory(next)
    pane.path = next
    reload()
    pane.navigated(next)
    if (service) service.noteRecent(next)
  }

  function pushHistory(next) {
    var trimmed = history.slice(0, historyIndex + 1)
    if (trimmed.length === 0 || trimmed[trimmed.length - 1] !== next) trimmed.push(next)
    if (trimmed.length > 100) trimmed = trimmed.slice(trimmed.length - 100)
    history = trimmed
    historyIndex = trimmed.length - 1
  }

  function goBack() {
    if (!canGoBack) return
    historyIndex = historyIndex - 1
    pane.path = history[historyIndex]
    reload()
    pane.navigated(pane.path)
  }

  function goForward() {
    if (!canGoForward) return
    historyIndex = historyIndex + 1
    pane.path = history[historyIndex]
    reload()
    pane.navigated(pane.path)
  }

  function goUp() {
    var parent = Model.parentPath(pane.path)
    if (parent === pane.path) return
    var leaving = Model.basename(pane.path)
    navigate(parent)
    Qt.callLater(function () { focusName(leaving) })
  }

  function focusName(name) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][0] === name) {
        setCursor(i, false, false)
        listView.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  function hitToRow(hit) {
    return [
      String(hit.name || ""), String(hit.kind || "f"),
      Number(hit.size) || 0, Number(hit.mtime) || 0,
      Number(hit.mode) || 0, null, String(hit.path || "")
    ]
  }

  function startSearch(query) {
    if (!service || !pane.path) return
    var trimmed = String(query || "").trim()
    pane.searchQuery = trimmed
    if (!trimmed) {
      stopSearch()
      return
    }
    if (_searchId) service.cancel(_searchId)
    if (_listId) service.cancel(_listId)
    pane.searching = true
    pane.searchTruncated = false
    pane.errorMessage = ""
    pane.loading = true
    pane.entries = []
    pane.rows = []
    pane.selection = ({})
    pane.cursorIndex = -1
    pane._pendingChunks = []

    _searchId = service.searchFiles(pane.path, trimmed, "substring", pane.showHidden,
      function (hit) {
        pane._pendingChunks.push(pane.hitToRow(hit))
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        pane.loading = false
        pane.searchTruncated = msg.truncated === true
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        pane.loading = false
        if (msg.code !== "ECANCELED")
          pane.errorMessage = String(msg.message || "Search failed")
        pane.statusChanged()
      })
  }

  function stopSearch() {
    if (_searchId && service) service.cancel(_searchId)
    _searchId = 0
    pane.searchQuery = ""
    pane.searchTruncated = false
    if (pane.searching) {
      pane.searching = false
      reload()
    }
  }

  function reload() {
    if (!service || !pane.path) return
    if (pane.searching) return
    if (_listId) service.cancel(_listId)
    _pendingChunks = []
    entries = []
    rows = []
    selection = ({})
    cursorIndex = -1
    anchorIndex = -1
    errorMessage = ""
    loading = true
    total = 0
    rebuildTimer.stop()

    _listId = service.listDirectory(pane.path, pane.showHidden,
      function (chunk) {
        var acc = pane._pendingChunks
        for (var i = 0; i < chunk.length; i++) acc.push(chunk[i])
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        pane.loading = false
        pane.total = Number(msg.total) || pane._pendingChunks.length
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (String(msg.code || "") === "ECANCELED") return
        pane.loading = false
        pane.errorMessage = String(msg.message || msg.code || "Cannot open this folder")
        pane.statusChanged()
      })

    rewatch()
  }

  function flushChunks() {
    if (_pendingChunks.length === 0 && entries.length === 0) {
      rows = []
      return
    }
    if (_pendingChunks.length > 0) {
      entries = entries.concat(_pendingChunks)
      _pendingChunks = []
    }
    if (loading) {
      rows = pane.filter ? Model.filterRaw(entries, pane.filter) : entries
      statusChanged()
      return
    }
    rebuild()
  }

  function rebuild() {
    var filtered = (pane.searching || !pane.filter) ? entries : Model.filterRaw(entries, pane.filter)
    if (!pane.searching && Model.isDefaultOrder(pane.sortBy, pane.descending, pane.dirsFirst))
      rows = filtered
    else
      rows = Model.sortRaw(filtered, pane.sortBy, pane.descending, pane.dirsFirst)
    if (cursorIndex >= rows.length) cursorIndex = rows.length - 1
    statusChanged()
  }

  function rewatch() {
    if (!service) return
    if (_watchId) service.unwatch(_watchId, _watchPath)
    _watchPath = pane.path
    _watchId = service.watchDirectory(pane.path, function () { refreshTimer.restart() })
  }

  function refresh() {
    var keepSelection = ({})
    for (var k in selection) keepSelection[k] = selection[k]
    var keepCursor = cursorIndex
    var restore = function () {
      pane.selection = keepSelection
      if (keepCursor >= 0 && keepCursor < pane.rows.length) pane.cursorIndex = keepCursor
    }
    reload()
    Qt.callLater(restore)
  }

  function setCursor(index, extend, toggle) {
    if (index < 0 || index >= rows.length) return
    cursorIndex = index
    if (toggle) {
      var name = rows[index][0]
      var next = ({})
      for (var k in selection) next[k] = selection[k]
      next[name] = !next[name]
      selection = next
      anchorIndex = index
      return
    }
    if (extend && anchorIndex >= 0) {
      var lo = Math.min(anchorIndex, index)
      var hi = Math.max(anchorIndex, index)
      var range = ({})
      for (var i = lo; i <= hi; i++) range[rows[i][0]] = true
      selection = range
      return
    }
    var single = ({})
    single[rows[index][0]] = true
    selection = single
    anchorIndex = index
  }

  function selectAll() {
    var all = ({})
    for (var i = 0; i < rows.length; i++) all[rows[i][0]] = true
    selection = all
  }

  function clearSelection() {
    selection = ({})
  }

  function jumpCursor(index, extend) {
    if (rows.length === 0) return
    var target = Math.max(0, Math.min(rows.length - 1, index))
    setCursor(target, extend, false)
    listView.positionViewAtIndex(target, ListView.Contain)
  }

  function moveCursor(delta, extend) {
    if (rows.length === 0) return
    var next = cursorIndex < 0 ? 0 : cursorIndex + delta
    next = Math.max(0, Math.min(rows.length - 1, next))
    setCursor(next, extend, false)
    listView.positionViewAtIndex(next, ListView.Contain)
  }

  function openEntry(entry) {
    if (!entry) return
    if (entry.isDir && !entry.isBroken) navigate(entry.path)
    else pane.openRequested(entry)
  }

  function gridLabel(name) {
    var text = String(name || "")
    if (text.length <= 26) return text
    return text.substring(0, 14) + "\u2026" + text.substring(text.length - 10)
  }

  function previewable(entry) {
    if (!pane.thumbnails) return false
    if (entry.isDir || entry.isBroken) return false
    if (entry.size <= 0 || entry.size > 24000000) return false
    var e = entry.ext
    return e === "png" || e === "jpg" || e === "jpeg" || e === "gif"
      || e === "webp" || e === "bmp" || e === "svg" || e === "ico" || e === "avif"
  }

  function openRow(row) {
    openEntry(Model.decodeEntry(row, pane.path))
  }

  function activateCursor() {
    openEntry(cursorEntry())
  }

  function setSort(column) {
    if (pane.sortBy === column) pane.descending = !pane.descending
    else {
      pane.sortBy = column
      pane.descending = false
    }
    rebuild()
  }

  property bool ready: true

  onServiceChanged: {
    if (service && pane.path && !loading && rows.length === 0) reload()
  }

  onShowHiddenChanged: if (ready) reload()
  onFilterChanged: if (ready) rebuild()
  onDirsFirstChanged: if (ready) rebuild()

  Component.onDestruction: {
    if (service && _watchId) service.unwatch(_watchId, _watchPath)
    if (service && _listId) service.cancel(_listId)
    if (service && _searchId) service.cancel(_searchId)
  }

  Timer {
    id: rebuildTimer
    interval: 120
    repeat: false
    onTriggered: pane.flushChunks()
  }

  Timer {
    id: stallWatchdog
    interval: 6000
    repeat: false
    running: pane.loading && pane.rows.length === 0 && pane.path !== ""
    onTriggered: {
      if (!pane.loading || pane.rows.length > 0) return
      if (!pane.service) return
      if (pane.searching) return
      pane.loading = false
      pane.reload()
    }
  }

  Timer {
    id: refreshTimer
    interval: 180
    repeat: false
    onTriggered: pane.refresh()
  }

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted

  Rectangle {
    anchors.fill: parent
    color: pane.bg
    border.width: pane.active ? Math.max(1, Style.space(1)) : 0
    border.color: Util.alpha(pane.accent, 0.5)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: function (mouse) {
        pane.activated()
        if (mouse.button === Qt.RightButton) {
          pane.clearSelection()
          pane.contextRequested(null, mouse.x, mouse.y)
        } else pane.clearSelection()
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(1)
      spacing: 0

      Row {
        id: header
        width: parent.width
        height: pane.view === "list" ? Style.space(22) : 0
        visible: pane.view === "list"
        spacing: 0

        Repeater {
          model: [
            { key: "name", label: "Name", weight: 0.52 },
            { key: "size", label: "Size", weight: 0.14 },
            { key: "type", label: "Type", weight: 0.16 },
            { key: "modified", label: "Modified", weight: 0.18 }
          ]

          delegate: Item {
            required property var modelData
            width: header.width * modelData.weight
            height: header.height

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: modelData.label + (pane.sortBy === modelData.key ? (pane.descending ? "  " + Icons.actionGlyph("chevronDown") : "  " + Icons.actionGlyph("chevronUp")) : "")
              color: pane.sortBy === modelData.key ? pane.accent : Util.alpha(pane.fg, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              onClicked: pane.setSort(modelData.key)
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: pane.view === "list" ? 1 : 0
        visible: pane.view === "list"
        color: Util.alpha(pane.fg, 0.12)
      }

      ListView {
        id: listView
        width: parent.width
        height: parent.height - header.height - (pane.view === "list" ? 1 : 0)
        clip: true
        model: pane.rows
        cacheBuffer: 400
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: pane.cursorIndex
        visible: pane.view === "list"

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)

          width: listView.width
          height: Style.space(22)
          color: pane.selection[modelData[0]]
            ? Util.alpha(pane.accent, Style.selectedFillAlpha)
            : (rowHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent")

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: pane.cursorIndex === index && pane.active ? 1 : 0
            border.color: Util.alpha(pane.accent, 0.8)
          }

          HoverHandler { id: rowHover }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[row.modelData[0]]) pane.setCursor(row.index, false, false)
                pane.contextRequested(row.entry, mouse.x + row.x, mouse.y + row.y)
                return
              }
              var extend = (mouse.modifiers & Qt.ShiftModifier) !== 0
              var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0
              pane.setCursor(row.index, extend, toggle)
            }
            onDoubleClicked: function (mouse) {
              if (mouse.button !== Qt.LeftButton) return
              pane.openEntry(row.entry)
            }
          }

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: header.width * 0.52
              height: parent.height

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Item {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: Style.space(18)

                  Text {
                    anchors.centerIn: parent
                    visible: !rowThumb.visible
                    text: Icons.glyphFor(row.entry)
                    color: row.entry.isBroken ? Color.urgent
                      : (row.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.75))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                  }

                  Image {
                    id: rowThumb
                    anchors.fill: parent
                    visible: pane.previewable(row.entry) && status === Image.Ready
                    source: pane.previewable(row.entry) ? Util.fileUrl(row.entry.path) : ""
                    sourceSize.width: Style.space(36)
                    sourceSize.height: Style.space(36)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(28)
                  text: row.entry.name
                  color: row.entry.isHidden ? Util.alpha(pane.fg, 0.55) : pane.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.italic: row.entry.isLink
                  elide: Text.ElideMiddle
                }
              }
            }

            Text {
              width: header.width * 0.14
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              rightPadding: Style.space(10)
              text: row.entry.isDir ? "" : Model.formatSize(row.entry.size)
              color: Util.alpha(pane.fg, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: header.width * 0.16
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.kindLabel(row.entry)
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              width: header.width * 0.18
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.formatDate(row.entry.mtime, Date.now())
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }
      }

      GridView {
        id: gridView
        width: parent.width
        height: parent.height - header.height
        clip: true
        model: pane.rows
        visible: pane.view === "grid"
        cellWidth: Style.space(110)
        cellHeight: Style.space(96)
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
          id: cell
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)

          width: gridView.cellWidth
          height: gridView.cellHeight
          radius: Style.cornerRadius
          color: pane.selection[modelData[0]]
            ? Util.alpha(pane.accent, Style.selectedFillAlpha)
            : (cellHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent")

          HoverHandler { id: cellHover }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[cell.modelData[0]]) pane.setCursor(cell.index, false, false)
                pane.contextRequested(cell.entry, mouse.x + cell.x, mouse.y + cell.y)
                return
              }
              var extend = (mouse.modifiers & Qt.ShiftModifier) !== 0
              var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0
              pane.setCursor(cell.index, extend, toggle)
            }
            onDoubleClicked: pane.openEntry(cell.entry)
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(12)
            spacing: Style.space(6)

            Item {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(48)
              height: Style.space(48)

              Text {
                anchors.centerIn: parent
                visible: !thumb.visible
                text: Icons.glyphFor(cell.entry)
                color: cell.entry.isBroken ? Color.urgent
                  : (cell.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.8))
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
              }

              Image {
                id: thumb
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                visible: pane.previewable(cell.entry) && status === Image.Ready
                source: pane.previewable(cell.entry) ? Util.fileUrl(cell.entry.path) : ""
                sourceSize.width: Style.space(96)
                sourceSize.height: Style.space(96)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: pane.gridLabel(cell.entry.name)
              color: pane.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              maximumLineCount: 2
              wrapMode: Text.WrapAnywhere
            }
          }
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: pane.errorMessage !== "" && pane.rows.length === 0
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter
      text: pane.errorMessage
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    Text {
      anchors.centerIn: parent
      visible: !pane.loading && pane.errorMessage === "" && pane.rows.length === 0
      text: pane.searching ? "No matches" : (pane.filter ? "Nothing matches" : "Empty folder")
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.centerIn: parent
      visible: pane.loading && pane.rows.length === 0
      text: pane.searching ? "Searching" : "Reading"
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
