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
  property var hiddenDrives: []
  property var servers: []
  property var session: null

  signal directoryChanged(string path, var names)
  signal conflictRaised(int jobId, var info)

  readonly property int activeTransfers: countActive()
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
    var configured = String(setting("homePath", "") || "").trim()
    if (configured) return Model.normalizePath(Model.expandTilde(configured, home))
    return home || "/"
  }

  property int _nextId: 1
  property var _pending: ({})
  property var _queue: []

  function request(payload, handlers) {
    var id = _nextId++
    var body = {}
    for (var k in payload) body[k] = payload[k]
    body.id = id
    _pending[id] = handlers || ({})
    var line = JSON.stringify(body) + "\n"
    if (helperReady && helper.running) helper.write(line)
    else {
      _queue.push(line)
      ensureHelper()
    }
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
  }

  function handleHelperExit() {
    helperReady = false
    _pending = ({})
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
    if (path) request({ op: "unwatch", path: path }, null)
  }

  function statPaths(paths, onResult) {
    return request({ op: "stat", paths: paths }, {
      onData: function (m) { if (m.t === "stat" && onResult) onResult(m.items) }
    })
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
    return request({ op: "mkdir", path: path }, { onDone: onDone, onError: onError })
  }

  function makeFile(path, onDone, onError) {
    return request({ op: "mkfile", path: path }, { onDone: onDone, onError: onError })
  }

  function renamePath(path, newName, onDone, onError) {
    return request({ op: "rename", path: path, newName: newName }, { onDone: onDone, onError: onError })
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

  function setClipboard(mode, paths) {
    clipboard = { mode: mode, paths: paths.slice() }
  }

  function clearClipboard() {
    clipboard = { mode: "", paths: [] }
  }

  function beginTransfer(op, sources, dest, conflict) {
    var label = sources.length === 1 ? Model.basename(sources[0]) : sources.length + " items"
    var record = {
      id: 0, op: op, label: label, dest: dest, state: "running",
      bytes: 0, total: 0, files: 0, filesTotal: 0, current: "", rate: 0,
      errors: [], startedMs: Date.now()
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
        scheduleTransferSweep()
        refreshTrash()
      },
      onError: function (m) {
        updateTransfer(m.id, { state: m.code === "ECANCELED" ? "cancelled" : "failed", message: String(m.message || "") })
        scheduleTransferSweep()
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
    var next = []
    for (var i = 0; i < transfers.length; i++) {
      var s = transfers[i].state
      if (s === "running" || s === "paused") next.push(transfers[i])
    }
    transfers = next
  }

  function scheduleTransferSweep() {
    sweepTimer.restart()
  }

  function trashPaths(paths, onDone, onError) {
    return request({ op: "trash", paths: paths }, {
      onDone: function (m) { refreshTrash(); if (onDone) onDone(m) },
      onError: onError
    })
  }

  function deletePaths(paths, onDone, onError) {
    return request({ op: "delete", paths: paths }, { onDone: onDone, onError: onError })
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
      }
    })
  }

  function refreshDrives() {
    request({ op: "drives" }, {
      onData: function (m) { if (m.t === "drives") root.drives = m.drives || [] }
    })
  }

  function refreshUserDirs() {
    request({ op: "dirs" }, {
      onData: function (m) { if (m.t === "dirs") root.userDirs = m.dirs || ({}) }
    })
  }

  function updateSetting(key, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var patch = {}
    patch[key] = value
    return shell.updateEntryInline(pluginId, patch)
  }

  function connectToServer(uri, user, domain, password, anonymous, onDone, onError) {
    return request({
      op: "mounturi", uri: uri, user: user || "", domain: domain || "",
      password: password || "", anonymous: anonymous === true
    }, {
      onDone: function (m) {
        root.rememberServer(uri)
        root.refreshDrives()
        if (onDone) onDone(m)
      },
      onError: onError
    })
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

  function rememberServer(uri) {
    var value = String(uri || "").trim()
    if (!value) return
    var next = [value]
    for (var i = 0; i < servers.length && next.length < 10; i++)
      if (servers[i] !== value) next.push(servers[i])
    servers = next
    persist()
  }

  function forgetServer(uri) {
    var next = []
    for (var i = 0; i < servers.length; i++)
      if (String(servers[i]) !== String(uri)) next.push(servers[i])
    servers = next
    persist()
  }

  function openExternally(path) {
    Quickshell.execDetached(["gio", "open", path])
  }

  function openWith(execString, path) {
    var cleaned = String(execString || "").replace(/%[fFuUdDnNickvm]/g, "").trim()
    if (!cleaned) return
    Quickshell.execDetached(["sh", "-c", cleaned + " \"$1\"", "omafile", path])
  }

  function openTerminal(path) {
    var configured = String(setting("terminal", "") || "").trim()
    if (configured) Quickshell.execDetached(["sh", "-c", configured, "omafile"])
    else Quickshell.execDetached(["xdg-terminal-exec"])
  }

  function openEditor(path) {
    var configured = String(setting("editor", "") || "").trim()
    if (configured) Quickshell.execDetached(["sh", "-c", configured + " \"$1\"", "omafile", path])
    else Quickshell.execDetached(["omarchy-launch-editor", path])
  }

  function copyToClipboardText(text) {
    Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "omafile", String(text)])
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

  function togglePinned(path) {
    var next = []
    var found = false
    for (var i = 0; i < pinned.length; i++) {
      if (pinned[i] === path) found = true
      else next.push(pinned[i])
    }
    if (!found) next.push(path)
    pinned = next
    persist()
  }

  function openWindow(path) {
    var payload = path ? JSON.stringify({ path: path }) : "{}"
    if (shell) shell.summon(pluginId, payload)
  }

  function toggleWindow() {
    if (shell) shell.toggle(pluginId, "{}")
  }

  function windowOpen() {
    return shell ? shell.isPluginOpen(pluginId) === true : false
  }

  function saveSoon() {
    saveTimer.restart()
  }

  function persist() {
    var payload = {
      version: 1,
      recent: recent,
      pinned: pinned,
      hiddenDrives: hiddenDrives,
      servers: servers,
      session: session
    }
    stateFile.setText(JSON.stringify(payload, null, 2))
  }

  function loadState(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object") return
    if (parsed.recent) recent = parsed.recent
    if (parsed.pinned) pinned = parsed.pinned
    if (parsed.hiddenDrives) hiddenDrives = parsed.hiddenDrives
    if (parsed.servers) servers = parsed.servers
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

  property Timer sweepTimer: Timer {
    id: sweepTimer
    interval: 6000
    repeat: false
    onTriggered: root.clearFinishedTransfers()
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
      root.openWindow(String(path || ""))
      return "ok"
    }

    function toggle(): string {
      root.toggleWindow()
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
        pending: Object.keys(root._pending),
        trashCount: root.trashCount,
        drives: root.drives.length,
        windowOpen: root.windowOpen()
      })
    }
  }
}
