import QtQuick

QtObject {
  id: mock
  property var calls: []
  property var files: [["alpha.yml", "f", 30, 300, 420, null], ["beta.png", "f", 10, 100, 420, null], ["docs", "d", 0, 200, 493, null]]
  property var session: null
  property var pinned: []
  property var clipboard: null
  property var transfers: []
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
  property var values: ({})
  property var pickRequest: null
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
  function setting(key, fallback) { return values[key] !== undefined ? values[key] : fallback }
  function settingNow(key, fallback) { return setting(key, fallback) }
  function updateSetting(key, value) { var v = values; v[key] = value; values = v }
  function startPath() { return "/tmp" }
  function rememberSession(s) { session = s }
  function listDirectory(path, hidden, onChunk, onDone, onError) {
    Qt.callLater(function () { onChunk(mock.files); onDone({ total: mock.files.length }) })
    return 1
  }
  function listRecent(onChunk, onDone, onError) { Qt.callLater(function () { onDone({ total: 0 }) }); return 2 }
  function watchDirectory() { return 3 }
  function unwatch() {}
  function cancel() {}
  function noteRecent() {}
  function trashFilesPath() { return "/tmp/.trash" }
  function driveHidden() { return false }
  function networkMounts() { return [] }
  function statPaths(paths, cb) {}
  function peekFile(path, limit, onDone, onError) { record("peekFile", [path]); onDone({ text: "key: value\n", binary: false, truncated: false }) }
  function openWith(command, path, inTerminal) { record("openWith", [command, path, inTerminal]) }
  function runCommandOn(text, path) { record("runCommandOn", [text, path]); return true }
  function openExternally(path) { record("openExternally", [path]) }
  function finishPick(result) { record("finishPick", [result]); pickRequest = null }
}
