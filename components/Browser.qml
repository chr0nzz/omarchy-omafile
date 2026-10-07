import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  readonly property string pluginId: "xyzlab.omafile"
  readonly property string home: Quickshell.env("HOME") || ""
  signal openRequested()
  signal closeRequested()
  signal dismissRequested()

  property bool pickerWindow: false
  property var pickerRequest: null

  property bool split: false
  property int activeSide: 0
  property bool sidebarVisible: true
  property var tabsA: []
  property var tabsB: []
  property int activeA: 0
  property int activeB: 0
  property string dialogMode: ""
  property string dialogValue: ""
  property string dialogTitle: ""
  property string dialogError: ""
  property var dialogPayload: null
  property string confirmAction: ""
  property string settingsSection: "opening"
  readonly property real viewScale: clampViewScale(service ? service.settingNow("viewScale", 1) : 1)
  property var pendingDrop: null
  onMenuOpenChanged: if (!menuOpen) pendingDrop = null
  property bool menuOpen: false
  property int menuCursor: -1
  property var menuActions: []
  // Tracks Shift so an open context menu can swap Move to trash for Delete permanently.
  property bool shiftHeld: false
  onShiftHeldChanged: refreshEntryMenu()
  property string focusZone: "pane"
  property int appCursor: 0
  property real menuX: 0
  property real menuY: 0
  property var menuEntry: null
  property string menuKind: ""
  property string statusText: ""
  property bool transfersOpen: false
  property bool transfersMinimized: false
  property bool transfersAutoOpened: false
  readonly property int transferCount: service && service.transfers ? service.transfers.length : 0
  readonly property int runningTransfers: service ? Number(service.activeTransfers) || 0 : 0

  onStatusTextChanged: if (statusText !== "") statusTimer.restart()
  onRunningTransfersChanged: {
    if (runningTransfers > 0) {
      transfersCloseTimer.stop()
      if (!transfersPopTimer.running && !transfersOpen) transfersPopTimer.start()
    } else if (transfersAutoOpened) {
      transfersCloseTimer.restart()
    }
  }
  onTransferCountChanged: if (transferCount === 0) transfersOpen = false

  readonly property var captionOptions: [
    { label: "None", value: "none" },
    { label: "Size, or items in a folder", value: "size" },
    { label: "Type", value: "type" },
    { label: "Modified", value: "modified" },
    { label: "Permissions", value: "permissions" }
  ]
  readonly property var gridCaptions: [
    textSetting("gridCaption1", "none"), textSetting("gridCaption2", "none"), textSetting("gridCaption3", "none")
  ]

  function showTransfers(open) {
    transfersOpen = open && transferCount > 0
    transfersAutoOpened = false
    transfersMinimized = !open
    transfersCloseTimer.stop()
  }

  Timer {
    id: statusTimer
    interval: 4000
    onTriggered: root.statusText = ""
  }

  Timer {
    id: transfersPopTimer
    interval: 900
    onTriggered: {
      if (root.runningTransfers > 0 && !root.transfersMinimized && !root.transfersOpen) {
        root.transfersOpen = true
        root.transfersAutoOpened = true
      }
    }
  }

  Timer {
    id: transfersCloseTimer
    interval: 4000
    onTriggered: {
      if (root.runningTransfers === 0 && root.transfersAutoOpened) {
        root.transfersOpen = false
        root.transfersAutoOpened = false
      }
    }
  }
  property string appFilter: ""
  property bool appAlways: false
  readonly property bool appChoiceReady: {
    var count = filteredApps().length
    if (canRunTyped && (appCursor < 0 || count === 0)) return true
    return appCursor >= 0 && appCursor < count
  }
  readonly property bool canRunTyped: dialogMode === "openwith"
    && Model.tokenizeCommand(appFilter).length > 0
  property bool findMode: false
  property bool connectAnonymous: false
  property string connectStatus: ""
  property bool connectFailed: false
  function startPath() {
    return service ? service.startPath() : (home || "/")
  }
  function defaultTab(path) {
    return {
      path: path || startPath(),
      view: Model.normalizeViewMode(service ? String(service.settingNow("defaultView", "list")) : "list"),
      sortBy: service ? String(service.settingNow("sortBy", "name")) : "name",
      descending: false,
      hidden: service ? service.settingNow("showHidden", false) === true : false,
      filter: ""
    }
  }
  function inheritedTab(fromSide, path) {
    var p = paneFor(fromSide)
    var tab = defaultTab(path || p.path)
    if (!p.ready) return tab
    tab.view = Model.normalizeViewMode(p.view)
    tab.sortBy = p.sortBy
    tab.descending = p.descending
    tab.hidden = p.showHidden
    return tab
  }
  function paneFor(side) {
    return side === 1 ? paneB : paneA
  }
  function tabsFor(side) {
    return side === 1 ? tabsB : tabsA
  }
  function setTabs(side, value) {
    if (side === 1) tabsB = value
    else tabsA = value
  }
  function activeIndexFor(side) {
    return side === 1 ? activeB : activeA
  }
  function setActiveIndex(side, value) {
    if (side === 1) activeB = value
    else activeA = value
  }
  function activePane() {
    return paneFor(activeSide)
  }
  function captureTab(side) {
    var p = paneFor(side)
    return {
      path: p.path, view: p.view, sortBy: p.sortBy,
      descending: p.descending, hidden: p.showHidden, filter: p.filter
    }
  }
  function storeCurrentTab(side) {
    var list = tabsFor(side).slice()
    var idx = activeIndexFor(side)
    if (idx < 0 || idx >= list.length) return
    list[idx] = captureTab(side)
    setTabs(side, list)
  }
  function applyTab(side, tab) {
    var p = paneFor(side)
    p.ready = false
    p.view = Model.normalizeViewMode(tab.view)
    p.sortBy = tab.sortBy || "name"
    p.descending = tab.descending === true
    p.filter = tab.filter || ""
    p.showHidden = tab.hidden === true
    p.dirsFirst = service ? service.settingNow("sortDirsFirst", true) === true : true
    p.thumbnails = service ? service.settingNow("thumbnails", true) !== false : true
    p.ready = true
    p.navigate(tab.path, true)
  }
  function selectTab(side, index) {
    var list = tabsFor(side)
    if (index < 0 || index >= list.length) return
    storeCurrentTab(side)
    setActiveIndex(side, index)
    applyTab(side, tabsFor(side)[index])
    activeSide = side
    rememberSession()
  }
  function newTab(side, path) {
    storeCurrentTab(side)
    var list = tabsFor(side).slice()
    list.push(inheritedTab(side, path))
    setTabs(side, list)
    setActiveIndex(side, list.length - 1)
    applyTab(side, list[list.length - 1])
    activeSide = side
    rememberSession()
  }
  property var closedTabs: []

  function closeTab(side, index) {
    storeCurrentTab(side)
    var list = tabsFor(side).slice()
    if (list.length <= 1) {
      if (split) closePaneSide(side)
      else requestClose()
      return
    }
    var gone = closedTabs.slice()
    gone.push({ side: side, index: index, tab: list[index] })
    if (gone.length > 20) gone.shift()
    closedTabs = gone
    list.splice(index, 1)
    var idx = activeIndexFor(side)
    if (idx >= list.length) idx = list.length - 1
    else if (index < idx) idx = idx - 1
    setTabs(side, list)
    setActiveIndex(side, idx)
    applyTab(side, list[idx])
    rememberSession()
  }
  function restoreClosedTab() {
    if (closedTabs.length === 0) { statusText = "No closed tabs"; return }
    var gone = closedTabs.slice()
    var last = gone.pop()
    closedTabs = gone
    var side = last.side === 1 && split ? 1 : 0
    storeCurrentTab(side)
    var list = tabsFor(side).slice()
    var at = Math.max(0, Math.min(list.length, Number(last.index) || 0))
    list.splice(at, 0, last.tab)
    setTabs(side, list)
    setActiveIndex(side, at)
    applyTab(side, list[at])
    activeSide = side
    rememberSession()
  }

  function jumpToTab(index) {
    var list = tabsFor(activeSide)
    if (index < 0 || index >= list.length) return
    selectTab(activeSide, index)
  }

  function moveTab(delta) {
    var side = activeSide
    storeCurrentTab(side)
    var list = tabsFor(side).slice()
    var from = activeIndexFor(side)
    var to = from + delta
    if (to < 0 || to >= list.length) return
    var tab = list.splice(from, 1)[0]
    list.splice(to, 0, tab)
    setTabs(side, list)
    setActiveIndex(side, to)
    rememberSession()
  }

  function closePaneSide(side) {
    if (side === 0) {
      storeCurrentTab(1)
      tabsA = tabsB
      activeA = activeB
      applyTab(0, tabsA[activeA])
    }
    tabsB = []
    activeB = 0
    split = false
    activeSide = 0
    rememberSession()
  }

  function toggleSplit() {
    split = !split
    if (split && tabsB.length === 0) {
      tabsB = [inheritedTab(0, paneA.path)]
      activeB = 0
      applyTab(1, tabsB[0])
    }
    if (!split) activeSide = 0
    rememberSession()
  }
  function otherSide() {
    return activeSide === 1 ? 0 : 1
  }
  function rememberSession() {
    if (!service || !sessionRestored || pickerWindow) return
    storeCurrentTab(activeSide)
    service.rememberSession({
      split: split, activeSide: activeSide, sidebar: sidebarVisible,
      tabsA: tabsFor(0), tabsB: tabsFor(1), activeA: activeA, activeB: activeB
    })
  }
  function restoreSession() {
    var s = service && !pickerWindow ? service.session : null
    if (s && s.tabsA && s.tabsA.length > 0) {
      tabsA = s.tabsA
      activeA = Math.max(0, Math.min(s.tabsA.length - 1, Number(s.activeA) || 0))
      sidebarVisible = s.sidebar !== false
      split = s.split === true
      if (s.tabsB && s.tabsB.length > 0) {
        tabsB = s.tabsB
        activeB = Math.max(0, Math.min(s.tabsB.length - 1, Number(s.activeB) || 0))
      }
    } else {
      tabsA = [defaultTab(startPath())]
      activeA = 0
    }
    applyTab(0, tabsA[activeA])
    if (split && tabsB.length > 0) applyTab(1, tabsB[activeB])
  }
  function open(payloadJson) {
    closingFromHost = false
    var target = ""
    var wantDialog = ""
    var wantSelect = ""
    var wantPick = false
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed && typeof parsed.path === "string") target = parsed.path
        if (parsed && typeof parsed.dialog === "string") wantDialog = parsed.dialog
        if (parsed && typeof parsed.select === "string") wantSelect = parsed.select
        if (parsed && parsed.pick === true) wantPick = true
      } catch (e) {
      }
    }
    ensureSession()
    root.openRequested()
    Qt.callLater(function () {
      if (target) activePane().navigate(target)
      keyCatcher.forceActiveFocus()
      if (wantSelect) {
        var pane = activePane()
        selectTimer.pendingName = wantSelect
        selectTimer.pendingPane = pane
        selectTimer.restart()
      }
      if (wantDialog === "shortcuts") showDialog("shortcuts", "Keyboard shortcuts", "", null)
      if (wantPick) beginPickSession()
    })
  }
  function close() {
    root.closeRequested()
  }
  function requestClose() {
    if (pickerRequest) answerPick({ ok: false })
    rememberSession()
    root.dismissRequested()
  }

  readonly property var pick: pickerRequest
  readonly property bool picking: pick !== null && pick !== undefined
  readonly property bool pickSaving: picking && (pick.mode === "save" || pick.mode === "savefiles")
  readonly property bool pickNeedsName: picking && pick.mode === "save"
  property int pickFilter: -1

  Component.onDestruction: {
    if (pickerRequest) answerPick({ ok: false })
  }

  function answerPick(result) {
    var request = pickerRequest
    pickerRequest = null
    if (service && request) service.finishPick(result, request)
  }

  function pickFilters() {
    return picking && pick.filters && pick.filters.length ? pick.filters : []
  }

  function pickPatterns() {
    var list = pickFilters()
    if (pickFilter < 0 || pickFilter >= list.length) return []
    return list[pickFilter].patterns || []
  }

  function pickTitle() {
    if (!picking) return ""
    if (pick.title) return String(pick.title)
    if (pick.mode === "save") return "Save file"
    if (pick.mode === "savefiles") return "Choose a folder to save into"
    if (pick.directory) return "Choose a folder"
    return pick.multiple ? "Choose files" : "Choose a file"
  }

  function pickAcceptLabel() {
    if (picking && pick.acceptLabel) return String(pick.acceptLabel).replace(/_/g, "")
    if (pickSaving) return "Save"
    return "Select"
  }

  function beginPickSession() {
    if (!picking) return
    closeMenu()
    if (dialogMode !== "") closeDialog()
    if (previewOpen) closePreview()
    var filters = pickFilters()
    var wanted = Number(pick.currentFilter)
    pickFilter = filters.length === 0 ? -1
      : (isFinite(wanted) && wanted >= 0 && wanted < filters.length ? wanted : 0)
    var folder = String(pick.currentFolder || "")
    if (!folder && pick.currentFile) folder = Model.dirname(String(pick.currentFile))
    var p = activePane()
    if (folder) p.navigate(folder)
    var name = String(pick.currentName || "")
    if (!name && pick.currentFile) name = Model.basename(String(pick.currentFile))
    pickNameField.text = name
    if (pickNeedsName) {
      pickNameField.forceActiveFocus()
      var dot = name.lastIndexOf(".")
      if (dot > 0) pickNameField.select(0, dot)
      else pickNameField.selectAll()
    } else keyCatcher.forceActiveFocus()
  }

  function completePick(paths) {
    if (!picking) return
    answerPick({ ok: true, paths: paths, filter: pickFilter })
    rememberSession()
    root.dismissRequested()
  }

  function cancelPick() {
    if (!picking) return
    answerPick({ ok: false })
    rememberSession()
    root.dismissRequested()
  }

  function pickTargetFolder() {
    var p = activePane()
    var sel = p.selectedEntries
    if (sel.length === 1 && sel[0].isDir) return sel[0].path
    return p.virtualView ? "" : p.path
  }

  function acceptPick(entries) {
    if (!picking) return
    var p = activePane()
    if (pick.mode === "save") {
      var name = String(pickNameField.text || "").trim()
      if (!name) { statusText = "Type a name to save as"; pickNameField.forceActiveFocus(); return }
      if (name.indexOf("/") >= 0) { statusText = "The name cannot contain a slash"; return }
      if (p.virtualView) { statusText = "Pick a folder to save into"; return }
      var target = Model.joinPath(p.path, name)
      for (var i = 0; i < p.rows.length; i++) {
        if (p.rows[i][0] === name) {
          confirmAction = "pickreplace"
          confirm.message = "\"" + name + "\" already exists. Replace it?"
          confirm.confirmText = "Replace"
          dialogPayload = [target]
          confirm.opened = true
          keyCatcher.forceActiveFocus()
          return
        }
      }
      completePick([target])
      return
    }
    if (pick.mode === "savefiles") {
      var folder = pickTargetFolder()
      if (!folder) { statusText = "Pick a folder to save into"; return }
      var names = pick.files || []
      var out = []
      for (var n = 0; n < names.length; n++) out.push(Model.joinPath(folder, String(names[n])))
      completePick(out)
      return
    }
    if (pick.directory) {
      var dir = pickTargetFolder()
      if (dir) completePick([dir])
      return
    }
    var chosen = entries || p.selectedEntries
    var files = []
    for (var k = 0; k < chosen.length; k++) if (!chosen[k].isDir) files.push(chosen[k].path)
    if (files.length === 0) {
      var cursor = p.cursorEntry()
      if (cursor && cursor.isDir && chosen.length <= 1) p.openEntry(cursor)
      else statusText = "Select a file"
      return
    }
    completePick(pick.multiple ? files : [files[0]])
  }
  function showDialog(mode, title, value, payload) {
    dialogMode = mode
    dialogTitle = title
    dialogValue = value || ""
    dialogPayload = payload || null
    dialogError = ""
    appFilter = ""
    appAlways = false
    Qt.callLater(function () {
      if (dialogMode === "rename" || dialogMode === "newfolder" || dialogMode === "newfile" || dialogMode === "path"
          || dialogMode === "bookmarkname" || dialogMode === "compress") {
        dialogField.text = root.dialogValue
        dialogField.forceActiveFocus()
        if (dialogMode === "rename") {
          var dot = root.dialogValue.lastIndexOf(".")
          if (dot > 0) dialogField.select(0, dot)
          else dialogField.selectAll()
        } else dialogField.selectAll()
      } else if (dialogMode === "openwith") {
        appField.text = ""
        root.appCursor = 0
        appField.forceActiveFocus()
      } else if (dialogMode === "connect") {
        var saved = root.service ? root.service.settingsForServer(root.dialogValue) : null
        root.connectStatus = root.dialogPayload && root.dialogPayload.error ? String(root.dialogPayload.error) : ""
        root.connectFailed = root.connectStatus !== ""
        serverField.text = root.dialogValue
        userField.text = saved ? String(saved.user || "") : ""
        domainField.text = saved ? String(saved.domain || "") : ""
        passwordField.text = ""
        root.connectAnonymous = saved ? saved.anonymous === true : false
        if (root.connectFailed && !root.connectAnonymous) passwordField.forceActiveFocus()
        else serverField.forceActiveFocus()
      }
    })
  }
  function closeDialog() {
    dialogMode = ""
    dialogPayload = null
    dialogError = ""
    keyCatcher.forceActiveFocus()
  }
  property string quickConnecting: ""
  function openServer(uri) {
    var address = String(uri || "")
    if (!service || !address || !service.isRememberedServer(address)) {
      showDialog("connect", "Connect to a server", address, null)
      return
    }
    if (quickConnecting === address) return
    var saved = service.settingsForServer(address)
    var label = Model.serverLabel(address)
    var key = Model.serverKeyOf(address)
    var mounts = service.networkMounts()
    var connected = false
    for (var i = 0; i < mounts.length; i++)
      if (mounts[i].host && Model.serverKey(mounts[i].user, mounts[i].host, mounts[i].port) === key) connected = true
    quickConnecting = address
    statusText = (connected ? "Opening " : "Connecting to ") + label
    service.connectToServer(address, saved.user, saved.domain, "", saved.anonymous === true,
      function (m) {
        root.quickConnecting = ""
        root.statusText = connected ? "" : "Connected to " + label
        var target = String(m.path || "")
        if (target) root.activePane().navigate(target)
      },
      function (m) {
        root.quickConnecting = ""
        root.statusText = ""
        root.showDialog("connect", "Connect to " + label, address,
          { error: String(m.message || "Could not connect") + ". Check the details and try again." })
      })
  }
  function submitConnect() {
    if (!service) return
    var uri = String(serverField.text || "").trim()
    if (!uri) {
      connectStatus = "Enter an address"
      connectFailed = true
      return
    }
    connectStatus = "Connecting"
    connectFailed = false
    service.connectToServer(uri, userField.text, domainField.text, passwordField.text,
      connectAnonymous,
      function (m) {
        root.connectStatus = ""
        root.connectFailed = false
        passwordField.text = ""
        var target = String(m.path || "")
        root.closeDialog()
        if (target) root.activePane().navigate(target)
      },
      function (m) {
        root.connectStatus = String(m.message || "Could not connect")
        root.connectFailed = true
      })
  }
  function submitDialog() {
    var p = activePane()
    var value = String(dialogField.text || "").trim()
    if (dialogMode === "path") {
      closeDialog()
      p.navigate(value)
      return
    }
    if (dialogMode === "bookmarkname") {
      var place = dialogPayload
      closeDialog()
      if (place && place.path) service.renameBookmark(place.path, value)
      return
    }
    if (!value) {
      dialogError = "Name cannot be empty"
      return
    }
    if (value.indexOf("/") >= 0) {
      dialogError = "Name cannot contain a slash"
      return
    }
    if (dialogMode === "compress") {
      var targets = dialogPayload || []
      var archiveName = value + compressFormat
      closeDialog()
      if (targets.length > 0) compressNow(targets, archiveName)
      return
    }
    if (dialogMode === "newfolder") {
      service.makeDirectory(Model.joinPath(p.path, value),
        function () { closeDialog(); p.refresh() },
        function (m) { root.dialogError = String(m.message || "Could not create the folder") })
    } else if (dialogMode === "newfile") {
      service.makeFile(Model.joinPath(p.path, value),
        function () { closeDialog(); p.refresh() },
        function (m) { root.dialogError = String(m.message || "Could not create the file") })
    } else if (dialogMode === "rename") {
      var entry = dialogPayload
      if (!entry) return closeDialog()
      service.renamePath(entry.path, value,
        function () { closeDialog(); p.refresh() },
        function (m) { root.dialogError = String(m.message || "Could not rename") })
    }
  }
  function doCopy() {
    var p = activePane()
    var paths = p.selectedPaths()
    if (paths.length === 0) return
    service.setClipboard("copy", paths)
    statusText = Model.formatCount(paths.length, "item copied", "items copied")
  }
  function doCut() {
    var p = activePane()
    var paths = p.selectedPaths()
    if (paths.length === 0) return
    service.setClipboard("cut", paths)
    statusText = Model.formatCount(paths.length, "item cut", "items cut")
  }
  function doPaste() {
    if (!service) return
    var pane = activePane()
    if (pane.virtualView || !pane.path) return
    var dest = pane.path
    service.readSystemClipboard(function (sys) {
      var clip = sys || service.clipboard
      if (clip && clip.image && (!clip.paths || clip.paths.length === 0)) {
        service.pasteImage(dest, clip.image, function (path) {
          root.statusText = "Pasted " + Model.basename(path)
        }, function (m) {
          root.statusText = String(m.message || "Could not paste the image")
        })
        return
      }
      if (!clip || !clip.paths || clip.paths.length === 0) {
        root.statusText = "Nothing to paste"
        return
      }
      service.beginTransfer(clip.mode === "cut" ? "move" : "copy", clip.paths, dest, "ask")
      if (clip.mode === "cut") {
        service.clearClipboard()
        service.clearSystemClipboard()
      }
    })
  }

  function handleDrop(urls, dest, position) {
    closeMenu()
    if (!service) return
    var paths = []
    for (var i = 0; i < urls.length; i++) {
      var u = String(urls[i])
      if (u.indexOf("file://") !== 0) continue
      var path
      try { path = decodeURIComponent(u.substring(7)) } catch (e) { continue }
      if (dest !== "trash:") {
        if (path === dest || dest.indexOf(path + "/") === 0) continue
        if (Model.parentPath(path) === dest) continue
      }
      paths.push(path)
    }
    if (paths.length === 0) return
    if (dest === "trash:") {
      performTrash(paths)
      return
    }
    var action = service.settingNow("dropAction", "auto")
    if (action === "copy" || action === "move") {
      transferDrop(action, paths, dest)
      return
    }
    if (action !== "ask") {
      service.sameDevice(paths[0], dest, function (same) {
        root.transferDrop(same ? "move" : "copy", paths, dest)
      })
      return
    }
    pendingDrop = { paths: paths, dest: dest }
    menuEntry = null
    menuKind = "drop"
    menuActions = [
      { key: "drop:copy", label: "Copy", glyph: Icons.actionGlyph("copy") },
      { key: "drop:move", label: "Move", glyph: Icons.actionGlyph("cut") },
      { key: "drop:cancel", label: "Cancel" }
    ]
    var pt = position ? keyCatcher.mapFromGlobal(position.x, position.y) : Qt.point(width / 2, height / 2)
    menuX = pt.x
    menuY = pt.y
    menuCursor = -1
    menuOpen = true
    keyCatcher.forceActiveFocus()
  }

  function transferDrop(action, paths, dest) {
    service.beginTransfer(action, paths, dest, "ask")
    statusText = (action === "move" ? "Moving " : "Copying ") + Model.formatCount(paths.length, "item", "items")
      + " to " + Model.basename(dest)
  }
  function clampViewScale(value) {
    var n = Number(value)
    if (!isFinite(n) || n <= 0) return 1
    return Math.max(minViewScale, Math.min(maxViewScale, Math.round(n * 20) / 20))
  }
  readonly property real minViewScale: 0.5
  readonly property real maxViewScale: 3
  function setViewScale(value) {
    var next = clampViewScale(value)
    if (next !== viewScale) applySettingNow("viewScale", next)
    statusText = "View size " + Math.round(next * 100) + "%"
  }
  function nudgeViewScale(delta) {
    setViewScale(viewScale + delta)
  }
  function transferToOtherPane(op) {
    if (!split) return
    var from = activePane()
    var to = paneFor(otherSide())
    var paths = from.selectedPaths()
    if (paths.length === 0) return
    service.beginTransfer(op, paths, to.path, "ask")
  }
  function trashRoot() {
    return service && typeof service.trashFilesPath === "function" ? service.trashFilesPath() : ""
  }
  function paneInTrash(p) {
    return p !== null && p !== undefined && !p.virtualView && Model.isTrashPath(p.path, trashRoot())
  }
  function doTrash(given) {
    var paths = given || activePane().selectedPaths()
    if (paths.length === 0) return
    if (Model.allInTrash(paths, trashRoot())) return askDelete(paths)
    if (service.settingNow("useTrash", true) !== true) return askDelete(paths)
    if (service.settingNow("confirmTrash", true) !== true) return performTrash(paths)
    confirmAction = "trash"
    confirm.message = "Move " + Model.formatCount(paths.length, "item", "items") + " to trash?"
    confirm.confirmText = "Move to trash"
    dialogPayload = paths
    confirm.opened = true
  }
  function performTrash(paths) {
    var p = activePane()
    service.trashPaths(paths, function () { p.refresh() }, null)
    statusText = Model.formatCount(paths.length, "item moved to trash", "items moved to trash")
  }
  function askDelete(paths) {
    var targets = paths || activePane().selectedPaths()
    if (targets.length === 0) return
    if (service.settingNow("confirmDelete", true) !== true) return performDelete(targets)
    confirmAction = "delete"
    confirm.message = "Permanently delete " + Model.formatCount(targets.length, "item", "items") + "? This cannot be undone."
    confirm.confirmText = "Delete"
    dialogPayload = targets
    confirm.opened = true
  }
  function performDelete(paths) {
    service.deletePaths(paths, function () { root.refreshPanes() }, null)
    statusText = Model.formatCount(paths.length, "item deleted", "items deleted")
  }
  function restorablePaths() {
    var p = activePane()
    var paths = p.selectedPaths()
    if (paths.length === 0 && p.cursorEntry()) paths = [p.cursorEntry().path]
    return Model.trashItemNames(paths, trashRoot())
  }
  function doRestore() {
    var names = restorablePaths()
    if (names.length === 0 || !service) return
    service.restoreFromTrash(names, function (m) {
      var ok = 0
      var results = m && m.results ? m.results : []
      for (var i = 0; i < results.length; i++) if (results[i].ok) ok++
      root.statusText = ok === names.length
        ? Model.formatCount(ok, "item restored", "items restored")
        : "Restored " + ok + " of " + names.length
      root.refreshPanes()
    }, function (m) {
      root.statusText = String(m && m.message ? m.message : "Could not restore")
    })
  }
  function askEmptyTrash() {
    if (!service || service.trashCount <= 0) return
    if (service.settingNow("confirmDelete", true) !== true) return performEmptyTrash()
    confirmAction = "emptytrash"
    confirm.message = "Permanently delete all " + Model.formatCount(service.trashCount, "item", "items")
      + " in the trash? This cannot be undone."
    confirm.confirmText = "Empty trash"
    dialogPayload = null
    confirm.opened = true
  }
  function performEmptyTrash() {
    if (!service) return
    service.emptyTrash(function () {
      var panes = split ? [paneA, paneB] : [paneA]
      for (var i = 0; i < panes.length; i++) {
        var p = panes[i]
        var top = Model.trashRootOf(p.path, root.trashRoot())
        if (!p.virtualView && top !== "" && Model.normalizePath(p.path) !== top) p.navigate(top)
        else p.refresh()
      }
    })
    statusText = "Trash emptied"
  }
  function doRename() {
    var p = activePane()
    var entry = p.cursorEntry()
    var sel = p.selectedEntries
    if (sel.length === 1) entry = sel[0]
    if (!entry) return
    showDialog("rename", "Rename", entry.name, entry)
  }
  function openSelection() {
    activePane().activateCursor()
  }
  function handleOpenRequest(entry) {
    if (!entry || !service) return
    if (picking) {
      if (pickNeedsName) pickNameField.text = entry.name
      else if (!pickSaving && !pick.directory) acceptPick([entry])
      return
    }
    if (extractsOnOpen(entry)) {
      extractArchives([entry])
      return
    }
    service.openExternally(entry.path)
    afterLaunch()
  }

  function extractsOnOpen(entry) {
    return boolSetting("extractOnOpen", false) && Model.isArchive(entry)
  }

  function archiveTargets(entry) {
    var p = activePane()
    var sel = p ? p.selectedEntries : []
    var list = []
    var inSelection = false
    for (var i = 0; i < sel.length; i++) if (entry && sel[i].path === entry.path) inSelection = true
    var source = inSelection ? sel : (entry ? [entry] : [])
    for (var j = 0; j < source.length; j++) if (Model.isArchive(source[j])) list.push(source[j])
    return list
  }

  function extractArchives(entries) {
    if (!service || entries.length === 0) return
    var p = activePane()
    var pending = entries.length
    var failed = 0
    var last = ""
    statusText = entries.length === 1 ? "Extracting " + entries[0].name
      : "Extracting " + Model.formatCount(entries.length, "archive", "archives")
    function finished() {
      pending--
      if (pending > 0 || last === "") return
      root.statusText = failed > 0
        ? "Extracted to " + Model.basename(last) + ", " + Model.formatCount(failed, "archive failed", "archives failed")
        : "Extracted to " + Model.basename(last)
      if (p.path !== Model.parentPath(last)) return
      p.refresh()
      selectTimer.pendingName = Model.basename(last)
      selectTimer.pendingPane = p
      selectTimer.restart()
    }
    for (var i = 0; i < entries.length; i++) {
      (function (entry) {
        service.extractArchive(entry.path, function (m) {
          last = String(m.path || "")
          finished()
        }, function (m) {
          failed++
          root.statusText = m && m.code === "ECANCELED" ? "Extraction of " + entry.name + " cancelled"
            : "Could not extract " + entry.name + ": " + String((m && m.message) || "")
          finished()
        })
      })(entries[i])
    }
  }

  property string compressFormat: ".zip"

  function compressTargets(entry) {
    var p = activePane()
    if (!entry || !p || p.virtualView || paneInTrash(p)) return []
    var sel = p.selectedEntries
    var inSelection = false
    for (var i = 0; i < sel.length; i++) if (sel[i].path === entry.path) inSelection = true
    var list = inSelection ? sel : [entry]
    var folder = Model.parentPath(list[0].path)
    for (var j = 1; j < list.length; j++) if (Model.parentPath(list[j].path) !== folder) return []
    var out = []
    for (var k = 0; k < list.length; k++) out.push(list[k])
    return out
  }

  function askCompress(entry) {
    var targets = compressTargets(entry)
    if (targets.length === 0) return
    showDialog("compress", "Compress " + (targets.length === 1 ? targets[0].name : Model.formatCount(targets.length, "item", "items")),
      Model.compressName(targets), targets)
  }

  function compressNow(targets, name) {
    var p = activePane()
    var paths = []
    for (var i = 0; i < targets.length; i++) paths.push(targets[i].path)
    statusText = "Compressing " + name
    service.compressPaths(paths, name, function (m) {
      var out = String(m.path || "")
      root.statusText = "Compressed to " + Model.basename(out)
      if (p.path !== Model.parentPath(out)) return
      p.refresh()
      selectTimer.pendingName = Model.basename(out)
      selectTimer.pendingPane = p
      selectTimer.restart()
    }, function (m) {
      root.statusText = m && m.code === "ECANCELED" ? "Compressing " + name + " cancelled"
        : "Could not compress: " + String((m && m.message) || "")
    })
  }

  function afterLaunch() {
    if (popupMode) requestClose()
  }
  function isBookmarked(path) {
    if (!service) return false
    var list = service.pinned
    for (var i = 0; i < list.length; i++) if (String(list[i]) === String(path)) return true
    return false
  }
  function contextActions(entry) {
    var p = activePane()
    var hasEntry = entry !== null && entry !== undefined
    var items = []
    var sep = 0
    function separator() { items.push({ key: "sep" + (++sep), label: "", glyph: "" }) }
    var claude = service && service.claudeAvailable
    if (hasEntry) {
      items.push({ key: "open", label: "Open", glyph: Icons.actionGlyph("open"), hint: "Enter" })
      items.push({ key: "openwith", label: "Open with", glyph: Icons.actionGlyph("open") })
      if (entry.isDir)
        items.push({ key: "opentab", label: "Open in new tab", glyph: Icons.actionGlyph("add"), hint: "Ctrl+Enter" })
      else
        items.push({ key: "preview", label: "Preview", glyph: Icons.actionGlyph("search"), hint: "Space" })
      separator()
      items.push({ key: "cut", label: "Cut", glyph: Icons.actionGlyph("cut"), hint: "Ctrl+X" })
      items.push({ key: "copy", label: "Copy", glyph: Icons.actionGlyph("copy"), hint: "Ctrl+C" })
      items.push({ key: "paste", label: "Paste", glyph: Icons.actionGlyph("paste"), hint: "Ctrl+V", disabled: !service })
      items.push({ key: "copypath", label: "Copy path", glyph: Icons.actionGlyph("copy") })
      separator()
      var trashed = Model.allInTrash([entry.path], trashRoot())
      if (trashed && Model.trashItemNames([entry.path], trashRoot()).length > 0)
        items.push({ key: "restore", label: "Restore", glyph: Icons.actionGlyph("restore") })
      items.push({ key: "rename", label: "Rename", glyph: Icons.actionGlyph("rename"), hint: "F2" })
      if (archiveTargets(entry).length > 0)
        items.push({ key: "extract", label: "Extract here", glyph: Icons.actionGlyph("extract") })
      if (compressTargets(entry).length > 0)
        items.push({ key: "compress", label: "Compress\u2026", glyph: Icons.actionGlyph("extract") })
      if (entry.isDir) {
        items.push({
          key: "bookmark",
          label: root.isBookmarked(entry.path) ? "Remove bookmark" : "Add to bookmarks",
          glyph: Icons.placeGlyph("pinned")
        })
        separator()
        items.push({ key: "terminal", label: "Open in terminal", glyph: Icons.actionGlyph("terminal") })
        if (claude)
          items.push({ key: "claude", label: "Open Claude Code here", glyph: Icons.actionGlyph("terminal") })
      }
      separator()
      // Permanent delete stays behind Shift, except in the trash where it is the only way out.
      if (trashed)
        items.push({ key: "delete", label: "Delete permanently", glyph: Icons.actionGlyph("delete"), hint: "Delete" })
      else if (shiftHeld)
        items.push({ key: "delete", label: "Delete permanently", glyph: Icons.actionGlyph("delete"), hint: "Shift+Delete" })
      else
        items.push({ key: "trash", label: "Move to trash", glyph: Icons.actionGlyph("trash"), hint: "Delete" })
      items.push({ key: "properties", label: "Properties", glyph: Icons.actionGlyph("properties"), hint: "Ctrl+I" })
    } else {
      items.push({ key: "newfolder", label: "New folder", glyph: Icons.actionGlyph("newfolder"), hint: "Ctrl+Shift+N" })
      items.push({ key: "newfile", label: "New file", glyph: Icons.actionGlyph("newfile"), hint: "Ctrl+N" })
      items.push({ key: "paste", label: "Paste", glyph: Icons.actionGlyph("paste"), hint: "Ctrl+V", disabled: !service })
      separator()
      items.push({ key: "terminal", label: "Open in terminal", glyph: Icons.actionGlyph("terminal"), hint: "Ctrl+." })
      if (claude)
        items.push({ key: "claude", label: "Open Claude Code here", glyph: Icons.actionGlyph("terminal") })
      separator()
      items.push({
        key: "bookmark",
        label: root.isBookmarked(p.path) ? "Remove this bookmark" : "Bookmark this folder",
        glyph: Icons.placeGlyph("pinned")
      })
      items.push({ key: "copypath", label: "Copy path", glyph: Icons.actionGlyph("copy") })
      items.push({ key: "refresh", label: "Refresh", glyph: Icons.actionGlyph("refresh"), hint: "F5" })
      if (paneInTrash(p)) {
        separator()
        items.push({ key: "emptytrash", label: "Empty trash", glyph: Icons.actionGlyph("delete"),
          disabled: !service || service.trashCount <= 0 })
      }
    }
    return items
  }
  function placeMenuActions(row) {
    var items = []
    if (!row || row.unhide === true) return items
    var real = row.path && row.path !== "recent:"
    if (row.unmounted === true) {
      items.push({ key: "place:mount", label: "Mount", glyph: Icons.placeGlyph(row.key) })
      items.push({ key: "sep-place1", label: "", glyph: "" })
      items.push({ key: "place:hidedrive", label: "Hide", glyph: Icons.actionGlyph("hidden") })
      return items
    }
    if (row.server === true || row.connect === true) {
      items.push({ key: "place:connect", label: "Connect", glyph: Icons.placeGlyph("network") })
      if (row.remembered === true && row.uri)
        items.push({ key: "place:editserver", label: "Edit\u2026", glyph: Icons.actionGlyph("rename") })
      if (row.remembered === true && row.uri)
        items.push({ key: "place:forget", label: "Forget this server", glyph: Icons.actionGlyph("close") })
      return items
    }
    items.push({ key: "place:open", label: "Open", glyph: Icons.actionGlyph("open") })
    items.push({ key: "place:tab", label: "Open in new tab", glyph: Icons.actionGlyph("add") })
    if (split) items.push({ key: "place:other", label: "Open in the other pane", glyph: Icons.actionGlyph("split") })
    var extra = []
    if (row.bookmark === true) {
      extra.push({ key: "place:renamebookmark", label: "Rename bookmark", glyph: Icons.actionGlyph("rename") })
      extra.push({ key: "place:unbookmark", label: "Remove bookmark", glyph: Icons.actionGlyph("close") })
    }
    if (row.mounted === true)
      extra.push({ key: "place:disconnect", label: "Disconnect", glyph: Icons.actionGlyph("eject") })
    if (row.key === "drive" || row.key === "usb") {
      extra.push({ key: "place:unmount", label: "Unmount", glyph: Icons.actionGlyph("eject"),
        disabled: row.unmountable !== true })
      if (row.removable === true)
        extra.push({ key: "place:eject", label: "Eject", glyph: Icons.actionGlyph("eject") })
    }
    if (row.hideKey)
      extra.push({ key: "place:hidedrive", label: "Hide", glyph: Icons.actionGlyph("hidden") })
    if (row.connected === true && row.remembered === true && row.uri)
      extra.push({ key: "place:forget", label: "Forget this server", glyph: Icons.actionGlyph("close") })
    if (row.trash === true)
      extra.push({ key: "place:emptytrash", label: "Empty trash", glyph: Icons.actionGlyph("delete"),
        disabled: !service || service.trashCount <= 0 })
    if (extra.length > 0) {
      items.push({ key: "sep-place1", label: "", glyph: "" })
      items = items.concat(extra)
    }
    if (real) {
      items.push({ key: "sep-place2", label: "", glyph: "" })
      items.push({ key: "place:copypath", label: "Copy path", glyph: Icons.actionGlyph("copy") })
      items.push({ key: "place:properties", label: "Properties", glyph: Icons.actionGlyph("properties") })
    }
    return items
  }
  function openPlaceMenu(row, x, y) {
    var pt = sidebar.mapToItem(keyCatcher, x, y)
    menuKind = "sidebar"
    menuEntry = row
    menuActions = placeMenuActions(row)
    menuCursor = -1
    menuX = pt.x
    menuY = pt.y
    menuOpen = true
  }
  function runPlaceAction(action, row) {
    if (!row) return
    var path = String(row.path || "")
    if (action === "open") activePane().navigate(path)
    else if (action === "tab") newTab(activeSide, path)
    else if (action === "other" && split) {
      activeSide = otherSide()
      activePane().navigate(path)
    }
    else if (action === "unbookmark") service.togglePinned(path)
    else if (action === "renamebookmark") showDialog("bookmarkname", "Rename bookmark", String(row.label || ""), row)
    else if (action === "forget") {
      var key = Model.serverKeyOf(String(row.uri || ""))
      var saved = service.servers.slice()
      for (var i = 0; i < saved.length; i++)
        if (Model.serverKeyOf(String(saved[i])) === key) service.forgetServer(String(saved[i]))
      statusText = "Forgot " + String(row.label || row.uri || "")
    }
    else if (action === "disconnect") service.disconnectServer(path, null, null)
    else if (action === "mount") mountDriveAndOpen(String(row.device || ""))
    else if (action === "unmount") unmountDriveRow(row, false)
    else if (action === "eject") unmountDriveRow(row, true)
    else if (action === "hidedrive") service.toggleHiddenDrive(String(row.hideKey || ""))
    else if (action === "emptytrash") askEmptyTrash()
    else if (action === "copypath") {
      service.copyToClipboardText(path)
      statusText = "Path copied"
    }
    else if (action === "properties") showPlaceProperties(row)
    else if (action === "connect") openServer(String(row.uri || ""))
    else if (action === "editserver") showDialog("connect", "Connect to a server", String(row.uri || ""), null)
  }
  function driveNotice(title, m) {
    var detail = String((m && m.message) || "")
    statusText = detail ? title + ": " + detail : title
  }
  function mountDriveAndOpen(device) {
    if (!service || !device) return
    service.mountDrive(device, function (m) {
      if (m.path) root.activePane().navigate(String(m.path))
    }, function (m) {
      root.driveNotice("Could not mount " + device, m)
    })
  }
  function unmountDriveRow(row, powerOff) {
    if (!service || row.unmountable !== true) return
    var mount = String(row.path)
    var p = activePane()
    if (p && (p.path === mount || p.path.indexOf(mount + "/") === 0)) p.navigate(home)
    if (powerOff === true) {
      service.ejectDrive(row.device)
      return
    }
    service.unmountDrive(row.device, null, function (m) {
      root.driveNotice("Could not unmount " + mount, m)
    })
  }
  function bookmarkFolders(paths) {
    service.statPaths(paths, function (items) {
      var dirs = []
      for (var i = 0; i < items.length; i++)
        if (items[i] && !items[i].error && (items[i].kind === "d" || items[i].kind === "L")) dirs.push(String(items[i].path))
      if (dirs.length === 0) {
        root.statusText = "Only folders can be bookmarked"
        return
      }
      var added = service.addBookmarks(dirs)
      root.statusText = added > 0 ? Model.formatCount(added, "folder bookmarked", "folders bookmarked") : "Already bookmarked"
    })
  }
  function showPlaceProperties(row) {
    var path = String(row.path || "")
    service.statPaths([path], function (items) {
      var info = items && items.length > 0 ? items[0] : null
      if (!info || info.error) {
        root.statusText = "Could not read " + row.label
        return
      }
      var entry = Model.decodeEntry([path === "/" ? "/" : Model.basename(path), info.kind, info.size,
        info.mtime, info.mode, info.linkTarget, path], Model.dirname(path))
      entry.placeLabel = String(row.label || "")
      entry.skipUsage = path === "/"
      root.showProperties(entry)
    })
  }
  function runAction(key) {
    if (key.indexOf("drop:") === 0) {
      var drop = pendingDrop
      var action = key.substring(5)
      closeMenu()
      if (drop && (action === "copy" || action === "move")) transferDrop(action, drop.paths, drop.dest)
      return
    }
    if (key.indexOf("zoom:") === 0) {
      runZoom(key.substring(5))
      return
    }
    if (key.indexOf("place:") === 0) {
      var row = menuEntry
      menuOpen = false
      menuKind = ""
      runPlaceAction(key.substring(6), row)
      focusZone = "pane"
      keyCatcher.forceActiveFocus()
      return
    }
    var p = activePane()
    var entry = menuEntry
    menuOpen = false
    menuKind = ""
    if (key.indexOf("sort:") === 0) applySortPreset(key.substring(5))
    else if (key.indexOf("view:") === 0) setView(key.substring(5))
    else if (key === "preview") showPreview(entry)
    else if (key === "open") p.openEntry(entry)
    else if (key === "openwith") showDialog("openwith", "Open " + (entry ? entry.name : "") + " with", "", entry)
    else if (key === "opentab") newTab(activeSide, entry.path)
    else if (key === "copy") doCopy()
    else if (key === "cut") doCut()
    else if (key === "paste") doPaste()
    else if (key === "rename") doRename()
    else if (key === "trash") doTrash()
    else if (key === "delete") askDelete(null)
    else if (key === "restore") doRestore()
    else if (key === "emptytrash") askEmptyTrash()
    else if (key === "copypath") service.copyToClipboardText(entry ? entry.path : p.path)
    else if (key === "extract") extractArchives(archiveTargets(entry))
    else if (key === "compress") askCompress(entry)
    else if (key === "properties") showProperties(entry)
    else if (key === "newfolder") showDialog("newfolder", "New folder", "untitled folder", null)
    else if (key === "newfile") showDialog("newfile", "New file", "untitled", null)
    else if (key === "bookmark") service.togglePinned(entry && entry.isDir ? entry.path : p.path)
    else if (key === "terminal") service.openTerminal(entry && entry.isDir ? entry.path : p.path)
    else if (key === "claude") service.openClaude(entry && entry.isDir ? entry.path : p.path)
    else if (key === "refresh") p.refresh()
    else if (key === "togglehidden") { p.showHidden = !p.showHidden; rememberSession() }
    else if (key === "settings") showDialog("settings", "Settings", "", null)
    else if (key === "captions") {
      settingsSection = "view"
      showDialog("settings", "Settings", "", null)
    }
    else if (key === "shortcuts") showDialog("shortcuts", "Keyboard shortcuts", "", null)
  }
  function runZoom(action) {
    if (action === "in") nudgeViewScale(0.1)
    else if (action === "out") nudgeViewScale(-0.1)
    else setViewScale(1)
  }
  property bool previewOpen: false
  property var previewEntry: null
  property string previewText: ""
  property bool previewBinary: false
  property bool previewTruncated: false
  property bool previewLoading: false
  property int previewToken: 0
  readonly property string previewKind: Model.previewKind(previewEntry)

  function showPreview(entry) {
    if (!entry) return
    var token = ++previewToken
    previewEntry = entry
    previewText = ""
    previewBinary = false
    previewTruncated = false
    previewLoading = false
    previewOpen = true
    if (Model.previewKind(entry) !== "text" || !service) return
    previewLoading = true
    service.peekFile(entry.path, 262144, function (m) {
      if (token !== root.previewToken) return
      root.previewLoading = false
      root.previewText = String(m.text || "")
      root.previewBinary = m.binary === true
      root.previewTruncated = m.truncated === true
    }, function (m) {
      if (token !== root.previewToken) return
      root.previewLoading = false
      root.previewBinary = true
    })
  }

  function togglePreview() {
    if (previewOpen) closePreview()
    else showPreview(activePane().cursorEntry())
  }

  function closePreview() {
    previewToken++
    previewOpen = false
    previewEntry = null
    previewText = ""
    keyCatcher.forceActiveFocus()
  }

  function stepPreview(delta) {
    var p = activePane()
    p.moveCursor(delta, false)
    var entry = p.cursorEntry()
    if (entry) showPreview(entry)
  }

  function handlePreviewKey(event) {
    var p = activePane()
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) { closePreview(); return true }
    if (event.key === Qt.Key_Right) { stepPreview(1); return true }
    if (event.key === Qt.Key_Left) { stepPreview(-1); return true }
    if (event.key === Qt.Key_Down) { stepPreview(p.columnsPerRow()); return true }
    if (event.key === Qt.Key_Up) { stepPreview(-p.columnsPerRow()); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      var entry = previewEntry
      closePreview()
      p.openEntry(entry)
      return true
    }
    return false
  }

  function previewDetails() {
    var entry = previewEntry
    if (!entry) return ""
    var parts = [Model.kindLabel(entry)]
    if (!entry.isDir) parts.push(Model.formatSize(entry.size))
    parts.push(Model.formatFullDate(entry.mtime))
    return parts.join("   ")
  }

  property var propsInfo: null
  property real propsBytes: 0
  property int propsFiles: 0
  property int propsDirs: 0
  property int propsDuId: 0
  property bool propsUsageDone: false
  property var propsIdentity: null
  property string propsOpenerMime: ""
  property string propsOpenerHandler: ""
  function refreshOpener(path) {
    service.openerFor(path, function (m) {
      if (root.dialogMode !== "properties") return
      root.propsOpenerMime = String(m.mime || "")
      root.propsOpenerHandler = String(m.handler || "")
    })
  }
  function chooseOpener(handler) {
    if (!handler || propsOpenerMime === "") return
    service.setOpener(propsOpenerMime, handler, function () {
      root.propsOpenerHandler = handler
    }, function (m) {
      root.statusText = "Could not change the default application"
    })
  }
  function refreshPropsInfo(path) {
    service.statPaths([path], function (items) {
      if (items && items.length > 0 && root.dialogMode === "properties") root.propsInfo = items[0]
    })
  }
  function showProperties(entry) {
    if (!entry) return
    propsInfo = null
    propsBytes = 0
    propsFiles = 0
    propsDirs = 0
    propsUsageDone = false
    propsOpenerMime = ""
    propsOpenerHandler = ""
    showDialog("properties", "Properties", "", entry)
    refreshPropsInfo(entry.path)
    if (!entry.isDir) refreshOpener(entry.path)
    if (!propsIdentity) service.identity(function (m) { root.propsIdentity = m })
    if (entry.isDir && !entry.skipUsage) {
      propsDuId = service.diskUsage(entry.path, function (m) {
        root.propsBytes = Number(m.bytes) || 0
        root.propsFiles = Number(m.files) || 0
        root.propsDirs = Number(m.dirs) || 0
      }, function () { root.propsUsageDone = true })
    }
  }
  function enterFind() {
    var p = activePane()
    if (p) p.filter = ""
    findMode = true
    pathBar.clearFilter()
    pathBar.openFilter()
  }
  function exitFind() {
    findDebounce.stop()
    findMode = false
    pathBar.closeFilter()
    var p = activePane()
    if (p) {
      p.filter = ""
      p.stopSearch()
    }
  }
  function enterSidebar() {
    if (!sidebarVisible) { sidebarVisible = true; rememberSession() }
    sidebar.keyboardActive = true
    focusZone = "sidebar"
  }

  function leaveSidebar() {
    sidebar.keyboardActive = false
    focusZone = "pane"
    keyCatcher.forceActiveFocus()
  }

  function setView(mode) {
    var p = activePane()
    if (!p || !Model.isViewMode(mode)) return
    p.view = mode
    if (service && folderViewsOn()) service.rememberFolderView(p.path, mode)
    rememberSession()
  }

  function folderViewsOn() {
    return boolSetting("rememberFolderViews", true)
  }

  function applyFolderView(side) {
    if (!service || !folderViewsOn()) return
    var p = paneFor(side)
    p.view = service.viewForFolder(p.path, String(service.settingNow("defaultView", "list")))
  }

  function viewGlyph() {
    var p = activePane()
    var mode = p ? p.view : "list"
    for (var i = 0; i < Model.viewModes.length; i++)
      if (Model.viewModes[i].key === mode) return Model.viewModes[i].glyph
    return "list"
  }

  function applySortPreset(key) {
    var preset = Model.sortPreset(key)
    var p = activePane()
    if (!preset || !p) return
    p.setSortOrder(preset.sortBy, preset.descending)
    rememberSession()
  }

  function toolbarMenuActions(kind) {
    var p = activePane()
    var items = []
    var check = Icons.actionGlyph("check")
    if (kind === "main") {
      items.push({ key: "settings", label: "Settings", glyph: Icons.actionGlyph("settings"), hint: "Ctrl+," })
      items.push({ key: "shortcuts", label: "Keyboard shortcuts", glyph: Icons.actionGlyph("keyboard"), hint: "F1" })
      return items
    }
    var mode = p ? p.view : "list"
    var viewHints = { list: "Ctrl+1", grid: "Ctrl+2", compact: "Ctrl+3", gallery: "Ctrl+4" }
    for (var j = 0; j < Model.viewModes.length; j++) {
      var view = Model.viewModes[j]
      items.push({ key: "view:" + view.key, label: view.label, hint: viewHints[view.key] || "",
        glyph: view.key === mode ? check : Icons.actionGlyph(view.glyph) })
    }
    items.push({ label: "" })
    items.push({ key: "zoom:reset", kind: "zoom", label: "Zoom" })
    items.push({ label: "" })
    items.push({ kind: "header", label: "Sort by", disabled: true })
    var current = p ? Model.sortPresetKey(p.sortBy, p.descending) : ""
    for (var i = 0; i < Model.sortPresets.length; i++) {
      var preset = Model.sortPresets[i]
      items.push({ key: "sort:" + preset.key, label: preset.label,
        glyph: preset.key === current ? check : "", disabled: !p || p.virtualView })
    }
    items.push({ label: "" })
    items.push({ key: "togglehidden", label: "Show hidden files", hint: "Ctrl+H",
      glyph: p && p.showHidden ? check : Icons.actionGlyph("hidden") })
    items.push({ key: "captions", label: "Grid captions\u2026", glyph: Icons.actionGlyph("properties") })
    return items
  }
  function menuWidth() {
    return Style.space(230)
  }

  function openToolbarMenu(kind, anchor) {
    if (menuOpen && menuKind === kind) {
      closeMenu()
      return
    }
    menuEntry = null
    menuKind = kind
    menuActions = toolbarMenuActions(kind)
    menuCursor = -1
    var pt = anchor.mapToItem(keyCatcher, 0, anchor.height)
    menuX = pt.x + anchor.width - menuWidth()
    menuY = pt.y + Style.space(4)
    menuOpen = true
  }

  function paneAt(x, y) {
    if (split) {
      var pt = paneB.mapFromItem(keyCatcher, x, y)
      if (pt.x >= 0 && pt.y >= 0 && pt.x <= paneB.width && pt.y <= paneB.height) return 1
    }
    return 0
  }

  function mouseNavigate(button, x, y) {
    if (dialogMode !== "" || confirm.opened || previewOpen) return
    menuOpen = false
    activeSide = paneAt(x, y)
    var p = activePane()
    if (button === Qt.BackButton || button === Qt.ExtraButton4) p.goBack()
    else p.goForward()
  }

  function cycleTab(delta) {
    var list = tabsFor(activeSide)
    if (list.length < 2) return
    var index = activeIndexFor(activeSide) + delta
    if (index < 0) index = list.length - 1
    if (index >= list.length) index = 0
    selectTab(activeSide, index)
  }

  function openCursorInNewTab() {
    var entry = activePane().cursorEntry()
    if (entry && entry.isDir) newTab(activeSide, entry.path)
  }

  function toggleBookmarkHere() {
    if (!service) return
    var p = activePane()
    var entry = p.cursorEntry()
    var target = (entry && entry.isDir) ? entry.path : p.path
    service.togglePinned(target)
    statusText = isBookmarked(target) ? "Bookmarked" : "Bookmark removed"
  }

  function doUndo() {
    if (!service) return
    service.undo(function (entry) {
      root.statusText = "Undone: " + String(entry.label || "")
      root.refreshPanes()
    }, function (m) {
      root.statusText = String(m.message || "Nothing to undo")
    })
  }

  function doRedo() {
    if (!service) return
    service.redo(function (entry) {
      root.statusText = "Redone: " + String(entry.label || "")
      root.refreshPanes()
    }, function (m) {
      root.statusText = String(m.message || "Nothing to redo")
    })
  }

  function refreshPanes() {
    paneA.refresh()
    if (split) paneB.refresh()
  }

  property int openConfirmLimit: 5

  function openSelectedItems() {
    var p = activePane()
    var sel = p.selectedEntries
    if (sel.length <= 1 || picking) { p.activateCursor(); return }
    if (sel.length > openConfirmLimit) {
      confirmAction = "openmany"
      confirm.message = "Open " + Model.formatCount(sel.length, "item", "items") + "?"
      confirm.confirmText = "Open"
      dialogPayload = sel
      confirm.opened = true
      return
    }
    openEntries(sel)
  }

  function openEntries(sel) {
    var dirs = []
    var archives = []
    for (var i = 0; i < sel.length; i++) {
      if (sel[i].isDir && !sel[i].isBroken) dirs.push(sel[i].path)
      else if (extractsOnOpen(sel[i])) archives.push(sel[i])
      else if (service) service.openExternally(sel[i].path)
    }
    for (var d = 0; d < dirs.length; d++) newTab(activeSide, dirs[d])
    extractArchives(archives)
    if (archives.length < sel.length) afterLaunch()
  }

  function openFolderMenu() {
    menuKind = ""
    menuEntry = null
    menuActions = contextActions(null)
    menuCursor = firstMenuIndex()
    menuX = (sidebarVisible ? sidebar.width : 0) + Style.space(60) + (activeSide === 1 ? sideA.width : 0)
    menuY = toolbar.height + Style.space(20)
    menuOpen = true
  }

  function searchEverywhere() {
    var p = activePane()
    if (p.path !== home) p.navigate(home)
    enterFind()
    statusText = "Searching your home folder"
  }

  function openMenuAtCursor() {
    var p = activePane()
    var entry = p.cursorEntry()
    menuKind = ""
    menuEntry = entry
    menuActions = contextActions(entry)
    menuCursor = firstMenuIndex()
    var row = Math.max(0, p.cursorIndex)
    menuX = (sidebarVisible ? sidebar.width : 0) + Style.space(60)
      + (activeSide === 1 ? sideA.width : 0)
    var trashBar = activeSide === 1 ? trashBarB : trashBarA
    menuY = toolbar.height + Style.space(40) + Math.min(row, 18) * Style.space(22)
      + (trashBar.visible ? trashBar.height : 0)
    menuOpen = true
  }

  function refreshEntryMenu() {
    if (!menuOpen || menuKind !== "" || !menuEntry) return
    var current = menuCursor >= 0 && menuCursor < menuActions.length ? menuActions[menuCursor].key : ""
    menuActions = contextActions(menuEntry)
    if (current === "trash" || current === "delete") current = shiftHeld ? "delete" : "trash"
    menuCursor = -1
    for (var i = 0; i < menuActions.length; i++) if (current !== "" && menuActions[i].key === current) menuCursor = i
  }

  function closeMenu() {
    menuOpen = false
    menuKind = ""
    menuCursor = -1
    keyCatcher.forceActiveFocus()
  }

  function firstMenuIndex() {
    for (var i = 0; i < menuActions.length; i++)
      if (menuActions[i].label !== "" && !menuActions[i].disabled) return i
    return -1
  }

  function lastMenuIndex() {
    for (var i = menuActions.length - 1; i >= 0; i--)
      if (menuActions[i].label !== "" && !menuActions[i].disabled) return i
    return -1
  }

  function moveMenuCursor(delta) {
    if (menuActions.length === 0) return
    var index = menuCursor
    for (var step = 0; step < menuActions.length; step++) {
      index = index + delta
      if (index < 0) index = menuActions.length - 1
      if (index >= menuActions.length) index = 0
      var item = menuActions[index]
      if (item.label !== "" && !item.disabled) { menuCursor = index; return }
    }
  }

  function activateMenuCursor() {
    if (menuCursor < 0 || menuCursor >= menuActions.length) return
    var item = menuActions[menuCursor]
    if (!item || item.label === "" || item.disabled) return
    if (item.kind === "zoom") {
      runAction(item.key)
      return
    }
    menuCursor = -1
    runAction(item.key)
    keyCatcher.forceActiveFocus()
  }

  function moveAppCursor(delta) {
    var list = filteredApps()
    var floor = canRunTyped ? -1 : 0
    if (list.length === 0) {
      appCursor = floor
      return
    }
    appCursor = Math.max(floor, Math.min(list.length - 1, appCursor + delta))
  }

  function runTypedCommand() {
    var entry = dialogPayload
    var typed = appFilter
    closeDialog()
    if (!entry || !service) return
    service.runCommandOn(typed, entry.path)
    afterLaunch()
  }

  function chooseApp() {
    var list = filteredApps()
    if (canRunTyped && (appCursor < 0 || list.length === 0)) {
      runTypedCommand()
      return
    }
    if (appCursor < 0 || appCursor >= list.length) return
    launchApp(list[appCursor])
  }

  function launchApp(app) {
    if (!app) return
    var command = Array.prototype.slice.call(app.command || [])
    var inTerminal = app.runInTerminal === true
    var entry = dialogPayload
    closeDialog()
    if (!entry || !service) return
    service.openWith(command, entry.path, inTerminal)
    if (appAlways && app.id && !entry.isDir)
      service.setDefaultApp(entry.path, String(app.id), null, function (m) {
        root.statusText = "Could not set the default app: " + String((m && m.message) || "")
      })
    afterLaunch()
  }

  function handleKey(event) {
    if (confirm.opened) return confirm.handleKey(event)
    if (dialogMode === "conflict") {
      if (event.key === Qt.Key_Escape) { resolveConflict("skip", false); return true }
      if (event.key === Qt.Key_R) { resolveConflict("overwrite", false); return true }
      if (event.key === Qt.Key_K) { resolveConflict("rename", false); return true }
      if (event.key === Qt.Key_S) { resolveConflict("skip", false); return true }
      if (event.key === Qt.Key_A) { resolveConflict("skip", true); return true }
      return true
    }
    if (dialogMode !== "") return handleDialogKey(event)
    if (previewOpen) return handlePreviewKey(event)
    if (menuOpen) return handleMenuKey(event)
    if (focusZone === "sidebar") return handleSidebarKey(event)
    return handlePaneKey(event)
  }

  function handleDialogKey(event) {
    if (event.key === Qt.Key_Escape) {
      closeDialog()
      return true
    }
    if (dialogMode === "openwith") {
      if (event.key === Qt.Key_Down) { moveAppCursor(1); return true }
      if (event.key === Qt.Key_Up) { moveAppCursor(-1); return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { chooseApp(); return true }
    }
    if (dialogMode === "settings" || dialogMode === "shortcuts" || dialogMode === "properties") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { closeDialog(); return true }
    }
    return false
  }

  function handleMenuKey(event) {
    if (event.key === Qt.Key_Escape) { closeMenu(); return true }
    if (event.key === Qt.Key_Down) { moveMenuCursor(1); return true }
    if (event.key === Qt.Key_Up) { moveMenuCursor(-1); return true }
    if (event.key === Qt.Key_Home) { menuCursor = firstMenuIndex(); return true }
    if (event.key === Qt.Key_End) { menuCursor = lastMenuIndex(); return true }
    if (menuKind === "view") {
      var onZoom = menuCursor >= 0 && menuCursor < menuActions.length
        && menuActions[menuCursor].kind === "zoom"
      if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || (onZoom && event.key === Qt.Key_Right)) {
        runZoom("in")
        return true
      }
      if (event.key === Qt.Key_Minus || (onZoom && event.key === Qt.Key_Left)) {
        runZoom("out")
        return true
      }
      if (event.key === Qt.Key_0) { runZoom("reset"); return true }
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      activateMenuCursor()
      return true
    }
    return true
  }

  function handleSidebarKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape) { leaveSidebar(); return true }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { leaveSidebar(); return true }
    if (event.key === Qt.Key_Right) { leaveSidebar(); return true }
    if (event.key === Qt.Key_Down) { sidebar.moveCursor(1); return true }
    if (event.key === Qt.Key_Up) { sidebar.moveCursor(-1); return true }
    if (event.key === Qt.Key_Home) { sidebar.cursorIndex = 0; return true }
    if (event.key === Qt.Key_End) { sidebar.cursorIndex = sidebar.flatRows.length - 1; return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      sidebar.activateCursor(ctrl)
      if (!ctrl) leaveSidebar()
      return true
    }
    if (event.key === Qt.Key_Delete) { sidebar.removeCursor(); return true }
    if (ctrl && event.key === Qt.Key_B) { sidebarVisible = false; leaveSidebar(); return true }
    return true
  }

  function handlePaneKey(event) {
    var p = activePane()
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shiftKey = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (p.searching || findMode) { exitFind(); return true }
      if (p.filter !== "" || pathBar.filterOpen) { pathBar.closeFilter(); return true }
      if (p.selectedCount > 0) { p.clearSelection(); return true }
      if (picking) { cancelPick(); return true }
      if (popupMode) requestClose()
      return true
    }

    if (event.key === Qt.Key_Tab && !ctrl) {
      if (shiftKey) { enterSidebar(); return true }
      if (split) { activeSide = otherSide(); return true }
      enterSidebar()
      return true
    }
    if (event.key === Qt.Key_Backtab) { enterSidebar(); return true }

    if (event.key === Qt.Key_Menu || (shiftKey && event.key === Qt.Key_F10)) {
      openMenuAtCursor()
      return true
    }
    if (event.key === Qt.Key_F10) { openFolderMenu(); return true }
    if (event.key === Qt.Key_F9) { sidebarVisible = !sidebarVisible; rememberSession(); return true }

    if (ctrl && shiftKey && event.key === Qt.Key_T) { restoreClosedTab(); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_F) { searchEverywhere(); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_PageUp) { moveTab(-1); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_PageDown) { moveTab(1); return true }
    if (ctrl && (event.key === Qt.Key_Question || (shiftKey && event.key === Qt.Key_Slash))) {
      showDialog("shortcuts", "Keyboard shortcuts", "", null)
      return true
    }
    if (alt && !ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) { jumpToTab(event.key - Qt.Key_1); return true }
    if (alt && event.key === Qt.Key_Down) { openSelectedItems(); return true }

    if (ctrl && shiftKey && event.key === Qt.Key_N) { showDialog("newfolder", "New folder", "untitled folder", null); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_C) { transferToOtherPane("copy"); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_M) { transferToOtherPane("move"); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_I) { p.invertSelection(); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_Z) { doRedo(); return true }

    if (ctrl && event.key === Qt.Key_N) { showDialog("newfile", "New file", "untitled", null); return true }
    if (ctrl && event.key === Qt.Key_O) { openSelectedItems(); return true }
    if (ctrl && event.key === Qt.Key_T) { newTab(activeSide, null); return true }
    if (ctrl && event.key === Qt.Key_Period) { if (!p.virtualView) service.openTerminal(p.path); return true }
    if (ctrl && event.key === Qt.Key_W) { closeTab(activeSide, activeIndexFor(activeSide)); return true }
    if (ctrl && event.key === Qt.Key_Q) { requestClose(); return true }
    if (ctrl && event.key === Qt.Key_L) { pathBar.beginEdit(); return true }
    if (ctrl && event.key === Qt.Key_H) { p.showHidden = !p.showHidden; rememberSession(); return true }
    if (ctrl && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) { nudgeViewScale(0.1); return true }
    if (ctrl && event.key === Qt.Key_Minus) { nudgeViewScale(-0.1); return true }
    if (ctrl && event.key === Qt.Key_0) { setViewScale(1); return true }
    if (ctrl && event.key === Qt.Key_A) { p.selectAll(); return true }
    if (ctrl && event.key === Qt.Key_C) { doCopy(); return true }
    if (ctrl && event.key === Qt.Key_X) { doCut(); return true }
    if (ctrl && event.key === Qt.Key_V) { doPaste(); return true }
    if (ctrl && event.key === Qt.Key_F) { root.enterFind(); return true }
    if (ctrl && event.key === Qt.Key_R) { p.refresh(); return true }
    if (ctrl && event.key === Qt.Key_B) { sidebarVisible = !sidebarVisible; rememberSession(); return true }
    if (ctrl && event.key === Qt.Key_D) { toggleBookmarkHere(); return true }
    if (ctrl && event.key === Qt.Key_Z) { doUndo(); return true }
    if (ctrl && event.key === Qt.Key_I) { showProperties(p.cursorEntry()); return true }
    if (ctrl && event.key === Qt.Key_Space) { p.toggleCursorSelection(); return true }
    if (ctrl && event.key === Qt.Key_Comma) { showDialog("settings", "Settings", "", null); return true }
    if (ctrl && event.key === Qt.Key_1) { setView("list"); return true }
    if (ctrl && event.key === Qt.Key_2) { setView("grid"); return true }
    if (ctrl && event.key === Qt.Key_3) { setView("compact"); return true }
    if (ctrl && event.key === Qt.Key_4) { setView("gallery"); return true }
    if (ctrl && event.key === Qt.Key_PageDown) { cycleTab(1); return true }
    if (ctrl && event.key === Qt.Key_PageUp) { cycleTab(-1); return true }
    if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { openCursorInNewTab(); return true }

    if (event.key === Qt.Key_F1) { showDialog("shortcuts", "Keyboard shortcuts", "", null); return true }
    if (event.key === Qt.Key_F2) { doRename(); return true }
    if (event.key === Qt.Key_F5) { p.refresh(); return true }
    if (event.key === Qt.Key_F6) { toggleSplit(); return true }

    if (alt && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { showProperties(p.cursorEntry()); return true }
    if (alt && event.key === Qt.Key_Left) { p.goBack(); return true }
    if (alt && event.key === Qt.Key_Right) { p.goForward(); return true }
    if (alt && event.key === Qt.Key_Up) { p.goUp(); return true }
    if (alt && event.key === Qt.Key_Home) { p.navigate(home); return true }

    if (event.key === Qt.Key_Delete) {
      if (shiftKey) askDelete(null)
      else doTrash()
      return true
    }
    if (event.key === Qt.Key_Backspace) { if (!p.virtualView) p.goUp(); return true }

    if (event.key === Qt.Key_Slash) { pathBar.beginEditWith("/"); return true }
    if (event.key === Qt.Key_AsciiTilde) { pathBar.beginEditWith("~"); return true }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { openSelectedItems(); return true }
    if (event.key === Qt.Key_Space) { togglePreview(); return true }
    if (event.key === Qt.Key_Down) { p.moveCursor(p.columnsPerRow(), shiftKey); return true }
    if (event.key === Qt.Key_Up) { p.moveCursor(-p.columnsPerRow(), shiftKey); return true }
    if (event.key === Qt.Key_Right && p.view !== "list") { p.moveCursor(1, shiftKey); return true }
    if (event.key === Qt.Key_Left && p.view !== "list") { p.moveCursor(-1, shiftKey); return true }
    if (event.key === Qt.Key_PageDown) { p.moveCursor(12, shiftKey); return true }
    if (event.key === Qt.Key_PageUp) { p.moveCursor(-12, shiftKey); return true }
    if (event.key === Qt.Key_Home) { p.jumpCursor(0, shiftKey); return true }
    if (event.key === Qt.Key_End) { p.jumpCursor(p.rows.length - 1, shiftKey); return true }

    if (!ctrl && !alt && event.text && event.text.length === 1 && event.text >= " ") {
      root.enterFind()
      pathBar.seedFilter(event.text)
      return true
    }
    return false
  }
  Timer {
    id: selectTimer
    interval: 260
    repeat: false
    property string pendingName: ""
    property var pendingPane: null
    onTriggered: {
      if (!pendingPane || !pendingName) return
      pendingPane.focusName(pendingName)
      pendingName = ""
      pendingPane = null
    }
  }

  Timer {
    id: findDebounce
    interval: 320
    repeat: false
    onTriggered: {
      if (!root.findMode) return
      root.activePane().startSearch(pathBar.filterText)
    }
  }
  property bool sessionRestored: false
  function ensureSession() {
    if (sessionRestored) return
    sessionRestored = true
    restoreSession()
  }
  onServiceChanged: {
    if (!service) return
    ensureSession()
    if (paneA.path && paneA.rows.length === 0 && !paneA.loading) paneA.reload()
    if (root.split && paneB.path && paneB.rows.length === 0 && !paneB.loading) paneB.reload()
  }
  Connections {
    target: root.service
    enabled: root.service !== null
    function onConflictRaised(jobId, info) {
      root.showDialog("conflict", "File exists", "", { jobId: jobId, info: info })
    }
  }
  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    // Some xkb options (shift:both_capslock_cancel) report the Shift release as another key,
    // so the release is matched on the scan code of the press.
    property int shiftScanCode: -1
    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Shift) shiftScanCode = event.nativeScanCode
      root.shiftHeld = (event.modifiers & Qt.ShiftModifier) !== 0 || event.key === Qt.Key_Shift
      if (root.handleKey(event)) event.accepted = true
    }
    Keys.onReleased: function (event) {
      if (event.key === Qt.Key_Shift || (shiftScanCode > 0 && event.nativeScanCode === shiftScanCode)) {
        shiftScanCode = -1
        root.shiftHeld = false
      }
    }
    onActiveFocusChanged: if (!activeFocus) root.shiftHeld = false

    Column {
      anchors.fill: parent
      spacing: 0

      Rectangle {
        id: toolbar
        width: parent.width
        height: Style.space(38)
        color: Util.alpha(Color.foreground, 0.04)

        Row {
          id: navButtons
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Button {
            iconText: Icons.actionGlyph("back")
            tooltipText: "Back"
            enabled: root.activePane() ? root.activePane().canGoBack : false
            opacity: enabled ? 1 : 0.35
            onClicked: root.activePane().goBack()
          }

          Button {
            iconText: Icons.actionGlyph("forward")
            tooltipText: "Forward"
            enabled: root.activePane() ? root.activePane().canGoForward : false
            opacity: enabled ? 1 : 0.35
            onClicked: root.activePane().goForward()
          }

          Button {
            iconText: Icons.actionGlyph("up")
            tooltipText: "Up"
            onClicked: root.activePane().goUp()
          }
        }

        Row {
          id: rightControls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Button {
            id: viewButton
            objectName: "viewButton"
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph(root.viewGlyph())
            tooltipText: "View, zoom and sort"
            selected: root.menuOpen && root.menuKind === "view"
            onClicked: root.openToolbarMenu("view", viewButton)
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("copy")
            visible: root.split && root.activePane() !== null
              && root.activePane().selectedCount > 0
            tooltipText: "Copy the selection to the other pane"
            onClicked: root.transferToOtherPane("copy")
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("split")
            tooltipText: root.split ? "Close the second pane" : "Split into two panes"
            selected: root.split
            onClicked: root.toggleSplit()
          }

          Button {
            id: mainMenuButton
            objectName: "mainMenuButton"
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("menu")
            tooltipText: "Menu"
            selected: root.menuOpen && root.menuKind === "main"
            onClicked: root.openToolbarMenu("main", mainMenuButton)
          }
        }

        PathBar {
          id: pathBar
          objectName: "pathBar"
          onFilesDropped: function (urls, target, position) { root.handleDrop(urls, target, position) }
          anchors.left: navButtons.right
          anchors.right: rightControls.left
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          path: root.activePane() ? root.activePane().path : ""
          home: root.home
          findMode: root.findMode

          onNavigate: function (target) {
            root.activePane().navigate(target)
            keyCatcher.forceActiveFocus()
          }

          onFilterEdited: function (text) {
            if (root.findMode) {
              findDebounce.restart()
              return
            }
            var p = root.activePane()
            if (p) p.filter = text
          }

          onSearchSubmitted: function (text) {
            if (!root.findMode) return
            findDebounce.stop()
            root.activePane().startSearch(text)
          }

          onDismissed: {
            root.exitFind()
            keyCatcher.forceActiveFocus()
          }

          onEditingFinished: keyCatcher.forceActiveFocus()
        }
      }

      Row {
        width: parent.width
        height: parent.height - toolbar.height - statusBar.height
          - (pickBar.visible ? pickBar.height : 0)
        spacing: 0

        SidebarPlaces {
          id: sidebar
          objectName: "sidebar"
          width: root.sidebarVisible ? Style.space(190) : 0
          height: parent.height
          visible: root.sidebarVisible
          service: root.service
          currentPath: root.activePane() ? root.activePane().path : ""
          showDrives: root.service ? root.service.settingNow("showDrives", true) !== false : true
          onNavigate: function (target) {
            pathBar.endEdit()
            root.activePane().navigate(target)
            keyCatcher.forceActiveFocus()
          }
          onOpenInNewTab: function (target) { root.newTab(root.activeSide, target) }
          onRemoveBookmark: function (target) { root.service.togglePinned(target) }
          onDropRequested: function (urls, dest, position) { root.handleDrop(urls, dest, position) }
          onHideDrive: function (key) { root.service.toggleHiddenDrive(key) }
          onMountDrive: function (device) { root.mountDriveAndOpen(device) }
          onPlaceMenuRequested: function (row, x, y) { root.openPlaceMenu(row, x, y) }
          onBookmarkDropped: function (paths) { root.bookmarkFolders(paths) }
          onShowAllDrives: root.showDialog("settings", "Settings", "", null)
          onConnectServer: function (uri) { root.openServer(String(uri || "")) }
          onDisconnectServer: function (path) {
            if (root.service) root.service.disconnectServer(path, null, null)
          }
        }

        Row {
          id: panesRow
          width: parent.width - (root.sidebarVisible ? sidebar.width : 0)
          height: parent.height
          spacing: Style.space(2)

          Column {
            id: sideA
            width: root.split ? (panesRow.width - Style.space(2)) / 2 : panesRow.width
            height: parent.height
            spacing: 0

            TabStrip {
              id: tabStripA
              width: parent.width
              tabs: root.tabsA
              activeIndex: root.activeA
              visible: root.tabsA.length > 1 || root.split
              onSelectTab: function (index) { root.selectTab(0, index) }
              onCloseTab: function (index) { if (root.tabsA.length > 1) root.closeTab(0, index) }
              onAddTab: root.newTab(0, null)
            }

            TrashBar {
              id: trashBarA
              objectName: "trashBarA"
              width: parent.width
              visible: root.paneInTrash(paneA)
              service: root.service
              onEmptyRequested: {
                root.activeSide = 0
                root.askEmptyTrash()
              }
            }

            PaneView {
              id: paneA
              width: parent.width
              patterns: root.picking ? root.pickPatterns() : []
              height: parent.height - (tabStripA.visible ? tabStripA.height : 0)
                - (trashBarA.visible ? trashBarA.height : 0)
              service: root.service
              viewScale: root.viewScale
              captions: root.gridCaptions
              active: root.activeSide === 0
              onActivated: {
                root.activeSide = 0
                pathBar.endEdit()
                keyCatcher.forceActiveFocus()
              }
              onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
              onNewTabRequested: function (path) { root.newTab(0, path) }
              onNavigated: function (p) { root.applyFolderView(0); root.rememberSession() }
              onDropRequested: function (urls, dest, position) { root.handleDrop(urls, dest, position) }
              onZoomRequested: function (delta) { root.nudgeViewScale(delta) }
              onContextRequested: function (entry, x, y) {
                root.menuKind = ""
                root.menuEntry = entry
                root.menuActions = root.contextActions(entry)
                root.menuCursor = -1
                root.menuX = x + (root.sidebarVisible ? sidebar.width : 0)
                root.menuY = y + toolbar.height + (tabStripA.visible ? tabStripA.height : 0)
                  + (trashBarA.visible ? trashBarA.height : 0)
                root.menuOpen = true
              }
            }
          }

          Column {
            id: sideB
            width: root.split ? (panesRow.width - Style.space(2)) / 2 : 0
            height: parent.height
            visible: root.split
            spacing: 0

            TabStrip {
              id: tabStripB
              width: parent.width
              tabs: root.tabsB
              activeIndex: root.activeB
              visible: root.tabsB.length > 1 || root.split
              onSelectTab: function (index) { root.selectTab(1, index) }
              onCloseTab: function (index) { if (root.tabsB.length > 1) root.closeTab(1, index) }
              onAddTab: root.newTab(1, null)
            }

            TrashBar {
              id: trashBarB
              objectName: "trashBarB"
              width: parent.width
              visible: root.paneInTrash(paneB)
              service: root.service
              onEmptyRequested: {
                root.activeSide = 1
                root.askEmptyTrash()
              }
            }

            PaneView {
              id: paneB
              width: parent.width
              patterns: root.picking ? root.pickPatterns() : []
              height: parent.height - (tabStripB.visible ? tabStripB.height : 0)
                - (trashBarB.visible ? trashBarB.height : 0)
              service: root.service
              viewScale: root.viewScale
              captions: root.gridCaptions
              active: root.activeSide === 1
              onActivated: {
                root.activeSide = 1
                pathBar.endEdit()
                keyCatcher.forceActiveFocus()
              }
              onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
              onNewTabRequested: function (path) { root.newTab(1, path) }
              onNavigated: function (p) { root.applyFolderView(1); root.rememberSession() }
              onDropRequested: function (urls, dest, position) { root.handleDrop(urls, dest, position) }
              onZoomRequested: function (delta) { root.nudgeViewScale(delta) }
              onContextRequested: function (entry, x, y) {
                root.menuKind = ""
                root.menuEntry = entry
                root.menuActions = root.contextActions(entry)
                root.menuCursor = -1
                root.menuX = x + (root.sidebarVisible ? sidebar.width : 0) + sideA.width
                root.menuY = y + toolbar.height + (tabStripB.visible ? tabStripB.height : 0)
                  + (trashBarB.visible ? trashBarB.height : 0)
                root.menuOpen = true
              }
            }
          }
        }
      }

      Rectangle {
        id: pickBar
        objectName: "pickBar"
        width: parent.width
        height: Style.space(48)
        visible: root.picking
        color: Util.alpha(Color.accent, 0.08)

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: Util.alpha(Color.accent, 0.35)
        }

        Row {
          id: pickLeft
          anchors.left: parent.left
          anchors.right: pickRight.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            id: pickTitleText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, pickLeft.width * (root.pickNeedsName ? 0.35 : 1))
            text: root.pickTitle()
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          TextField {
            id: pickNameField
            objectName: "pickNameField"
            anchors.verticalCenter: parent.verticalCenter
            width: pickLeft.width - pickTitleText.width - pickLeft.spacing
            visible: root.pickNeedsName
            placeholderText: "File name"
            onAccepted: root.acceptPick(null)
            Keys.onEscapePressed: root.cancelPick()
          }
        }

        Row {
          id: pickRight
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Dropdown {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(190)
            visible: root.pickFilters().length > 0
            showLabel: false
            value: String(root.pickFilter)
            options: {
              var list = root.pickFilters()
              var out = []
              for (var i = 0; i < list.length; i++) out.push({ label: String(list[i].name || "Filter"), value: String(i) })
              return out
            }
            onChanged: function (v) { root.pickFilter = Number(v) }
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "Cancel"
            bordered: true
            onClicked: root.cancelPick()
          }

          Button {
            objectName: "pickAccept"
            anchors.verticalCenter: parent.verticalCenter
            text: root.pickAcceptLabel()
            bordered: true
            selected: true
            onClicked: root.acceptPick(null)
          }
        }
      }

      Rectangle {
        id: statusBar
        width: parent.width
        height: Style.space(24)
        color: Util.alpha(Color.foreground, 0.04)

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var p = root.activePane()
              if (!p) return ""
              if (p.loading)
                return Model.formatCount(p.rows.length, "item", "items") + ", reading"
              if (p.selectedCount > 0)
                return Model.selectionSummary(p.selectedEntries)
              if (p.searching)
                return Model.formatCount(p.rows.length, "match", "matches")
                  + (p.searchTruncated ? " (truncated)" : "")
              return Model.formatCount(p.rows.length, "item", "items")
            }
            color: Util.alpha(Color.foreground, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Rectangle {
          id: transferChip
          objectName: "transferChip"
          anchors.right: helperErrorText.visible ? helperErrorText.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.transferCount > 0
          width: chipRow.implicitWidth + Style.space(14)
          height: Style.space(18)
          radius: Style.cornerRadius
          color: root.transfersOpen ? Util.alpha(Color.accent, 0.2)
            : (chipHover.hovered ? Util.alpha(Color.foreground, 0.1) : "transparent")

          HoverHandler { id: chipHover }

          MouseArea {
            anchors.fill: parent
            onClicked: root.showTransfers(!root.transfersOpen)
          }

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Icons.actionGlyph(root.runningTransfers > 0 ? "copy" : "check")
              color: root.runningTransfers > 0 ? Color.accent : Util.alpha(Color.foreground, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.runningTransfers > 0
              width: Style.space(48)
              height: Style.space(4)
              radius: height / 2
              color: Util.alpha(Color.foreground, 0.15)

              Rectangle {
                width: parent.width * (root.service ? root.service.transferFraction : 0)
                height: parent.height
                radius: parent.radius
                color: Color.accent
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.runningTransfers > 0
                ? Model.formatCount(root.runningTransfers, "transfer", "transfers")
                : Model.formatCount(root.transferCount, "transfer done", "transfers done")
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Icons.actionGlyph(root.transfersOpen ? "chevronDown" : "chevronUp")
              color: Util.alpha(Color.foreground, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          id: helperErrorText
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          visible: text !== ""
          text: root.service ? (root.service.bookmarksError || root.service.helperError || "") : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    TransferBar {
      objectName: "transferPanel"
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      service: root.service
      visible: root.transfersOpen && root.transferCount > 0
      onMinimizeRequested: root.showTransfers(false)
    }

    MouseArea {
      objectName: "sideButtons"
      anchors.fill: parent
      acceptedButtons: Qt.BackButton | Qt.ForwardButton | Qt.ExtraButton3 | Qt.ExtraButton4
      onPressed: function (mouse) { root.mouseNavigate(mouse.button, mouse.x, mouse.y) }
    }

    MouseArea {
      anchors.fill: parent
      visible: root.menuOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: root.closeMenu()
    }

    Rectangle {
      id: contextMenu
      visible: root.menuOpen
      x: Math.max(0, Math.min(root.menuX, keyCatcher.width - width - Style.space(8)))
      y: Math.max(0, Math.min(root.menuY, keyCatcher.height - height - Style.space(8)))
      width: root.menuWidth()
      height: menuColumn.implicitHeight + Style.space(8)
      color: Color.menu.background
      border.width: Math.max(1, Style.space(1))
      border.color: Color.menu.border
      radius: Style.cornerRadius

      Column {
        id: menuColumn
        anchors.fill: parent
        anchors.margins: Style.space(4)
        spacing: 0

        Repeater {
          model: root.menuOpen ? root.menuActions : []

          delegate: Item {
            id: menuRow
            required property var modelData
            required property int index
            readonly property bool isHeader: modelData.kind === "header"
            readonly property bool isZoom: modelData.kind === "zoom"
            readonly property bool highlighted: !modelData.disabled && !isHeader
              && (root.menuCursor === index || (itemHover.hovered && !isZoom))
            width: menuColumn.width
            height: modelData.label === "" ? Style.space(7)
              : (isHeader ? Style.space(20) : Style.space(24))

            Rectangle {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              height: 1
              visible: modelData.label === ""
              color: Util.alpha(Color.menu.text, 0.15)
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(2)
              visible: menuRow.isHeader
              text: modelData.label
              color: Util.alpha(Color.menu.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.fill: parent
              visible: modelData.label !== "" && !menuRow.isHeader
              radius: Style.cornerRadius
              color: menuRow.highlighted ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: itemHover }

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  horizontalAlignment: Text.AlignHCenter
                  text: menuRow.isZoom ? Icons.actionGlyph("search") : (modelData.glyph || "")
                  color: Util.alpha(Color.menu.text, modelData.disabled ? 0.3 : 0.7)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconSmall
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: modelData.disabled
                    ? Util.alpha(Color.menu.text, 0.35)
                    : (menuRow.highlighted ? Color.menu.selectedText : Color.menu.text)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                visible: !menuRow.isZoom && !!modelData.hint
                text: modelData.hint || ""
                color: Util.alpha(menuRow.highlighted ? Color.menu.selectedText : Color.menu.text, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData.disabled && !menuRow.isZoom
                onClicked: root.runAction(modelData.key)
              }

              Row {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                visible: menuRow.isZoom
                spacing: Style.space(2)

                Repeater {
                  model: menuRow.isZoom ? [
                    { action: "out", text: "\u2212", wide: false },
                    { action: "reset", text: "", wide: true },
                    { action: "in", text: "+", wide: false }
                  ] : []

                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool atLimit: (modelData.action === "out" && root.viewScale <= root.minViewScale)
                      || (modelData.action === "in" && root.viewScale >= root.maxViewScale)
                    objectName: "zoom-" + modelData.action
                    width: Style.space(modelData.wide ? 44 : 22)
                    height: Style.space(20)
                    radius: Style.cornerRadius
                    color: zoomHover.hovered && !atLimit ? Util.alpha(Color.menu.text, 0.12) : "transparent"

                    HoverHandler { id: zoomHover }

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: modelData.wide ? Math.round(root.viewScale * 100) + "%" : modelData.text
                      color: Util.alpha(menuRow.highlighted ? Color.menu.selectedText : Color.menu.text,
                        parent.atLimit ? 0.3 : 1)
                      font.family: Style.font.family
                      font.pixelSize: modelData.wide ? Style.font.caption : Style.font.bodySmall
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: !parent.atLimit
                      onClicked: root.runZoom(modelData.action)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Rectangle {
      id: previewScrim
      objectName: "previewScrim"
      anchors.fill: parent
      visible: root.previewOpen
      color: Util.alpha(Color.background, 0.7)

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closePreview()
      }

      Rectangle {
        id: previewCard
        anchors.centerIn: parent
        width: Math.max(Style.space(240), parent.width - Style.space(60))
        height: Math.max(Style.space(200), parent.height - Style.space(60))
        color: Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent }

        Item {
          id: previewHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(12)
          height: Style.space(40)

          Column {
            anchors.left: parent.left
            anchors.right: previewButtons.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.previewEntry ? root.previewEntry.name : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideMiddle
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.previewDetails()
              color: Util.alpha(Color.popups.text, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            id: previewButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              text: "Open"
              bordered: true
              onClicked: {
                var entry = root.previewEntry
                root.closePreview()
                root.activePane().openEntry(entry)
              }
            }

            Button {
              iconText: Icons.actionGlyph("close")
              tooltipText: "Close preview"
              onClicked: root.closePreview()
            }
          }
        }

        Item {
          id: previewBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: previewHeader.bottom
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(12)
          clip: true

          Image {
            id: previewImage
            anchors.fill: parent
            visible: root.previewKind === "image"
            source: root.previewOpen && root.previewKind === "image" && root.previewEntry
              ? Util.fileUrl(root.previewEntry.path) : ""
            sourceSize.width: Math.max(1, previewBody.width * 2)
            sourceSize.height: Math.max(1, previewBody.height * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
          }

          Flickable {
            id: previewFlick
            anchors.fill: parent
            visible: root.previewKind === "text" && !root.previewBinary && !root.previewLoading
            contentWidth: Math.max(width, previewTextItem.implicitWidth)
            contentHeight: previewTextItem.implicitHeight + (root.previewTruncated ? Style.space(28) : 0)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            TextEdit {
              id: previewTextItem
              objectName: "previewText"
              readOnly: true
              selectByMouse: true
              textFormat: TextEdit.PlainText
              text: root.previewText
              color: Color.popups.text
              selectionColor: Util.alpha(Color.accent, 0.35)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              y: previewTextItem.implicitHeight + Style.space(8)
              visible: root.previewTruncated
              text: "Showing the first 256 KB"
              color: Util.alpha(Color.popups.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(10)
            visible: root.previewKind === "folder" || root.previewKind === "none"
              || (root.previewKind === "text" && (root.previewBinary || root.previewLoading))
              || (root.previewKind === "image" && previewImage.status === Image.Error)

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: Icons.glyphFor(root.previewEntry)
              color: root.previewEntry && root.previewEntry.isDir ? Color.accent : Util.alpha(Color.popups.text, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.displayLarge * 3
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.previewLoading ? "Reading"
                : (root.previewKind === "folder" ? "Folder. Press Enter to open it."
                  : "No preview for this kind of file")
              color: Util.alpha(Color.popups.text, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }

    Rectangle {
      id: dialogScrim
      anchors.fill: parent
      visible: root.dialogMode !== ""
      color: Util.alpha(Color.background, 0.6)

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (root.dialogMode === "conflict") root.resolveConflict("skip", false)
          else root.closeDialog()
        }
      }

      Rectangle {
        objectName: "dialogCard"
        anchors.centerIn: parent
        width: Math.min(root.width - Style.space(24), root.dialogMode === "settings" ? Style.space(780)
          : (root.dialogMode === "shortcuts" ? Style.space(470)
          : (root.dialogMode === "properties" ? Style.space(460)
          : (root.dialogMode === "openwith" ? Style.space(540) : Style.space(360)))))
        height: dialogColumn.implicitHeight + Style.space(28)
        color: Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent }

        Column {
          id: dialogColumn
          objectName: "dialogColumn"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(14)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            visible: root.dialogMode !== "properties"
            width: parent.width
            elide: Text.ElideMiddle
            text: root.dialogTitle
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }

          TextField {
            id: dialogField
            objectName: "dialogField"
            width: parent.width
            visible: root.dialogMode === "rename" || root.dialogMode === "newfolder"
              || root.dialogMode === "newfile" || root.dialogMode === "path"
              || root.dialogMode === "bookmarkname" || root.dialogMode === "compress"
            onAccepted: root.submitDialog()
            Keys.onEscapePressed: root.closeDialog()
          }

          Dropdown {
            objectName: "compressFormat"
            width: parent.width
            visible: root.dialogMode === "compress"
            label: "Format"
            value: root.compressFormat
            options: [
              { label: ".zip, opens anywhere", value: ".zip" },
              { label: ".tar.xz, smaller, for Linux and macOS", value: ".tar.xz" },
              { label: ".tar.gz, for Linux and macOS", value: ".tar.gz" },
              { label: ".7z, smallest, needs 7-Zip on Windows", value: ".7z" }
            ]
            onChanged: function (v) { root.compressFormat = v }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.dialogError !== ""
            text: root.dialogError
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          TextField {
            id: appField
            width: parent.width
            visible: root.dialogMode === "openwith"
            placeholderText: "Search applications or type a command"
            onTextChanged: {
              root.appFilter = text
              root.appCursor = 0
            }
            onAccepted: root.chooseApp()
            Keys.onEscapePressed: root.closeDialog()
          }

          Rectangle {
            width: parent.width
            height: Style.space(30)
            visible: root.canRunTyped
            color: (runHover.hovered || root.appCursor < 0)
              ? Util.alpha(Color.foreground, 0.08) : "transparent"
            radius: Style.cornerRadius

            HoverHandler { id: runHover }

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: "Run " + root.appFilter
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.appCursor = -1
                appField.forceActiveFocus()
              }
              onDoubleClicked: root.runTypedCommand()
            }
          }

          ListView {
            objectName: "openWithList"
            width: parent.width
            height: Math.max(Style.space(80), Math.min(Style.space(240), root.dialogRoom - Style.space(90)))
            currentIndex: root.appCursor
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            visible: root.dialogMode === "openwith"
            clip: true
            model: root.dialogMode === "openwith" ? root.filteredApps() : []

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
              required property var modelData
              width: ListView.view.width
              height: Style.space(26)
              required property int index
              color: (appHover.hovered || root.appCursor === index)
                ? Util.alpha(Color.foreground, 0.08) : "transparent"
              radius: Style.cornerRadius

              HoverHandler { id: appHover }

              Image {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                height: Style.space(18)
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: String(modelData.icon || "").charAt(0) === "/"
                  ? "file://" + modelData.icon
                  : Quickshell.iconPath(String(modelData.icon || ""), "application-x-executable")
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: appIcon.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                text: modelData.name
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.appCursor = index
                  appField.forceActiveFocus()
                }
                onDoubleClicked: root.launchApp(modelData)
              }
            }
          }

          Toggle {
            objectName: "appAlwaysToggle"
            width: parent.width
            visible: root.dialogMode === "openwith" && !(root.dialogPayload && root.dialogPayload.isDir)
            label: Model.alwaysOpenLabel(root.dialogPayload)
            titleSize: Style.font.bodySmall
            checked: root.appAlways
            onClicked: root.appAlways = !root.appAlways
          }

          Flickable {
            width: parent.width
            height: Math.min(Style.space(430), shortcutColumn.implicitHeight, root.dialogRoom)
            visible: root.dialogMode === "shortcuts"
            contentHeight: shortcutColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: shortcutColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.dialogMode === "shortcuts" ? root.shortcutRows() : []

                delegate: Item {
                  required property var modelData
                  width: shortcutColumn.width
                  height: modelData.section ? Style.space(26) : Style.space(20)

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    visible: modelData.section !== undefined
                    text: modelData.section ? modelData.section : ""
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.section === undefined
                    width: Style.space(190)
                    text: modelData.keys ? modelData.keys : ""
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(196)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.section === undefined
                    text: modelData.label ? modelData.label : ""
                    color: Util.alpha(Color.popups.text, 0.65)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          Row {
            id: settingsBody
            objectName: "settingsBody"
            width: parent.width
            height: Math.min(Style.space(430), root.dialogRoom)
            visible: root.dialogMode === "settings"
            spacing: Style.space(10)

            Column {
              id: settingsNav
              width: settingsBody.width < Style.space(520) ? Style.space(104) : Style.space(150)
              height: parent.height
              spacing: Style.space(2)

              Repeater {
                model: root.dialogMode === "settings" ? root.settingsSections() : []

                delegate: Rectangle {
                  required property var modelData
                  width: settingsNav.width
                  height: Style.space(28)
                  radius: Style.cornerRadius
                  color: root.settingsSection === modelData.key
                    ? Util.alpha(Color.accent, 0.18)
                    : (navHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")

                  HoverHandler { id: navHover }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(6)
                    text: modelData.label
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.settingsSection = modelData.key
                  }
                }
              }
            }

            Rectangle {
              width: Math.max(1, Style.space(1))
              height: parent.height
              color: Util.alpha(Color.foreground, 0.12)
            }

            Flickable {
              width: settingsBody.width - settingsNav.width
                - Style.space(20) - Math.max(1, Style.space(1))
              height: parent.height
              contentHeight: settingsColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: settingsColumn
                width: parent.width
                spacing: Style.space(4)

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "opening"

                  Toggle {
                    width: parent.width
                    label: "Open as a popup"
                    description: root.popupMode
                      ? "A centred panel over the desktop that closes when you click away"
                      : "Currently a normal window that tiles and resizes like any app"
                    checked: root.popupMode
                    onClicked: {
                      if (!root.service) return
                      root.service.updateSetting("windowMode", root.popupMode ? "window" : "popup")
                    }
                  }

                  Toggle {
                    width: parent.width
                    label: "Default file manager"
                    description: root.service && root.service.isDefaultFileManager
                      ? "Folders opened from other apps come here"
                      : "Other apps currently open folders in something else"
                    checked: root.service ? root.service.isDefaultFileManager : false
                    onClicked: {
                      if (!root.service) return
                      root.service.setDefaultFileManager(!checked, null, null)
                    }
                  }

                  Toggle {
                    width: parent.width
                    label: "Pick files for other apps"
                    description: root.service && root.service.filePickerBusy
                      ? "Waiting for your password"
                      : (root.service && root.service.filePicker
                        ? "Upload and save dialogs in browsers and other apps open Omafile"
                        : "Use Omafile instead of the GTK dialog when an app asks for a file. Asks for your password once.")
                    checked: root.service ? root.service.filePicker : false
                    onClicked: {
                      if (!root.service) return
                      root.service.setFilePicker(!checked)
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: root.service ? root.service.filePickerError !== "" : false
                    text: root.service ? root.service.filePickerError : ""
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  PanelSectionHeader {
                    width: parent.width
                    text: "Start folder"
                  }

                  TextField {
                    width: parent.width
                    text: root.textSetting("homePath", "")
                    placeholderText: "Your home folder"
                    onAccepted: root.applySettingNow("homePath", text)
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "Press Enter to save"
                    color: Util.alpha(Color.popups.text, 0.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "browsing"

                  Repeater {
                    model: root.dialogMode === "settings" ? root.browsingRows() : []

                    delegate: Toggle {
                      required property var modelData
                      width: settingsColumn.width
                      label: modelData.label
                      description: modelData.description
                      checked: root.boolSetting(modelData.key, modelData.fallback !== false)
                      onClicked: root.applySettingNow(modelData.key, !checked)
                    }
                  }

                  Dropdown {
                    objectName: "dropActionSetting"
                    width: parent.width
                    label: "Drag and drop"
                    value: root.textSetting("dropAction", "auto")
                    options: [
                      { label: "Automatic", value: "auto" },
                      { label: "Always ask", value: "ask" },
                      { label: "Always copy", value: "copy" },
                      { label: "Always move", value: "move" }
                    ]
                    onChanged: function (v) { root.applySettingNow("dropAction", v) }
                  }

                  PanelSectionHeader {
                    width: parent.width
                    text: "Defaults for new tabs"
                  }

                  Dropdown {
                    width: parent.width
                    label: "Sort by"
                    value: root.textSetting("sortBy", "name")
                    options: [
                      { label: "Name", value: "name" },
                      { label: "Size", value: "size" },
                      { label: "Modified", value: "modified" },
                      { label: "Type", value: "type" }
                    ]
                    onChanged: function (v) { root.applySettingNow("sortBy", v) }
                  }

                  Dropdown {
                    width: parent.width
                    label: "View"
                    value: root.textSetting("defaultView", "list")
                    options: [
                      { label: "List", value: "list" },
                      { label: "Compact", value: "compact" },
                      { label: "Grid", value: "grid" },
                      { label: "Gallery", value: "gallery" }
                    ]
                    onChanged: function (v) { root.applySettingNow("defaultView", v) }
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(6)
                  visible: root.settingsSection === "view"

                  PanelSectionHeader {
                    width: parent.width
                    text: "Rows, icons and grid cells"
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "Currently " + Math.round(root.viewScale * 100) + " percent. Ctrl with plus, minus, zero or the scroll wheel also works."
                    color: Util.alpha(Color.popups.text, 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  PanelSlider {
                    width: parent.width
                    value: root.viewScale
                    minimum: root.minViewScale
                    maximum: root.maxViewScale
                    step: 0.05
                    onReleased: function (v) { root.setViewScale(v) }
                  }

                  Button {
                    text: "Reset to 100 percent"
                    bordered: true
                    onClicked: root.setViewScale(1)
                  }

                  PanelSectionHeader {
                    width: parent.width
                    text: "Grid captions"
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "Extra lines under names in grid view. More of them appear as you zoom in."
                    color: Util.alpha(Color.popups.text, 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  Repeater {
                    model: [
                      { key: "gridCaption1", label: "First" },
                      { key: "gridCaption2", label: "Second" },
                      { key: "gridCaption3", label: "Third" }
                    ]

                    delegate: Dropdown {
                      required property var modelData
                      objectName: "captionPicker-" + modelData.key
                      width: settingsColumn.width
                      label: modelData.label
                      value: root.textSetting(modelData.key, "none")
                      options: root.captionOptions
                      onChanged: function (v) { root.applySettingNow(modelData.key, v) }
                    }
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "deleting"

                  Repeater {
                    model: root.dialogMode === "settings" ? root.deletingRows() : []

                    delegate: Toggle {
                      required property var modelData
                      width: settingsColumn.width
                      label: modelData.label
                      description: modelData.description
                      checked: root.boolSetting(modelData.key, true)
                      onClicked: root.applySettingNow(modelData.key, !checked)
                    }
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "commands"

                  PanelSectionHeader {
                    width: parent.width
                    text: "Terminal"
                  }

                  TextField {
                    width: parent.width
                    text: root.textSetting("terminal", "")
                    placeholderText: "System default"
                    onAccepted: root.applySettingNow("terminal", text)
                  }

                  PanelSectionHeader {
                    width: parent.width
                    text: "Editor"
                  }

                  TextField {
                    width: parent.width
                    text: root.textSetting("editor", "")
                    placeholderText: "Omarchy default"
                    onAccepted: root.applySettingNow("editor", text)
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: "For example alacritty -e nvim. Press Enter to save."
                    color: Util.alpha(Color.popups.text, 0.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "bar"

                  Repeater {
                    model: root.dialogMode === "settings" ? root.barRows() : []

                    delegate: Toggle {
                      required property var modelData
                      width: settingsColumn.width
                      label: modelData.label
                      description: modelData.description
                      checked: root.boolSetting(modelData.key, true)
                      onClicked: root.applySettingNow(modelData.key, !checked)
                    }
                  }

                  Toggle {
                    width: parent.width
                    label: "Trash can in the bar"
                    description: root.service && root.service.trashIcon
                      ? "A trash can of its own in the bar. Drag it anywhere from the Omarchy bar settings."
                      : "Adds a trash can to the bar, separate from this icon, showing how many items are in it"
                    checked: root.service ? root.service.trashIcon : false
                    onClicked: {
                      if (!root.service) return
                      root.service.setTrashIcon(!checked, null, null)
                    }
                  }

                  Toggle {
                    width: parent.width
                    visible: root.service ? root.service.trashIcon : false
                    label: "Ask before emptying"
                    description: "The first right click arms the trash can, the second empties it"
                    checked: root.boolSetting("trashConfirm", true)
                    onClicked: root.applySettingNow("trashConfirm", !checked)
                  }

                  PanelSectionHeader {
                    width: parent.width
                    text: "Bar glyph"
                  }

                  TextField {
                    width: parent.width
                    text: root.textSetting("glyph", "")
                    placeholderText: "Folder"
                    onAccepted: root.applySettingNow("glyph", text)
                  }
                }

                Column {
                  width: settingsColumn.width
                  spacing: Style.space(4)
                  visible: root.settingsSection === "drives"

                  Toggle {
                    width: parent.width
                    label: "Show drives"
                    description: "The Drives section in the sidebar"
                    checked: root.boolSetting("showDrives", true)
                    onClicked: root.applySettingNow("showDrives", !checked)
                  }

                  PanelSectionHeader {
                    width: parent.width
                    visible: root.hiddenDriveRows().length > 0
                    text: "Hidden drives"
                  }

                  Repeater {
                    model: root.dialogMode === "settings" ? root.hiddenDriveRows() : []

                    delegate: PlaceRow {
                      required property var modelData
                      width: settingsColumn.width
                      label: modelData.path
                      glyph: Icons.placeGlyph("drive")
                      trailing: "show"
                      onClicked: root.service.toggleHiddenDrive(modelData.path)
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: root.hiddenDriveRows().length === 0
                    text: "No hidden drives"
                    color: Util.alpha(Color.popups.text, 0.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.dialogMode === "connect"
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Address, for example smb://server/share, sftp://user@host or dav://host/path"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            TextField {
              id: serverField
              objectName: "serverField"
              width: parent.width
              placeholderText: "smb://server/share"
              onAccepted: root.submitConnect()
              Keys.onEscapePressed: root.closeDialog()
            }

            Toggle {
              width: parent.width
              label: "Connect anonymously"
              description: "Leave the user and password blank"
              checked: root.connectAnonymous
              onClicked: root.connectAnonymous = !root.connectAnonymous
            }

            TextField {
              id: userField
              objectName: "userField"
              width: parent.width
              visible: !root.connectAnonymous
              placeholderText: "User name"
              Keys.onEscapePressed: root.closeDialog()
            }

            TextField {
              id: domainField
              width: parent.width
              visible: !root.connectAnonymous
              placeholderText: "Domain or workgroup, optional"
              Keys.onEscapePressed: root.closeDialog()
            }

            TextField {
              id: passwordField
              width: parent.width
              visible: !root.connectAnonymous
              placeholderText: "Password"
              password: true
              onAccepted: root.submitConnect()
              Keys.onEscapePressed: root.closeDialog()
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.connectStatus !== ""
              text: root.connectStatus
              color: root.connectFailed ? Color.urgent : Util.alpha(Color.popups.text, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
          }

          Flickable {
            id: propsFlick
            objectName: "propsFlick"
            width: parent.width
            visible: root.dialogMode === "properties"
            height: Math.min(propsPanel.implicitHeight, Math.max(Style.space(120), root.dialogRoom - Style.space(60)))
            implicitHeight: height
            contentHeight: propsPanel.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            PropertiesPanel {
              id: propsPanel
              objectName: "propsPanel"
              width: propsFlick.width
              entry: root.dialogMode === "properties" ? root.dialogPayload : null
              info: root.propsInfo
              identity: root.propsIdentity
              service: root.service
              bytes: root.propsBytes
              files: root.propsFiles
              dirs: root.propsDirs
              usageDone: root.propsUsageDone
              openerMime: root.propsOpenerMime
              openerHandler: root.propsOpenerHandler
              onOpenerChosen: function (handler) { root.chooseOpener(handler) }
              onApplied: if (root.dialogPayload) root.refreshPropsInfo(root.dialogPayload.path)
            }
          }

          Column {
            width: parent.width
            visible: root.dialogMode === "conflict"
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.conflictMessage()
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: "Replace  R"
                bordered: true
                onClicked: root.resolveConflict("overwrite", false)
              }

              Button {
                text: "Keep both  K"
                bordered: true
                onClicked: root.resolveConflict("rename", false)
              }

              Button {
                text: "Skip  S"
                bordered: true
                onClicked: root.resolveConflict("skip", false)
              }

              Button {
                text: "Skip all  A"
                bordered: true
                onClicked: root.resolveConflict("skip", true)
              }
            }
          }

          Row {
            width: parent.width
            layoutDirection: Qt.RightToLeft
            spacing: Style.space(8)
            visible: root.dialogMode !== "conflict"

            Button {
              objectName: "dialogConfirmButton"
              enabled: root.dialogMode !== "openwith" || root.appChoiceReady
              opacity: enabled ? 1 : 0.4
              text: root.isReadOnlyDialog() ? "Close"
                : (root.dialogMode === "connect" ? "Connect"
                  : (root.dialogMode === "openwith" ? "Open"
                    : (root.dialogMode === "compress" ? "Compress" : "Confirm")))
              bordered: true
              onClicked: {
                if (root.isReadOnlyDialog()) root.closeDialog()
                else if (root.dialogMode === "openwith") root.chooseApp()
                else if (root.dialogMode === "connect") root.submitConnect()
                else root.submitDialog()
              }
            }

            Button {
              text: "Cancel"
              bordered: true
              visible: !root.isReadOnlyDialog()
              onClicked: root.closeDialog()
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: confirm
      anchors.fill: parent
      cancelText: "Cancel"
      onCanceled: {
        confirm.opened = false
        root.dialogPayload = null
        root.confirmAction = ""
        if (root.pickNeedsName) pickNameField.forceActiveFocus()
        else keyCatcher.forceActiveFocus()
      }
      onConfirmed: {
        confirm.opened = false
        var targets = root.dialogPayload
        var action = root.confirmAction
        root.dialogPayload = null
        root.confirmAction = ""
        if (action === "emptytrash") root.performEmptyTrash()
        else if (targets && action === "trash") root.performTrash(targets)
        else if (targets && action === "pickreplace") root.completePick(targets)
        else if (targets && action === "openmany") root.openEntries(targets)
        else if (targets) root.performDelete(targets)
        keyCatcher.forceActiveFocus()
      }
    }
  }

  function filteredApps() {
    var out = []
    var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var needle = String(appFilter || "").toLowerCase()
    for (var i = 0; i < all.length; i++) {
      var app = all[i]
      if (!app || app.noDisplay) continue
      if (needle && String(app.name || "").toLowerCase().indexOf(needle) < 0) continue
      out.push(app)
      if (out.length >= 200) break
    }
    out.sort(function (a, b) {
      return String(a.name || "").toLowerCase() < String(b.name || "").toLowerCase() ? -1 : 1
    })
    return out
  }

  function shortcutRows() {
    return [
      { section: "Navigation" },
      { keys: "Enter / Ctrl+O / Alt+Down", label: "Open the selected items" },
      { keys: "Backspace / Alt+Up", label: "Go to the parent folder" },
      { keys: "Alt+Left / Alt+Right", label: "Back and forward" },
      { keys: "Alt+Home", label: "Go to your home folder" },
      { keys: "Ctrl+L", label: "Type a path" },
      { keys: "/  or  ~", label: "Type a path, starting from root or home" },
      { keys: "Home / End", label: "First and last item" },
      { keys: "F5 / Ctrl+R", label: "Refresh" },
      { keys: "Ctrl+.", label: "Open a terminal in this folder" },
      { section: "Moving around without a mouse" },
      { keys: "Tab", label: "Sidebar, or the other pane when split" },
      { keys: "Shift+Tab", label: "Jump to the sidebar" },
      { keys: "Arrows, Enter", label: "Move and open, once in the sidebar" },
      { keys: "Ctrl+Enter", label: "Open a sidebar place in a new tab" },
      { keys: "Delete", label: "Remove a bookmark or hide a drive, in the sidebar" },
      { keys: "Escape", label: "Leave the sidebar" },
      { keys: "Shift+F10 / Menu", label: "Open the context menu on the current item" },
      { keys: "F10", label: "Open the menu for this folder" },
      { section: "Selection" },
      { keys: "Ctrl+Click", label: "Add one item to the selection" },
      { keys: "Ctrl+Space", label: "Add the item under the cursor" },
      { keys: "Shift+Click, Shift+Arrows", label: "Select a range" },
      { keys: "Ctrl+A", label: "Select everything" },
      { keys: "Ctrl+Shift+I", label: "Invert the selection" },
      { keys: "Escape", label: "Clear the selection" },
      { section: "Files" },
      { keys: "Ctrl+C / Ctrl+X / Ctrl+V", label: "Copy, cut and paste" },
      { keys: "Ctrl+Z / Ctrl+Shift+Z", label: "Undo and redo" },
      { keys: "F2", label: "Rename" },
      { keys: "Ctrl+Shift+N", label: "New folder" },
      { keys: "Ctrl+N", label: "New file" },
      { keys: "Delete", label: "Move to trash, or delete permanently inside the trash" },
      { keys: "Shift+Delete", label: "Delete permanently" },
      { keys: "Ctrl+I / Alt+Enter", label: "Properties" },
      { keys: "Ctrl+D", label: "Bookmark this folder" },
      { section: "Panes and tabs" },
      { keys: "Ctrl+T", label: "New tab" },
      { keys: "Ctrl+W", label: "Close the tab, or the window when it is the last one" },
      { keys: "Ctrl+Shift+T", label: "Reopen the last closed tab" },
      { keys: "Ctrl+PageUp / PageDown", label: "Previous and next tab" },
      { keys: "Ctrl+Shift+PageUp / PageDown", label: "Move the tab left or right" },
      { keys: "Alt+1 to Alt+9", label: "Go to that tab" },
      { keys: "Middle click", label: "Open a folder in a new tab" },
      { keys: "Ctrl+Enter", label: "Open the folder under the cursor in a new tab" },
      { keys: "F6", label: "Split into two panes" },
      { keys: "Tab", label: "Switch the active pane, while split" },
      { keys: "Ctrl+Shift+C / Ctrl+Shift+M", label: "Copy and move to the other pane" },
      { section: "View" },
      { keys: "Ctrl+1 / Ctrl+2 / Ctrl+3 / Ctrl+4", label: "List, grid, compact and gallery" },
      { keys: "Ctrl+Plus / Ctrl+Minus", label: "Zoom in and out, also Ctrl with the scroll wheel" },
      { keys: "Ctrl+0", label: "Reset the zoom to 100 percent" },
      { keys: "Space", label: "Preview the item under the cursor" },
      { keys: "Mouse back / forward", label: "Back and forward" },
      { keys: "Ctrl+H", label: "Show hidden files" },
      { keys: "F9 / Ctrl+B", label: "Show or hide the sidebar" },
      { keys: "Ctrl+F, or just type", label: "Search in this folder" },
      { keys: "Ctrl+Shift+F", label: "Search your whole home folder" },
      { keys: "Ctrl+Comma", label: "Settings" },
      { keys: "F1 / Ctrl+?", label: "This list" },
      { keys: "Ctrl+Q", label: "Close the window" },
      { section: "When a file already exists" },
      { keys: "R / K / S / A", label: "Replace, keep both, skip, skip all" }
    ]
  }

  function isReadOnlyDialog() {
    return dialogMode === "properties" || dialogMode === "shortcuts" || dialogMode === "settings"
  }

  readonly property bool popupMode: service ? service.windowMode === "popup" : false
  readonly property real dialogRoom: Math.max(Style.space(140), height - Style.space(130))

  function boolSetting(key, fallback) {
    if (!service) return fallback
    var v = service.settingNow(key, fallback)
    if (typeof v === "boolean") return v
    var text = String(v).toLowerCase()
    if (text === "true" || text === "1" || text === "yes" || text === "on") return true
    if (text === "false" || text === "0" || text === "no" || text === "off") return false
    return fallback
  }

  function settingsSections() {
    return [
      { key: "opening", label: "Opening" },
      { key: "browsing", label: "Browsing" },
      { key: "view", label: "View size" },
      { key: "deleting", label: "Deleting" },
      { key: "commands", label: "Commands" },
      { key: "bar", label: "Bar and trash" },
      { key: "drives", label: "Drives" }
    ]
  }

  function browsingRows() {
    return [
      { key: "showHidden", label: "Show hidden files",
        description: "Files and folders whose name starts with a dot" },
      { key: "sortDirsFirst", label: "Folders first",
        description: "List folders above files whatever the sort order" },
      { key: "thumbnails", label: "Previews and thumbnails",
        description: "Show images, video frames and document pages instead of a generic icon" },
      { key: "rememberFolderViews", label: "Remember the view for each folder",
        description: "A folder opens in the view you last picked there. Other folders open in the default view" },
      { key: "extractOnOpen", label: "Extract archives when opened", fallback: false,
        description: "Double click or Enter extracts zip, tar, 7z and rar files next to themselves instead of opening them in your default app" }
    ]
  }

  function deletingRows() {
    return [
      { key: "useTrash", label: "Delete moves to trash",
        description: "Turn this off to delete permanently every time" },
      { key: "confirmTrash", label: "Confirm moves to trash",
        description: "Ask before items are moved to the trash" },
      { key: "confirmDelete", label: "Confirm permanent deletes",
        description: "Ask before anything is destroyed for good" }
    ]
  }

  function barRows() {
    return [
      { key: "showTransferBadge", label: "Transfer progress on the bar icon",
        description: "A progress ring while a copy or move is running" }
    ]
  }

  function textSetting(key, fallback) {
    if (!service) return fallback
    var v = service.settingNow(key, fallback)
    return v === undefined || v === null ? fallback : String(v)
  }

  function applySettingNow(key, value) {
    if (!service) return
    service.updateSetting(key, value)
    if (key === "showHidden") {
      paneA.showHidden = value
      if (split) paneB.showHidden = value
    } else if (key === "sortDirsFirst") {
      paneA.dirsFirst = value
      if (split) paneB.dirsFirst = value
    } else if (key === "thumbnails") {
      paneA.thumbnails = value
      if (split) paneB.thumbnails = value
    }
    rememberSession()
  }

  function hiddenDriveRows() {
    if (!service) return []
    var out = []
    var list = service.hiddenDrives
    for (var i = 0; i < list.length; i++) out.push({ path: String(list[i]) })
    return out
  }

  function conflictMessage() {
    var payload = dialogPayload
    if (!payload || !payload.info) return ""
    var info = payload.info
    return "\"" + Model.basename(String(info.dest || "")) + "\" already exists in this folder."
  }

  function resolveConflict(action, applyAll) {
    var payload = dialogPayload
    closeDialog()
    if (!payload || !service) return
    service.resolveConflict(payload.jobId, action, applyAll)
  }
}
