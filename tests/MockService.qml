import QtQuick 6.11
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
  property var duResult: ({ bytes: 4096, files: 1, dirs: 0 })

  function diskUsage(path, onUpdate, onDone) {
    record("du", [path])
    if (onUpdate) onUpdate(duResult)
    if (onDone) onDone({})
    return 0
  }

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
  function cancel(id) { record("cancel", [id]) }
  property var textFiles: ({})
  property var writeResult: null
  function readText(path, onDone, onError) {
    record("readText", [path])
    var file = textFiles[path]
    Qt.callLater(function () {
      if (!file) { if (onError) onError({ code: "EBINARY", message: "this is not a text file" }); return }
      onDone({ t: "text", text: file.text, path: path, crlf: file.crlf === true, bom: file.bom === true,
        writable: file.writable !== false, ino: "1", dev: "2", mtimeNs: "3", size: file.text.length })
    })
    return 0
  }
  function writeText(path, text, expect, force, crlf, bom, onDone, onError) {
    record("writeText", [path, text, expect, force, crlf, bom])
    Qt.callLater(function () {
      if (mock.writeResult && mock.writeResult.code && !force) { if (onError) onError(mock.writeResult); return }
      if (onDone) onDone({ path: path, ino: "1", dev: "2", mtimeNs: "9", size: text.length })
    })
    return 0
  }
  property var duplicateResult: null
  function findDuplicates(root, path, hidden, onProgress, onDone, onError) {
    record("findDuplicates", [root, path, hidden])
    if (duplicateResult && duplicateResult.pending) return 77
    Qt.callLater(function () {
      onProgress({ phase: "looking", files: 10, current: root, done: 0, total: 0 })
      if (mock.duplicateResult && mock.duplicateResult.error) onError(mock.duplicateResult.error)
      else onDone(mock.duplicateResult || { groups: [], scanned: 10 })
    })
    return 77
  }
  function noteRecent() {}
  function trashFilesPath() { return "/tmp/.trash" }
  property string gvfsRoot: ""
  function isGvfsPath(p) { return gvfsRoot !== "" && String(p).indexOf(gvfsRoot + "/") === 0 }
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
  property var identityInfo: ({ uid: 1000, user: "me", groups: ["me", "wheel"], root: false,
    allUsers: ["daemon", "me", "root"], allGroups: ["me", "nogroup", "users", "wheel"] })
  function identity(cb) { record("identity", []); if (cb) cb(identityInfo) }
  function openerFor(path, cb) { record("openerFor", [path]); if (cb) cb({ mime: "text/yaml", handler: "" }) }
  function setOpener(mime, handler, onDone, onError) { record("setOpener", [mime, handler]); if (onDone) onDone({}) }
  property var modeResult: ({})
  function changeMode(path, setBits, clearBits, recursive, onDone, onError) {
    record("changeMode", [path, setBits, clearBits, recursive])
    if (modeResult.code && onError) onError(modeResult)
    else if (onDone) onDone({})
  }
  property var ownerResult: ({})
  function changeOwner(path, owner, group, recursive, privileged, onDone, onError) {
    record("changeOwner", [path, owner, group, recursive, privileged === true])
    if (ownerResult.code && onError) onError(ownerResult)
    else if (onDone) onDone({})
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
  property var unmountResult: ({})
  function unmountDrive(device, onDone, onError) {
    record("unmountDrive", [device])
    if (unmountResult.code) { if (onError) onError(unmountResult) }
    else if (onDone) onDone({})
  }
  function ejectDrive(device, onDone, onError) { record("ejectDrive", [device]) }
  property var unlockResult: ({ path: "/tmp/docs" })
  function unlockDrive(device, passphrase, onDone, onError) {
    record("unlockDrive", [device, passphrase])
    if (unlockResult.code) { if (onError) onError(unlockResult) }
    else if (onDone) onDone(unlockResult)
  }
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
  function openExternallyFiles(paths) { record("openExternallyFiles", [paths]) }
  function appCommand(app) {
    var exec = Model.tokenizeCommand(String((app && app.execString) || ""))
    return exec.length > 0 ? exec : Array.prototype.slice.call((app && app.command) || [])
  }
  property bool agentAvailable: false
  property string agentName: "Claude Code"
  property string omarchyEditor: "nvim"
  property string omarchyAgent: ""
  property bool omarchyAgentFound: false
  property bool claudeAvailable: false
  property var programsFound: ({ code: true, nvim: true, nano: true })
  readonly property var editorApps: Model.knownEditors.filter(function (e) { return mock.programsFound[e.id] === true })
  readonly property string editorChoice: String(settingNow("editorChoice", "") || "")
  readonly property string editorCommand: String(settingNow("editor", "") || "").trim()
  property var missingPrograms: ({})
  function refreshDefaults() { record("refreshDefaults", []); return 0 }
  function checkProgram(command, onResult) {
    var program = Model.commandProgram(command)
    record("checkProgram", [program])
    Qt.callLater(function () { onResult(program !== "" && mock.missingPrograms[program] !== true) })
    return 0
  }
  function editorPlan(onPlan) {
    if (editorChoice === "omarchy" || editorChoice === "omafile") { onPlan({ mode: editorChoice }); return }
    var command = editorCommand
    if (!command) { onPlan({ ask: true, error: "" }); return }
    checkProgram(command, function (found) { onPlan(found ? { mode: "own", command: command } : { ask: true, error: command }) })
  }
  function launchEditor(plan, paths) { record("launchEditor", [plan, paths]) }
  function setOmarchyEditor(id) { record("setOmarchyEditor", [id]); omarchyEditor = id; return true }
  function openAgent(path) { record("openAgent", [path]) }
  property var compressResult: null
  function makeDirectory(path, onDone, onError) { record("makeDirectory", [path]); if (onDone) onDone({}) }
  function makeFile(path, onDone, onError) { record("makeFile", [path]); if (onDone) onDone({}) }
  function makeLink(path, target, onDone, onError) { record("makeLink", [path, target]); if (onDone) onDone({}) }
  property var transcodeResult: null
  function transcodePaths(paths, format, resolution, onDone, onError) {
    record("transcodePaths", [paths, format, resolution])
    if (transcodeResult && transcodeResult.error) { if (onError) onError({ message: transcodeResult.error, code: transcodeResult.code }) }
    else if (onDone) onDone({ outputs: paths.map(function (p) { return p.replace(/\.[^.\/]+$/, "-" + resolution + "." + format) }), failures: [] })
  }
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
  property string thumbResult: ""
  property var thumbResults: ({})
  function thumbnailFor(path, mtime, bucket, onReady) {
    record("thumbnailFor", [path, mtime, bucket])
    onReady(thumbResults[bucket] !== undefined ? thumbResults[bucket] : thumbResult)
    return null
  }
  function releaseThumbnail(ticket) {}
  function finishPick(result, request) { record("finishPick", [result, request]); pickRequest = null }
  property var systemClipboard: null
  property bool sameDrive: true
  function readSystemClipboard(onDone) { onDone(systemClipboard) }
  property string clipboardText: ""
  property var remoteRoots: []
  property var audioTags: ({ title: "Tone" })
  function previewAudio(path, onReady, onError) {
    record("previewAudio", [path])
    Qt.callLater(function () { onReady({ path: path, title: mock.audioTags.title || "", artist: "", album: "" }) })
    return 9
  }
  function isRemotePath(p) { return remoteRoots.some(function (r) { return Model.isWithin(p, r) }) }
  function resolveConflict(id, action, all, seq) { record("resolveConflict", [id, action, all, seq]) }
  function transferOwner(id) { return null }
  function readClipboardText(onText) { record("readClipboardText", []); Qt.callLater(function () { onText(mock.clipboardText) }) }
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
