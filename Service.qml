import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "xyzlab.omafile"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/omafile"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string helperPath: String(Qt.resolvedUrl("bin/omafile-helper")).replace(/^file:\/\//, "")

  readonly property var defaults: manifest && manifest.barWidget && manifest.barWidget.defaults ? manifest.barWidget.defaults : ({})
  readonly property var settings: resolveSettings(shell ? shell.barConfig : null)

  property bool helperReady: false
  property string helperError: ""
  property int helperRestarts: 0

  property var transfers: []
  property var clipboard: ({ mode: "", paths: [] })
  property var drives: []
  property var userDirs: ({})
  property int trashCount: 0
  property real trashBytes: 0
  property var recent: []
  property var pinned: []
  property var bookmarkLabels: ({})
  property bool bookmarksMigrated: false
  property bool bookmarksLoaded: false
  property var _legacyPinned: []
  property bool bookmarksDirty: false
  property string bookmarksError: ""
  property bool _bookmarkWritePending: false
  property bool _bookmarkReadPending: false
  property int _bookmarkRevision: 0
  property int _bookmarkGeneration: 0
  property bool _stateLoaded: false
  property int _bookmarkWatchId: 0
  property var hiddenDrives: []
  property var placeOrder: ({})
  property var servers: []
  property var serverSettings: ({})
  property var folderViews: ({})
  property var session: null
  property var pickRequest: null
  property bool filePicker: false
  property bool filePickerBusy: false
  property string filePickerError: ""
  readonly property string portalSetupPath: String(Qt.resolvedUrl("bin/omafile-portal-setup")).replace(/^file:\/\//, "")

  signal directoryChanged(string path, var names)
  signal conflictRaised(int jobId, var info)

  readonly property int activeTransfers: countActive()
  readonly property int finishedTransfers: transfers.length - activeTransfers
  readonly property var runningTransfers: transfers.filter(function (t) { return root.transferActive(t) })
  readonly property var transferIndex: indexTransfers(transfers)
  property var runningTransferIds: []

  onTransfersChanged: {
    var next = []
    for (var i = 0; i < transfers.length; i++) if (transferActive(transfers[i])) next.push(transfers[i].id)
    var same = next.length === runningTransferIds.length
      && next.every(function (id, n) { return id === root.runningTransferIds[n] })
    if (!same) runningTransferIds = next
  }

  function indexTransfers(list) {
    var out = {}
    for (var i = 0; i < list.length; i++) out[list[i].id] = list[i]
    return out
  }

  function transferActive(t) {
    return t.state === "running" || t.state === "paused"
  }
  readonly property real transferFraction: aggregateFraction()

  function countActive() {
    var n = 0
    for (var i = 0; i < transfers.length; i++)
      if (transfers[i].state === "running" || transfers[i].state === "paused") n++
    return n
  }

  function aggregateFraction() {
    var done = 0
    var total = 0
    for (var i = 0; i < transfers.length; i++) {
      var t = transfers[i]
      if (t.state !== "running" && t.state !== "paused") continue
      done += t.bytes
      total += t.total
    }
    if (total <= 0) return 0
    return Math.max(0, Math.min(1, done / total))
  }

  function resolveSettings(config) {
    var merged = {}
    for (var d in defaults) merged[d] = defaults[d]
    var entry = findEntry(config)
    if (entry) for (var k in entry) if (k !== "id") merged[k] = entry[k]
    return merged
  }

  function findEntry(config) {
    if (!config || typeof config !== "object") return null
    var key = Util.canonicalWidgetId(pluginId)
    var bar = config.bar && typeof config.bar === "object" ? config.bar : config
    var layout = bar && bar.layout && typeof bar.layout === "object" ? bar.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var arr = layout[sections[s]]
      if (!arr) continue
      for (var i = 0; i < arr.length; i++) {
        var item = arr[i]
        if (!item || typeof item !== "object") continue
        if (Util.canonicalWidgetId(String(item.id || "")) === key) return item
      }
    }
    return null
  }

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function startPath() {
    var configured = String(settingNow("homePath", "") || "").trim()
    if (configured) return Model.normalizePath(Model.expandTilde(configured, home))
    return home || "/"
  }

  function trashFilesPath() {
    var base = Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")
    return base + "/Trash/files"
  }

  property int _nextId: 1
  property var _pending: ({})
  property var _queue: []

  function request(payload, handlers) {
    var id = _nextId++
    var body = {}
    for (var k in payload) body[k] = payload[k]
    body.id = id
    var entry = handlers || ({})
    entry._op = String(payload.op || "")
    _pending[id] = entry
    var line = JSON.stringify(body) + "\n"
    if (helperReady && helper.running) helper.write(line)
    else {
      _queue.push(line)
      ensureHelper()
    }
    return id
  }

  function sendOneWay(payload) {
    var id = _nextId++
    var body = {}
    for (var k in payload) body[k] = payload[k]
    body.id = id
    sendRaw(body)
    return id
  }

  function sendRaw(payload) {
    var line = JSON.stringify(payload) + "\n"
    if (helperReady && helper.running) helper.write(line)
    else {
      _queue.push(line)
      ensureHelper()
    }
  }

  function cancel(id) {
    if (!id) return
    request({ op: "cancel", target: id }, null)
    releasePending(id)
  }

  function handleHelperExit() {
    helperReady = false
    if (_bookmarkReadPending || _bookmarkWritePending)
      bookmarksError = "Bookmarks could not be synced: file helper stopped. Local bookmarks are saved."
    _bookmarkGeneration++
    _bookmarkReadPending = false
    _bookmarkWritePending = false
    _bookmarkWatchId = 0
    bookmarksLoaded = false
    _queue = _queue.filter(function (line) {
      var op = JSON.parse(line).op
      return op !== "bookmarks" && op !== "setbookmarks"
    })
    _pending = ({})
    _thumbWaiting = ({})
    if (helperRestarts < 8) {
      helperRestarts++
      restartTimer.restart()
    } else {
      helperError = "File helper stopped unexpectedly"
    }
  }

  function ensureHelper() {
    if (helper.running) return
    helper.running = true
  }

  function drainQueue() {
    while (_queue.length > 0) {
      helper.write(_queue.shift())
    }
  }

  function handleLine(line) {
    var text = String(line || "").trim()
    if (!text) return
    var msg = null
    try {
      msg = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!msg || typeof msg !== "object") return
    var id = Number(msg.id)
    var handlers = _pending[id]
    if (!handlers) return
    var type = String(msg.t || "")
    if (type === "error") {
      if (handlers.onError) handlers.onError(msg)
      releasePending(id)
      return
    }
    if (type === "done") {
      if (handlers.onDone) handlers.onDone(msg)
      if (!handlers.keepAlive) releasePending(id)
      return
    }
    if (handlers.onData) handlers.onData(msg)
  }

  function pendingSummary() {
    var counts = {}
    for (var k in _pending) {
      var op = String(_pending[k]._op || "unknown")
      counts[op] = (counts[op] || 0) + 1
    }
    return counts
  }

  function releasePending(id) {
    var next = {}
    for (var k in _pending) if (Number(k) !== Number(id)) next[k] = _pending[k]
    _pending = next
  }

  function listDirectory(path, hidden, onChunk, onDone, onError) {
    return request({ op: "list", path: path, hidden: hidden === true, chunk: 500 }, {
      onData: function (m) { if (m.t === "entries" && onChunk) onChunk(m.c) },
      onDone: function (m) { if (onDone) onDone(m) },
      onError: function (m) { if (onError) onError(m) }
    })
  }

  function watchDirectory(path, onChanged) {
    return request({ op: "watch", path: path }, {
      keepAlive: true,
      onData: function (m) {
        if (m.t !== "changed") return
        if (onChanged) onChanged(m)
        root.directoryChanged(String(m.path || ""), m.names || [])
      }
    })
  }

  function unwatch(watchId, path) {
    if (watchId) releasePending(watchId)
    if (path) sendOneWay({ op: "unwatch", path: path })
  }

  function statPaths(paths, onResult) {
    return request({ op: "stat", paths: paths }, {
      onData: function (m) { if (m.t === "stat" && onResult) onResult(m.items) }
    })
  }

  function identity(onResult) {
    return request({ op: "identity" }, {
      onData: function (m) { if (m.t === "identity" && onResult) onResult(m) }
    })
  }

  function openerFor(path, onResult) {
    return request({ op: "opener", path: path }, {
      onData: function (m) { if (m.t === "opener" && onResult) onResult(m) }
    })
  }

  function setOpener(mime, handler, onDone, onError) {
    return request({ op: "setopener", mime: mime, handler: handler }, { onDone: onDone, onError: onError })
  }

  function changeMode(path, setBits, clearBits, recursive, onDone, onError) {
    return request({ op: "chmod", path: path, set: setBits, clear: clearBits, recursive: !!recursive }, {
      onDone: onDone,
      onError: onError
    })
  }

  function changeOwner(path, owner, group, recursive, onDone, onError) {
    var req = { op: "chown", path: path, recursive: !!recursive }
    if (owner) req.owner = owner
    if (group) req.group = group
    return request(req, { onDone: onDone, onError: onError })
  }

  function peekFile(path, limit, onDone, onError) {
    var result = null
    return request({ op: "peek", path: path, limit: limit }, {
      onData: function (m) { if (m.t === "peek") result = m },
      onDone: function () { if (onDone && result) onDone(result) },
      onError: function (m) { if (onError) onError(m) }
    })
  }

  property var thumbExts: ({})
  property var _thumbCache: ({})
  property var _thumbWaiting: ({})

  property var _countCache: ({})

  function itemCounts(paths, mtimes, hidden, onResult) {
    var ready = {}
    var missing = []
    for (var i = 0; i < paths.length; i++) {
      var key = (hidden ? "h|" : "v|") + mtimes[i] + "|" + paths[i]
      if (_countCache[key] !== undefined) ready[paths[i]] = _countCache[key]
      else missing.push(i)
    }
    if (Object.keys(ready).length > 0) onResult(ready)
    if (missing.length === 0) return 0
    var ask = missing.map(function (i) { return paths[i] })
    return request({ op: "counts", paths: ask, hidden: hidden === true }, {
      onData: function (m) {
        if (m.t !== "counts") return
        var got = m.counts || {}
        for (var j = 0; j < missing.length; j++) {
          var p = paths[missing[j]]
          if (got[p] === undefined) continue
          root._countCache[(hidden ? "h|" : "v|") + mtimes[missing[j]] + "|" + p] = Number(got[p])
        }
        onResult(got)
      }
    })
  }

  function refreshThumbTypes() {
    request({ op: "thumbtypes" }, {
      onData: function (m) {
        if (m.t !== "thumbtypes") return
        var next = {}
        var list = m.exts || []
        for (var i = 0; i < list.length; i++) next[String(list[i])] = true
        root.thumbExts = next
      }
    })
  }

  function thumbnailFor(path, mtime, bucket, onReady) {
    var key = bucket + "|" + mtime + "|" + path
    if (_thumbCache[key] !== undefined) {
      onReady(_thumbCache[key])
      return null
    }
    var ticket = { key: key, onReady: onReady, released: false }
    var waiting = _thumbWaiting[key]
    if (waiting) {
      waiting.tickets.push(ticket)
      return ticket
    }
    waiting = { tickets: [ticket], result: "", id: 0 }
    _thumbWaiting[key] = waiting
    waiting.id = request({ op: "thumb", path: path, size: bucket }, {
      onData: function (m) { if (m.t === "thumb") waiting.result = String(m.thumb || "") },
      onDone: function () { root.finishThumbnail(key, waiting.result, true) },
      onError: function (m) { root.finishThumbnail(key, "", m.code === "EUNSUPPORTED") }
    })
    return ticket
  }

  function finishThumbnail(key, result, remember) {
    var waiting = _thumbWaiting[key]
    if (!waiting) return
    delete _thumbWaiting[key]
    if (remember) _thumbCache[key] = result
    for (var i = 0; i < waiting.tickets.length; i++) {
      var ticket = waiting.tickets[i]
      if (!ticket.released) ticket.onReady(result)
    }
  }

  function releaseThumbnail(ticket) {
    if (!ticket || ticket.released) return
    ticket.released = true
    var waiting = _thumbWaiting[ticket.key]
    if (!waiting) return
    for (var i = 0; i < waiting.tickets.length; i++) if (!waiting.tickets[i].released) return
    delete _thumbWaiting[ticket.key]
    cancel(waiting.id)
  }

  function diskUsage(path, onUpdate, onDone) {
    return request({ op: "du", path: path }, {
      onData: function (m) { if (m.t === "du" && onUpdate) onUpdate(m) },
      onDone: onDone
    })
  }

  function freeSpace(path, onResult) {
    return request({ op: "freespace", path: path }, {
      onData: function (m) { if (m.t === "space" && onResult) onResult(m) }
    })
  }

  function makeDirectory(path, onDone, onError) {
    return request({ op: "mkdir", path: path }, {
      onDone: function (m) {
        root.recordUndo({ kind: "create", path: path, isDir: true, label: "New folder" })
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function makeFile(path, onDone, onError) {
    return request({ op: "mkfile", path: path }, {
      onDone: function (m) {
        root.recordUndo({ kind: "create", path: path, isDir: false, label: "New file" })
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function renamePath(path, newName, onDone, onError) {
    return request({ op: "rename", path: path, newName: newName }, {
      onDone: function (m) {
        root.recordUndo({
          kind: "rename", from: path, to: Model.joinPath(Model.dirname(path), newName),
          label: "Rename to " + newName
        })
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function listRecent(onChunk, onDone, onError) {
    return request({ op: "recent", limit: 200 }, {
      onData: function (m) { if (m.t === "entries" && onChunk) onChunk(m.c) },
      onDone: onDone,
      onError: onError
    })
  }

  function searchFiles(rootPath, query, mode, hidden, onHit, onDone, onError) {
    return request({
      op: "search", root: rootPath, query: query, mode: mode || "substring",
      maxResults: 2000, maxDepth: 12, hidden: hidden === true
    }, {
      onData: function (m) { if (m.t === "hit" && onHit) onHit(m) },
      onDone: onDone,
      onError: onError
    })
  }

  property int _clipboardRevision: 0
  property bool _clipboardWritePending: false
  readonly property var cutPaths: {
    var cut = {}
    if (clipboard && clipboard.mode === "cut")
      for (var i = 0; i < clipboard.paths.length; i++) cut[clipboard.paths[i]] = true
    return cut
  }

  function setClipboard(mode, paths) {
    _clipboardRevision++
    clipboard = { mode: mode, paths: paths.slice() }
    var revision = _clipboardRevision
    _clipboardWritePending = true
    request({ op: "clipset", mode: mode, paths: paths.slice() }, {
      onDone: function () { if (revision === root._clipboardRevision) root._clipboardWritePending = false },
      onError: function () { if (revision === root._clipboardRevision) root._clipboardWritePending = false }
    })
  }

  function readSystemClipboard(onDone) {
    var revision = _clipboardRevision
    return request({ op: "clipget" }, {
      onDone: function (m) {
        var result = { mode: String(m.mode || "copy"), paths: m.paths || [], image: String(m.image || "") }
        if (revision === root._clipboardRevision) root.clipboard = result
        onDone(result)
      },
      onError: function () { onDone(null) }
    })
  }

  function clearSystemClipboard() {
    request({ op: "clipclear" }, null)
  }

  function sameDevice(path, dest, onDone) {
    return request({ op: "samedev", path: path, dest: dest }, {
      onDone: function (m) { onDone(m.same === true) },
      onError: function () { onDone(false) }
    })
  }

  function clearClipboard() {
    _clipboardRevision++
    _clipboardWritePending = false
    clipboard = { mode: "", paths: [] }
  }

  function pasteImage(dest, type, onDone, onError) {
    var result = ""
    return request({ op: "clipimage", dest: dest, type: type }, {
      onData: function (m) { if (m.t === "clipimage") result = String(m.path || "") },
      onDone: function () { if (onDone) onDone(result) },
      onError: function (m) { if (onError) onError(m) }
    })
  }

  property Timer clipboardRefreshTimer: Timer {
    interval: 1000
    repeat: true
    running: !root._clipboardWritePending && root.clipboard && root.clipboard.mode === "cut" && root.clipboard.paths.length > 0
    onTriggered: root.readSystemClipboard(function () {})
  }

  function beginTransfer(op, sources, dest, conflict) {
    var label = sources.length === 1 ? Model.basename(sources[0]) : sources.length + " items"
    var record = {
      id: 0, op: op, label: label, dest: dest, state: "running",
      bytes: 0, total: 0, files: 0, filesTotal: 0, current: "", rate: 0,
      errors: [], startedMs: Date.now(), finishedMs: 0, count: sources.length,
      from: sources.length > 0 ? Model.dirname(sources[0]) : ""
    }
    var id = request({ op: op, sources: sources, dest: dest, conflict: conflict || "ask" }, {
      onData: function (m) {
        if (m.t === "progress") updateTransfer(m.id, {
          bytes: Number(m.bytes) || 0, total: Number(m.total) || 0,
          files: Number(m.files) || 0, filesTotal: Number(m.filesTotal) || 0,
          current: String(m.current || ""), rate: Number(m.rate) || 0
        })
        else if (m.t === "conflict") {
          updateTransfer(m.id, { state: "paused" })
          root.conflictRaised(Number(m.id), m)
        }
      },
      onDone: function (m) {
        updateTransfer(m.id, {
          state: "done", errors: m.errors || [],
          copied: Number(m.copied) || 0, skipped: Number(m.skipped) || 0
        })
        if ((Number(m.copied) || 0) > 0) {
          var created = []
          for (var i = 0; i < sources.length; i++)
            created.push(Model.joinPath(dest, Model.basename(sources[i])))
          root.recordUndo({
            kind: op, sources: sources.slice(), dest: dest, created: created,
            label: (op === "move" ? "Move " : "Copy ") + Model.formatCount(sources.length, "item", "items")
          })
        }
        trimTransferHistory()
        refreshTrash()
      },
      onError: function (m) {
        updateTransfer(m.id, { state: m.code === "ECANCELED" ? "cancelled" : "failed", message: String(m.message || "") })
        trimTransferHistory()
      }
    })
    record.id = id
    var next = transfers.slice()
    next.push(record)
    transfers = next
    return id
  }

  function resolveConflict(jobId, action, applyAll) {
    sendRaw({ id: jobId, op: "resolve", action: action, applyAll: applyAll === true })
    updateTransfer(jobId, { state: action === "cancel" ? "cancelled" : "running" })
  }

  function updateTransfer(id, patch) {
    var next = []
    var touched = false
    for (var i = 0; i < transfers.length; i++) {
      var t = transfers[i]
      if (Number(t.id) === Number(id)) {
        var merged = {}
        for (var k in t) merged[k] = t[k]
        for (var p in patch) merged[p] = patch[p]
        if (!transferActive(merged) && !merged.finishedMs) merged.finishedMs = Date.now()
        next.push(merged)
        touched = true
      } else next.push(t)
    }
    if (!touched) return
    transfers = next
  }

  function cancelTransfer(id) {
    cancel(id)
    updateTransfer(id, { state: "cancelled" })
  }

  function clearFinishedTransfers() {
    transfers = transfers.filter(function (t) { return root.transferActive(t) })
  }

  function clearTransfer(id) {
    transfers = transfers.filter(function (t) { return Number(t.id) !== Number(id) || root.transferActive(t) })
  }

  function markTransfersSeen() {
    var changed = false
    var next = transfers.map(function (t) {
      if (root.transferActive(t) || t.seen) return t
      changed = true
      var copy = {}
      for (var k in t) copy[k] = t[k]
      copy.seen = true
      return copy
    })
    if (changed) transfers = next
  }

  function trimTransferHistory() {
    seenTimer.restart()
    var finished = 0
    for (var i = transfers.length - 1; i >= 0; i--) if (!transferActive(transfers[i])) finished++
    if (finished <= 50) return
    var drop = finished - 50
    transfers = transfers.filter(function (t) {
      if (drop > 0 && !root.transferActive(t)) {
        drop--
        return false
      }
      return true
    })
  }

  function recordUndo(entry) {
    var next = undoStack.slice()
    next.push(entry)
    if (next.length > 40) next.shift()
    undoStack = next
    redoStack = []
  }

  function popUndo() {
    if (undoStack.length === 0) return null
    var next = undoStack.slice()
    var entry = next.pop()
    undoStack = next
    return entry
  }

  function pushRedo(entry) {
    var next = redoStack.slice()
    next.push(entry)
    redoStack = next
  }

  function popRedo() {
    if (redoStack.length === 0) return null
    var next = redoStack.slice()
    var entry = next.pop()
    redoStack = next
    return entry
  }

  function undo(onDone, onError) {
    var entry = popUndo()
    if (!entry) {
      if (onError) onError({ message: "Nothing to undo" })
      return
    }
    applyReverse(entry, function () {
      root.pushRedo(entry)
      if (onDone) onDone(entry)
    }, onError)
  }

  function redo(onDone, onError) {
    var entry = popRedo()
    if (!entry) {
      if (onError) onError({ message: "Nothing to redo" })
      return
    }
    applyForward(entry, function () {
      var next = undoStack.slice()
      next.push(entry)
      undoStack = next
      if (onDone) onDone(entry)
    }, onError)
  }

  function applyReverse(entry, onDone, onError) {
    if (entry.kind === "trash")
      request({ op: "restore", items: entry.trashinfo }, { onDone: function (m) { refreshTrash(); onDone(m) }, onError: onError })
    else if (entry.kind === "rename")
      request({ op: "rename", path: entry.to, newName: Model.basename(entry.from) }, { onDone: onDone, onError: onError })
    else if (entry.kind === "move")
      request({ op: "move", sources: entry.created, dest: Model.dirname(entry.sources[0]), conflict: "rename" }, { onDone: onDone, onError: onError })
    else if (entry.kind === "copy")
      request({ op: "trash", paths: entry.created }, { onDone: function (m) { refreshTrash(); onDone(m) }, onError: onError })
    else if (entry.kind === "create")
      request({ op: "trash", paths: [entry.path] }, { onDone: function (m) { refreshTrash(); onDone(m) }, onError: onError })
    else if (onError) onError({ message: "Cannot undo that" })
  }

  function applyForward(entry, onDone, onError) {
    if (entry.kind === "trash")
      request({ op: "trash", paths: entry.paths }, { onDone: function (m) { refreshTrash(); onDone(m) }, onError: onError })
    else if (entry.kind === "rename")
      request({ op: "rename", path: entry.from, newName: Model.basename(entry.to) }, { onDone: onDone, onError: onError })
    else if (entry.kind === "move")
      request({ op: "move", sources: entry.sources, dest: entry.dest, conflict: "rename" }, { onDone: onDone, onError: onError })
    else if (entry.kind === "copy")
      request({ op: "copy", sources: entry.sources, dest: entry.dest, conflict: "rename" }, { onDone: onDone, onError: onError })
    else if (entry.kind === "create")
      request({ op: entry.isDir ? "mkdir" : "mkfile", path: entry.path }, { onDone: onDone, onError: onError })
    else if (onError) onError({ message: "Cannot redo that" })
  }

  function trashPaths(paths, onDone, onError) {
    return request({ op: "trash", paths: paths }, {
      onDone: function (m) {
        var names = []
        var results = m.results || []
        for (var i = 0; i < results.length; i++)
          if (results[i].ok && results[i].trashinfo) names.push(results[i].trashinfo)
        if (names.length > 0)
          root.recordUndo({
            kind: "trash", paths: paths.slice(), trashinfo: names,
            label: Model.formatCount(names.length, "item moved to trash", "items moved to trash")
          })
        refreshTrash()
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function deletePaths(paths, onDone, onError) {
    return request({ op: "delete", paths: paths }, {
      onDone: function (m) { refreshTrash(); if (onDone) onDone(m) },
      onError: onError
    })
  }

  function restoreFromTrash(names, onDone, onError) {
    return request({ op: "restore", items: names }, {
      onDone: function (m) { refreshTrash(); if (onDone) onDone(m) },
      onError: onError
    })
  }

  function emptyTrash(onDone) {
    return request({ op: "emptytrash" }, {
      onDone: function (m) { refreshTrash(); if (onDone) onDone(m) }
    })
  }

  function refreshTrash() {
    request({ op: "trashinfo" }, {
      onData: function (m) {
        if (m.t !== "trash") return
        root.trashCount = Number(m.count) || 0
        root.trashBytes = Number(m.bytes) || 0
        root.syncTrashWatches(m.infoDirs || [])
      }
    })
  }

  property var _trashWatches: ({})

  function syncTrashWatches(dirs) {
    var wanted = ({})
    for (var i = 0; i < dirs.length; i++) {
      var dir = String(dirs[i] || "")
      if (!dir) continue
      wanted[dir] = true
      if (_trashWatches[dir]) continue
      _trashWatches[dir] = watchDirectory(dir, function () { trashSettle.restart() })
    }
    for (var held in _trashWatches) {
      if (wanted[held]) continue
      unwatch(_trashWatches[held], held)
      delete _trashWatches[held]
    }
  }

  Timer {
    id: trashSettle
    interval: 250
    repeat: false
    onTriggered: root.refreshTrash()
  }

  function refreshDrives() {
    request({ op: "drives" }, {
      onData: function (m) {
        if (m.t !== "drives") return
        var next = m.drives || []
        if (JSON.stringify(next) !== JSON.stringify(root.drives)) root.drives = next
      }
    })
  }

  function refreshUserDirs() {
    request({ op: "dirs" }, {
      onData: function (m) { if (m.t === "dirs") root.userDirs = m.dirs || ({}) }
    })
  }

  property var localSettings: ({})
  property var undoStack: []
  property var redoStack: []

  readonly property bool canUndo: undoStack.length > 0
  readonly property bool canRedo: redoStack.length > 0
  readonly property string undoLabel: canUndo ? String(undoStack[undoStack.length - 1].label || "") : ""
  readonly property string redoLabel: canRedo ? String(redoStack[redoStack.length - 1].label || "") : ""

  readonly property string windowMode: String(settingNow("windowMode", "window"))

  function settingNow(name, fallback) {
    if (localSettings[name] !== undefined) return localSettings[name]
    return setting(name, fallback)
  }

  function updateSetting(key, value) {
    var next = {}
    for (var k in localSettings) next[k] = localSettings[k]
    next[key] = value
    localSettings = next
    var patch = {}
    patch[key] = value
    request({ op: "barsettings", settings: patch }, null)
    return true
  }

  property bool trashIcon: false

  function refreshTrashIcon() {
    request({ op: "baricon", action: "status" }, {
      onData: function (m) {
        if (m.t !== "baricon") return
        root.trashIcon = m.trashIcon === true
      }
    })
  }

  function setTrashIcon(enabled, onDone, onError) {
    request({ op: "baricon", action: enabled ? "add" : "remove" }, {
      onData: function (m) {
        if (m.t !== "baricon") return
        root.trashIcon = m.trashIcon === true
      },
      onDone: function (m) { if (onDone) onDone(m) },
      onError: function (m) { if (onError) onError(m) }
    })
  }

  function connectToServer(uri, user, domain, password, anonymous, onDone, onError) {
    return request({
      op: "mounturi", uri: uri, user: user || "", domain: domain || "",
      password: password || "", anonymous: anonymous === true
    }, {
      onDone: function (m) {
        root.rememberServer(uri, { user: String(user || ""), domain: String(domain || ""), anonymous: anonymous === true })
        root.refreshDrives()
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function settingsForServer(uri) {
    var saved = serverSettings[String(uri || "")]
    return saved ? saved : ({ user: "", domain: "", anonymous: false })
  }

  function isRememberedServer(uri) {
    return servers.indexOf(String(uri || "")) >= 0
  }

  function disconnectServer(path, onDone, onError) {
    return request({ op: "unmounturi", path: path }, {
      onDone: function (m) {
        root.refreshDrives()
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  property var discovered: []
  property bool isDefaultFileManager: false
  property string previousFileManager: ""

  function refreshDefaultHandler() {
    request({ op: "defaultfm" }, {
      onDone: function (m) {
        root.isDefaultFileManager = m.isOmafile === true
      }
    })
  }

  function setDefaultFileManager(enabled, onDone, onError) {
    return request({
      op: "setdefaultfm", enabled: enabled === true, previous: previousFileManager
    }, {
      onDone: function (m) {
        root.isDefaultFileManager = m.isOmafile === true
        if (m.previous !== undefined) {
          root.previousFileManager = String(m.previous || "")
          root.persist()
        }
        if (onDone) onDone(m)
      },
      onError: onError
    })
  }

  function refreshDiscovered() {
    request({ op: "netdiscover" }, {
      onData: function (m) { if (m.t === "drives") root.discovered = m.drives || [] }
    })
  }

  function networkMounts() {
    var out = []
    for (var i = 0; i < drives.length; i++)
      if (drives[i] && drives[i].network === true) out.push(drives[i])
    return out
  }

  function rememberServer(uri, settings) {
    var value = String(uri || "").trim()
    if (!value) return
    var next = [value]
    for (var i = 0; i < servers.length && next.length < 10; i++)
      if (servers[i] !== value) next.push(servers[i])
    servers = next
    var saved = {}
    for (var k in serverSettings) if (next.indexOf(k) >= 0) saved[k] = serverSettings[k]
    if (settings) saved[value] = settings
    serverSettings = saved
    persist()
  }

  function forgetServer(uri) {
    var next = []
    for (var i = 0; i < servers.length; i++)
      if (String(servers[i]) !== String(uri)) next.push(servers[i])
    servers = next
    var saved = {}
    for (var k in serverSettings) if (k !== String(uri)) saved[k] = serverSettings[k]
    serverSettings = saved
    persist()
  }

  function compressPaths(paths, name, onDone, onError) {
    var folder = Model.dirname(paths[0])
    var record = {
      id: 0, op: "compress", label: name, dest: folder, state: "running",
      bytes: 0, total: 0, files: 0, filesTotal: 0, current: "", rate: 0,
      errors: [], startedMs: Date.now(), finishedMs: 0, count: paths.length, from: folder
    }
    var id = request({ op: "compress", paths: paths, name: name }, {
      onData: function (m) {
        if (m.t === "progress") updateTransfer(m.id, {
          bytes: Number(m.bytes) || 0, total: Number(m.total) || 0,
          files: Number(m.files) || 0, current: String(m.current || ""), rate: Number(m.rate) || 0
        })
      },
      onDone: function (m) {
        updateTransfer(m.id, { state: "done", result: String(m.path || "") })
        trimTransferHistory()
        if (onDone) onDone(m)
      },
      onError: function (m) {
        updateTransfer(m.id, { state: m.code === "ECANCELED" ? "cancelled" : "failed", message: String(m.message || "") })
        trimTransferHistory()
        if (onError) onError(m)
      }
    })
    record.id = id
    var next = transfers.slice()
    next.push(record)
    transfers = next
    return id
  }

  function extractArchive(path, onDone, onError) {
    var folder = Model.dirname(path)
    var record = {
      id: 0, op: "extract", label: Model.basename(path), dest: folder, state: "running",
      bytes: 0, total: 0, files: 0, filesTotal: 0, current: "", rate: 0,
      errors: [], startedMs: Date.now(), finishedMs: 0, count: 1, from: folder
    }
    var id = request({ op: "extract", path: path }, {
      onData: function (m) {
        if (m.t === "progress") updateTransfer(m.id, {
          bytes: Number(m.bytes) || 0, total: Number(m.total) || 0,
          files: Number(m.files) || 0, current: String(m.current || ""), rate: Number(m.rate) || 0
        })
      },
      onDone: function (m) {
        updateTransfer(m.id, { state: "done", result: String(m.path || "") })
        trimTransferHistory()
        if (onDone) onDone(m)
      },
      onError: function (m) {
        updateTransfer(m.id, { state: m.code === "ECANCELED" ? "cancelled" : "failed", message: String(m.message || "") })
        trimTransferHistory()
        if (onError) onError(m)
      }
    })
    record.id = id
    var next = transfers.slice()
    next.push(record)
    transfers = next
    return id
  }

  function openExternally(path) {
    Quickshell.execDetached(["gio", "open", path])
  }

  function openWith(command, path, inTerminal) {
    var argv = Model.expandFieldCodes(command, path)
    if (argv.length === 0) return
    if (inTerminal) argv = ["xdg-terminal-exec"].concat(argv)
    Quickshell.execDetached(argv)
  }

  function setDefaultApp(path, desktopId, onDone, onError) {
    var id = desktopId.slice(-8) === ".desktop" ? desktopId : desktopId + ".desktop"
    return openerFor(path, function (m) {
      if (!m.mime) {
        if (onError) onError({ message: "unknown file type" })
        return
      }
      root.setOpener(String(m.mime), id, onDone, onError)
    })
  }

  function runCommandOn(text, path) {
    var argv = Model.tokenizeCommand(text)
    if (argv.length === 0) return false
    argv.push(String(path))
    Quickshell.execDetached(argv)
    return true
  }

  function openTerminal(path) {
    var configured = String(settingNow("terminal", "") || "").trim()
    if (configured) Quickshell.execDetached(["sh", "-c", "cd \"$1\" && " + configured, "omafile", path])
    else Quickshell.execDetached(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path])
  }

  function openClaude(path) {
    Quickshell.execDetached(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path,
      "bash", "-c", "claude; exec bash"])
  }

  function openEditor(path) {
    var configured = String(settingNow("editor", "") || "").trim()
    if (configured) Quickshell.execDetached(["sh", "-c", configured + " \"$1\"", "omafile", path])
    else Quickshell.execDetached(["omarchy-launch-editor", path])
  }

  function copyToClipboardText(text) {
    Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "omafile", String(text)])
  }

  function mountDrive(devicePath, onDone, onError) {
    return request({ op: "mountdev", device: String(devicePath) }, {
      onDone: function (m) {
        root.refreshDrives()
        if (onDone) onDone(m)
      },
      onError: function (m) {
        root.refreshDrives()
        if (onError) onError(m)
      }
    })
  }

  function unmountDrive(devicePath, onDone, onError) {
    return request({ op: "unmountdev", device: String(devicePath) }, {
      onDone: function (m) {
        root.refreshDrives()
        if (onDone) onDone(m)
      },
      onError: function (m) {
        root.refreshDrives()
        if (onError) onError(m)
      }
    })
  }

  function ejectDrive(devicePath) {
    Quickshell.execDetached(["sh", "-c",
      "udisksctl unmount -b \"$1\" && udisksctl power-off -b \"$1\"", "omafile", String(devicePath)])
  }

  function noteRecent(path) {
    var next = [path]
    for (var i = 0; i < recent.length && next.length < 12; i++)
      if (recent[i] !== path) next.push(recent[i])
    recent = next
    saveSoon()
  }

  function driveHidden(key) {
    var id = String(key || "")
    for (var i = 0; i < hiddenDrives.length; i++)
      if (String(hiddenDrives[i]) === id) return true
    return false
  }

  function toggleHiddenDrive(key) {
    var id = String(key || "")
    if (!id) return
    var next = []
    var found = false
    for (var i = 0; i < hiddenDrives.length; i++) {
      if (String(hiddenDrives[i]) === id) found = true
      else next.push(hiddenDrives[i])
    }
    if (!found) next.push(id)
    hiddenDrives = next
    persist()
  }

  function showAllDrives() {
    hiddenDrives = []
    persist()
  }

  function placeOrderFor(section) {
    var saved = placeOrder[String(section || "")]
    return saved ? saved : []
  }

  function hasPlaceOrder(section) {
    return placeOrderFor(section).length > 0
  }

  function setPlaceOrder(section, ids) {
    var key = String(section || "")
    if (!key) return
    var next = {}
    for (var k in placeOrder) next[k] = placeOrder[k]
    next[key] = Model.rememberPlaceOrder(placeOrderFor(key), ids)
    placeOrder = next
    persist()
  }

  function resetPlaceOrder(section) {
    var key = String(section || "")
    if (!hasPlaceOrder(key)) return
    var next = {}
    for (var k in placeOrder) if (k !== key) next[k] = placeOrder[k]
    placeOrder = next
    persist()
  }

  function togglePinned(path) {
    var next = []
    var found = false
    for (var i = 0; i < pinned.length; i++) {
      if (pinned[i] === path) found = true
      else next.push(pinned[i])
    }
    if (!found) next.push(path)
    pinned = next
    writeBookmarks()
  }

  function addBookmarks(paths) {
    var next = pinned.slice()
    var added = 0
    for (var i = 0; i < paths.length; i++) {
      if (next.indexOf(paths[i]) >= 0) continue
      next.push(paths[i])
      added++
    }
    if (added === 0) return 0
    pinned = next
    writeBookmarks()
    return added
  }

  function bookmarkLabel(path) {
    var label = bookmarkLabels[path]
    return label ? String(label) : (Model.basename(String(path)) || "/")
  }

  function renameBookmark(path, label) {
    var next = {}
    for (var k in bookmarkLabels) next[k] = bookmarkLabels[k]
    var clean = String(label || "").trim()
    if (clean === "" || clean === Model.basename(String(path))) delete next[path]
    else next[path] = clean
    bookmarkLabels = next
    writeBookmarks()
  }

  function writeBookmarks() {
    bookmarksDirty = true
    _bookmarkRevision++
    persist()
    if (!bookmarksLoaded) refreshBookmarks()
    else flushBookmarks()
  }

  function flushBookmarks() {
    if (_bookmarkWritePending || !bookmarksLoaded || !bookmarksDirty) return
    var items = []
    for (var i = 0; i < pinned.length; i++)
      items.push({ path: pinned[i], label: bookmarkLabels[pinned[i]] || "" })
    var revision = _bookmarkRevision
    var generation = _bookmarkGeneration
    _bookmarkWritePending = true
    request({ op: "setbookmarks", items: items }, {
      onDone: function () {
        if (generation !== root._bookmarkGeneration) return
        root._bookmarkWritePending = false
        if (revision !== root._bookmarkRevision) {
          root.flushBookmarks()
          return
        }
        root.bookmarksDirty = false
        root.bookmarksMigrated = true
        root._legacyPinned = []
        root.bookmarksError = ""
        root.persist()
      },
      onError: function (m) {
        if (generation !== root._bookmarkGeneration) return
        root._bookmarkWritePending = false
        root.bookmarksError = "Bookmarks could not be saved: " + String(m.message || m.code || "unknown error")
        root.persist()
      }
    })
  }

  function refreshBookmarks() {
    if (!_stateLoaded || _bookmarkReadPending || _bookmarkWritePending) return
    if (bookmarksLoaded && bookmarksDirty) {
      flushBookmarks()
      return
    }
    var generation = _bookmarkGeneration
    var revision = _bookmarkRevision
    var snapshot = null
    _bookmarkReadPending = true
    request({ op: "bookmarks" }, {
      onData: function (m) {
        if (m.t === "bookmarks") snapshot = m
      },
      onError: function (m) {
        if (generation !== root._bookmarkGeneration) return
        root._bookmarkReadPending = false
        root.bookmarksError = "Bookmarks could not be read: " + String(m.message || m.code || "unknown error")
      },
      onDone: function () {
        if (generation !== root._bookmarkGeneration) return
        root._bookmarkReadPending = false
        if (revision !== root._bookmarkRevision) {
          root.refreshBookmarks()
          return
        }
        if (!snapshot) {
          root.bookmarksError = "Bookmarks could not be read: missing response"
          return
        }
        var paths = []
        var labels = {}
        var list = snapshot.items || []
        for (var i = 0; i < list.length; i++) {
          var path = String(list[i].path || "")
          if (!path || paths.indexOf(path) >= 0) continue
          paths.push(path)
          if (list[i].label) labels[path] = String(list[i].label)
        }
        if (root.bookmarksDirty && root.bookmarksMigrated) {
          paths = root.pinned.slice()
          labels = root.bookmarkLabels
        } else if (!root.bookmarksMigrated) {
          for (var j = 0; j < root.pinned.length; j++) {
            var local = root.pinned[j]
            if (paths.indexOf(local) < 0) paths.push(local)
            if (root.bookmarkLabels[local]) labels[local] = root.bookmarkLabels[local]
          }
        }
        root.bookmarksLoaded = true
        root.pinned = paths
        root.bookmarkLabels = labels
        root.bookmarksError = ""
        if (!root.bookmarksMigrated || root.bookmarksDirty) {
          root.bookmarksDirty = true
          root.persist()
          root.flushBookmarks()
        } else root.persist()
        if (!root._bookmarkWatchId && snapshot.dir) {
          root._bookmarkWatchId = root.watchDirectory(String(snapshot.dir), function (change) {
            var names = change.names || []
            if (names.length === 0 || names.indexOf("bookmarks") >= 0) bookmarkReloadTimer.restart()
          })
        }
      }
    })
  }

  property Timer bookmarkReloadTimer: Timer {
    interval: 250
    onTriggered: root.refreshBookmarks()
  }

  function openWindow(path) {
    var payload = path ? JSON.stringify({ path: path }) : "{}"
    if (shell) shell.summon(pluginId, payload)
  }

  function newWindow() {
    if (shell) shell.summon(pluginId, JSON.stringify({ newWindow: true }))
  }

  function toggleWindow() {
    if (shell) shell.toggle(pluginId, "{}")
  }

  function beginPick(requestJson) {
    var parsed = null
    try {
      parsed = JSON.parse(String(requestJson || ""))
    } catch (e) {
      return "invalid request"
    }
    if (!parsed || typeof parsed.result !== "string" || parsed.result === "") return "result path required"
    if (pickRequest) writePickResult(pickRequest.result, { ok: false })
    pickRequest = parsed
    return "ok"
  }

  function finishPick(result, request) {
    var current = pickRequest
    if (!current) return
    if (request && String(request.result) !== String(current.result)) return
    pickRequest = null
    writePickResult(current.result, result || { ok: false })
  }

  function cancelPick(resultPath) {
    if (!pickRequest) return
    if (resultPath && String(resultPath) !== String(pickRequest.result)) return
    pickRequest = null
  }

  function refreshFilePicker() {
    if (!portalStatus.running) portalStatus.running = true
  }

  function setFilePicker(enabled) {
    if (filePickerBusy) return
    filePickerBusy = true
    filePickerError = ""
    portalToggle.command = [portalSetupPath, enabled ? "enable" : "disable"]
    portalToggle.running = true
  }

  function writePickResult(file, result) {
    Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"",
      "omafile", JSON.stringify(result), String(file)])
  }

  function windowOpen() {
    return shell ? shell.isPluginOpen(pluginId) === true : false
  }

  function saveSoon() {
    saveTimer.restart()
  }

  function viewForFolder(path, fallback) {
    return Model.folderViewFor(folderViews, path, fallback)
  }

  function rememberFolderView(path, view) {
    folderViews = Model.rememberFolderView(folderViews, path, view)
    saveSoon()
  }

  function persist() {
    var payload = {
      version: 1,
      recent: recent,
      bookmarksMigrated: bookmarksMigrated,
      pinned: pinned,
      bookmarkLabels: bookmarkLabels,
      bookmarksDirty: bookmarksDirty,
      hiddenDrives: hiddenDrives,
      placeOrder: placeOrder,
      servers: servers,
      serverSettings: serverSettings,
      folderViews: folderViews,
      previousFileManager: previousFileManager,
      session: session
    }
    stateFile.setText(JSON.stringify(payload, null, 2))
  }

  function loadState(raw) {
    applyState(raw)
    _stateLoaded = true
    refreshBookmarks()
  }

  function applyState(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object") return
    if (parsed.recent) recent = parsed.recent
    if (parsed.pinned && !bookmarksLoaded) {
      pinned = parsed.pinned
      _legacyPinned = parsed.pinned.slice()
    }
    if (!bookmarksLoaded) {
      bookmarksMigrated = parsed.bookmarksMigrated === true
      bookmarksDirty = parsed.bookmarksDirty === true
      if (parsed.bookmarkLabels) bookmarkLabels = parsed.bookmarkLabels
    }
    if (parsed.hiddenDrives) hiddenDrives = parsed.hiddenDrives
    if (parsed.placeOrder && typeof parsed.placeOrder === "object") placeOrder = Model.cleanPlaceOrder(parsed.placeOrder)
    if (parsed.servers) servers = parsed.servers
    if (parsed.serverSettings && typeof parsed.serverSettings === "object") serverSettings = parsed.serverSettings
    if (parsed.folderViews && typeof parsed.folderViews === "object") folderViews = parsed.folderViews
    if (parsed.previousFileManager) previousFileManager = String(parsed.previousFileManager)
    if (parsed.session) session = parsed.session
  }

  function rememberSession(value) {
    session = value
    saveSoon()
  }

  Component.onCompleted: {
    ensureHelper()
    Qt.callLater(function () {
      refreshUserDirs()
      refreshDrives()
      refreshTrash()
      refreshTrashIcon()
      refreshDiscovered()
      refreshDefaultHandler()
      refreshFilePicker()
      refreshThumbTypes()
    })
  }

  property Process helper: Process {
    id: helper
    command: [root.helperPath]
    running: false
    stdinEnabled: true

    onRunningChanged: {
      if (running) {
        root.helperReady = true
        root.helperError = ""
        Qt.callLater(root.drainQueue)
        Qt.callLater(root.refreshBookmarks)
      } else {
        root.helperReady = false
      }
    }

    onExited: root.handleHelperExit()

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) { root.handleLine(line) }
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var text = String(line || "").trim()
        if (text) root.helperError = text
      }
    }
  }

  property bool claudeAvailable: false

  property Process claudeCheck: Process {
    command: ["sh", "-c", "command -v claude"]
    running: true
    onExited: function (code) { root.claudeAvailable = code === 0 }
  }

  property Process portalStatus: Process {
    id: portalStatus
    command: [root.portalSetupPath, "status"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.filePicker = parsed.enabled === true && parsed.systemFile === true
        } catch (e) {
          root.filePicker = false
        }
      }
    }
  }

  property Process portalToggle: Process {
    id: portalToggle
    running: false
    stderr: StdioCollector { id: portalToggleErr }
    onExited: function (code) {
      root.filePickerBusy = false
      if (code !== 0) {
        var lines = String(portalToggleErr.text || "").trim().split("\n")
        root.filePickerError = lines[lines.length - 1] || "Could not change the file picker"
      }
      root.refreshFilePicker()
    }
  }

  property Timer restartTimer: Timer {
    id: restartTimer
    interval: 400 * Math.max(1, root.helperRestarts)
    repeat: false
    onTriggered: root.ensureHelper()
  }

  property Timer saveTimer: Timer {
    id: saveTimer
    interval: 900
    repeat: false
    onTriggered: root.persist()
  }

  property Timer seenTimer: Timer {
    id: seenTimer
    interval: 6000
    repeat: false
    onTriggered: root.markTransfersSeen()
  }

  property Timer drivesTimer: Timer {
    id: drivesTimer
    interval: 15000
    repeat: true
    running: true
    onTriggered: root.refreshDrives()
  }

  property FileView stateFile: FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
  }

  property IpcHandler ipc: IpcHandler {
    target: "omafile"

    function open(path: string): string {
      root.openWindow(String(path || ""))
      return "ok"
    }

    function reveal(path: string): string {
      var target = String(path || "")
      if (!target) return "path required"
      var parent = Model.dirname(target)
      var name = Model.basename(target)
      if (root.shell)
        root.shell.summon(root.pluginId, JSON.stringify({ path: parent, select: name }))
      return "ok"
    }

    function toggle(): string {
      root.toggleWindow()
      return "ok"
    }

    function newwindow(): string {
      root.newWindow()
      return "ok"
    }

    function windowmode(mode: string): string {
      var value = String(mode || "").toLowerCase()
      if (value !== "window" && value !== "popup") return "use window or popup"
      root.updateSetting("windowMode", value)
      return "ok"
    }

    function trashicon(state: string): string {
      var value = String(state || "").toLowerCase()
      if (value === "on" || value === "add" || value === "true") { root.setTrashIcon(true, null, null); return "ok" }
      if (value === "off" || value === "remove" || value === "false") { root.setTrashIcon(false, null, null); return "ok" }
      if (value === "" || value === "status") return root.trashIcon ? "on" : "off"
      return "use on, off or status"
    }

    function pick(request: string): string {
      return root.beginPick(request)
    }

    function pickcancel(result: string): string {
      root.cancelPick(result)
      return "ok"
    }

    function shortcuts(): string {
      if (root.shell) root.shell.summon(root.pluginId, JSON.stringify({ dialog: "shortcuts" }))
      return "ok"
    }

    function trash(path: string): string {
      if (!path) return "path required"
      root.trashPaths([String(path)], null, null)
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        helper: root.helperReady,
        helperError: root.helperError,
        transfers: root.transfers.map(function (t) {
          return { id: t.id, op: t.op, label: t.label, state: t.state, bytes: t.bytes, total: t.total }
        }),
        active: root.activeTransfers,
        pending: root.pendingSummary(),
        trashCount: root.trashCount,
        drives: root.drives.length,
        windowOpen: root.windowOpen()
      })
    }
  }
}
