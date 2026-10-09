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
  property real viewScale: 1
  property var patterns: []

  readonly property int rowHeight: Math.round(Style.space(22) * viewScale)
  readonly property int listIconSize: Math.round(Style.space(18) * viewScale)
  readonly property bool galleryView: view === "gallery"
  readonly property int gridIconSize: Math.round(Style.space(galleryView ? 150 : 48) * viewScale)
  readonly property bool compactView: view === "compact"

  function scaled(value) {
    return Math.max(1, Math.round(value * viewScale))
  }
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
  property int _generation: 0
  readonly property bool virtualView: pane.path === "recent:"
  property int _listId: 0
  property int _softId: 0
  property var _changedNames: ({})
  property bool _changedAll: false
  property real _lastChangeApplied: 0
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
  signal newTabRequested(string path)
  signal contextRequested(var entry, real sceneX, real sceneY)
  signal statusChanged()
  signal dropRequested(var urls, string dest, var position)

  property string dragUriList: ""
  property var dragGrab: null

  function fileUri(path) {
    return "file://" + encodeURI(String(path)).replace(/#/g, "%23").replace(/\?/g, "%3F")
  }

  function prepareDrag(entry) {
    var paths = selectedPaths()
    if (paths.indexOf(entry.path) < 0) paths = [entry.path]
    var uris = []
    for (var i = 0; i < paths.length; i++) uris.push(fileUri(paths[i]))
    dragUriList = uris.join("\r\n") + "\r\n"
    dragBadgeGlyph.text = Icons.glyphFor(entry)
    dragBadgeLabel.text = paths.length === 1 ? entry.name : Model.formatCount(paths.length, "item", "items")
    Qt.callLater(function () {
      dragBadge.grabToImage(function (result) { pane.dragGrab = result })
    })
  }

  function pressItem(index, mouse) {
    var extend = (mouse.modifiers & Qt.ShiftModifier) !== 0
    var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0
    if (!extend && !toggle && pane.selection[pane.rows[index][0]]) {
      pane.cursorIndex = index
      return true
    }
    pane.setCursor(index, extend, toggle)
    return false
  }

  function hotIndex(x, y) {
    var index = hitTestIndex(x, y)
    if (index < 0) return -1
    var v = activeView()
    var pt = bandArea.mapToItem(v, x, y)
    if (pane.view === "list") return pt.x < header.width * 0.52 ? index : -1
    if (pane.compactView) return index
    var cw = gridView.cellWidth
    var cols = Math.max(1, Math.floor(gridView.width / cw))
    var cx = (pt.x + v.contentX) - (index % cols) * cw
    return (cx > cw * 0.12 && cx < cw * 0.88) ? index : -1
  }
  signal zoomRequested(real delta)

  readonly property int wheelLines: 3

  function wheelStep() {
    if (pane.view === "grid" || pane.galleryView) return Math.max(gridView.cellHeight, pane.rowHeight * wheelLines)
    return pane.rowHeight * wheelLines
  }

  function wheelScroll(wheel) {
    if (wheel.pixelDelta.y !== 0 || wheel.angleDelta.y === 0) return false
    var v = activeView()
    var top = v.originY - v.topMargin
    var bottom = Math.max(top, v.originY + v.contentHeight + v.bottomMargin - v.height)
    var from = wheelGlide.running && wheelGlide.target === v ? wheelGlide.to : v.contentY
    var to = Math.max(top, Math.min(bottom, from - wheel.angleDelta.y / 120 * wheelStep()))
    wheelGlide.stop()
    v.cancelFlick()
    if (to === v.contentY) return true
    wheelGlide.target = v
    wheelGlide.from = v.contentY
    wheelGlide.to = to
    wheelGlide.start()
    return true
  }

  NumberAnimation {
    id: wheelGlide
    property: "contentY"
    duration: 140
    easing.type: Easing.OutCubic
  }

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

  function activeView() {
    return pane.view === "list" ? listView : gridView
  }

  function onScrollHandle(x, y) {
    var bar = activeView().ScrollBar.vertical
    if (!bar || !bar.visible) return false
    var pt = bandArea.mapToItem(bar, x, y)
    return bar.contains(pt)
  }

  function columnsPerRow() {
    if (pane.view === "list" || gridView.cellWidth <= 0) return 1
    return Math.max(1, Math.floor(gridView.width / gridView.cellWidth))
  }

  function hitTestIndex(x, y) {
    var v = activeView()
    var pt = bandArea.mapToItem(v, x, y)
    if (pt.x < 0 || pt.y < 0 || pt.x > v.width || pt.y > v.height) return -1
    return v.indexAt(pt.x + v.contentX, pt.y + v.contentY)
  }

  function selectInBand(x1, y1, x2, y2, base) {
    var v = activeView()
    var a = bandArea.mapToItem(v, Math.min(x1, x2), Math.min(y1, y2))
    var b = bandArea.mapToItem(v, Math.max(x1, x2), Math.max(y1, y2))
    var left = a.x + v.contentX
    var top = a.y + v.contentY
    var right = b.x + v.contentX
    var bottom = b.y + v.contentY
    var next = {}
    for (var k in base) if (base[k]) next[k] = true
    if (pane.view === "list") {
      var h = pane.rowHeight
      if (h > 0) {
        var i0 = Math.max(0, Math.floor(top / h))
        var i1 = Math.min(pane.rows.length - 1, Math.floor(bottom / h))
        for (var i = i0; i <= i1; i++) next[pane.rows[i][0]] = true
      }
    } else {
      var cw = gridView.cellWidth
      var chh = gridView.cellHeight
      if (cw > 0 && chh > 0) {
        var cols = Math.max(1, Math.floor(gridView.width / cw))
        var c0 = Math.max(0, Math.floor(left / cw))
        var c1 = Math.min(cols - 1, Math.floor(right / cw))
        var r0 = Math.max(0, Math.floor(top / chh))
        var r1 = Math.floor(bottom / chh)
        for (var r = r0; r <= r1; r++) {
          for (var c = c0; c <= c1; c++) {
            var idx = r * cols + c
            if (idx >= 0 && idx < pane.rows.length) next[pane.rows[idx][0]] = true
          }
        }
      }
    }
    pane.selection = next
    pane.statusChanged()
  }

  function cursorEntry() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return null
    return Model.decodeEntry(rows[cursorIndex], pane.path)
  }

  function navigate(target, recordHistory) {
    var raw = String(target || "")
    var next = raw === "recent:"
      ? raw
      : Model.normalizePath(Model.expandTilde(raw, Quickshell.env("HOME") || ""))
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
    if (pane.virtualView) return
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
        activeView().positionViewAtIndex(i, ListView.Contain)
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

    var searchGeneration = ++pane._generation

    _searchId = service.searchFiles(pane.path, trimmed, "substring", pane.showHidden,
      function (hit) {
        if (searchGeneration !== pane._generation) return
        pane._pendingChunks.push(pane.hitToRow(hit))
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (searchGeneration !== pane._generation) return
        pane.loading = false
        pane.searchTruncated = msg.truncated === true
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (searchGeneration !== pane._generation) return
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

  function loadRecent() {
    if (!service) return
    if (_listId) service.cancel(_listId)
    var generation = ++pane._generation
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

    if (_watchId) {
      service.unwatch(_watchId, _watchPath)
      _watchId = 0
      _watchPath = ""
    }

    _listId = service.listRecent(
      function (chunk) {
        if (generation !== pane._generation) return
        var acc = pane._pendingChunks
        for (var i = 0; i < chunk.length; i++) acc.push(chunk[i])
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        pane.total = Number(msg.total) || 0
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        if (String(msg.code || "") !== "ECANCELED")
          pane.errorMessage = String(msg.message || "Could not read recent files")
        pane.statusChanged()
      })
  }

  function reload() {
    if (!service || !pane.path) return
    if (pane.virtualView) {
      loadRecent()
      return
    }
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

    var generation = ++pane._generation

    _listId = service.listDirectory(pane.path, pane.showHidden,
      function (chunk) {
        if (generation !== pane._generation) return
        var acc = pane._pendingChunks
        for (var i = 0; i < chunk.length; i++) acc.push(chunk[i])
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        pane.total = Number(msg.total) || pane._pendingChunks.length
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (generation !== pane._generation) return
        if (String(msg.code || "") === "ECANCELED") return
        pane.loading = false
        pane.errorMessage = String(msg.message || msg.code || "Cannot open this folder")
        pane.statusChanged()
      })

    if (!_watchId || _watchPath !== pane.path) rewatch()
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
      rows = Model.filterByPatterns(pane.filter ? Model.filterRaw(entries, pane.filter) : entries, pane.patterns)
      statusChanged()
      return
    }
    rebuild()
  }

  function rebuild() {
    var filtered = Model.filterByPatterns(((pane.searching || pane.virtualView) || !pane.filter)
      ? entries : Model.filterRaw(entries, pane.filter), pane.patterns)
    if (pane.virtualView
        || (!pane.searching && Model.isDefaultOrder(pane.sortBy, pane.descending, pane.dirsFirst)))
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
    _watchId = service.watchDirectory(pane.path, function (m) { pane.noteChanges(m) })
  }

  function noteChanges(m) {
    var names = m && m.names ? m.names : []
    if (names.length === 0 || names.length > 200) _changedAll = true
    else for (var i = 0; i < names.length; i++) _changedNames[String(names[i])] = true
    if (refreshTimer.running) return
    refreshTimer.interval = Date.now() - _lastChangeApplied < 1000 ? 1000 : 180
    refreshTimer.start()
  }

  function applyChanges() {
    _lastChangeApplied = Date.now()
    var all = _changedAll
    var names = Object.keys(_changedNames)
    _changedAll = false
    _changedNames = ({})
    if (pane.virtualView || pane.searching || pane.loading) return
    if (all) refresh()
    else if (names.length > 0) patchEntries(names)
  }

  function refresh() {
    if (!service || !pane.path) return
    if (pane.virtualView || pane.searching) {
      reload()
      return
    }
    if (_softId) service.cancel(_softId)
    var path = pane.path
    var generation = pane._generation
    var buffer = []
    _softId = service.listDirectory(path, pane.showHidden,
      function (chunk) {
        for (var i = 0; i < chunk.length; i++) buffer.push(chunk[i])
      },
      function () {
        pane._softId = 0
        if (generation !== pane._generation || path !== pane.path) return
        pane.replaceEntries(buffer)
      },
      function (msg) {
        pane._softId = 0
        if (String(msg.code || "") === "ECANCELED") return
        if (generation !== pane._generation || path !== pane.path) return
        pane.reload()
      })
  }

  function patchEntries(names) {
    var path = pane.path
    var generation = pane._generation
    var paths = names.map(function (n) { return Model.joinPath(path, n) })
    service.statPaths(paths, function (items) {
      if (generation !== pane._generation || path !== pane.path) return
      var byName = {}
      for (var i = 0; i < items.length; i++) byName[names[i]] = items[i]
      var next = []
      var seen = {}
      for (var j = 0; j < pane.entries.length; j++) {
        var raw = pane.entries[j]
        var item = byName[raw[0]]
        seen[raw[0]] = true
        if (!item) next.push(raw)
        else if (!item.error) next.push([raw[0], item.kind, item.size, item.mtime, item.mode, item.linkTarget])
      }
      for (var k = 0; k < names.length; k++) {
        var name = names[k]
        var fresh = byName[name]
        if (seen[name] || !fresh || fresh.error) continue
        if (!pane.showHidden && name.charAt(0) === ".") continue
        next.push([name, fresh.kind, fresh.size, fresh.mtime, fresh.mode, fresh.linkTarget])
      }
      pane.replaceEntries(next)
    })
  }

  function replaceEntries(list) {
    var view = activeView()
    var keepY = view.contentY
    var keepSelection = ({})
    for (var k in selection) if (selection[k]) keepSelection[k] = true
    var cursorName = cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex][0] : ""
    entries = list
    rebuild()
    var nextSelection = ({})
    var nextCursor = -1
    for (var i = 0; i < rows.length; i++) {
      var name = rows[i][0]
      if (keepSelection[name]) nextSelection[name] = true
      if (name === cursorName) nextCursor = i
    }
    selection = nextSelection
    if (nextCursor >= 0) cursorIndex = nextCursor
    view.contentY = Math.max(0, Math.min(keepY, view.contentHeight - view.height))
    Qt.callLater(function () {
      view.contentY = Math.max(0, Math.min(keepY, view.contentHeight - view.height))
    })
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

  function toggleCursorSelection() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return
    var name = rows[cursorIndex][0]
    var next = ({})
    for (var k in selection) next[k] = selection[k]
    next[name] = !next[name]
    selection = next
    anchorIndex = cursorIndex
  }

  function invertSelection() {
    var next = ({})
    for (var i = 0; i < rows.length; i++) {
      var name = rows[i][0]
      if (!selection[name]) next[name] = true
    }
    selection = next
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
    activeView().positionViewAtIndex(target, ListView.Contain)
  }

  function moveCursor(delta, extend) {
    if (rows.length === 0) return
    var next = cursorIndex < 0 ? 0 : cursorIndex + delta
    next = Math.max(0, Math.min(rows.length - 1, next))
    setCursor(next, extend, false)
    activeView().positionViewAtIndex(next, ListView.Contain)
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

  function middleOpen(entry) {
    if (!entry) return
    if (entry.isDir && !entry.isBroken) pane.newTabRequested(entry.path)
    else pane.openRequested(entry)
  }

  property var captions: []
  property var dirCounts: ({})
  property var _countQueue: ({})
  property var _countPending: ({})
  readonly property var shownCaptions: {
    if (pane.view !== "grid" && !pane.galleryView) return []
    var list = []
    for (var i = 0; i < captions.length; i++)
      if (captions[i] && captions[i] !== "none" && list.indexOf(captions[i]) < 0) list.push(String(captions[i]))
    var room = viewScale < 0.9 ? 1 : (viewScale < 1.3 ? 2 : 3)
    return list.slice(0, room)
  }
  readonly property int captionFontSize: Math.max(8, Math.round(pane.scaled(Style.font.caption) * 0.92))
  readonly property int captionLineHeight: Math.round(captionFontSize * 1.4)

  onPathChanged: {
    dirCounts = ({})
    _countPending = ({})
  }


  function captionText(entry, kind) {
    if (!entry) return ""
    if (kind === "size") {
      if (!entry.isDir) return Model.formatSize(entry.size)
      var n = dirCounts[entry.path + "|" + entry.mtime]
      if (n === undefined) {
        queueCount(entry)
        return ""
      }
      return n < 0 ? "" : Model.formatCount(n, "item", "items")
    }
    if (kind === "type") return Model.kindLabel(entry)
    if (kind === "modified") return Model.formatDate(entry.mtime)
    if (kind === "permissions") return Model.formatMode(entry.mode)
    return ""
  }

  function queueCount(entry) {
    if (!service || !service.itemCounts) return
    if (_countQueue[entry.path] !== undefined || _countPending[entry.path]) return
    var first = Object.keys(_countQueue).length === 0
    _countQueue[entry.path] = entry.mtime
    if (first) Qt.callLater(flushCounts)
  }

  function flushCounts() {
    var queue = _countQueue
    _countQueue = ({})
    var paths = Object.keys(queue)
    if (paths.length === 0 || !service) return
    var mtimes = paths.map(function (p) { return queue[p] })
    for (var i = 0; i < paths.length; i++) _countPending[paths[i]] = true
    var forPath = pane.path
    service.itemCounts(paths, mtimes, pane.showHidden, function (got) {
      if (forPath !== pane.path) return
      var next = {}
      for (var k in pane.dirCounts) next[k] = pane.dirCounts[k]
      for (var p in got) {
        next[p + "|" + queue[p]] = Number(got[p])
        delete pane._countPending[p]
      }
      pane.dirCounts = next
    })
  }

  function isCut(entry) {
    if (!entry || !service || !service.cutPaths) return false
    return service.cutPaths[entry.path] === true
  }

  function thumbable(entry) {
    if (!pane.thumbnails || !pane.service || !pane.service.thumbExts) return false
    if (entry.isDir || entry.isBroken || entry.size <= 0) return false
    return pane.service.thumbExts[entry.ext] === true
  }

  function openRow(row) {
    openEntry(Model.decodeEntry(row, pane.path))
  }

  function activateCursor() {
    openEntry(cursorEntry())
  }

  function setSort(column) {
    if (pane.virtualView) return
    if (pane.sortBy === column) pane.descending = !pane.descending
    else {
      pane.sortBy = column
      pane.descending = false
    }
    rebuild()
  }

  function setSortOrder(column, descending) {
    if (pane.virtualView) return
    pane.sortBy = column
    pane.descending = descending === true
    rebuild()
  }

  property bool ready: true

  onServiceChanged: {
    if (service && pane.path && !loading && rows.length === 0) reload()
  }

  onShowHiddenChanged: {
    dirCounts = ({})
    _countPending = ({})
    if (ready) reload()
  }
  onFilterChanged: if (ready) rebuild()
  onPatternsChanged: if (ready) rebuild()
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
    onTriggered: pane.applyChanges()
  }

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted

  Rectangle {
    id: dragBadge
    z: -1
    width: badgeRow.implicitWidth + Style.space(20)
    height: badgeRow.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: Util.alpha(pane.accent, 0.9)

    Row {
      id: badgeRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        id: dragBadgeGlyph
        color: pane.bg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        textFormat: Text.PlainText
        id: dragBadgeLabel
        color: pane.bg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: paneDrop.containsDrag ? Qt.tint(pane.bg, Util.alpha(pane.accent, 0.08)) : pane.bg
    border.width: Math.max(1, Style.space(1))
    border.color: pane.active
      ? Util.alpha(pane.accent, 0.5) : Util.alpha(pane.fg, 0.15)

    DropTarget {
      id: paneDrop
      anchors.fill: parent
      target: pane.virtualView || pane.searching ? "" : pane.path
      onFilesDropped: function (urls, dest, position) { pane.dropRequested(urls, dest, position) }
    }

    MouseArea {
      id: bandArea
      anchors.fill: parent
      z: 10
      acceptedButtons: Qt.LeftButton | Qt.RightButton

      property real originX: 0
      property real originY: 0
      property real currentX: 0
      property real currentY: 0
      property bool banding: false
      property var baseSelection: ({})
      property int pressedIndex: -1
      property bool moved: false
      property int pressModifiers: 0

      onPressed: function (mouse) {
        pane.activated()
        if (pane.onScrollHandle(mouse.x, mouse.y)) {
          mouse.accepted = false
          return
        }
        if (pane.view === "list" && mouse.y < header.height + Style.space(1)) {
          mouse.accepted = false
          return
        }
        if (pane.hotIndex(mouse.x, mouse.y) >= 0) {
          mouse.accepted = false
          return
        }
        pressedIndex = pane.hitTestIndex(mouse.x, mouse.y)
        moved = false
        if (mouse.button === Qt.RightButton) {
          if (pressedIndex >= 0) {
            var hit = Model.decodeEntry(pane.rows[pressedIndex], pane.path)
            if (!pane.selection[pane.rows[pressedIndex][0]]) pane.setCursor(pressedIndex, false, false)
            pane.contextRequested(hit, mouse.x, mouse.y)
            return
          }
          pane.clearSelection()
          pane.contextRequested(null, mouse.x, mouse.y)
          return
        }
        pressModifiers = mouse.modifiers
        var additive = (mouse.modifiers & Qt.ControlModifier) !== 0
        baseSelection = additive ? pane.selection : ({})
        if (!additive) pane.clearSelection()
        originX = mouse.x
        originY = mouse.y
        currentX = mouse.x
        currentY = mouse.y
        banding = true
      }

      onPositionChanged: function (mouse) {
        if (!banding) return
        if (!moved && Math.abs(mouse.x - originX) + Math.abs(mouse.y - originY) < Style.space(4)) return
        moved = true
        currentX = mouse.x
        currentY = mouse.y
        pane.selectInBand(originX, originY, currentX, currentY, baseSelection)
      }

      onReleased: {
        if (banding && !moved && pressedIndex >= 0)
          pane.setCursor(pressedIndex, (pressModifiers & Qt.ShiftModifier) !== 0,
            (pressModifiers & Qt.ControlModifier) !== 0)
        banding = false
      }
      onCanceled: banding = false
      onDoubleClicked: function (mouse) {
        if (pressedIndex >= 0 && pressedIndex < pane.rows.length)
          pane.openEntry(Model.decodeEntry(pane.rows[pressedIndex], pane.path))
      }

      property real wheelAccum: 0

      onWheel: function (wheel) {
        if (!(wheel.modifiers & Qt.ControlModifier)) {
          if (!pane.wheelScroll(wheel)) wheel.accepted = false
          return
        }
        wheelAccum += wheel.angleDelta.y
        var steps = wheelAccum > 0 ? Math.floor(wheelAccum / 120) : Math.ceil(wheelAccum / 120)
        if (steps !== 0) {
          wheelAccum -= steps * 120
          pane.zoomRequested(steps * 0.1)
        }
      }

      Rectangle {
        visible: bandArea.banding && bandArea.moved
        x: Math.min(bandArea.originX, bandArea.currentX)
        y: Math.min(bandArea.originY, bandArea.currentY)
        width: Math.abs(bandArea.currentX - bandArea.originX)
        height: Math.abs(bandArea.currentY - bandArea.originY)
        color: Util.alpha(pane.accent, 0.15)
        border.width: 1
        border.color: Util.alpha(pane.accent, 0.6)
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
            objectName: "header-" + modelData.key
            width: header.width * modelData.weight
            height: header.height

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: modelData.label + ((pane.sortBy === modelData.key && !pane.virtualView)
                ? (pane.descending ? "  " + Icons.actionGlyph("chevronDown")
                  : "  " + Icons.actionGlyph("chevronUp")) : "")
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

        ScrollBar.vertical: ScrollHandle { objectName: "listScroll" }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)
          readonly property bool isCut: pane.isCut(entry)

          width: listView.width
          height: pane.rowHeight
          color: rowDrop.containsDrag ? Util.alpha(pane.accent, 0.3)
            : pane.selection[modelData[0]]
            ? Util.alpha(pane.accent, Style.selectedFillAlpha)
            : (rowHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent")

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: pane.cursorIndex === index && pane.active ? 1 : 0
            border.color: Util.alpha(pane.accent, 0.8)
          }

          HoverHandler { id: rowHover }

          DropTarget {
            id: rowDrop
            anchors.fill: parent
            target: row.entry.isDir && !row.entry.isBroken && !pane.virtualView ? row.entry.path : ""
            onFilesDropped: function (urls, dest, position) { pane.dropRequested(urls, dest, position) }
          }

          DragProxy {
            id: rowDrag
            view: pane
            active: rowMouse.drag.active
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            drag.target: rowDrag
            drag.threshold: Style.space(8)
            property bool narrowOnRelease: false
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button !== Qt.LeftButton) pane.dragUriList = ""
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[row.modelData[0]]) pane.setCursor(row.index, false, false)
                pane.contextRequested(row.entry, mouse.x + row.x, mouse.y + row.y)
                return
              }
              if (mouse.button === Qt.MiddleButton) { pane.middleOpen(row.entry); return }
              narrowOnRelease = pane.pressItem(row.index, mouse)
              if (mouse.button === Qt.LeftButton) pane.prepareDrag(row.entry)
            }
            onReleased: {
              if (narrowOnRelease && !drag.active) pane.setCursor(row.index, false, false)
              narrowOnRelease = false
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
                  id: rowIcon
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: pane.listIconSize

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: !rowThumb.visible
                    opacity: row.isCut ? 0.3 : 1
                    text: Icons.glyphFor(row.entry)
                    color: row.entry.isBroken ? Color.urgent
                      : (row.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.75))
                    font.family: Style.font.family
                    font.pixelSize: pane.scaled(Style.font.icon)
                  }

                  ThumbImage {
                    id: rowThumb
                    opacity: row.isCut ? 0.3 : 1
                    anchors.fill: parent
                    service: pane.service
                    entry: row.entry
                    direct: pane.previewable(row.entry)
                    generated: pane.thumbable(row.entry)
                    requestSize: pane.listIconSize * 2
                    sourceSize.width: Style.space(36)
                    sourceSize.height: pane.listIconSize * 2
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: row.isCut
                    text: Icons.actionGlyph("cut")
                    color: pane.fg
                    font.family: Style.font.family
                    font.pixelSize: pane.scaled(Style.font.iconSmall)
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(28)
                  text: row.entry.name
                  opacity: row.isCut ? 0.55 : 1
                  color: row.entry.isHidden ? Util.alpha(pane.fg, 0.55) : pane.fg
                  font.family: Style.font.family
                  font.pixelSize: pane.scaled(Style.font.body)
                  font.italic: row.entry.isLink
                  elide: Text.ElideMiddle
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: header.width * 0.14
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              rightPadding: Style.space(10)
              text: row.entry.isDir ? "" : Model.formatSize(row.entry.size)
              color: Util.alpha(pane.fg, 0.7)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(Style.font.bodySmall)
            }

            Text {
              textFormat: Text.PlainText
              width: header.width * 0.16
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.kindLabel(row.entry)
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(Style.font.bodySmall)
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: header.width * 0.18
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.formatDate(row.entry.mtime, Date.now())
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(Style.font.bodySmall)
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
        visible: pane.view !== "list"
        cellWidth: pane.compactView ? Math.round(Style.space(230) * pane.viewScale)
          : Math.round(Style.space(pane.galleryView ? 190 : 110) * pane.viewScale)
        cellHeight: pane.compactView ? pane.rowHeight + Style.space(2)
          : Math.round(Style.space(pane.galleryView ? 196 : 96) * pane.viewScale) + pane.shownCaptions.length * pane.captionLineHeight
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollHandle { objectName: "gridScroll" }

        delegate: Rectangle {
          id: cell
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)
          readonly property bool isCut: pane.isCut(entry)

          width: gridView.cellWidth - (pane.compactView ? Style.space(4) : 0)
          height: gridView.cellHeight
          color: "transparent"

          Rectangle {
            objectName: "cellBackground"
            anchors.fill: parent
            anchors.margins: pane.compactView ? Style.space(1) : Style.space(4)
            radius: Style.cornerRadius
            color: cellDrop.containsDrag
              ? Util.alpha(pane.accent, 0.3)
              : (pane.selection[cell.modelData[0]]
                ? Util.alpha(pane.accent, Style.selectedFillAlpha)
                : (cellHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent"))
            readonly property bool isCursor: pane.cursorIndex === cell.index && pane.active
            readonly property bool isSelected: pane.selection[cell.modelData[0]] === true
            border.width: isCursor || isSelected ? Math.max(1, Style.space(1)) : 0
            border.color: isCursor ? Util.alpha(pane.accent, 0.8) : Util.alpha(pane.accent, 0.35)
          }

          HoverHandler { id: cellHover }

          DropTarget {
            id: cellDrop
            anchors.fill: parent
            target: cell.entry.isDir && !cell.entry.isBroken && !pane.virtualView ? cell.entry.path : ""
            onFilesDropped: function (urls, dest, position) { pane.dropRequested(urls, dest, position) }
          }

          DragProxy {
            id: cellDrag
            view: pane
            active: cellMouse.drag.active
          }

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            drag.target: cellDrag
            drag.threshold: Style.space(8)
            property bool narrowOnRelease: false
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button !== Qt.LeftButton) pane.dragUriList = ""
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[cell.modelData[0]]) pane.setCursor(cell.index, false, false)
                pane.contextRequested(cell.entry, mouse.x + cell.x, mouse.y + cell.y)
                return
              }
              if (mouse.button === Qt.MiddleButton) { pane.middleOpen(cell.entry); return }
              narrowOnRelease = pane.pressItem(cell.index, mouse)
              pane.prepareDrag(cell.entry)
            }
            onReleased: {
              if (narrowOnRelease && !drag.active) pane.setCursor(cell.index, false, false)
              narrowOnRelease = false
            }
            onDoubleClicked: function (mouse) {
              if (mouse.button !== Qt.LeftButton) return
              pane.openEntry(cell.entry)
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            visible: pane.compactView

            Item {
              id: compactIcon
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: pane.listIconSize

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: !compactThumb.visible
                opacity: cell.isCut ? 0.3 : 1
                text: Icons.glyphFor(cell.entry)
                color: cell.entry.isBroken ? Color.urgent
                  : (cell.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.75))
                font.family: Style.font.family
                font.pixelSize: pane.scaled(Style.font.icon)
              }

              ThumbImage {
                id: compactThumb
                opacity: cell.isCut ? 0.3 : 1
                anchors.fill: parent
                active: pane.compactView
                service: pane.service
                entry: cell.entry
                direct: pane.previewable(cell.entry)
                generated: pane.thumbable(cell.entry)
                requestSize: pane.listIconSize * 2
                sourceSize.width: Style.space(36)
                sourceSize.height: pane.listIconSize * 2
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: cell.isCut
                text: Icons.actionGlyph("cut")
                color: pane.fg
                font.family: Style.font.family
                font.pixelSize: pane.scaled(Style.font.iconSmall)
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(26)
              text: cell.entry.name
              opacity: cell.isCut ? 0.55 : 1
              color: cell.entry.isHidden ? Util.alpha(pane.fg, 0.55) : pane.fg
              font.family: Style.font.family
              font.pixelSize: pane.scaled(Style.font.bodySmall)
              font.italic: cell.entry.isLink
              elide: Text.ElideMiddle
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(12)
            spacing: Style.space(6)
            visible: !pane.compactView

            Item {
              id: gridIcon
              anchors.horizontalCenter: parent.horizontalCenter
              width: pane.galleryView ? parent.width : pane.gridIconSize
              height: pane.gridIconSize

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: !thumb.visible
                opacity: cell.isCut ? 0.3 : 1
                text: Icons.glyphFor(cell.entry)
                color: cell.entry.isBroken ? Color.urgent
                  : (cell.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.8))
                font.family: Style.font.family
                font.pixelSize: pane.scaled(pane.galleryView ? Style.font.displayLarge * 2 : Style.font.displayLarge)
              }

              ThumbImage {
                id: thumb
                opacity: cell.isCut ? 0.3 : 1
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                active: !pane.compactView
                service: pane.service
                entry: cell.entry
                direct: pane.previewable(cell.entry)
                generated: pane.thumbable(cell.entry)
                requestSize: pane.gridIconSize * 2
                sourceSize.width: pane.galleryView ? Math.round(Style.space(360) * pane.viewScale) : pane.gridIconSize * 2
                sourceSize.height: pane.gridIconSize * 2
              }

              Rectangle {
                objectName: "cutMark"
                anchors.fill: parent
                visible: cell.isCut
                color: "transparent"
                radius: Style.cornerRadius
                border.width: Math.max(1, Style.space(1))
                border.color: Util.alpha(pane.fg, 0.45)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: Icons.actionGlyph("cut")
                  color: pane.fg
                  font.family: Style.font.family
                  font.pixelSize: Math.round(parent.height * 0.45)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: pane.galleryView ? cell.entry.name : pane.gridLabel(cell.entry.name)
              opacity: cell.isCut ? 0.55 : 1
              color: pane.fg
              font.family: Style.font.family
              font.pixelSize: pane.scaled(Style.font.caption)
              maximumLineCount: pane.galleryView ? 1 : 2
              wrapMode: pane.galleryView ? Text.NoWrap : Text.WrapAnywhere
              elide: pane.galleryView ? Text.ElideMiddle : Text.ElideNone
            }

            Column {
              width: parent.width
              visible: pane.shownCaptions.length > 0
              spacing: 0

              Repeater {
                model: pane.shownCaptions

                delegate: Text {
                  textFormat: Text.PlainText
                  required property var modelData
                  objectName: "caption-" + modelData
                  width: parent.width
                  height: pane.captionLineHeight
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: pane.captionText(cell.entry, modelData)
                  color: Util.alpha(pane.fg, 0.5)
                  font.family: Style.font.family
                  font.pixelSize: pane.captionFontSize
                  elide: Text.ElideMiddle
                }
              }
            }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
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
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: !pane.loading && pane.errorMessage === "" && pane.rows.length === 0
      text: pane.searching ? "No matches"
        : (pane.virtualView ? "Nothing opened recently"
          : (pane.filter ? "Nothing matches" : "Empty folder"))
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: pane.loading && pane.rows.length === 0
      text: pane.searching ? "Searching" : "Reading"
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
