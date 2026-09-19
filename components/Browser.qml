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
  readonly property real viewScale: clampViewScale(service ? service.setting("viewScale", 1) : 1)
  property bool menuOpen: false
  property int menuCursor: -1
  property var menuActions: []
  property string focusZone: "pane"
  property int appCursor: 0
  property real menuX: 0
  property real menuY: 0
  property var menuEntry: null
  property string menuKind: ""
  property string statusText: ""
  property string appFilter: ""
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
      view: service ? String(service.setting("defaultView", "list")) : "list",
      sortBy: service ? String(service.setting("sortBy", "name")) : "name",
      descending: false,
      hidden: service ? service.setting("showHidden", false) === true : false,
      filter: ""
    }
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
    p.view = tab.view || "list"
    p.sortBy = tab.sortBy || "name"
    p.descending = tab.descending === true
    p.filter = tab.filter || ""
    p.showHidden = tab.hidden === true
    p.dirsFirst = service ? service.setting("sortDirsFirst", true) === true : true
    p.thumbnails = service ? service.setting("thumbnails", true) !== false : true
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
    list.push(defaultTab(path || paneFor(side).path))
    setTabs(side, list)
    setActiveIndex(side, list.length - 1)
    applyTab(side, list[list.length - 1])
    activeSide = side
    rememberSession()
  }
  function closeTab(side, index) {
    var list = tabsFor(side).slice()
    if (list.length <= 1) return
    list.splice(index, 1)
    var idx = activeIndexFor(side)
    if (idx >= list.length) idx = list.length - 1
    else if (index < idx) idx = idx - 1
    setTabs(side, list)
    setActiveIndex(side, idx)
    applyTab(side, list[idx])
    rememberSession()
  }
  function toggleSplit() {
    split = !split
    if (split && tabsB.length === 0) {
      tabsB = [defaultTab(paneA.path)]
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
    if (!service || !sessionRestored) return
    storeCurrentTab(activeSide)
    service.rememberSession({
      split: split, activeSide: activeSide, sidebar: sidebarVisible,
      tabsA: tabsFor(0), tabsB: tabsFor(1), activeA: activeA, activeB: activeB
    })
  }
  function restoreSession() {
    var s = service ? service.session : null
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
    if (picking) service.finishPick({ ok: false })
    rememberSession()
    root.dismissRequested()
  }

  readonly property var pick: service ? service.pickRequest : null
  readonly property bool picking: pick !== null && pick !== undefined
  readonly property bool pickSaving: picking && (pick.mode === "save" || pick.mode === "savefiles")
  readonly property bool pickNeedsName: picking && pick.mode === "save"
  property int pickFilter: -1

  Component.onDestruction: {
    if (service && service.pickRequest) service.finishPick({ ok: false })
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
    service.finishPick({ ok: true, paths: paths, filter: pickFilter })
    rememberSession()
    root.dismissRequested()
  }

  function cancelPick() {
    if (!picking) return
    service.finishPick({ ok: false })
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
    Qt.callLater(function () {
      if (dialogMode === "rename" || dialogMode === "newfolder" || dialogMode === "newfile" || dialogMode === "path") {
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
        root.connectStatus = ""
        root.connectFailed = false
        serverField.text = root.dialogValue
        serverField.forceActiveFocus()
      }
    })
  }
  function closeDialog() {
    dialogMode = ""
    dialogPayload = null
    dialogError = ""
    keyCatcher.forceActiveFocus()
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
    if (!value) {
      dialogError = "Name cannot be empty"
      return
    }
    if (value.indexOf("/") >= 0) {
      dialogError = "Name cannot contain a slash"
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
    var clip = service ? service.clipboard : null
    if (!clip || !clip.paths || clip.paths.length === 0) return
    var p = activePane()
    service.beginTransfer(clip.mode === "cut" ? "move" : "copy", clip.paths, p.path, "ask")
    if (clip.mode === "cut") service.clearClipboard()
  }
  function clampViewScale(value) {
    var n = Number(value)
    if (!isFinite(n) || n <= 0) return 1
    return Math.max(0.8, Math.min(2.5, Math.round(n * 20) / 20))
  }
  function setViewScale(value) {
    var next = clampViewScale(value)
    applySettingNow("viewScale", next)
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
  function doTrash() {
    var paths = activePane().selectedPaths()
    if (paths.length === 0) return
    if (service.setting("useTrash", true) !== true) return askDelete(paths)
    if (service.setting("confirmTrash", true) !== true) return performTrash(paths)
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
    if (service.setting("confirmDelete", true) !== true) return performDelete(targets)
    confirmAction = "delete"
    confirm.message = "Permanently delete " + Model.formatCount(targets.length, "item", "items") + "? This cannot be undone."
    confirm.confirmText = "Delete"
    dialogPayload = targets
    confirm.opened = true
  }
  function performDelete(paths) {
    var p = activePane()
    service.deletePaths(paths, function () { p.refresh() }, null)
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
    service.openExternally(entry.path)
    afterLaunch()
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
    if (hasEntry) {
      items.push({ key: "open", label: entry.isDir ? "Open" : "Open", glyph: Icons.actionGlyph("open") })
      items.push({ key: "openwith", label: "Open with", glyph: Icons.actionGlyph("open") })
      if (!entry.isDir) items.push({ key: "preview", label: "Preview", glyph: Icons.actionGlyph("search") })
      if (entry.isDir) {
        items.push({ key: "opentab", label: "Open in new tab", glyph: Icons.actionGlyph("add") })
        items.push({
          key: "bookmark",
          label: root.isBookmarked(entry.path) ? "Remove bookmark" : "Add to bookmarks",
          glyph: Icons.placeGlyph("pinned")
        })
      }
      items.push({ key: "sep1", label: "", glyph: "" })
      items.push({ key: "copy", label: "Copy", glyph: Icons.actionGlyph("copy") })
      items.push({ key: "cut", label: "Cut", glyph: Icons.actionGlyph("cut") })
    }
    items.push({ key: "paste", label: "Paste", glyph: Icons.actionGlyph("paste"),
      disabled: !service || !service.clipboard || service.clipboard.paths.length === 0 })
    if (hasEntry) {
      items.push({ key: "sep2", label: "", glyph: "" })
      items.push({ key: "rename", label: "Rename", glyph: Icons.actionGlyph("rename") })
      items.push({ key: "trash", label: "Move to trash", glyph: Icons.actionGlyph("trash") })
      items.push({ key: "delete", label: "Delete permanently", glyph: Icons.actionGlyph("delete") })
      items.push({ key: "sep3", label: "", glyph: "" })
      items.push({ key: "copypath", label: "Copy path", glyph: Icons.actionGlyph("copy") })
      items.push({ key: "properties", label: "Properties", glyph: Icons.actionGlyph("properties") })
    } else {
      items.push({ key: "sep2", label: "", glyph: "" })
      items.push({ key: "newfolder", label: "New folder", glyph: Icons.actionGlyph("newfolder") })
      items.push({ key: "newfile", label: "New file", glyph: Icons.actionGlyph("newfile") })
      items.push({ key: "sep3", label: "", glyph: "" })
      items.push({
        key: "bookmark",
        label: root.isBookmarked(p.path) ? "Remove this bookmark" : "Bookmark this folder",
        glyph: Icons.placeGlyph("pinned")
      })
      items.push({ key: "terminal", label: "Open in terminal", glyph: Icons.actionGlyph("terminal") })
      items.push({ key: "refresh", label: "Refresh", glyph: Icons.actionGlyph("refresh") })
    }
    return items
  }
  function runAction(key) {
    var p = activePane()
    var entry = menuEntry
    menuOpen = false
    menuKind = ""
    if (key.indexOf("sort:") === 0) applySortPreset(key.substring(5))
    else if (key.indexOf("view:") === 0) setView(key.substring(5))
    else if (key === "preview") showPreview(entry)
    else if (key === "open") p.openEntry(entry)
    else if (key === "openwith") showDialog("openwith", "Open with", "", entry)
    else if (key === "opentab") newTab(activeSide, entry.path)
    else if (key === "copy") doCopy()
    else if (key === "cut") doCut()
    else if (key === "paste") doPaste()
    else if (key === "rename") doRename()
    else if (key === "trash") doTrash()
    else if (key === "delete") askDelete(null)
    else if (key === "copypath") service.copyToClipboardText(entry ? entry.path : p.path)
    else if (key === "properties") showProperties(entry)
    else if (key === "newfolder") showDialog("newfolder", "New folder", "untitled folder", null)
    else if (key === "newfile") showDialog("newfile", "New file", "untitled", null)
    else if (key === "bookmark") service.togglePinned(entry && entry.isDir ? entry.path : p.path)
    else if (key === "terminal") service.openTerminal(p.path)
    else if (key === "refresh") p.refresh()
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
  function showProperties(entry) {
    if (!entry) return
    propsInfo = null
    propsBytes = 0
    propsFiles = 0
    propsDirs = 0
    showDialog("properties", "Properties", "", entry)
    service.statPaths([entry.path], function (items) {
      if (items && items.length > 0) root.propsInfo = items[0]
    })
    if (entry.isDir) {
      propsDuId = service.diskUsage(entry.path, function (m) {
        root.propsBytes = Number(m.bytes) || 0
        root.propsFiles = Number(m.files) || 0
        root.propsDirs = Number(m.dirs) || 0
      }, null)
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
    rememberSession()
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
    if (kind === "sort") {
      var current = p ? Model.sortPresetKey(p.sortBy, p.descending) : ""
      for (var i = 0; i < Model.sortPresets.length; i++) {
        var preset = Model.sortPresets[i]
        items.push({ key: "sort:" + preset.key, label: preset.label,
          glyph: preset.key === current ? check : "", disabled: !p || p.virtualView })
      }
    } else {
      var mode = p ? p.view : "list"
      for (var j = 0; j < Model.viewModes.length; j++) {
        var view = Model.viewModes[j]
        items.push({ key: "view:" + view.key, label: view.label,
          glyph: view.key === mode ? check : Icons.actionGlyph(view.glyph) })
      }
    }
    return items
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
    menuX = pt.x + anchor.width - Style.space(200)
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
    menuY = toolbar.height + Style.space(40) + Math.min(row, 18) * Style.space(22)
    menuOpen = true
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
      requestClose()
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

    if (ctrl && shiftKey && event.key === Qt.Key_N) { showDialog("newfolder", "New folder", "untitled folder", null); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_C) { transferToOtherPane("copy"); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_M) { transferToOtherPane("move"); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_I) { p.invertSelection(); return true }
    if (ctrl && shiftKey && event.key === Qt.Key_Z) { doRedo(); return true }

    if (ctrl && event.key === Qt.Key_N) { showDialog("newfile", "New file", "untitled", null); return true }
    if (ctrl && event.key === Qt.Key_T) { newTab(activeSide, null); return true }
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

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { p.activateCursor(); return true }
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
    Keys.onPressed: function (event) {
      if (root.handleKey(event)) event.accepted = true
    }

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
            id: sortButton
            objectName: "sortButton"
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("sort")
            tooltipText: "Sort"
            selected: root.menuOpen && root.menuKind === "sort"
            onClicked: root.openToolbarMenu("sort", sortButton)
          }

          Button {
            id: viewButton
            objectName: "viewButton"
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph(root.viewGlyph())
            tooltipText: "View"
            selected: root.menuOpen && root.menuKind === "view"
            onClicked: root.openToolbarMenu("view", viewButton)
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("hidden")
            tooltipText: "Show hidden files"
            selected: root.activePane() ? root.activePane().showHidden : false
            onClicked: {
              var p = root.activePane()
              p.showHidden = !p.showHidden
              root.rememberSession()
            }
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
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("settings")
            tooltipText: "Settings"
            onClicked: root.showDialog("settings", "Settings", "", null)
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: Icons.actionGlyph("keyboard")
            tooltipText: "Keyboard shortcuts"
            onClicked: root.showDialog("shortcuts", "Keyboard shortcuts", "", null)
          }
        }

        PathBar {
          id: pathBar
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
          width: root.sidebarVisible ? Style.space(190) : 0
          height: parent.height
          visible: root.sidebarVisible
          service: root.service
          currentPath: root.activePane() ? root.activePane().path : ""
          showDrives: root.service ? root.service.setting("showDrives", true) !== false : true
          onNavigate: function (target) {
            pathBar.endEdit()
            root.activePane().navigate(target)
            keyCatcher.forceActiveFocus()
          }
          onOpenInNewTab: function (target) { root.newTab(root.activeSide, target) }
          onRemoveBookmark: function (target) { root.service.togglePinned(target) }
          onHideDrive: function (key) { root.service.toggleHiddenDrive(key) }
          onShowAllDrives: root.showDialog("settings", "Settings", "", null)
          onConnectServer: function (uri) {
            root.showDialog("connect", "Connect to a server", String(uri || ""), null)
          }
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
              onCloseTab: function (index) { root.closeTab(0, index) }
              onAddTab: root.newTab(0, null)
            }

            PaneView {
              id: paneA
              width: parent.width
              patterns: root.picking ? root.pickPatterns() : []
              height: parent.height - (tabStripA.visible ? tabStripA.height : 0)
              service: root.service
              viewScale: root.viewScale
              active: root.activeSide === 0
              onActivated: {
                root.activeSide = 0
                pathBar.endEdit()
                keyCatcher.forceActiveFocus()
              }
              onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
              onNavigated: function (p) { root.rememberSession() }
              onContextRequested: function (entry, x, y) {
                root.menuKind = ""
                root.menuEntry = entry
                root.menuActions = root.contextActions(entry)
                root.menuCursor = -1
                root.menuX = x + (root.sidebarVisible ? sidebar.width : 0)
                root.menuY = y + toolbar.height + (tabStripA.visible ? tabStripA.height : 0)
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
              onCloseTab: function (index) { root.closeTab(1, index) }
              onAddTab: root.newTab(1, null)
            }

            PaneView {
              id: paneB
              width: parent.width
              patterns: root.picking ? root.pickPatterns() : []
              height: parent.height - (tabStripB.visible ? tabStripB.height : 0)
              service: root.service
              viewScale: root.viewScale
              active: root.activeSide === 1
              onActivated: {
                root.activeSide = 1
                pathBar.endEdit()
                keyCatcher.forceActiveFocus()
              }
              onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
              onNavigated: function (p) { root.rememberSession() }
              onContextRequested: function (entry, x, y) {
                root.menuKind = ""
                root.menuEntry = entry
                root.menuActions = root.contextActions(entry)
                root.menuCursor = -1
                root.menuX = x + (root.sidebarVisible ? sidebar.width : 0) + sideA.width
                root.menuY = y + toolbar.height + (tabStripB.visible ? tabStripB.height : 0)
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
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var p = root.activePane()
              if (!p) return ""
              if (p.loading)
                return Model.formatCount(p.rows.length, "item", "items") + ", reading"
              if (p.selectedCount > 0)
                return Model.formatCount(p.selectedCount, "item selected", "items selected")
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
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.service !== null && root.service.helperError !== ""
          text: root.service ? root.service.helperError : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    TransferBar {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      service: root.service
      visible: root.service !== null && root.service.transfers.length > 0
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
      x: Math.min(root.menuX, keyCatcher.width - width - Style.space(8))
      y: Math.min(root.menuY, keyCatcher.height - height - Style.space(8))
      width: Style.space(200)
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
            required property var modelData
            required property int index
            width: menuColumn.width
            height: modelData.label === "" ? Style.space(7) : Style.space(24)

            Rectangle {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              height: 1
              visible: modelData.label === ""
              color: Util.alpha(Color.menu.text, 0.15)
            }

            Rectangle {
              anchors.fill: parent
              visible: modelData.label !== ""
              radius: Style.cornerRadius
              color: (itemHover.hovered || root.menuCursor === index) && !modelData.disabled
                ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: itemHover }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.glyph
                  color: Util.alpha(Color.menu.text, modelData.disabled ? 0.3 : 0.7)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconSmall
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: modelData.disabled
                    ? Util.alpha(Color.menu.text, 0.35)
                    : ((itemHover.hovered || root.menuCursor === index)
                      ? Color.menu.selectedText : Color.menu.text)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData.disabled
                onClicked: root.runAction(modelData.key)
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
              width: parent.width
              text: root.previewEntry ? root.previewEntry.name : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideMiddle
            }

            Text {
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
              anchors.horizontalCenter: parent.horizontalCenter
              text: Icons.glyphFor(root.previewEntry)
              color: root.previewEntry && root.previewEntry.isDir ? Color.accent : Util.alpha(Color.popups.text, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.displayLarge * 3
            }

            Text {
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
          : ((root.dialogMode === "openwith" || root.dialogMode === "properties")
            ? Style.space(420) : Style.space(360))))
        height: dialogColumn.implicitHeight + Style.space(28)
        color: Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent }

        Column {
          id: dialogColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(14)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(10)

          Text {
            text: root.dialogTitle
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }

          TextField {
            id: dialogField
            width: parent.width
            visible: root.dialogMode === "rename" || root.dialogMode === "newfolder"
              || root.dialogMode === "newfile" || root.dialogMode === "path"
            onAccepted: root.submitDialog()
            Keys.onEscapePressed: root.closeDialog()
          }

          Text {
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
              onClicked: root.runTypedCommand()
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

              Text {
                anchors.left: parent.left
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
                onClicked: root.launchApp(modelData)
              }
            }
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
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    visible: modelData.section !== undefined
                    text: modelData.section ? modelData.section : ""
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
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
                      checked: root.boolSetting(modelData.key, true)
                      onClicked: root.applySettingNow(modelData.key, !checked)
                    }
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
                    width: parent.width
                    text: "Currently " + Math.round(root.viewScale * 100) + " percent. Ctrl with plus, minus or zero also works."
                    color: Util.alpha(Color.popups.text, 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  PanelSlider {
                    width: parent.width
                    value: root.viewScale
                    minimum: 0.8
                    maximum: 2.5
                    step: 0.05
                    onReleased: function (v) { root.setViewScale(v) }
                  }

                  Button {
                    text: "Reset to 100 percent"
                    bordered: true
                    onClicked: root.setViewScale(1)
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
              width: parent.width
              text: "Address, for example smb://server/share, sftp://user@host or dav://host/path"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            TextField {
              id: serverField
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
              width: parent.width
              visible: root.connectStatus !== ""
              text: root.connectStatus
              color: root.connectFailed ? Color.urgent : Util.alpha(Color.popups.text, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
          }

          Column {
            width: parent.width
            visible: root.dialogMode === "properties"
            spacing: Style.space(6)

            Repeater {
              model: root.dialogMode === "properties" ? root.propertyRows() : []

              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(10)

                Text {
                  width: Style.space(110)
                  text: modelData.label
                  color: Util.alpha(Color.popups.text, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: parent.width - Style.space(120)
                  text: modelData.value
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.dialogMode === "conflict"
            spacing: Style.space(8)

            Text {
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
              text: root.isReadOnlyDialog() ? "Close"
                : (root.dialogMode === "connect" ? "Connect" : "Confirm")
              bordered: true
              onClicked: {
                if (root.isReadOnlyDialog()) root.closeDialog()
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
        if (targets && action === "trash") root.performTrash(targets)
        else if (targets && action === "pickreplace") root.completePick(targets)
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
      { keys: "Enter", label: "Open the selected item" },
      { keys: "Backspace / Alt+Up", label: "Go to the parent folder" },
      { keys: "Alt+Left / Alt+Right", label: "Back and forward" },
      { keys: "Alt+Home", label: "Go to your home folder" },
      { keys: "Ctrl+L", label: "Type a path" },
      { keys: "/  or  ~", label: "Type a path, starting from root or home" },
      { keys: "Home / End", label: "First and last item" },
      { keys: "F5 / Ctrl+R", label: "Refresh" },
      { section: "Moving around without a mouse" },
      { keys: "Tab", label: "Sidebar, or the other pane when split" },
      { keys: "Shift+Tab", label: "Jump to the sidebar" },
      { keys: "Arrows, Enter", label: "Move and open, once in the sidebar" },
      { keys: "Ctrl+Enter", label: "Open a sidebar place in a new tab" },
      { keys: "Delete", label: "Remove a bookmark or hide a drive, in the sidebar" },
      { keys: "Escape", label: "Leave the sidebar" },
      { keys: "Shift+F10 / Menu", label: "Open the context menu on the current item" },
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
      { keys: "Delete", label: "Move to trash" },
      { keys: "Shift+Delete", label: "Delete permanently" },
      { keys: "Ctrl+I / Alt+Enter", label: "Properties" },
      { keys: "Ctrl+D", label: "Bookmark this folder" },
      { section: "Panes and tabs" },
      { keys: "Ctrl+T / Ctrl+W", label: "New tab and close tab" },
      { keys: "Ctrl+PageUp / PageDown", label: "Previous and next tab" },
      { keys: "Ctrl+Enter", label: "Open the folder under the cursor in a new tab" },
      { keys: "F6", label: "Split into two panes" },
      { keys: "Tab", label: "Switch the active pane, while split" },
      { keys: "Ctrl+Shift+C / Ctrl+Shift+M", label: "Copy and move to the other pane" },
      { section: "View" },
      { keys: "Ctrl+1 / Ctrl+2", label: "List and grid" },
      { keys: "Ctrl+3 / Ctrl+4", label: "Compact and gallery" },
      { keys: "Space", label: "Preview the item under the cursor" },
      { keys: "Mouse back / forward", label: "Back and forward" },
      { keys: "Ctrl+H", label: "Show hidden files" },
      { keys: "Ctrl+B", label: "Show or hide the sidebar" },
      { keys: "Ctrl+F, or just type", label: "Search in this folder" },
      { keys: "Ctrl+Comma", label: "Settings" },
      { keys: "F1", label: "This list" },
      { keys: "Ctrl+Q / Escape", label: "Close the window" },
      { section: "When a file already exists" },
      { keys: "R / K / S / A", label: "Replace, keep both, skip, skip all" }
    ]
  }

  function propertyRows() {
    var entry = dialogPayload
    var info = propsInfo
    if (!entry) return []
    var rows = []
    rows.push({ label: "Name", value: entry.name })
    rows.push({ label: "Location", value: Model.dirname(entry.path) })
    rows.push({ label: "Type", value: Model.kindLabel(entry) })
    if (entry.isDir) {
      rows.push({ label: "Contents", value: propsFiles + " files, " + propsDirs + " folders" })
      rows.push({ label: "Size", value: Model.formatSize(propsBytes) })
    } else {
      rows.push({ label: "Size", value: Model.formatSize(entry.size) })
    }
    rows.push({ label: "Modified", value: Model.formatFullDate(entry.mtime) })
    if (info) {
      rows.push({ label: "Permissions", value: Model.formatMode(info.mode) })
      rows.push({ label: "Owner", value: String(info.owner || "") + ":" + String(info.group || "") })
      if (info.mime) rows.push({ label: "MIME type", value: String(info.mime) })
    }
    if (entry.linkTarget) rows.push({ label: "Links to", value: String(entry.linkTarget) })
    return rows
  }

  function isReadOnlyDialog() {
    return dialogMode === "properties" || dialogMode === "openwith"
      || dialogMode === "shortcuts" || dialogMode === "settings"
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
      { key: "thumbnails", label: "Image previews",
        description: "Draw the picture instead of a generic icon" }
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
