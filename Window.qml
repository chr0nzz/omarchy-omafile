import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Icons.js" as Icons
import "components"

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: "xyzlab.omafile"
  readonly property string home: Quickshell.env("HOME") || ""

  property bool closingFromHost: false
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

  property bool menuOpen: false
  property real menuX: 0
  property real menuY: 0
  property var menuEntry: null

  property string statusText: ""
  property string appFilter: ""
  property bool findMode: false

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
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed && typeof parsed.path === "string") target = parsed.path
        if (parsed && typeof parsed.dialog === "string") wantDialog = parsed.dialog
      } catch (e) {
      }
    }
    ensureSession()
    window.visible = true
    Qt.callLater(function () {
      if (target) activePane().navigate(target)
      keyCatcher.forceActiveFocus()
      if (wantDialog === "shortcuts") showDialog("shortcuts", "Keyboard shortcuts", "", null)
    })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    rememberSession()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else window.visible = false
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
        appField.forceActiveFocus()
      }
    })
  }

  function closeDialog() {
    dialogMode = ""
    dialogPayload = null
    dialogError = ""
    keyCatcher.forceActiveFocus()
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

  function transferToOtherPane(op) {
    if (!split) return
    var from = activePane()
    var to = paneFor(otherSide())
    var paths = from.selectedPaths()
    if (paths.length === 0) return
    service.beginTransfer(op, paths, to.path, "ask")
  }

  function doTrash() {
    var p = activePane()
    var paths = p.selectedPaths()
    if (paths.length === 0) return
    if (service.setting("useTrash", true) !== true) return askDelete(paths)
    service.trashPaths(paths, function () { p.refresh() }, null)
    statusText = Model.formatCount(paths.length, "item moved to trash", "items moved to trash")
  }

  function askDelete(paths) {
    var targets = paths || activePane().selectedPaths()
    if (targets.length === 0) return
    if (service.setting("confirmDelete", true) !== true) return performDelete(targets)
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
    service.openExternally(entry.path)
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
      if (!entry.isDir) items.push({ key: "openwith", label: "Open with", glyph: Icons.actionGlyph("open") })
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
    if (key === "open") p.openEntry(entry)
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
    pathBar.focusFilter()
  }

  function exitFind() {
    findDebounce.stop()
    findMode = false
    pathBar.clearFilter()
    var p = activePane()
    if (p) {
      p.filter = ""
      p.stopSearch()
    }
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
    if (dialogMode !== "") {
      if (event.key === Qt.Key_Escape) {
        closeDialog()
        return true
      }
      return false
    }
    if (menuOpen) {
      if (event.key === Qt.Key_Escape) {
        menuOpen = false
        return true
      }
      return false
    }

    var p = activePane()
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shiftKey = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (p.searching || findMode) {
        exitFind()
        return true
      }
      if (p.filter !== "") {
        pathBar.clearFilter()
        return true
      }
      requestClose()
      return true
    }
    if (ctrl && event.key === Qt.Key_T) { newTab(activeSide, null); return true }
    if (ctrl && event.key === Qt.Key_W) { closeTab(activeSide, activeIndexFor(activeSide)); return true }
    if (ctrl && event.key === Qt.Key_L) { pathBar.beginEdit(); return true }
    if (ctrl && event.key === Qt.Key_H) { p.showHidden = !p.showHidden; rememberSession(); return true }
    if (ctrl && event.key === Qt.Key_A) { p.selectAll(); return true }
    if (ctrl && event.key === Qt.Key_C) { doCopy(); return true }
    if (ctrl && event.key === Qt.Key_X) { doCut(); return true }
    if (ctrl && event.key === Qt.Key_V) { doPaste(); return true }
    if (ctrl && event.key === Qt.Key_F) { root.enterFind(); return true }
    if (ctrl && event.key === Qt.Key_R) { p.refresh(); return true }
    if (ctrl && event.key === Qt.Key_B) { sidebarVisible = !sidebarVisible; rememberSession(); return true }
    if (ctrl && event.key === Qt.Key_D) { toggleSplit(); return true }
    if (event.key === Qt.Key_F1) { showDialog("shortcuts", "Keyboard shortcuts", "", null); return true }

    if (event.key === Qt.Key_Tab) {
      if (split) { activeSide = otherSide(); return true }
      return true
    }
    if (event.key === Qt.Key_F2) { doRename(); return true }
    if (event.key === Qt.Key_F5) { transferToOtherPane("copy"); return true }
    if (event.key === Qt.Key_F6) { transferToOtherPane("move"); return true }
    if (event.key === Qt.Key_F7) { showDialog("newfolder", "New folder", "untitled folder", null); return true }
    if (event.key === Qt.Key_Delete) {
      if (shiftKey) askDelete(null)
      else doTrash()
      return true
    }
    if (event.key === Qt.Key_Backspace) { p.goUp(); return true }
    if (alt && event.key === Qt.Key_Left) { p.goBack(); return true }
    if (alt && event.key === Qt.Key_Right) { p.goForward(); return true }
    if (alt && event.key === Qt.Key_Up) { p.goUp(); return true }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { p.activateCursor(); return true }
    if (event.key === Qt.Key_Down) { p.moveCursor(1, shiftKey); return true }
    if (event.key === Qt.Key_Up) { p.moveCursor(-1, shiftKey); return true }
    if (event.key === Qt.Key_PageDown) { p.moveCursor(12, shiftKey); return true }
    if (event.key === Qt.Key_PageUp) { p.moveCursor(-12, shiftKey); return true }
    if (event.key === Qt.Key_Home) { p.jumpCursor(0, shiftKey); return true }
    if (event.key === Qt.Key_End) { p.jumpCursor(p.rows.length - 1, shiftKey); return true }
    return false
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

  Connections {
    target: root.service
    enabled: root.service !== null
    function onConflictRaised(jobId, info) {
      root.showDialog("conflict", "File exists", "", { jobId: jobId, info: info })
    }
  }

  FloatingWindow {
    id: window
    title: "Omafile"
    color: Color.background
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(640, 420)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) root.requestClose()
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
              anchors.verticalCenter: parent.verticalCenter
              iconText: Icons.actionGlyph(root.activePane() && root.activePane().view === "grid" ? "list" : "grid")
              tooltipText: "Switch view"
              onClicked: {
                var p = root.activePane()
                p.view = p.view === "grid" ? "list" : "grid"
                root.rememberSession()
              }
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
              iconText: Icons.actionGlyph("split")
              tooltipText: root.split ? "Close the second pane" : "Split into two panes"
              selected: root.split
              onClicked: root.toggleSplit()
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: Icons.actionGlyph("menu")
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
          }
        }

        Row {
          width: parent.width
          height: parent.height - toolbar.height - statusBar.height
          spacing: 0

          SidebarPlaces {
            id: sidebar
            width: root.sidebarVisible ? Style.space(190) : 0
            height: parent.height
            visible: root.sidebarVisible
            service: root.service
            currentPath: root.activePane() ? root.activePane().path : ""
            showDrives: root.service ? root.service.setting("showDrives", true) !== false : true
            onNavigate: function (target) { root.activePane().navigate(target) }
            onOpenInNewTab: function (target) { root.newTab(root.activeSide, target) }
            onRemoveBookmark: function (target) { root.service.togglePinned(target) }
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
                visible: root.tabsA.length > 1
                onSelectTab: function (index) { root.selectTab(0, index) }
                onCloseTab: function (index) { root.closeTab(0, index) }
                onAddTab: root.newTab(0, null)
              }

              PaneView {
                id: paneA
                width: parent.width
                height: parent.height - (tabStripA.visible ? tabStripA.height : 0)
                service: root.service
                active: root.activeSide === 0
                onActivated: root.activeSide = 0
                onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
                onNavigated: function (p) { root.rememberSession() }
                onContextRequested: function (entry, x, y) {
                  root.menuEntry = entry
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
                visible: root.tabsB.length > 1
                onSelectTab: function (index) { root.selectTab(1, index) }
                onCloseTab: function (index) { root.closeTab(1, index) }
                onAddTab: root.newTab(1, null)
              }

              PaneView {
                id: paneB
                width: parent.width
                height: parent.height - (tabStripB.visible ? tabStripB.height : 0)
                service: root.service
                active: root.activeSide === 1
                onActivated: root.activeSide = 1
                onOpenRequested: function (entry) { root.handleOpenRequest(entry) }
                onNavigated: function (p) { root.rememberSession() }
                onContextRequested: function (entry, x, y) {
                  root.menuEntry = entry
                  root.menuX = x + (root.sidebarVisible ? sidebar.width : 0) + sideA.width
                  root.menuY = y + toolbar.height + (tabStripB.visible ? tabStripB.height : 0)
                  root.menuOpen = true
                }
              }
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
        anchors.fill: parent
        visible: root.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.menuOpen = false
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
            model: root.menuOpen ? root.contextActions(root.menuEntry) : []

            delegate: Item {
              required property var modelData
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
                color: itemHover.hovered && !modelData.disabled
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
                      : (itemHover.hovered ? Color.menu.selectedText : Color.menu.text)
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
          anchors.centerIn: parent
          width: root.dialogMode === "shortcuts" ? Style.space(470)
            : ((root.dialogMode === "openwith" || root.dialogMode === "properties")
              ? Style.space(420) : Style.space(360))
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
              placeholderText: "Search applications"
              onTextChanged: root.appFilter = text
              Keys.onEscapePressed: root.closeDialog()
            }

            ListView {
              width: parent.width
              height: Style.space(240)
              visible: root.dialogMode === "openwith"
              clip: true
              model: root.dialogMode === "openwith" ? root.filteredApps() : []

              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Style.space(26)
                color: appHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent"
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
                  onClicked: {
                    var entry = root.dialogPayload
                    root.closeDialog()
                    if (entry) root.service.openWith(modelData.execString, entry.path)
                  }
                }
              }
            }

            Flickable {
              width: parent.width
              height: Math.min(Style.space(430), shortcutColumn.implicitHeight)
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
                text: root.isReadOnlyDialog() ? "Close" : "Confirm"
                bordered: true
                onClicked: {
                  if (root.isReadOnlyDialog()) root.closeDialog()
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
          keyCatcher.forceActiveFocus()
        }
        onConfirmed: {
          confirm.opened = false
          var targets = root.dialogPayload
          root.dialogPayload = null
          if (targets) root.performDelete(targets)
          keyCatcher.forceActiveFocus()
        }
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
      { keys: "Backspace", label: "Go to the parent folder" },
      { keys: "Alt+Left / Alt+Right", label: "Back and forward" },
      { keys: "Ctrl+L", label: "Type a path" },
      { keys: "Home / End", label: "First and last item" },
      { section: "Selection" },
      { keys: "Ctrl+Click", label: "Add one item to the selection" },
      { keys: "Shift+Click", label: "Select a range" },
      { keys: "Ctrl+A", label: "Select everything" },
      { section: "Files" },
      { keys: "Ctrl+C / Ctrl+X / Ctrl+V", label: "Copy, cut and paste" },
      { keys: "F2", label: "Rename" },
      { keys: "F7", label: "New folder" },
      { keys: "Delete", label: "Move to trash" },
      { keys: "Shift+Delete", label: "Delete permanently" },
      { section: "Panes and tabs" },
      { keys: "Ctrl+T / Ctrl+W", label: "New tab and close tab" },
      { keys: "Ctrl+D", label: "Split into two panes" },
      { keys: "Tab", label: "Switch the active pane" },
      { keys: "F5 / F6", label: "Copy and move to the other pane" },
      { section: "View" },
      { keys: "Ctrl+H", label: "Show hidden files" },
      { keys: "Ctrl+F", label: "Search in this folder" },
      { keys: "Ctrl+B", label: "Show or hide the sidebar" },
      { keys: "Ctrl+R", label: "Refresh" },
      { keys: "F1", label: "This list" },
      { keys: "Escape", label: "Leave search, then close the window" },
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
    return dialogMode === "properties" || dialogMode === "openwith" || dialogMode === "shortcuts"
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
