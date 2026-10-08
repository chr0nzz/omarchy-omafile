import QtQuick
import "../Model.js" as Model

QtObject {
  id: mock
  property var calls: []
  property var files: [["alpha.yml", "f", 30, 300, 420, null], ["beta.png", "f", 10, 100, 420, null], ["docs", "d", 0, 200, 493, null]]
  property var session: null
  property var pinned: []
  property var clipboard: ({ mode: "", paths: [] })
  property var cutPaths: ({})
  property var transfers: []
  readonly property int activeTransfers: transfers.filter(function (t) { return t.state === "running" || t.state === "paused" }).length
  readonly property int finishedTransfers: transfers.length - activeTransfers
  readonly property real transferFraction: 0.5
  readonly property string home: "/home/me"
  function clearFinishedTransfers() {
    record("clearFinishedTransfers", [])
    transfers = transfers.filter(function (t) { return t.state === "running" || t.state === "paused" })
  }
  function clearTransfer(id) { record("clearTransfer", [id]); transfers = transfers.filter(function (t) { return t.id !== id }) }
  function cancelTransfer(id) { record("cancelTransfer", [id]) }
  property string helperError: ""
  property string windowMode: "window"
  property bool trashIcon: false
  property int trashCount: 0
  property bool isDefaultFileManager: false
  property var userDirs: ({})
  property var drives: []
  property var discovered: []
  property var servers: []
  property var hiddenDrives: []
  property var placeOrder: ({})
  property var values: ({})
  property var pickRequest: null
  property var thumbExts: ({ yml: true })
  signal conflictRaised(int jobId, var info)

  function record(name, args) {
    var next = calls.slice()
    next.push({ name: name, args: args })
    calls = next
  }
  function called(name) {
    for (var i = calls.length - 1; i >= 0; i--) if (calls[i].name === name) return calls[i]
    return null
  }
  property var localValues: ({})
  property var folderViews: ({})
  function viewForFolder(path, fallback) { return Model.folderViewFor(folderViews, path, fallback) }
  function rememberFolderView(path, view) { record("rememberFolderView", [path, view]); folderViews = Model.rememberFolderView(folderViews, path, view) }
  function setting(key, fallback) { return values[key] !== undefined ? values[key] : fallback }
  function settingNow(key, fallback) { return localValues[key] !== undefined ? localValues[key] : setting(key, fallback) }
  function updateSetting(key, value) { var v = {}; for (var k in localValues) v[k] = localValues[k]; v[key] = value; localValues = v }
  function startPath() { return "/tmp" }
  function rememberSession(s) { session = s }
  function listDirectory(path, hidden, onChunk, onDone, onError) {
    record("listDirectory", [path])
    Qt.callLater(function () { onChunk(mock.files); onDone({ total: mock.files.length }) })
    return 1
  }
  function listRecent(onChunk, onDone, onError) { Qt.callLater(function () { onDone({ total: 0 }) }); return 2 }
  property var watchCallback: null
  function watchDirectory(path, onChanged) { watchCallback = onChanged; return 3 }
  function unwatch() {}
  function cancel() {}
  function noteRecent() {}
  function trashFilesPath() { return "/tmp/.trash" }
  function driveHidden() { return false }
  function networkMounts() { return drives.filter(function (d) { return d.network === true }) }
  property var statItems: ({})
  property var devices: ({})
  function statPaths(paths, cb) {
    record("statPaths", [paths])
    var items = paths.map(function (p) {
      var item = mock.statItems[p] || { error: "ENOENT" }
      var out = { path: p, dev: mock.devices[p] !== undefined ? mock.devices[p] : 1 }
      for (var k in item) out[k] = item[k]
      return out
    })
    if (cb) cb(items)
  }
  property var identityInfo: ({ uid: 1000, user: "me", groups: ["me", "wheel"], root: false })
  function identity(cb) { record("identity", []); if (cb) cb(identityInfo) }
  function openerFor(path, cb) { record("openerFor", [path]); if (cb) cb({ mime: "text/yaml", handler: "" }) }
  function setOpener(mime, handler, onDone, onError) { record("setOpener", [mime, handler]); if (onDone) onDone({}) }
  function changeMode(path, setBits, clearBits, recursive, onDone, onError) {
    record("changeMode", [path, setBits, clearBits, recursive])
    if (onDone) onDone({})
  }
  function changeOwner(path, owner, group, recursive, onDone, onError) {
    record("changeOwner", [path, owner, group, recursive])
    if (onDone) onDone({})
  }
  function beginTransfer(op, sources, dest, conflict) { record("beginTransfer", [op, sources, dest, conflict]); return 1 }
  function trashPaths(paths, onDone, onError) { record("trashPaths", [paths]); if (onDone) onDone() }
  function deletePaths(paths, onDone, onError) { record("deletePaths", [paths]); if (onDone) onDone({ results: [] }) }
  function restoreFromTrash(names, onDone, onError) {
    record("restoreFromTrash", [names])
    if (onDone) onDone({ results: names.map(function (n) { return { path: n, ok: true } }) })
  }
  function toggleHiddenDrive(key) { record("toggleHiddenDrive", [key]) }
  property var mountResult: ({ path: "/tmp/docs" })
  function mountDrive(device, onDone, onError) {
    record("mountDrive", [device])
    if (mountResult.error) { if (onError) onError({ message: mountResult.error }) }
    else if (onDone) onDone(mountResult)
  }
  function unmountDrive(device, onDone, onError) { record("unmountDrive", [device]); if (onDone) onDone({}) }
  function ejectDrive(device) { record("ejectDrive", [device]) }
  function togglePinned(path) { record("togglePinned", [path]) }
  function placeOrderFor(section) { return placeOrder[section] || [] }
  function hasPlaceOrder(section) { return placeOrderFor(section).length > 0 }
  function setPlaceOrder(section, ids) {
    record("setPlaceOrder", [section, ids])
    var next = {}
    for (var k in placeOrder) next[k] = placeOrder[k]
    next[section] = Model.rememberPlaceOrder(placeOrderFor(section), ids)
    placeOrder = next
  }
  function resetPlaceOrder(section) {
    record("resetPlaceOrder", [section])
    var next = {}
    for (var k in placeOrder) if (k !== section) next[k] = placeOrder[k]
    placeOrder = next
  }
  property var bookmarkLabels: ({})
  function bookmarkLabel(path) { return bookmarkLabels[path] || String(path).split("/").pop() }
  function addBookmarks(paths) { record("addBookmarks", [paths]); pinned = pinned.concat(paths); return paths.length }
  function renameBookmark(path, label) { record("renameBookmark", [path, label]) }
  function forgetServer(uri) { record("forgetServer", [uri]) }
  property var serverSettings: ({})
  property var connectResult: null
  function settingsForServer(uri) { return serverSettings[uri] || { user: "", domain: "", anonymous: false } }
  function isRememberedServer(uri) { return servers.indexOf(uri) >= 0 }
  function connectToServer(uri, user, domain, password, anonymous, onDone, onError) {
    record("connectToServer", [uri, user, domain, password, anonymous])
    if (connectResult && connectResult.error) onError({ message: connectResult.error })
    else onDone({ path: connectResult ? connectResult.path : "" })
    return 0
  }
  function disconnectServer(path, onDone, onError) { record("disconnectServer", [path]) }
  function copyToClipboardText(text) { record("copyToClipboardText", [text]) }
  function emptyTrash(onDone) { record("emptyTrash", []); trashCount = 0; if (onDone) onDone({}) }
  function peekFile(path, limit, onDone, onError) { record("peekFile", [path]); onDone({ text: "key: value\n", binary: false, truncated: false }) }
  function openWith(command, path, inTerminal) { record("openWith", [command, path, inTerminal]) }
  function setDefaultApp(path, desktopId) { record("setDefaultApp", [path, desktopId]) }
  function runCommandOn(text, path) { record("runCommandOn", [text, path]); return true }
  function openExternally(path) { record("openExternally", [path]) }
  property var compressResult: null
  function makeDirectory(path, onDone, onError) { record("makeDirectory", [path]); if (onDone) onDone({}) }
  function compressPaths(paths, name, onDone, onError) {
    record("compressPaths", [paths, name])
    if (compressResult && compressResult.error) { if (onError) onError({ message: compressResult.error, code: compressResult.code }) }
    else if (onDone) onDone({ path: "/tmp/" + name })
  }
  property var extractResults: ({})
  function extractArchive(path, onDone, onError) {
    record("extractArchive", [path])
    var out = extractResults[path]
    if (out && out.error) { if (onError) onError({ message: out.error }) }
    else if (onDone) onDone({ path: out ? out.path : path.replace(/\.zip$/, "") })
  }
  function thumbnailFor(path, mtime, bucket, onReady) { record("thumbnailFor", [path, mtime, bucket]); onReady(""); return null }
  function releaseThumbnail(ticket) {}
  function finishPick(result, request) { record("finishPick", [result, request]); pickRequest = null }
  property var systemClipboard: null
  property bool sameDrive: true
  function readSystemClipboard(onDone) { onDone(systemClipboard) }
  function clearSystemClipboard() { record("clearSystemClipboard", []) }
  function clearClipboard() { record("clearClipboard", []); clipboard = { mode: "", paths: [] }; cutPaths = ({}) }
  function setClipboard(mode, paths) {
    record("setClipboard", [mode, paths])
    clipboard = { mode: mode, paths: paths.slice() }
    var cut = {}
    if (mode === "cut") for (var i = 0; i < paths.length; i++) cut[paths[i]] = true
    cutPaths = cut
  }
  function pasteImage(dest, type, onDone, onError) { record("pasteImage", [dest, type]); onDone(dest + "/Pasted image.png"); return 0 }
  function sameDevice(path, dest, onDone) { onDone(sameDrive) }
  function itemCounts(paths, mtimes, hidden, onResult) {
    record("itemCounts", [paths])
    var out = {}
    for (var i = 0; i < paths.length; i++) out[paths[i]] = 3
    Qt.callLater(function () { onResult(out) })
    return 0
  }
}
