import QtQuick 6.11
import QtTest
import Quickshell
import "FilePlugin/components" as Plugin
import "FilePlugin/tests" as Mocks
import "FilePlugin/Model.js" as Model
ShellRoot {
  id: harness
  property bool passed: false
  Mocks.MockService { id: mock }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1000; implicitHeight: 640
    Plugin.Browser { id: browser; anchors.fill: parent; service: mock }
    TestCase {
      id: tests
      name: "BrowserFlows"
      when: window.visible
      onCompletedChanged: {
        if (!harness.passed) console.log("OMAFILE_BROWSER_FLOWS_FAILED")
        Qt.quit()
      }
      property int failures: 0
      function cleanup() {
        if (qtest_results.failed) { failures++; console.log("FAILED_IN " + qtest_results.functionName) }
      }
      function pane() { return browser.activePane() }
      function names() { return pane().rows.map(function (r) { return r[0] }) }
      function waitRows() { tryVerify(function () { return pane().rows.length === 3 && !pane().loading }, 5000) }
      function menuItem(label) {
        var idx = -1
        for (var i = 0; i < browser.menuActions.length; i++) if (browser.menuActions[i].label === label) idx = i
        verify(idx >= 0, "menu item " + label)
        browser.runAction(browser.menuActions[idx].key)
      }

      function test_1_openWith() {
        waitRows()
        tryVerify(function () { return DesktopEntries.applications.values.length > 0 }, 10000)
        pane().setCursor(0, false, false)
        browser.menuEntry = pane().cursorEntry()
        browser.runAction("openwith")
        compare(browser.dialogMode, "openwith")
        var list = findChild(browser, "openWithList")
        wait(200)
        mouseClick(list.itemAtIndex(0))
        compare(browser.dialogMode, "openwith")
        compare(mock.called("openWith"), null, "single click only selects")
        mouseDoubleClickSequence(list.itemAtIndex(0))
        var call = mock.called("openWith")
        verify(call !== null, "openWith called by click")
        compare(call.args[1], ["/tmp/alpha.yml"])
        compare(browser.dialogMode, "")
      }

      function openWithDialogFor(index) {
        if (browser.dialogMode !== "") browser.closeDialog()
        mock.calls = []
        waitRows()
        tryVerify(function () { return DesktopEntries.applications.values.length > 0 }, 10000)
        pane().setCursor(index, false, false)
        browser.menuEntry = pane().cursorEntry()
        browser.runAction("openwith")
        compare(browser.dialogMode, "openwith")
        wait(200)
      }

      function test_1b_openButtonLaunchesSelection() {
        openWithDialogFor(0)
        var list = findChild(browser, "openWithList")
        var button = findChild(browser, "dialogConfirmButton")
        compare(button.text, "Open")
        verify(button.enabled)
        mouseClick(list.itemAtIndex(1))
        compare(browser.appCursor, 1)
        compare(mock.called("openWith"), null, "selecting does not launch")
        mouseClick(button)
        var call = mock.called("openWith")
        verify(call !== null, "Open button launches")
        compare(call.args[1], ["/tmp/alpha.yml"])
        compare(mock.called("setDefaultApp"), null, "no default without the toggle")
        compare(browser.dialogMode, "")
      }

      function test_1c_alwaysSetsDefault() {
        openWithDialogFor(0)
        var list = findChild(browser, "openWithList")
        var toggle = findChild(browser, "appAlwaysToggle")
        verify(toggle.visible)
        compare(toggle.label, "Always open " + Model.extensionLabel("yml") + " (*.yml) with this app")
        mouseClick(toggle)
        verify(browser.appAlways)
        var chosen = String(list.model[1].id)
        mouseClick(list.itemAtIndex(1))
        mouseClick(findChild(browser, "dialogConfirmButton"))
        var call = mock.called("setDefaultApp")
        verify(call !== null, "setDefaultApp called")
        compare(call.args[0], "/tmp/alpha.yml")
        compare(call.args[1], chosen)
        verify(mock.called("openWith") !== null, "app still launches")
      }

      function test_1d_toggleResetsEachTime() {
        openWithDialogFor(0)
        mouseClick(findChild(browser, "appAlwaysToggle"))
        verify(browser.appAlways)
        browser.closeDialog()
        openWithDialogFor(0)
        verify(!browser.appAlways)
        browser.closeDialog()
      }

      function test_1e_openDisabledWithoutChoice() {
        openWithDialogFor(0)
        var button = findChild(browser, "dialogConfirmButton")
        verify(button.enabled)
        browser.appFilter = "   "
        compare(browser.filteredApps().length, 0)
        verify(!button.enabled, "disabled with nothing to open")
        mouseClick(button)
        compare(browser.dialogMode, "openwith", "dialog stays open")
        compare(mock.called("openWith"), null)
        browser.appFilter = "zzqq-not-an-app"
        verify(button.enabled, "enabled again for a typed command")
        browser.closeDialog()
      }

      function test_1f_typedCommandIgnoresToggle() {
        openWithDialogFor(0)
        mouseClick(findChild(browser, "appAlwaysToggle"))
        browser.appFilter = "zzqq-not-an-app"
        browser.appCursor = -1
        mouseClick(findChild(browser, "dialogConfirmButton"))
        verify(mock.called("runCommandOn") !== null, "typed command runs")
        compare(mock.called("setDefaultApp"), null, "typed command sets no default")
      }

      function test_1g_noToggleForFolders() {
        openWithDialogFor(2)
        verify(!findChild(browser, "appAlwaysToggle").visible)
        var list = findChild(browser, "openWithList")
        browser.appAlways = true
        mouseClick(list.itemAtIndex(0))
        mouseClick(findChild(browser, "dialogConfirmButton"))
        verify(mock.called("openWith") !== null, "folder still opens with the app")
        compare(mock.called("setDefaultApp"), null, "folders never get a default")
      }

      function test_1h_enterInOpenWithLaunchesOnce() {
        openWithDialogFor(0)
        var field = findChild(browser, "appField")
        tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_E)
        verify(browser.filteredApps().length > 0)
        keyClick(Qt.Key_Return)
        compare(browser.dialogMode, "")
        compare(count("openWith"), 1, "Enter launches the chosen app once")
        compare(mock.called("openExternally"), null, "and never opens the file in the default app too")

        openWithDialogFor(0)
        tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_Z)
        keyClick(Qt.Key_Q)
        keyClick(Qt.Key_Q)
        browser.appCursor = -1
        keyClick(Qt.Key_Return)
        compare(count("runCommandOn"), 1, "Enter runs a typed command once")
        compare(mock.called("openExternally"), null)
      }

      function test_2_sortMenu() {
        waitRows()
        mouseClick(findChild(browser, "viewButton"))
        verify(browser.menuOpen)
        compare(browser.menuKind, "view")
        menuItem("Z to A")
        verify(!browser.menuOpen)
        compare(pane().sortBy, "name")
        compare(pane().descending, true)
        browser.setView("grid")
        mouseClick(findChild(browser, "viewButton"))
        menuItem("Last modified")
        compare(pane().sortBy, "modified")
        compare(pane().descending, true)
        compare(names()[0], "docs")
        compare(names()[1], "alpha.yml")
        browser.setView("list")
      }

      function test_3_viewMenu() {
        waitRows()
        var modes = [["Compact", "compact"], ["Gallery", "gallery"], ["Grid", "grid"], ["List", "list"]]
        for (var i = 0; i < modes.length; i++) {
          mouseClick(findChild(browser, "viewButton"))
          compare(browser.menuKind, "view")
          menuItem(modes[i][0])
          compare(pane().view, modes[i][1])
          wait(50)
          mouseClick(pane(), 60, pane().view === "list" ? 40 : 20)
          compare(pane().selectedCount, 1, "click selects in " + modes[i][1])
        }
      }

      function test_3a_thumbnailRequests() {
        waitRows()
        browser.setView("grid")
        waitForRendering(browser)
        var call = mock.called("thumbnailFor")
        verify(call !== null, "grid asks for a generated thumbnail")
        compare(call.args[0], "/tmp/alpha.yml")
        compare(call.args[2], "large")
        for (var i = 0; i < mock.calls.length; i++)
          if (mock.calls[i].name === "thumbnailFor") verify(mock.calls[i].args[0] !== "/tmp/beta.png", "no thumbnailer is set up for png in the mock")
        var grid = []
        function walk(item) {
          if (item.hasOwnProperty("generated") && item.hasOwnProperty("cachedPath")) grid.push(item)
          for (var j = 0; j < item.children.length; j++) walk(item.children[j])
        }
        walk(browser)
        verify(grid.length > 0)
        for (var k = 0; k < grid.length; k++) verify(String(grid[k].source).indexOf("/tmp/beta.png") < 0, "images are never decoded straight from the file")
        browser.setView("list")
      }

      function test_3aa_galleryView() {
        waitRows()
        keyClick(Qt.Key_4, Qt.ControlModifier)
        compare(pane().view, "gallery", "Ctrl+4 opens the gallery")
        waitForRendering(browser)
        var bucket = ""
        for (var i = 0; i < mock.calls.length; i++)
          if (mock.calls[i].name === "thumbnailFor" && mock.calls[i].args[0] === "/tmp/alpha.yml") bucket = mock.calls[i].args[2]
        compare(bucket, "x-large", "the gallery asks for large previews")
        keyClick(Qt.Key_1, Qt.ControlModifier)
        compare(pane().view, "list")
      }

      function test_3ab_folderViews() {
        pane().navigate("/tmp")
        waitRows()
        mock.folderViews = ({})
        browser.setView("grid")
        pane().navigate("/tmp/docs")
        tryVerify(function () { return pane().path === "/tmp/docs" })
        compare(pane().view, "list", "a folder without a saved view opens in the default view")
        browser.setView("gallery")
        pane().goBack()
        tryVerify(function () { return pane().path === "/tmp" })
        compare(pane().view, "grid", "a folder opens in its own view")
        pane().goForward()
        tryVerify(function () { return pane().path === "/tmp/docs" })
        compare(pane().view, "gallery")
        mock.updateSetting("rememberFolderViews", false)
        browser.setView("compact")
        pane().navigate("/tmp")
        tryVerify(function () { return pane().path === "/tmp" })
        compare(pane().view, "compact", "with the setting off the tab keeps its view")
        compare(mock.folderViews["/tmp/docs"], "gallery", "with the setting off nothing new is saved")
        mock.updateSetting("rememberFolderViews", true)
        mock.folderViews = ({})
        browser.setView("list")
        mock.folderViews = ({})
        waitRows()
      }

      function test_3b_zoomAndMenus() {
        waitRows()
        browser.setViewScale(1)
        mouseClick(findChild(browser, "viewButton"))
        compare(browser.menuKind, "view")
        waitForRendering(browser)
        mouseClick(findChild(browser, "zoom-in"))
        verify(browser.menuOpen, "zoom keeps the menu open")
        compare(browser.viewScale, 1.1)
        mouseClick(findChild(browser, "zoom-in"))
        compare(browser.viewScale, 1.2)
        mouseClick(findChild(browser, "zoom-out"))
        compare(browser.viewScale, 1.1)
        compare(pane().viewScale, 1.1)
        mouseClick(findChild(browser, "zoom-reset"))
        compare(browser.viewScale, 1)
        var hidden = pane().showHidden
        menuItem("Show hidden files")
        compare(pane().showHidden, !hidden)
        verify(!browser.menuOpen)
        pane().showHidden = hidden
        mouseWheel(pane(), 200, 200, 0, 120, Qt.NoButton, Qt.ControlModifier)
        compare(browser.viewScale, 1.1)
        mouseWheel(pane(), 200, 200, 0, -240, Qt.NoButton, Qt.ControlModifier)
        compare(browser.viewScale, 0.9)
        for (var i = 0; i < 30; i++) mouseWheel(pane(), 200, 200, 0, 120, Qt.NoButton, Qt.ControlModifier)
        compare(browser.viewScale, 3)
        for (var j = 0; j < 30; j++) mouseWheel(pane(), 200, 200, 0, -120, Qt.NoButton, Qt.ControlModifier)
        compare(browser.viewScale, 0.5)
        browser.setViewScale(1)
        mouseClick(findChild(browser, "mainMenuButton"))
        compare(browser.menuKind, "main")
        menuItem("Keyboard shortcuts")
        compare(browser.dialogMode, "shortcuts")
        browser.closeDialog()
      }

      function test_3d_newTabKeepsView() {
        waitRows()
        browser.setView("grid")
        pane().setSortOrder("modified", true)
        pane().showHidden = true
        keyClick(Qt.Key_T, Qt.ControlModifier)
        compare(browser.tabsA.length, 2)
        waitRows()
        compare(pane().view, "grid")
        compare(pane().sortBy, "modified")
        compare(pane().descending, true)
        compare(pane().showHidden, true)
        browser.closeTab(0, 1)
        browser.setView("list")
        pane().setSortOrder("name", false)
        pane().showHidden = false
        waitRows()
      }

      function test_3e_breadcrumbDrops() {
        mock.updateSetting("dropAction", "move")
        var bar = findChild(browser, "pathBar")
        verify(bar !== null)
        compare(bar.crumbTarget({ path: "~" }), bar.home || "/")
        compare(bar.crumbTarget({ path: "~/docs" }), (bar.home || "") + "/docs")
        compare(bar.crumbTarget({ path: "/tmp" }), "/tmp")
        mock.calls = []
        var target = findChild(bar, "locationDrop")
        verify(target !== null)
        target.filesDropped(["file:///tmp/docs/inner.txt"], "/tmp", bar.mapToGlobal(20, 20))
        compare(mock.called("beginTransfer").args[0], "move")
        compare(mock.called("beginTransfer").args[2], "/tmp")
        var crumb = findChild(bar, "crumbDrop0")
        verify(crumb !== null)
        mock.calls = []
        crumb.filesDropped(["file:///tmp/docs/inner.txt"], "/tmp", bar.mapToGlobal(20, 20))
        compare(mock.called("beginTransfer").args[2], "/tmp")
        mock.updateSetting("dropAction", "auto")
      }

      function test_3f_clipboard() {
        waitRows()
        pane().setSortOrder("name", false)
        pane().setCursor(0, false, false)
        mock.calls = []
        keyClick(Qt.Key_X, Qt.ControlModifier)
        compare(mock.called("setClipboard").args[0], "cut")
        compare(mock.called("setClipboard").args[1], ["/tmp/alpha.yml"])
        browser.setView("grid")
        waitForRendering(browser)
        var mark = findChild(pane(), "cutMark")
        verify(mark !== null && mark.visible, "cut items show the scissors mark")

        mock.systemClipboard = { mode: "cut", paths: ["/tmp/alpha.yml"], image: "" }
        pane().navigate("/tmp/docs")
        waitRows()
        mock.calls = []
        keyClick(Qt.Key_V, Qt.ControlModifier)
        compare(mock.called("beginTransfer").args[0], "move")
        compare(mock.called("beginTransfer").args[2], "/tmp/docs")
        verify(mock.called("clearClipboard") !== null, "a cut is used up by pasting")

        mock.systemClipboard = { mode: "copy", paths: [], image: "image/png" }
        keyClick(Qt.Key_V, Qt.ControlModifier)
        compare(mock.called("pasteImage").args[0], "/tmp/docs")

        mock.systemClipboard = null
        mock.clipboard = { mode: "copy", paths: ["/tmp/beta.png"] }
        mock.calls = []
        keyClick(Qt.Key_V, Qt.ControlModifier)
        compare(mock.called("beginTransfer").args[0], "copy", "falls back to the internal clipboard")
        mock.clipboard = { mode: "", paths: [] }
        mock.cutPaths = ({})
        pane().navigate("/tmp")
        browser.setView("list")
        waitRows()
      }

      function transfer(id, state) {
        return { id: id, op: "copy", label: "clip.mp4", dest: "/home/me/Videos", from: "/home/me/Downloads",
          state: state, bytes: state === "done" ? 10 : 4, total: 10, files: 1, filesTotal: 2, current: "/home/me/Downloads/clip.mp4",
          rate: 2, errors: [], startedMs: Date.now() - 1000, finishedMs: state === "done" ? Date.now() : 0, count: 1 }
      }

      function test_3g_transfersAndStatus() {
        var panel = findChild(browser, "transferPanel")
        var chip = findChild(browser, "transferChip")
        browser.statusText = "Moving 3 items to Test"
        mock.transfers = [transfer(1, "running")]
        wait(200)
        mock.transfers = [transfer(1, "done")]
        wait(1100)
        verify(!panel.visible, "a quick transfer never pops the panel up")
        verify(chip.visible, "finished transfers stay reachable from the status bar")

        mock.transfers = [transfer(1, "done"), transfer(2, "running")]
        tryVerify(function () { return panel.visible }, 2000, "a slow transfer opens the panel")
        compare(browser.transfersAutoOpened, true)
        var row = findChild(panel, "transfer-2")
        verify(row !== null)
        compare(row.open, false)
        mouseClick(row, 40, 8)
        compare(row.open, true, "clicking a transfer shows its details")
        var moved = transfer(2, "running")
        moved.bytes = 7
        mock.transfers = [transfer(1, "done"), moved]
        wait(50)
        verify(findChild(panel, "transfer-2") === row, "progress updates keep the same row")
        compare(row.open, true, "and keep it expanded")
        compare(row.item.bytes, 7)
        mouseClick(findChild(row, "cancelTransfer"))
        compare(mock.called("cancelTransfer").args[0], 2, "the stop button works mid transfer")

        mouseClick(findChild(panel, "minimizeTransfers"))
        verify(!panel.visible, "minimize hides the panel")
        mock.transfers = [transfer(1, "done"), transfer(2, "running"), transfer(3, "running")]
        wait(1100)
        verify(!panel.visible, "stays minimized while more work runs")
        mouseClick(chip)
        verify(panel.visible, "the status bar chip reopens it")

        mouseClick(findChild(panel, "clearCompleted"))
        verify(mock.called("clearFinishedTransfers") !== null)
        compare(mock.transfers.length, 2)
        mock.transfers = [transfer(2, "done")]
        wait(100)
        verify(panel.visible, "a panel the user opened stays open when work finishes")
        var doneRow = null
        tryVerify(function () { doneRow = findChild(panel, "transfer-2"); return doneRow !== null && doneRow.live === false }, 2000)
        mouseClick(findChild(doneRow, "clearTransfer"))
        compare(mock.called("clearTransfer").args[0], 2)
        verify(!panel.visible && !chip.visible, "nothing left, nothing shown")
        browser.transfersMinimized = false

        tryVerify(function () { return browser.statusText === "" }, 5000, "status messages fade out")
      }

      function count(name) {
        var n = 0
        for (var i = 0; i < mock.calls.length; i++) if (mock.calls[i].name === name) n++
        return n
      }

      function test_3h_liveUpdates() {
        waitRows()
        browser.setView("list")
        pane().setSortOrder("name", false)
        pane().setCursor(1, false, false)
        compare(pane().cursorEntry().name, "beta.png")
        mock.calls = []
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 999, mtime: 500, mode: 420, linkTarget: null },
          "/tmp/new.txt": { kind: "f", size: 5, mtime: 600, mode: 420, linkTarget: null } }
        mock.watchCallback({ names: ["alpha.yml", "new.txt"] })
        tryVerify(function () { return names().indexOf("new.txt") >= 0 }, 2000, "new file appears")
        compare(count("listDirectory"), 0, "named changes are patched, not re-listed")
        compare(pane().rows.filter(function (r) { return r[0] === "alpha.yml" })[0][2], 999)
        compare(pane().cursorEntry().name, "beta.png", "cursor stays on the same file")
        compare(pane().selectedCount, 1)

        mock.calls = []
        for (var i = 0; i < 6; i++) mock.watchCallback({ names: ["alpha.yml"] })
        wait(400)
        verify(count("statPaths") <= 1, "bursts are throttled, got " + count("statPaths"))

        mock.statItems = ({})
        wait(1100)
        mock.calls = []
        mock.watchCallback({ names: ["new.txt"] })
        tryVerify(function () { return names().indexOf("new.txt") < 0 }, 2500, "deleted file disappears")

        wait(1100)
        mock.calls = []
        mock.watchCallback({ names: [] })
        for (var t = 0; t < 20; t++) {
          verify(pane().rows.length > 0, "a full refresh never blanks the view")
          wait(60)
        }
        compare(count("listDirectory"), 1)
        waitRows()
        mock.statItems = ({})
      }

      function test_3ha_liveUpdatesKeepRows() {
        waitRows()
        browser.setView("list")
        pane().setSortOrder("name", false)
        var list = findChild(pane(), "fileList")
        verify(list !== null, "file list")
        var before = []
        for (var i = 0; i < 3; i++) before.push(list.itemAtIndex(i))
        var at = names().indexOf("alpha.yml")
        wait(1100)
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 777, mtime: 700, mode: 420, linkTarget: null } }
        mock.watchCallback({ names: ["alpha.yml"] })
        tryVerify(function () { return pane().rows[at][2] === 777 }, 2500, "size updates")
        for (var j = 0; j < 3; j++) verify(list.itemAtIndex(j) === before[j], "row " + j + " keeps its delegate")
        compare(list.itemAtIndex(at).entry.size, 777)

        wait(1100)
        mock.statItems = { "/tmp/new.txt": { kind: "f", size: 5, mtime: 600, mode: 420, linkTarget: null } }
        mock.watchCallback({ names: ["new.txt"] })
        tryVerify(function () { return names().indexOf("new.txt") >= 0 }, 2500, "new file appears")
        for (var k = 0; k < 3; k++) {
          var name = before[k].entry.name
          verify(list.itemAtIndex(names().indexOf(name)) === before[k], name + " keeps its delegate")
        }

        mock.statItems = ({})
        wait(1100)
        mock.watchCallback({ names: [] })
        waitRows()
      }

      function test_3hb_filterResetKeepsScrolling() {
        waitRows()
        browser.setView("list")
        var saved = mock.files
        var many = []
        for (var i = 0; i < 400; i++) many.push(["file-" + (1000 + i) + ".txt", "f", i, i, 420, null])
        mock.files = many
        pane().refresh()
        tryVerify(function () { return pane().rows.length === 400 }, 5000)
        var list = findChild(pane(), "fileList")
        wait(300)
        list.contentY = 3000
        tryVerify(function () { return list.contentY > 2000 }, 2000, "the list scrolls down")
        wait(100)
        pane().filter = "file-11"
        tryVerify(function () { return pane().rows.length === 100 }, 2000)
        pane().filter = ""
        tryVerify(function () { return pane().rows.length === 400 }, 2000)
        wait(100)
        compare(list.originY, 0, "replacing every row starts the list afresh")
        list.positionViewAtBeginning()
        wait(100)
        compare(list.indexAt(10, list.contentY + 5), 0, "the first row shows at the top")
        mock.files = saved
        pane().refresh()
        waitRows()
      }

      function beginPick() {
        browser.beginPickSession()
        tryCompare(browser, "pickInputHeld", false)
      }

      function menuLabels(items) { return items.filter(function (i) { return i.label !== "" }).map(function (i) { return i.label }) }

      function test_3i_sidebarMenu() {
        verify(menuLabels(browser.placeMenuActions({ key: "pinned", bookmark: true, label: "Work", path: "/tmp/work" })).indexOf("Remove bookmark") >= 0)
        verify(menuLabels(browser.placeMenuActions({ key: "networkdrive", label: "laptop", path: "/run/user/1000/gvfs/sftp:host=laptop", mounted: true })).indexOf("Disconnect") >= 0)
        var trash = browser.placeMenuActions({ key: "trash", label: "Trash", path: "/tmp/.trash", trash: true })
        compare(trash.filter(function (i) { return i.label === "Empty trash" })[0].disabled, true)
        verify(menuLabels(browser.placeMenuActions({ key: "recent", label: "Recent", path: "recent:" })).indexOf("Copy path") < 0)

        mock.calls = []
        browser.runPlaceAction("copypath", { key: "home", label: "Home", path: "/home/me" })
        compare(mock.called("copyToClipboardText").args[0], "/home/me")

        var homeRow = findChild(browser, "place-home")
        verify(homeRow !== null)
        mock.calls = []
        mouseClick(homeRow, 20, homeRow.height / 2, Qt.RightButton)
        verify(browser.menuOpen, "right click opens a menu")
        compare(browser.menuKind, "sidebar")
        compare(mock.called("toggleHiddenDrive"), null, "right click no longer hides anything")
        compare(menuLabels(browser.menuActions)[0], "Open")
        browser.closeMenu()
      }

      function test_3j_bookmarks() {
        mock.calls = []
        mock.statItems = { "/tmp/docs": { kind: "d", size: 0, mtime: 1, mode: 16877, linkTarget: null },
          "/tmp/alpha.yml": { kind: "f", size: 3, mtime: 1, mode: 420, linkTarget: null } }
        browser.bookmarkFolders(["/tmp/docs", "/tmp/alpha.yml"])
        compare(mock.called("addBookmarks").args[0], ["/tmp/docs"], "only folders are bookmarked")
        compare(browser.statusText, "1 folder bookmarked")
        mock.statItems = ({})

        var row = { key: "pinned", bookmark: true, label: "docs", path: "/tmp/docs" }
        verify(menuLabels(browser.placeMenuActions(row)).indexOf("Rename bookmark") >= 0)
        browser.runPlaceAction("renamebookmark", row)
        compare(browser.dialogMode, "bookmarkname")
        var field = findChild(browser, "dialogField")
        verify(field !== null)
        tryCompare(field, "text", "docs")
        field.text = "Project docs"
        browser.submitDialog()
        compare(mock.called("renameBookmark").args[0], "/tmp/docs")
        compare(mock.called("renameBookmark").args[1], "Project docs")
        compare(browser.dialogMode, "")

        var server = { key: "networkdrive", label: "laptop", path: "", uri: "ssh://laptop", server: true, remembered: true }
        verify(menuLabels(browser.placeMenuActions(server)).indexOf("Forget this server") >= 0)
        mock.servers = ["ssh://laptop/home/menno/", "ssh://nas", "ssh://laptop/"]
        mock.calls = []
        browser.runPlaceAction("forget", server)
        compare(count("forgetServer"), 2, "every saved address for that server is forgotten")
        compare(mock.calls.filter(function (c) { return c.name === "forgetServer" }).map(function (c) { return c.args[0] }),
          ["ssh://laptop/home/menno/", "ssh://laptop/"])
        mock.servers = []
        mock.pinned = []
      }

      function networkRows() {
        var side = findChild(browser, "sidebar")
        var sections = side.sections()
        var out = { drives: [], network: [] }
        for (var i = 0; i < sections.length; i++) {
          if (sections[i].title === "Drives") out.drives = sections[i].rows
          if (sections[i].title === "Network") out.network = sections[i].rows.filter(function (r) { return r.connect !== true })
        }
        return out
      }

      function test_3k_networkEntries() {
        mock.servers = ["ssh://laptop/home/menno/", "ssh://laptop", "ssh://laptop/"]
        var rows = networkRows()
        compare(rows.network.length, 1, "three saved addresses are one server")
        compare(rows.network[0].label, "laptop")
        compare(rows.network[0].connected, false)
        compare(rows.network[0].uri, "ssh://laptop/home/menno/", "connects to the most recent address")

        mock.drives = [{ name: "laptop", label: "laptop", path: "/run/user/1000/gvfs/sftp:host=laptop",
          mount: "/run/user/1000/gvfs/sftp:host=laptop", network: true, gvfs: true, host: "laptop", user: "", port: "",
          free: 10, total: 20, fstype: "sftp", removable: false }]
        rows = networkRows()
        compare(rows.drives.length, 0, "a connected share is not listed under Drives")
        compare(rows.network.length, 1, "and is not listed twice under Network")
        compare(rows.network[0].label, "laptop")
        compare(rows.network[0].connected, true)
        verify(menuLabels(browser.placeMenuActions(rows.network[0])).indexOf("Disconnect") >= 0)
        verify(menuLabels(browser.placeMenuActions(rows.network[0])).indexOf("Forget this server") >= 0)
        mock.drives = []
        mock.servers = []
      }

      function sectionRows(id) {
        var groups = findChild(browser, "sidebar").sections()
        for (var i = 0; i < groups.length; i++) if (groups[i].id === id) return groups[i].rows
        return []
      }

      function placeIds() { return sectionRows("places").map(function (r) { return r.orderId }) }

      function test_3k_placeOrder() {
        var side = findChild(browser, "sidebar")
        mock.placeOrder = ({})
        compare(placeIds(), ["home", "recent", "root"])
        var first = browser.placeMenuActions(sectionRows("places")[0])
        compare(first.filter(function (i) { return i.label === "Move up" })[0].disabled, true)
        compare(first.filter(function (i) { return i.label === "Move down" })[0].disabled, false)
        compare(first.filter(function (i) { return i.label === "Reset order" })[0].disabled, true)

        browser.runPlaceAction("movedown", sectionRows("places")[0])
        compare(placeIds(), ["recent", "home", "root"])
        side.moveRow(sectionRows("places")[2], -2)
        compare(placeIds(), ["root", "recent", "home"])

        browser.enterSidebar()
        side.cursorIndex = 0
        keyClick(Qt.Key_Down, Qt.ControlModifier)
        compare(placeIds(), ["recent", "root", "home"])
        compare(side.cursorRow().orderId, "root", "the cursor follows the moved row")
        browser.leaveSidebar()

        wait(50)
        var recentRow = null
        var homeRow = null
        tryVerify(function () {
          recentRow = findChild(browser, "place-recent")
          homeRow = findChild(browser, "place-home")
          return recentRow !== null && homeRow !== null
        })
        var start = recentRow.mapToItem(side, 20, recentRow.height / 2)
        var end = homeRow.mapToItem(side, 20, homeRow.height * 0.75)
        var homeTop = homeRow.mapToItem(side, 0, 0).y
        mousePress(side, start.x, start.y)
        for (var step = 1; step <= 10; step++) mouseMove(side, start.x, start.y + (end.y - start.y) * step / 10, -1, Qt.LeftButton)
        compare(side.dragTo, 2, "the dragged row targets the slot under the pointer")
        tryVerify(function () { return Math.abs(homeRow.mapToItem(side, 0, 0).y - (homeTop - side.rowStep)) < 1 }, 2000, "the rows it passes slide up")
        mouseRelease(side, start.x, end.y)
        tryVerify(function () { return placeIds()[2] === "recent" }, 2000, "dragging a row drops it below the target")
        compare(placeIds(), ["root", "home", "recent"])

        wait(50)
        var header = findChild(browser, "section-places")
        verify(header !== null)
        mouseClick(header, 20, header.height / 2, Qt.RightButton)
        verify(browser.menuOpen)
        compare(menuLabels(browser.menuActions), ["Move section up", "Move section down", "Reset order", "Reset section order"])
        menuItem("Reset order")
        compare(placeIds(), ["home", "recent", "root"])
        browser.closeMenu()

        var server = sectionRows("network").filter(function (r) { return r.connect === true })[0]
        compare(menuLabels(browser.placeMenuActions(server)).indexOf("Move up"), -1, "Connect to a server stays last")
        mock.placeOrder = ({})
      }

      function sectionIds() { return findChild(browser, "sidebar").sections().map(function (g) { return g.id }) }

      function test_3k_sectionOrder() {
        var side = findChild(browser, "sidebar")
        mock.placeOrder = ({})
        wait(50)
        compare(sectionIds(), ["places", "bookmarks", "network"])
        var places = findChild(browser, "section-places")
        var bookmarks = findChild(browser, "section-bookmarks")
        var placesColumn = places.parent
        var bookmarksColumn = bookmarks.parent
        var bookmarksTop = bookmarksColumn.mapToItem(side, 0, 0).y
        var start = places.mapToItem(side, 20, places.height / 2)
        var offset = bookmarksColumn.y + bookmarksColumn.height / 2 - placesColumn.y - placesColumn.height / 2 + 4
        mousePress(side, start.x, start.y)
        for (var step = 1; step <= 10; step++) mouseMove(side, start.x, start.y + offset * step / 10, -1, Qt.LeftButton)
        compare(side.sectionDragTo, 1, "Places is dragged below Bookmarks")
        tryVerify(function () {
          var shift = side.sectionShift("bookmarks")
          return shift < -placesColumn.height && Math.abs(bookmarksColumn.mapToItem(side, 0, 0).y - (bookmarksTop + shift)) < 1
        }, 2000, "Bookmarks slides up into the space Places left")
        wait(50)
        mouseRelease(side, start.x, start.y + offset)
        tryVerify(function () { return sectionIds()[0] === "bookmarks" }, 2000, "the section order is saved")
        compare(sectionIds(), ["bookmarks", "places", "network"])
        compare(mock.called("setPlaceOrder").args[0], "sections")

        wait(50)
        var network = findChild(browser, "section-network")
        mouseClick(network, 20, network.height / 2, Qt.RightButton)
        verify(browser.menuOpen)
        compare(browser.menuActions.filter(function (i) { return i.label === "Move section down" })[0].disabled, true)
        menuItem("Move section up")
        compare(sectionIds(), ["bookmarks", "network", "places"])

        wait(50)
        network = findChild(browser, "section-network")
        mouseClick(network, 20, network.height / 2, Qt.RightButton)
        menuItem("Reset section order")
        compare(sectionIds(), ["places", "bookmarks", "network"])
        browser.closeMenu()
        mock.placeOrder = ({})
      }

      function test_3l_quickConnect() {
        mock.servers = ["ssh://laptop/home/menno/"]
        mock.serverSettings = { "ssh://laptop/home/menno/": { user: "menno", domain: "", anonymous: false } }
        mock.connectResult = { path: "/tmp/docs" }
        mock.calls = []
        browser.openServer("ssh://laptop/home/menno/")
        var call = mock.called("connectToServer")
        compare(call.args[0], "ssh://laptop/home/menno/")
        compare(call.args[1], "menno", "saved user name is reused")
        compare(call.args[3], "", "no password is stored or sent")
        compare(browser.dialogMode, "", "a saved server connects without the dialog")
        compare(pane().path, "/tmp/docs")
        pane().navigate("/tmp")
        waitRows()

        mock.connectResult = { error: "Permission denied" }
        browser.openServer("ssh://laptop/home/menno/")
        compare(browser.dialogMode, "connect", "a failed quick connect asks for details")
        var user = findChild(browser, "userField")
        tryCompare(user, "text", "menno")
        compare(browser.connectFailed, true)
        verify(browser.connectStatus.indexOf("Permission denied") === 0, browser.connectStatus)
        var password = findChild(browser, "passwordField")
        tryCompare(password, "activeFocus", true)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_B)
        keyClick(Qt.Key_Backspace)
        compare(password.text, "a", "the password field still edits")
        compare(password.editUndo.length, 0, "a password keeps no undo history")
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        compare(password.text, "a", "so undo cannot bring a typed password back")
        keyClick(Qt.Key_Y, Qt.ControlModifier)
        compare(password.text, "a", "and neither can redo")
        browser.closeDialog()

        mock.calls = []
        browser.openServer("smb://nas/media")
        compare(browser.dialogMode, "connect", "unknown servers open the dialog")
        compare(mock.called("connectToServer"), null)
        browser.closeDialog()

        var row = { key: "networkdrive", label: "laptop", path: "", uri: "ssh://laptop/home/menno/", server: true, remembered: true }
        verify(menuLabels(browser.placeMenuActions(row)).indexOf("Edit\u2026") >= 0)
        browser.runPlaceAction("editserver", row)
        compare(browser.dialogMode, "connect")
        tryCompare(findChild(browser, "serverField"), "text", "ssh://laptop/home/menno/")
        browser.closeDialog()
        mock.servers = []
        mock.serverSettings = ({})
        mock.connectResult = null
      }

      function test_3n_drives() {
        mock.drives = [
          { name: "sdb1", label: "Stick", path: "/dev/sdb1", mount: "/run/media/me/Stick", removable: true,
            fstype: "vfat", free: 1, total: 2 },
          { name: "sda2", label: "", path: "/dev/sda2", mount: "", removable: false, fstype: "ntfs", mountable: true },
          { name: "sda3", label: "", path: "/dev/sda3", mount: "", removable: false, fstype: "crypto_LUKS", mountable: false },
          { name: "boot", label: "", path: "/dev/sda1", mount: "/boot", removable: false, fstype: "vfat", free: 1, total: 2 }
        ]
        var drives = networkRows().drives
        compare(drives.length, 3, "unmountable partitions are not listed")
        var stick = drives[0], idle = drives[1], boot = drives[2]
        compare(stick.key, "usb")
        compare(stick.unmountable, true)
        compare(idle.unmounted, true)
        compare(idle.label, "sda2")
        compare(idle.hideKey, "/dev/sda2")
        compare(boot.unmountable, false)

        compare(menuLabels(browser.placeMenuActions(idle)), ["Mount", "Hide", "Move up", "Move down", "Reset order"])
        var labels = menuLabels(browser.placeMenuActions(stick))
        verify(labels.indexOf("Open") >= 0)
        verify(labels.indexOf("Unmount") >= 0)
        verify(labels.indexOf("Eject") >= 0)
        verify(labels.indexOf("Hide") >= 0)
        var bootItems = browser.placeMenuActions(boot)
        compare(bootItems.filter(function (i) { return i.label === "Unmount" })[0].disabled, true)
        verify(menuLabels(bootItems).indexOf("Eject") < 0)

        mock.calls = []
        browser.runPlaceAction("mount", idle)
        compare(mock.called("mountDrive").args[0], "/dev/sda2")
        compare(pane().path, "/tmp/docs", "a mounted drive opens")
        mock.mountResult = { error: "Not authorized" }
        browser.runPlaceAction("mount", idle)
        compare(browser.statusText, "Could not mount /dev/sda2: Not authorized")
        mock.mountResult = { path: "/tmp/docs" }

        pane().navigate("/run/media/me/Stick/photos")
        mock.calls = []
        browser.runPlaceAction("unmount", stick)
        compare(mock.called("unmountDrive").args[0], "/dev/sdb1")
        compare(pane().path, browser.home, "leaves the drive before unmounting")
        browser.runPlaceAction("eject", stick)
        compare(mock.called("ejectDrive").args[0], "/dev/sdb1")
        mock.calls = []
        browser.runPlaceAction("unmount", boot)
        compare(mock.called("unmountDrive"), null, "system mounts are never unmounted")
        browser.runPlaceAction("hidedrive", idle)
        compare(mock.called("toggleHiddenDrive").args[0], "/dev/sda2")

        mock.drives = []
        pane().navigate("/tmp")
        waitRows()
      }

      function test_3o_encryptedDrives() {
        mock.drives = [
          { name: "sda3", label: "", path: "/dev/sda3", mount: "", removable: false, fstype: "crypto_LUKS",
            size: 2000000000000, mountable: false, locked: true },
          { name: "sdb1", label: "Vault", path: "/dev/sdb1", mount: "", removable: true, fstype: "crypto_LUKS",
            size: 64000000000, mountable: false, locked: true },
          { name: "luks-1", label: "Inner", path: "/dev/mapper/luks-1", mount: "/run/media/me/Inner", removable: true,
            fstype: "ext4", free: 1, total: 2 }
        ]
        var drives = networkRows().drives
        compare(drives.length, 3)
        var bare = drives[0], vault = drives[1], inner = drives[2]
        compare(bare.locked, true)
        compare(bare.label, Model.formatSize(2000000000000) + " Encrypted")
        compare(vault.label, "Vault", "a LUKS label is shown as is")
        compare(inner.locked, false)
        compare(menuLabels(browser.placeMenuActions(bare)), ["Unlock…", "Hide", "Move up", "Move down", "Reset order"])

        mock.calls = []
        browser.runPlaceAction("unlock", bare)
        compare(browser.dialogMode, "unlock")
        compare(mock.called("mountDrive"), null, "a locked drive is never mounted directly")
        var field = findChild(browser, "unlockField")
        tryCompare(field, "activeFocus", true)
        browser.submitUnlock()
        compare(mock.called("unlockDrive"), null, "an empty passphrase is not sent")
        compare(browser.unlockFailed, true)

        mock.unlockResult = { code: "EPASSPHRASE", message: "wrong passphrase" }
        field.text = "nope"
        keyClick(Qt.Key_Return)
        compare(mock.called("unlockDrive").args[0], "/dev/sda3")
        compare(mock.called("unlockDrive").args[1], "nope")
        compare(browser.dialogMode, "unlock", "a wrong passphrase keeps the dialog open")
        compare(browser.unlockStatus, "Wrong passphrase. Try again.")
        compare(field.text, "", "a wrong passphrase is cleared")
        tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_B)
        compare(field.text, "ab", "typing edits the passphrase")
        compare(field.editUndo.length, 0, "a passphrase keeps no undo history")
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        compare(field.text, "ab", "and undo leaves it alone")

        mock.unlockResult = { path: "/tmp/docs" }
        mock.calls = []
        field.text = "correct horse"
        keyClick(Qt.Key_Return)
        compare(mock.called("unlockDrive").args[1], "correct horse")
        compare(browser.dialogMode, "", "the dialog closes once unlocked")
        compare(field.text, "", "the passphrase is not kept")
        compare(pane().path, "/tmp/docs", "an unlocked drive opens")

        mock.unlockResult = { path: "", device: "/dev/dm-1", message: "no filesystem" }
        browser.askUnlock(vault)
        field.text = "correct horse"
        browser.submitUnlock()
        compare(browser.dialogMode, "")
        compare(browser.statusText, "Unlocked Vault, but could not mount it: no filesystem")

        browser.askUnlock(vault)
        field.text = "typed"
        keyClick(Qt.Key_Escape)
        compare(browser.dialogMode, "")
        compare(field.text, "", "cancelling forgets the passphrase")

        mock.servers = ["ssh://laptop/"]
        mock.serverSettings = { "ssh://laptop/": { user: "menno", domain: "", anonymous: false } }
        mock.connectResult = { error: "Permission denied" }
        browser.askUnlock(vault)
        field.text = "half typed"
        browser.openServer("ssh://laptop/")
        compare(browser.dialogMode, "unlock", "a failed quick connect never replaces the unlock dialog")
        compare(browser.statusText, "Could not connect to laptop: Permission denied")
        browser.showDialog("shortcuts", "Keyboard shortcuts", "", null)
        compare(field.text, "", "another dialog taking over forgets the passphrase")
        compare(field.editUndo.length, 0, "and its undo history")
        browser.closeDialog()
        mock.servers = []
        mock.serverSettings = ({})
        mock.connectResult = null

        pane().navigate("/run/media/me/Inner")
        mock.unmountResult = { code: "ELOCK", message: "busy" }
        mock.calls = []
        browser.runPlaceAction("unmount", inner)
        compare(mock.called("unmountDrive").args[0], "/dev/mapper/luks-1")
        compare(browser.statusText, "Unmounted /run/media/me/Inner, but could not lock it: busy")
        mock.unmountResult = ({})
        verify(menuLabels(browser.placeMenuActions(inner)).indexOf("Eject") >= 0, "an encrypted stick can be ejected")

        mock.unlockResult = { path: "/tmp/docs" }
        mock.drives = []
        pane().navigate("/tmp")
        waitRows()
      }

      function test_3m_gridCaptions() {
        waitRows()
        pane().setSortOrder("name", false)
        browser.setView("grid")
        var grid = pane().activeView()
        var plainHeight = grid.cellHeight
        browser.applySettingNow("gridCaption1", "size")
        browser.applySettingNow("gridCaption2", "type")
        compare(pane().shownCaptions, ["size", "type"])
        verify(grid.cellHeight > plainHeight, "captions make room for themselves")
        var byName = function (n) { return Model.decodeEntry(pane().rows.filter(function (r) { return r[0] === n })[0], "/tmp") }
        pane().captionText(byName("docs"), "size")
        tryVerify(function () { return pane().captionText(byName("docs"), "size") === "3 items" }, 2000,
          "folders show how many items they hold")
        var alpha = byName("alpha.yml")
        compare(pane().captionText(alpha, "size"), Model.formatSize(30))
        compare(pane().captionText(alpha, "type"), Model.kindLabel(alpha))
        browser.setViewScale(0.8)
        compare(pane().shownCaptions, ["size"], "fewer captions when zoomed out")
        browser.setViewScale(1)
        waitForRendering(browser)
        var bg = findChild(grid.itemAtIndex(0), "cellBackground")
        verify(bg.width < grid.itemAtIndex(0).width, "tiles keep a margin around the selection")
        browser.applySettingNow("gridCaption1", "none")
        browser.applySettingNow("gridCaption2", "none")
        compare(pane().shownCaptions, [])
        browser.setView("list")
      }

      function test_4_mouseBackForward() {
        waitRows()
        pane().navigate("/tmp/docs")
        pane().navigate("/tmp/docs/inner")
        compare(pane().path, "/tmp/docs/inner")
        mouseClick(pane(), 200, 200, Qt.BackButton)
        compare(pane().path, "/tmp/docs")
        mouseClick(pane(), 200, 200, Qt.BackButton)
        compare(pane().path, "/tmp")
        mouseClick(pane(), 200, 200, Qt.ForwardButton)
        compare(pane().path, "/tmp/docs")
        pane().navigate("/tmp")
        waitRows()
      }

      function test_5_preview() {
        waitRows()
        pane().setSortOrder("name", false)
        pane().setCursor(0, false, false)
        compare(pane().cursorEntry().name, "alpha.yml")
        keyClick(Qt.Key_Space)
        verify(browser.previewOpen)
        compare(browser.previewKind, "text")
        compare(browser.previewText, "key: value\n")
        var text = findChild(browser, "previewText")
        verify(text.visible, "text preview visible")
        keyClick(Qt.Key_Right)
        compare(browser.previewEntry.name, "beta.png")
        compare(browser.previewKind, "image")
        var shown = findChild(browser, "previewImage")
        verify(String(shown.source).indexOf("/tmp/beta.png") < 0, "the original image never reaches the shell's decoder")
        keyClick(Qt.Key_Space)
        verify(!browser.previewOpen)
      }

      function test_5e_previewZoomAndPan() {
        waitRows()
        var savedExts = mock.thumbExts
        mock.thumbExts = { yml: true, png: true }
        mock.thumbResult = String(Qt.resolvedUrl("FilePlugin/icon.png")).replace(/^file:\/\//, "")
        mock.calls = []
        var png = Model.decodeEntry(["beta.png", "f", 10, 100, 420, null], "/tmp")
        browser.showPreview(png)
        var image = findChild(browser, "previewImage")
        tryCompare(image, "status", Image.Ready)
        verify(String(image.source).indexOf("/tmp/beta.png") < 0, "zooming still shows the helper's preview, never the original")
        compare(mock.called("thumbnailFor").args[2], "xx-large")
        var area = findChild(browser, "previewZoomArea")
        verify(area.enabled)

        mouseWheel(area, area.width / 2, area.height / 2, 0, 120)
        verify(browser.previewZoom > 1, "the wheel zooms in")
        browser.zoomPreviewAt(4, area.width / 2, area.height / 2)
        mouseDrag(area, area.width / 2, area.height / 2, 40, 30)
        verify(browser.previewPanX > 0 && browser.previewPanY > 0, "dragging pans")
        browser.panPreview(100000, -100000)
        var size = browser.previewPaintedSize(browser.previewZoom)
        compare(browser.previewPanX, Math.max(0, (size.w - area.width) / 2), "panning stops at the edge")
        compare(browser.previewPanY, -Math.max(0, (size.h - area.height) / 2))
        mouseDoubleClickSequence(area)
        compare(browser.previewZoom, 1, "a double click resets")
        compare(browser.previewPanX, 0)

        keyClick(Qt.Key_Equal)
        verify(browser.previewZoom > 1, "+ zooms in")
        keyClick(Qt.Key_Minus)
        compare(browser.previewZoom, 1, "- zooms back out")
        for (var i = 0; i < 30; i++) browser.zoomPreviewAt(1.25, 10, 10)
        compare(browser.previewZoom, browser.previewZoomMax)
        browser.panPreview(5, 5)
        browser.showPreview(Model.decodeEntry(["gamma.png", "f", 10, 100, 420, null], "/tmp"))
        compare(browser.previewZoom, browser.previewZoomMax, "the zoom stays while moving to the next picture")
        compare(browser.previewPanX, 0, "and the next picture starts centred")
        keyClick(Qt.Key_0)
        compare(browser.previewZoom, 1)
        browser.closePreview()

        compare(browser.previewSide, 1024, "automatic keeps the standard preview on a small window")
        verify(!findChild(browser, "previewBase").active, "and makes no second preview")

        function buckets() { return mock.calls.filter(function (c) { return c.name === "thumbnailFor" }).map(function (c) { return c.args[2] }) }
        mock.updateSetting("previewSize", "4096")
        mock.calls = []
        browser.showPreview(png)
        tryVerify(function () { return buckets().indexOf("preview-4096") >= 0 })
        verify(buckets().indexOf("xx-large") >= 0, "the standard preview shows while the big one is made")
        tryCompare(image, "status", Image.Ready)
        verify(!findChild(browser, "previewBase").visible, "the standard preview steps aside once the big one is ready")
        browser.closePreview()
        compare(browser.previewZoom, 1, "closing resets the zoom")

        mock.thumbResults = { "preview-4096": "" }
        mock.calls = []
        browser.showPreview(png)
        var base = findChild(browser, "previewBase")
        tryCompare(base, "status", Image.Ready)
        verify(base.visible, "if the big preview cannot be made the standard one stays")
        verify(browser.previewImageReady)
        verify(findChild(browser, "previewZoomArea").enabled, "and can still be zoomed")
        browser.closePreview()
        mock.thumbResults = ({})

        mock.updateSetting("previewSize", "7680")
        mock.calls = []
        browser.showPreview(png)
        tryVerify(function () { return buckets().indexOf("preview-7680") >= 0 })
        browser.closePreview()
        mock.updateSetting("previewSize", "auto")
        mock.thumbResult = ""
        mock.thumbExts = savedExts
      }

      function test_5b_audioPreview() {
        var tone = Quickshell.env("OMAFILE_TEST_TONE") || ""
        verify(tone !== "", "browser-flows.sh passes a tone file")
        browser.previewVolume = 0.5
        browser.previewMuted = true
        browser.showPreview(Model.decodeEntry([Model.basename(tone), "f", 320044, 100, 420, null], Model.dirname(tone)))
        compare(browser.previewKind, "audio")
        var loader = findChild(browser, "audioPreviewLoader")
        tryVerify(function () { return loader.status === Loader.Ready }, 5000, "audio player loads")
        var audio = loader.item
        tryVerify(function () { return audio.playing }, 5000, "audio starts on its own")
        verify(mock.called("previewAudio") !== null, "the shell only plays a copy the helper cleaned")
        compare(audio.title, "Tone", "the title comes from the helper, not from the file in the shell")
        tryVerify(function () { return audio.player.duration > 19000 }, 5000, "duration is read")
        verify(Math.abs(audio.player.audioOutput.volume - 0.1505) < 0.001, "the slider maps to output volume")
        verify(audio.player.audioOutput.muted, "the output starts muted")
        keyClick(Qt.Key_K)
        verify(!audio.playing, "K pauses")
        var before = audio.player.position
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        tryVerify(function () { return audio.player.position >= before + 4000 }, 3000, "Shift+Right skips ahead")
        verify(browser.previewOpen, "seeking keeps the preview on this file")
        keyClick(Qt.Key_M)
        verify(!browser.previewMuted, "M unmutes")
        verify(!audio.player.audioOutput.muted, "the output follows the mute")
        keyClick(Qt.Key_M)
        verify(browser.previewMuted, "M mutes again")
        keyClick(Qt.Key_P)
        tryVerify(function () { return audio.playing }, 3000, "P resumes")
        keyClick(Qt.Key_Space)
        verify(!browser.previewOpen)
        tryVerify(function () { return loader.item === null }, 3000, "closing the preview drops the player")
        browser.showPreview(Model.decodeEntry(["missing.mp3", "f", 10, 100, 420, null], "/tmp/omafile-no-such-dir"))
        tryVerify(function () { return loader.item && loader.item.failed }, 5000, "a file that will not play reports it")
        keyClick(Qt.Key_Escape)
        verify(!browser.previewOpen)
        browser.previewVolume = 1
        browser.previewMuted = false
      }

      function textInputs(item, out) {
        if (item.hasOwnProperty("echoMode") && item.hasOwnProperty("cursorPosition")) out.push(item)
        for (var i = 0; i < item.children.length; i++) textInputs(item.children[i], out)
        return out
      }

      function editableInputs() {
        return textInputs(browser, []).filter(function (t) { return !t.readOnly })
      }

      function editableHidden() {
        return editableInputs().filter(function (t) { return !t.visible }).map(function (t) { return String(t) })
      }

      function shownChild(name) {
        var found = null
        function walk(item) {
          if (found) return
          if (item.objectName === name && item.visible) { found = item; return }
          for (var i = 0; i < item.children.length; i++) walk(item.children[i])
        }
        walk(browser)
        return found
      }

      function namedChildren(name) {
        var out = []
        function walk(item) {
          if (item.objectName === name) out.push(item)
          for (var i = 0; i < item.children.length; i++) walk(item.children[i])
        }
        walk(browser)
        return out
      }

      function test_5c_inputsNeverLetQtReadTheClipboard() {
        waitRows()
        verify(textInputs(browser, []).length >= 13, "found the text inputs")
        compare(editableInputs().length, 0, "nothing is editable to Qt while every editor is closed")

        keyClick(Qt.Key_L, Qt.ControlModifier)
        tryVerify(function () { return browser.activePane() && textInputs(browser, []).some(function (t) { return t.visible && t.activeFocus }) }, 3000, "the path editor takes focus")
        compare(editableInputs().length, 0, "the open path editor stays read only to Qt")
        keyClick(Qt.Key_Escape)

        mock.calls = []
        browser.showDialog("newfolder", "New folder", "", null)
        var field = findChild(browser, "dialogField")
        tryVerify(function () { return field.visible && field.activeFocus }, 3000)
        verify(field.readOnly, "an open dialog field stays read only to Qt")
        keyClick(Qt.Key_A)
        keyClick("B")
        keyClick(Qt.Key_C)
        compare(field.text, "aBc", "typing still edits the field")
        keyClick(Qt.Key_Backspace)
        compare(field.text, "aB")
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Delete)
        compare(field.text, "a")
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        compare(field.text, "aB", "undo brings the last edit back")
        keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
        compare(field.text, "a", "and redo removes it again")
        mock.clipboardText = "x\ny"
        keyClick(Qt.Key_V, Qt.ControlModifier)
        tryCompare(field, "text", "ax y", 3000, "paste goes through the helper and stays on one line")
        verify(mock.called("readClipboardText") !== null, "paste asks the helper for bounded clipboard text")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        keyClick(Qt.Key_Backspace)
        compare(field.text, "", "select all and delete clears the field")
        browser.closeDialog()
        compare(editableInputs().length, 0)

        var saved = mock.statItems
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 30, mtime: 300, atime: 300, ctime: 300,
          mode: 33188, uid: 1000, gid: 1000, owner: "me", group: "me", mime: "text/yaml" } }
        browser.showProperties(Model.decodeEntry(["alpha.yml", "f", 30, 300, 420, null], "/tmp"))
        tryVerify(function () { return shownChild("changeOpenerButton") !== null && shownChild("changeOpenerButton").visible }, 3000)
        compare(namedChildren("changeOpener").length, 0, "the app search is not created until it is needed")
        shownChild("changeOpenerButton").clicked()
        tryVerify(function () { var d = shownChild("changeOpener"); return d !== null && d.popupOpen }, 3000, "clicking opens the app search")
        var search = findChild(shownChild("changeOpener"), "appChooserSearch")
        verify(search !== null, "the app search uses the safe field")
        tryVerify(function () { return search.activeFocus }, 3000)
        verify(search.readOnly, "the app search stays read only to Qt")
        keyClick(Qt.Key_Z)
        compare(search.text, "z")
        shownChild("changeOpener").close()
        tryVerify(function () { return namedChildren("changeOpener").length === 0 }, 3000, "closing the list removes it again")
        browser.closeDialog()
        mock.statItems = saved
        compare(editableInputs().length, 0)
      }

      function test_6_settingsFit() {
        window.implicitWidth = 480
        window.implicitHeight = 330
        wait(100)
        browser.showDialog("settings", "Settings", "", null)
        wait(50)
        var card = findChild(browser, "dialogCard")
        verify(card.width <= browser.width, "card width " + card.width + " fits " + browser.width)
        verify(card.height <= browser.height, "card height " + card.height + " fits " + browser.height)
        browser.closeDialog()
        window.implicitWidth = 1000
        window.implicitHeight = 640
        wait(100)
      }

      function labels(entry) {
        return browser.contextActions(entry).map(function (a) { return a.label })
      }

      function test_5a_trashView() {
        waitRows()
        pane().setSortOrder("name", false)
        var bar = findChild(browser, "trashBarA")
        verify(!bar.visible, "no trash bar outside the trash")
        pane().setCursor(0, false, false)
        verify(labels(pane().cursorEntry()).indexOf("Move to trash") >= 0)
        verify(labels(pane().cursorEntry()).indexOf("Restore") < 0)

        mock.trashCount = 0
        pane().navigate("/tmp/.trash")
        waitRows()
        waitForRendering(browser)
        verify(bar.visible, "trash bar shows in the trash")
        var button = findChild(bar, "emptyTrashButton")
        verify(!button.enabled, "empty trash is disabled when the trash is empty")
        compare(findChild(bar, "trashSummary").text, "Empty")

        mock.trashCount = 3
        verify(button.enabled)
        compare(findChild(bar, "trashSummary").text, "3 items")
        mock.calls = []
        mouseClick(button)
        verify(findChild(browser, "trashBarA") !== null)
        compare(browser.confirmAction, "emptytrash")
        compare(mock.called("emptyTrash"), null, "asks before emptying")
        keyClick(Qt.Key_Return)
        verify(mock.called("emptyTrash") !== null)
        compare(browser.confirmAction, "")
        verify(!button.enabled, "disabled again once emptied")
        compare(pane().path, "/tmp/.trash")

        waitRows()
        pane().setCursor(0, false, false)
        var entry = pane().cursorEntry()
        compare(entry.path, "/tmp/.trash/alpha.yml")
        var inTrash = labels(entry)
        verify(inTrash.indexOf("Move to trash") < 0, "no second trash from the trash")
        verify(inTrash.indexOf("Delete permanently") >= 0)
        verify(inTrash.indexOf("Restore") >= 0)
        var empty = browser.contextActions(null)
        var emptyItem = empty.filter(function (a) { return a.key === "emptytrash" })[0]
        verify(emptyItem !== undefined, "empty area menu offers Empty trash")
        verify(emptyItem.disabled === true)

        mock.calls = []
        keyClick(Qt.Key_Delete)
        compare(mock.called("trashPaths"), null, "Delete never trashes again")
        compare(browser.confirmAction, "delete")
        keyClick(Qt.Key_Return)
        compare(mock.called("deletePaths").args[0], ["/tmp/.trash/alpha.yml"])

        mock.calls = []
        pane().setCursor(0, false, false)
        keyClick(Qt.Key_Delete, Qt.ShiftModifier)
        compare(browser.confirmAction, "delete")
        keyClick(Qt.Key_Escape)
        compare(browser.confirmAction, "")
        compare(mock.called("deletePaths"), null)

        pane().setCursor(1, false, false)
        browser.menuEntry = pane().cursorEntry()
        var restoring = browser.menuEntry.name
        browser.menuActions = browser.contextActions(browser.menuEntry)
        menuItem("Restore")
        compare(mock.called("restoreFromTrash").args[0], [restoring])
        compare(browser.statusText, "1 item restored")

        waitRows()
        mock.calls = []
        mock.values = { confirmTrash: false }
        pane().setCursor(0, false, false)
        browser.menuActions = browser.contextActions(pane().cursorEntry())
        menuItem("Delete permanently")
        compare(mock.called("trashPaths"), null)
        compare(browser.confirmAction, "delete")
        keyClick(Qt.Key_Escape)
        mock.values = ({})

        pane().navigate("/tmp")
        waitRows()
        verify(!bar.visible)

        pane().setCursor(0, false, false)
        browser.openMenuAtCursor()
        var outside = menuLabels(browser.menuActions)
        verify(outside.indexOf("Move to trash") >= 0)
        verify(outside.indexOf("Delete permanently") < 0, "permanent delete hides behind Shift")
        keyPress(Qt.Key_Shift)
        verify(menuLabels(browser.menuActions).indexOf("Delete permanently") >= 0, "Shift reveals permanent delete")
        verify(menuLabels(browser.menuActions).indexOf("Move to trash") < 0)
        keyRelease(Qt.Key_Shift)
        verify(menuLabels(browser.menuActions).indexOf("Move to trash") >= 0, "releasing Shift restores trash")
        browser.closeMenu()
      }

      function test_7_pickOpen() {
        waitRows()
        mock.pickRequest = { mode: "open", result: "/run/v.json" }
        verify(!browser.picking, "a portal request leaves an open window alone")
        mock.pickRequest = null
        browser.pickerRequest = { mode: "open", multiple: false, directory: false, result: "/run/x.json",
          filters: [{ name: "Images", patterns: ["*.png"] }, { name: "All", patterns: ["*"] }], currentFilter: 0 }
        beginPick()
        verify(findChild(browser, "pickBar").visible)
        tryVerify(function () { return !pane().loading && pane().rows.length === 2 })
        waitForRendering(browser)
        verify(names().indexOf("alpha.yml") < 0, "filter hides yml")
        browser.pickFilter = 1
        compare(pane().rows.length, 3)
        var idx = names().indexOf("beta.png")
        pane().setCursor(idx, false, false)
        keyClick(Qt.Key_Return)
        var call = mock.called("finishPick")
        verify(call !== null)
        compare(call.args[0].ok, true)
        compare(call.args[0].paths[0], "/tmp/beta.png")
        compare(call.args[0].filter, 1)
        compare(call.args[1].result, "/run/x.json")
        verify(!browser.picking)
      }

      function test_8_pickSaveAndCancel() {
        mock.calls = []
        browser.pickerRequest = { mode: "save", result: "/run/y.json", currentFolder: "/tmp", currentName: "new.txt", filters: [] }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        waitForRendering(browser)
        mouseClick(findChild(browser, "pickAccept"))
        compare(mock.called("finishPick").args[0].paths[0], "/tmp/new.txt")
        mock.calls = []
        var savedStat = mock.statItems
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 30, linkTarget: null } }
        browser.pickerRequest = { mode: "save", result: "/run/z.json", currentFolder: "/tmp", currentName: "alpha.yml" }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        waitForRendering(browser)
        mouseClick(findChild(browser, "pickAccept"))
        compare(mock.called("finishPick"), null, "asks before replacing")
        keyClick(Qt.Key_Escape)
        verify(browser.picking, "escape only dismisses the replace prompt")
        mouseClick(findChild(browser, "pickAccept"))
        keyClick(Qt.Key_Return)
        compare(mock.called("finishPick").args[0].paths[0], "/tmp/alpha.yml")
        mock.calls = []
        mock.statItems = { "/tmp/.hidden.txt": { kind: "f", size: 1, linkTarget: null } }
        browser.pickerRequest = { mode: "save", result: "/run/h.json", currentFolder: "/tmp", currentName: ".hidden.txt" }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        mouseClick(findChild(browser, "pickAccept"))
        compare(mock.called("finishPick"), null, "a hidden file that is not in the view still asks before replacing")
        keyClick(Qt.Key_Escape)
        mock.statItems = { "/tmp/link.txt": { kind: "l", size: 1, linkTarget: "/etc/passwd" } }
        findChild(browser, "pickNameField").text = "link.txt"
        browser.acceptPick(null)
        compare(mock.called("finishPick"), null, "saving over a link is refused")
        verify(browser.statusText.indexOf("is a link") >= 0)
        browser.cancelPick()
        mock.statItems = savedStat
        mock.calls = []
        browser.pickerRequest = { mode: "open", result: "/run/w.json" }
        beginPick()
        waitForRendering(browser)
        keyClick(Qt.Key_Escape)
        compare(mock.called("finishPick").args[0].ok, false)
      }

      SignalSpy { id: dismissSpy; target: browser; signalName: "dismissRequested" }

      function test_9a_tabKeys() {
        pane().navigate("/tmp")
        waitRows()
        compare(browser.tabsA.length, 1)
        keyClick(Qt.Key_T, Qt.ControlModifier)
        compare(browser.tabsA.length, 2)
        pane().navigate("/tmp/docs")
        tryVerify(function () { return pane().path === "/tmp/docs" })
        keyClick(Qt.Key_W, Qt.ControlModifier)
        compare(browser.tabsA.length, 1)
        keyClick(Qt.Key_T, Qt.ShiftModifier | Qt.ControlModifier)
        compare(browser.tabsA.length, 2, "closed tab restored")
        compare(browser.activeA, 1)
        tryVerify(function () { return pane().path === "/tmp/docs" })
        keyClick(Qt.Key_1, Qt.AltModifier)
        compare(browser.activeA, 0)
        keyClick(Qt.Key_PageDown, Qt.ShiftModifier | Qt.ControlModifier)
        compare(browser.activeA, 1, "tab moved right")
        compare(browser.tabsA[0].path, "/tmp/docs")
        keyClick(Qt.Key_W, Qt.ControlModifier)
        compare(browser.tabsA.length, 1)
        dismissSpy.clear()
        keyClick(Qt.Key_W, Qt.ControlModifier)
        compare(dismissSpy.count, 1, "Ctrl+W on the last tab closes the window")
        dismissSpy.clear()
        keyClick(Qt.Key_Escape)
        compare(dismissSpy.count, 0, "Escape leaves the window open")
        pane().navigate("/tmp")
        waitRows()
      }

      function test_9b_openSeveral() {
        waitRows()
        mock.calls = []
        pane().selectAll()
        keyClick(Qt.Key_Return)
        compare(count("openExternallyFiles"), 1, "the files open in one go")
        compare(mock.called("openExternallyFiles").args[0], ["/tmp/alpha.yml", "/tmp/beta.png"], "both files open")
        compare(browser.tabsA.length, 2, "the folder opens in a new tab")
        keyClick(Qt.Key_W, Qt.ControlModifier)
        pane().clearSelection()
      }

      function test_9ba_menuActsOnTheWholeSelection() {
        waitRows()
        mock.updateSetting("editorChoice", "omarchy")
        pane().setSortOrder("name", false)
        var alpha = names().indexOf("alpha.yml")
        var beta = names().indexOf("beta.png")
        pane().setCursor(alpha, false, false)
        pane().setCursor(beta, false, true)
        var clicked = pane().cursorEntry()
        compare(clicked.name, "beta.png")
        compare(pane().selectedEntries.length, 2)

        mock.calls = []
        browser.menuEntry = clicked
        browser.runAction("open")
        compare(mock.called("openExternallyFiles").args[0].length, 2, "Open in the menu opens every selected file")
        mock.calls = []
        browser.menuEntry = clicked
        browser.runAction("editor")
        compare(mock.called("launchEditor").args[1].length, 2, "Open in editor gets every selected file")
        browser.menuEntry = clicked
        browser.runAction("openwith")
        compare(browser.dialogTitle, "Open 2 items with")
        wait(200)
        mouseDoubleClickSequence(findChild(browser, "openWithList").itemAtIndex(0))
        compare(mock.called("openWith").args[1].length, 2, "Open with gets every selected file")

        mock.calls = []
        var outside = Model.decodeEntry(["gamma.txt", "f", 1, 100, 420, null], "/tmp")
        browser.menuEntry = outside
        browser.runAction("editor")
        compare(mock.called("launchEditor").args[1], ["/tmp/gamma.txt"], "an item outside the selection acts alone")
        pane().clearSelection()
      }

      function test_9bb_openManyAsksFirst() {
        waitRows()
        mock.calls = []
        var limit = browser.openConfirmLimit
        browser.openConfirmLimit = 2
        pane().selectAll()
        keyClick(Qt.Key_Return)
        compare(mock.called("openExternallyFiles"), null, "asks before opening more than the limit")
        keyClick(Qt.Key_Escape)
        compare(mock.called("openExternallyFiles"), null, "cancel opens nothing")
        compare(browser.tabsA.length, 1)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Return)
        compare(mock.called("openExternallyFiles").args[0], ["/tmp/alpha.yml", "/tmp/beta.png"], "confirming opens both files")
        compare(browser.tabsA.length, 2, "confirming opens the folder in a new tab")
        browser.openConfirmLimit = limit
        keyClick(Qt.Key_W, Qt.ControlModifier)
        pane().clearSelection()
      }

      function test_9c_folderMenu() {
        waitRows()
        keyClick(Qt.Key_F10)
        verify(browser.menuOpen)
        compare(browser.menuEntry, null)
        keyClick(Qt.Key_Escape)
        verify(!browser.menuOpen)
        var shown = browser.sidebarVisible
        keyClick(Qt.Key_F9)
        compare(browser.sidebarVisible, !shown)
        keyClick(Qt.Key_F9)
        compare(browser.sidebarVisible, shown)
      }

      function test_9ca_editorAndAgentItems() {
        waitRows()
        mock.updateSetting("editorChoice", "omarchy")
        var file = { name: "notes.txt", path: "/tmp/notes.txt", isDir: false, ext: "txt" }
        var folder = { name: "docs", path: "/tmp/docs", isDir: true, ext: "" }
        var fileLabels = menuLabels(browser.contextActions(file))
        compare(fileLabels[fileLabels.indexOf("Open with") + 1], "Open in editor")
        verify(menuLabels(browser.contextActions(folder)).indexOf("Open in editor") >= 0)
        verify(menuLabels(browser.contextActions(null)).indexOf("Open in editor") < 0)
        mock.calls = []
        browser.menuEntry = file
        browser.runAction("editor")
        compare(mock.called("launchEditor").args[1], ["/tmp/notes.txt"])

        verify(menuLabels(browser.contextActions(folder)).indexOf("Open Claude Code here") < 0, "no agent item without an agent")
        mock.agentAvailable = true
        verify(menuLabels(browser.contextActions(folder)).indexOf("Open Claude Code here") >= 0)
        verify(menuLabels(browser.contextActions(null)).indexOf("Open Claude Code here") >= 0)
        verify(menuLabels(browser.contextActions(file)).indexOf("Open Claude Code here") < 0, "files get no agent item")
        mock.agentName = "omp"
        verify(menuLabels(browser.contextActions(folder)).indexOf("Open omp here") >= 0)
        mock.calls = []
        browser.menuEntry = folder
        browser.runAction("agent")
        compare(mock.called("openAgent").args[0], "/tmp/docs")
        mock.agentAvailable = false
        mock.agentName = "Claude Code"
      }

      function test_9cb_editorIsAskedForOnce() {
        waitRows()
        mock.updateSetting("editorChoice", "")
        mock.updateSetting("editor", "")
        var file = { name: "notes.txt", path: "/tmp/notes.txt", isDir: false, ext: "txt" }
        function values() { return browser.editorPickOptions().map(function (o) { return o.value }) }

        mock.calls = []
        browser.menuEntry = file
        browser.runAction("editor")
        tryCompare(browser, "dialogMode", "editorpick")
        compare(mock.called("launchEditor"), null, "nothing opens before you choose")
        verify(mock.called("refreshDefaults") !== null)
        compare(values(), ["omarchy", "omafile", "app:code", "app:nvim", "app:nano", "own"], "Omarchy's default, Omafile's editor, the editors you have, or a command")
        compare(browser.editorPickOptions()[0].label, "Omarchy's default, Neovim")
        keyClick(Qt.Key_Escape)
        compare(browser.dialogMode, "")
        compare(mock.called("launchEditor"), null, "cancelling opens nothing")
        compare(mock.editorChoice, "", "and saves nothing")

        browser.menuEntry = file
        browser.runAction("editor")
        tryCompare(browser, "dialogMode", "editorpick")
        keyClick(Qt.Key_Return)
        compare(mock.editorChoice, "omarchy", "Omarchy's default is the first choice")
        compare(mock.called("launchEditor").args[0].mode, "omarchy")
        compare(mock.called("launchEditor").args[1], ["/tmp/notes.txt"])
        mock.calls = []
        browser.runAction("editor")
        compare(browser.dialogMode, "", "it asks only once")
        compare(mock.called("launchEditor").args[0].mode, "omarchy")

        mock.updateSetting("editorChoice", "")
        browser.menuEntry = file
        browser.runAction("editor")
        tryCompare(browser, "dialogMode", "editorpick")
        keyClick(Qt.Key_Down)
        compare(browser.editorPick, "omafile")
        keyClick(Qt.Key_Down)
        compare(browser.editorPick, "app:code")
        verify(browser.editorPickCanAlso, "VS Code can also become Omarchy's default")
        var also = findChild(browser, "editorPickAlso")
        verify(also.visible)
        waitForRendering(browser)
        mouseClick(also)
        verify(browser.editorPickAlso)
        mock.calls = []
        keyClick(Qt.Key_Return)
        compare(mock.called("setOmarchyEditor").args[0], "code")
        compare(mock.editorCommand, "code")
        compare(mock.editorChoice, "own")
        compare(mock.called("launchEditor").args[0].command, "code")

        mock.updateSetting("editor", "-e nano")
        mock.missingPrograms = { "-e": true }
        mock.calls = []
        browser.menuEntry = file
        browser.runAction("editor")
        tryCompare(browser, "dialogMode", "editorpick")
        compare(mock.called("launchEditor"), null, "a command that does not exist is never run")
        verify(browser.editorPickError.indexOf("\u201c-e nano\u201d is not a command") === 0, browser.editorPickError)
        browser.chooseEditorPick("app:nano")
        verify(!browser.editorPickCanAlso, "nano cannot be Omarchy's default")
        browser.chooseEditorPick("own")
        var typed = findChild(browser, "editorCustomField")
        tryCompare(typed, "activeFocus", true)
        mock.missingPrograms = { "zz-missing": true }
        typed.text = "zz-missing --flag"
        keyClick(Qt.Key_Return)
        tryVerify(function () { return browser.editorPickError.indexOf("zz-missing") > 0 })
        compare(browser.dialogMode, "editorpick", "a typed command that does not exist keeps the dialog open")
        typed.text = "nano -w"
        keyClick(Qt.Key_Return)
        tryCompare(browser, "dialogMode", "")
        compare(mock.editorCommand, "nano -w")
        compare(mock.called("launchEditor").args[0].command, "nano -w")
        mock.missingPrograms = ({})

        compare(browser.editorSettingValue, "own")
        browser.chooseEditorSetting("app:nano")
        compare(browser.editorSettingValue, "app:nano")
        browser.chooseEditorSetting("omarchy")
        compare(browser.editorSettingValue, "omarchy")
        browser.chooseEditorSetting("own")
        compare(browser.editorSettingValue, "own")
        browser.chooseEditorSetting("")
        compare(browser.editorSettingValue, "")
        compare(mock.editorCommand, "", "asking again clears the old command")

        mock.omarchyAgent = "omp"
        mock.omarchyAgentFound = true
        compare(browser.agentPlaceholder(), "Omarchy's default, Oh My Pi")
        mock.omarchyAgentFound = false
        mock.claudeAvailable = true
        compare(browser.agentPlaceholder(), "Claude Code")
        mock.omarchyAgent = ""
        mock.claudeAvailable = false
        mock.updateSetting("editorChoice", "omarchy")
      }

      function test_9cc_omafileEditorAsDefault() {
        waitRows()
        mock.updateSetting("editorChoice", "")
        mock.updateSetting("editor", "")
        mock.textFiles = { "/tmp/alpha.yml": { text: "key: value\n" } }
        var alpha = Model.decodeEntry(["alpha.yml", "f", 30, 300, 420, null], "/tmp")
        var view = editorView()
        mock.calls = []
        browser.menuEntry = alpha
        browser.runAction("editor")
        tryCompare(browser, "dialogMode", "editorpick")
        browser.chooseEditorPick("omafile")
        keyClick(Qt.Key_Return)
        compare(mock.editorChoice, "omafile", "Omafile's editor can be the default")
        verify(view.open, "the file opens in Omafile's editor")
        compare(mock.called("launchEditor"), null, "no other app is started")
        tryCompare(view, "loading", false)
        view.finishClose()

        mock.calls = []
        browser.menuEntry = alpha
        browser.runAction("editor")
        compare(browser.dialogMode, "", "it is not asked again")
        verify(view.open, "Open in editor goes straight to Omafile's editor")
        tryCompare(view, "loading", false)
        view.finishClose()

        var docs = Model.decodeEntry(["docs", "d", 0, 200, 493, null], "/tmp")
        mock.calls = []
        browser.menuEntry = docs
        browser.runAction("editor")
        compare(view.open, false)
        compare(mock.called("launchEditor").args[0].mode, "omarchy", "a folder opens in Omarchy's default editor")
        compare(mock.called("launchEditor").args[1], ["/tmp/docs"])
        verify(browser.statusText.indexOf("one text file at a time") > 0, browser.statusText)

        pane().setSortOrder("name", false)
        pane().setCursor(names().indexOf("alpha.yml"), false, false)
        pane().setCursor(names().indexOf("beta.png"), false, true)
        mock.calls = []
        browser.menuEntry = pane().cursorEntry()
        browser.runAction("editor")
        compare(view.open, false)
        compare(mock.called("launchEditor").args[1].length, 2, "several files open together in Omarchy's default editor")
        pane().clearSelection()

        compare(browser.editorSettingValue, "omafile")
        verify(browser.editorSettingOptions().map(function (o) { return o.value }).indexOf("omafile") === 2)
        browser.chooseEditorSetting("omarchy")
        compare(mock.editorChoice, "omarchy")
        browser.chooseEditorSetting("omafile")
        compare(mock.editorChoice, "omafile")
        mock.updateSetting("editorChoice", "omarchy")
        mock.textFiles = ({})
      }

      function test_9d_pasteFromSystemClipboard() {
        pane().navigate("/tmp")
        waitRows()
        mock.calls = []
        mock.systemClipboard = { mode: "cut", paths: ["/elsewhere/a.txt"] }
        browser.doPaste()
        var call = mock.called("beginTransfer")
        compare(call.args[0], "move")
        compare(call.args[1][0], "/elsewhere/a.txt")
        compare(call.args[2], "/tmp")
        verify(mock.called("clearSystemClipboard") !== null, "a cut is used up")
        mock.calls = []
        mock.systemClipboard = { mode: "copy", paths: [] }
        browser.doPaste()
        compare(mock.called("beginTransfer"), null)
        compare(browser.statusText, "Nothing to paste")
        mock.systemClipboard = null
      }

      function test_9e_dropMovesOrCopies() {
        waitRows()
        mock.calls = []
        mock.updateSetting("dropAction", "move")
        browser.handleDrop(["file:///elsewhere/My%20file.txt", "https://example.com/x"], "/tmp/docs")
        var call = mock.called("beginTransfer")
        compare(call.args[0], "move")
        compare(call.args[1].length, 1)
        compare(call.args[1][0], "/elsewhere/My file.txt")
        mock.calls = []
        mock.updateSetting("dropAction", "copy")
        browser.handleDrop(["file:///elsewhere/a.txt"], "/tmp/docs")
        compare(mock.called("beginTransfer").args[0], "copy")
        mock.calls = []
        browser.handleDrop(["file:///tmp/docs"], "/tmp/docs")
        browser.handleDrop(["file:///tmp/alpha.yml"], "/tmp")
        compare(mock.called("beginTransfer"), null, "no drop onto itself or its own folder")
        mock.updateSetting("dropAction", "auto")
        var wasSame = mock.sameDrive
        mock.sameDrive = true
        browser.handleDrop(["file:///elsewhere/a.txt"], "/tmp/docs")
        compare(mock.called("beginTransfer").args[0], "move", "automatic moves on the same drive")
        verify(!browser.menuOpen)
        mock.calls = []
        mock.sameDrive = false
        browser.handleDrop(["file:///elsewhere/a.txt"], "/tmp/docs")
        compare(mock.called("beginTransfer").args[0], "copy", "automatic copies to another drive")
        verify(!browser.menuOpen)
        mock.sameDrive = wasSame
      }

      function test_9f_dropChoices() {
        mock.updateSetting("dropAction", "ask")
        mock.calls = []
        var position = browser.mapToGlobal(320, 220)
        browser.handleDrop(["file:///elsewhere/a.txt"], "/tmp/docs", position)
        verify(browser.menuOpen)
        compare(browser.menuKind, "drop")
        compare(browser.menuX, 320)
        compare(browser.menuY, 220)
        compare(mock.called("beginTransfer"), null)
        menuItem("Copy")
        compare(mock.called("beginTransfer").args[0], "copy")
        verify(!browser.menuOpen)
        compare(browser.pendingDrop, null)
        browser.runAction("drop:move")
        compare(mock.called("beginTransfer").args[0], "copy", "consumed drop cannot run twice")
        browser.handleDrop(["file:///elsewhere/folder"], "/tmp/docs", position)
        menuItem("Move")
        compare(mock.called("beginTransfer").args[0], "move")
        for (var i = 0; i < 3; i++) {
          mock.calls = []
          browser.handleDrop(["file:///elsewhere/a.txt"], "/tmp/docs", position)
          if (i === 0) menuItem("Cancel")
          else if (i === 1) keyClick(Qt.Key_Escape)
          else mouseClick(browser, 10, 10)
          verify(!browser.menuOpen)
          compare(browser.pendingDrop, null)
          compare(mock.called("beginTransfer"), null)
        }
        browser.handleDrop(["file:///tmp/docs", "file:///tmp/%ZZ"], "/tmp/docs/child", position)
        verify(!browser.menuOpen)
        compare(mock.called("beginTransfer"), null)
        mock.updateSetting("dropAction", "auto")
        browser.showDialog("settings", "Settings", "", null)
        browser.settingsSection = "browsing"
        var setting = findChild(browser, "dropActionSetting")
        verify(setting !== null)
        compare(setting.value, "auto")
        compare(setting.options[0].value, "auto")
        setting.changed("copy")
        compare(mock.settingNow("dropAction", "auto"), "copy")
        setting.changed("auto")
        browser.closeDialog()
      }

      function test_9g_propertiesPermissions() {
        waitRows()
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 30, mtime: 300, atime: 300, ctime: 300,
          mode: 33188, uid: 1000, gid: 1000, owner: "me", group: "me", mime: "text/yaml" } }
        pane().setCursor(0, false, false)
        browser.showProperties(pane().cursorEntry())
        compare(browser.dialogMode, "properties")
        tryVerify(function () { return browser.propsInfo !== null && browser.propsIdentity !== null }, 3000)
        wait(200)
        mouseClick(findChild(browser, "securityTab"))
        wait(200)
        var mode = findChild(browser, "modeText")
        tryVerify(function () { return mode.text.indexOf("644") === 0 }, 3000)
        var boxes = []
        function collect(item) {
          if (item.objectName === "permBox") boxes.push(item)
          for (var i = 0; i < item.children.length; i++) collect(item.children[i])
        }
        collect(findChild(browser, "dialogCard"))
        compare(boxes.length, 9)
        mouseClick(boxes[0])
        tryVerify(function () { return mode.text.indexOf("244") === 0 }, 3000)
        wait(150)
        mouseClick(findChild(browser, "applyPermissions"))
        var call = mock.called("changeMode")
        verify(call !== null, "changeMode called")
        compare(call.args[0], "/tmp/alpha.yml")
        compare(call.args[1], 0)
        compare(call.args[2], 256)
        browser.closeDialog()
      }

      function test_9h_propertiesReadOnlyForOthers() {
        waitRows()
        mock.statItems = { "/tmp/alpha.yml": { kind: "f", size: 30, mtime: 300, atime: 300, ctime: 300,
          mode: 33188, uid: 0, gid: 0, owner: "root", group: "root", mime: "text/yaml" } }
        pane().setCursor(0, false, false)
        browser.showProperties(pane().cursorEntry())
        tryVerify(function () { return browser.propsInfo !== null }, 3000)
        wait(200)
        mouseClick(findChild(browser, "securityTab"))
        wait(200)
        var boxes = []
        function collect(item) {
          if (item.objectName === "permBox") boxes.push(item)
          for (var i = 0; i < item.children.length; i++) collect(item.children[i])
        }
        collect(findChild(browser, "dialogCard"))
        mouseClick(boxes[0])
        compare(findChild(browser, "modeText").text.indexOf("644"), 0)
        compare(findChild(browser, "applyPermissions").visible, false)
        browser.closeDialog()
      }

      function test_9g_extractArchives() {
        waitRows()
        var zip = { name: "pack.zip", path: "/tmp/pack.zip", isDir: false, ext: "zip" }
        var tar = { name: "src.tar.gz", path: "/tmp/src.tar.gz", isDir: false, ext: "gz" }
        var text = { name: "notes.txt", path: "/tmp/notes.txt", isDir: false, ext: "txt" }
        mock.calls = []
        compare(browser.boolSetting("extractOnOpen", false), false)
        browser.handleOpenRequest(zip)
        compare(mock.called("extractArchive"), null, "archives open in the default app by default")
        compare(mock.called("openExternally").args[0], "/tmp/pack.zip")

        verify(menuLabels(browser.contextActions(zip)).indexOf("Extract here") >= 0)
        verify(menuLabels(browser.contextActions(text)).indexOf("Extract here") < 0)
        mock.calls = []
        browser.menuEntry = zip
        browser.runAction("extract")
        compare(mock.called("extractArchive").args[0], "/tmp/pack.zip")
        compare(browser.statusText, "Extracted to pack")

        mock.updateSetting("extractOnOpen", true)
        mock.calls = []
        browser.handleOpenRequest(zip)
        compare(mock.called("extractArchive").args[0], "/tmp/pack.zip")
        compare(mock.called("openExternally"), null)
        mock.calls = []
        browser.openEntries([zip, tar, text])
        compare(count("extractArchive"), 2, "every opened archive is extracted")
        compare(mock.called("openExternallyFiles").args[0], ["/tmp/notes.txt"])

        mock.extractResults = { "/tmp/pack.zip": { error: "damaged" } }
        mock.calls = []
        browser.handleOpenRequest(zip)
        compare(browser.statusText, "Could not extract pack.zip: damaged")
        mock.extractResults = ({})
        mock.updateSetting("extractOnOpen", false)

        browser.showDialog("settings", "Settings", "", null)
        browser.settingsSection = "browsing"
        var rows = browser.browsingRows()
        compare(rows[rows.length - 1].key, "extractOnOpen")
        compare(rows[rows.length - 1].fallback, false)
        browser.closeDialog()
      }

      function test_9i_extractInTransfers() {
        var panel = findChild(browser, "transferPanel")
        var job = { id: 9, op: "extract", label: "photos.zip", dest: "/home/me/Downloads", from: "/home/me/Downloads",
          state: "running", bytes: 50, total: 200, files: 3, filesTotal: 0, current: "a.jpg", rate: 10,
          errors: [], startedMs: Date.now() - 2000, finishedMs: 0, count: 1 }
        var details = panel.details(job)
        compare(details[0].value, "Extracting photos.zip")
        verify(details.some(function (d) { return d.key === "Files" && d.value === "3" }))
        verify(details.some(function (d) { return d.key === "Read" }))
        verify(panel.statusLine(job).indexOf("of") > 0)
        job.total = 0
        compare(panel.statusLine(job), "Extracting")
        mock.calls = []
        mock.transfers = [job]
        tryVerify(function () { return panel.visible && findChild(panel, "transfer-9") !== null }, 3000)
        var row = findChild(panel, "transfer-9")
        mouseClick(findChild(row, "cancelTransfer"))
        compare(mock.called("cancelTransfer").args[0], 9, "an extraction can be cancelled from the panel")
        mock.transfers = []
      }

      function editorView() { return findChild(browser, "textEditorView") }
      function editorText() { return findChild(browser, "textEditorText") }

      function test_9ka_textEditor() {
        waitRows()
        var alpha = Model.decodeEntry(["alpha.yml", "f", 30, 300, 420, null], "/tmp")
        var png = Model.decodeEntry(["beta.png", "f", 10, 100, 420, null], "/tmp")
        var docs = Model.decodeEntry(["docs", "d", 0, 200, 493, null], "/tmp")
        verify(menuLabels(browser.contextActions(alpha)).indexOf("Edit") >= 0, "text files can be edited")
        verify(menuLabels(browser.contextActions(png)).indexOf("Edit") < 0, "pictures cannot")
        verify(menuLabels(browser.contextActions(docs)).indexOf("Edit") < 0, "folders cannot")

        mock.textFiles = { "/tmp/alpha.yml": { text: "key: value\n  nested: a b\n" } }
        mock.calls = []
        browser.menuEntry = alpha
        browser.runAction("edittext")
        var view = editorView()
        var area = editorText()
        verify(view.open)
        tryCompare(view, "loading", false)
        tryCompare(area, "activeFocus", true)
        compare(view.dirty, false)
        keyClick(Qt.Key_X)
        keyClick(Qt.Key_Y)
        compare(area.model.indexOf("xykey: value"), 0, "typing edits the file")
        verify(view.dirty)
        verify(findChild(browser, "textEditorTitle").text.indexOf("●") === 0, "the title shows unsaved changes")
        verify(browser.holdsUnsaved)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Z)
        compare(area.model, "xykey: value\n  nested: a b\n  z\n", "Enter keeps the indent, and a no-break space is kept")
        tryCompare(view, "position", "Line 3, column 4")
        keyClick(Qt.Key_S, Qt.ControlModifier)
        var write = mock.called("writeText")
        compare(write.args[0], "/tmp/alpha.yml")
        compare(write.args[1], area.model, "the exact text is saved")
        compare(write.args[3], false)
        tryCompare(view, "dirty", false)
        compare(findChild(browser, "textEditorNotice").text, "Saved")

        keyClick(Qt.Key_F, Qt.ControlModifier)
        var find = findChild(browser, "textEditorFind")
        tryCompare(find, "activeFocus", true)
        find.text = "NESTED"
        keyClick(Qt.Key_Return)
        compare(findChild(browser, "textEditorNotice").text, "Not found", "a search with capitals is exact")
        find.text = "nested"
        keyClick(Qt.Key_Return)
        compare(area.model.slice(area.selectionStart, area.selectionEnd), "nested")
        keyClick(Qt.Key_Escape)
        tryCompare(area, "activeFocus", true)

        keyClick(Qt.Key_Q)
        verify(view.dirty)
        mock.calls = []
        keyClick(Qt.Key_Escape)
        compare(view.prompt, "unsaved", "closing with unsaved changes asks first")
        verify(view.open)
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorDiscard"))
        compare(view.open, false)
        compare(mock.called("writeText"), null, "Don't save writes nothing")

        browser.editText(alpha)
        tryCompare(view, "loading", false)
        tryCompare(area, "activeFocus", true)
        keyClick(Qt.Key_W)
        mock.writeResult = { code: "ECONFLICT", message: "changed" }
        mock.calls = []
        keyClick(Qt.Key_S, Qt.ControlModifier)
        tryCompare(view, "prompt", "conflict")
        verify(findChild(browser, "textEditorPromptText").text.indexOf("changed on disk") > 0)
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorConfirm"))
        tryVerify(function () { return mock.calls.filter(function (c) { return c.name === "writeText" }).length === 2 })
        compare(mock.calls.filter(function (c) { return c.name === "writeText" })[1].args[3], true, "Overwrite forces the save")
        tryCompare(view, "dirty", false)
        mock.writeResult = null

        keyClick(Qt.Key_E)
        browser.requestClose()
        compare(view.prompt, "unsaved", "closing Omafile asks before losing edits")
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorConfirm"))
        tryCompare(view, "open", false)
        compare(mock.calls.filter(function (c) { return c.name === "writeText" }).length, 3, "Save then closes")

        mock.textFiles = { "/tmp/locked.txt": { text: "keep me", writable: false } }
        browser.editText(Model.decodeEntry(["locked.txt", "f", 7, 100, 292, null], "/tmp"))
        tryCompare(view, "loading", false)
        tryCompare(area, "activeFocus", true)
        keyClick(Qt.Key_A)
        compare(area.model, "keep me", "a read only file is not changed")
        compare(findChild(browser, "textEditorNotice").text, "This file is read only for you")
        verify(!findChild(browser, "textEditorSave").enabled)
        keyClick(Qt.Key_Escape)
        compare(view.open, false, "nothing to save, so it closes at once")

        browser.editText(Model.decodeEntry(["notes.txt", "f", 7, 100, 420, null], "/tmp"))
        tryVerify(function () { return view.loadError !== "" })
        verify(view.loadError.indexOf("not a text file") > 0)
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorClose"))
        compare(view.open, false)
        mock.textFiles = ({})
      }

      function test_9kc_editorAutoSave() {
        waitRows()
        function writes() { return mock.calls.filter(function (c) { return c.name === "writeText" }) }
        var view = editorView()
        var area = editorText()
        compare(view.autoSave, false, "auto save is off by default")
        mock.updateSetting("editorAutoSave", true)
        view.autoSaveDelay = 200
        mock.textFiles = { "/tmp/auto.txt": { text: "one\n" } }
        mock.calls = []
        browser.editText(Model.decodeEntry(["auto.txt", "f", 4, 100, 420, null], "/tmp"))
        tryCompare(view, "loading", false)
        tryCompare(area, "activeFocus", true)
        compare(findChild(browser, "textEditorAutoSave").text, "Auto save on")
        keyClick(Qt.Key_End, Qt.ControlModifier)
        keyClick(Qt.Key_A)
        compare(writes().length, 0, "nothing is saved while you type")
        tryVerify(function () { return writes().length === 1 }, 3000)
        compare(writes()[0].args[1], "one\na")
        tryCompare(view, "dirty", false)
        keyClick(Qt.Key_B); keyClick(Qt.Key_C); keyClick(Qt.Key_D)
        tryVerify(function () { return writes().length === 2 }, 3000)
        wait(400)
        compare(writes().length, 2, "a burst of typing is saved once")
        compare(writes()[1].args[1], "one\nabcd")

        mock.writeResult = { code: "ECONFLICT", message: "changed" }
        keyClick(Qt.Key_E)
        tryCompare(view, "prompt", "conflict")
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorCancel"))
        verify(view.autoSavePaused)
        compare(view.notice, "Auto save is paused until you save")
        var before = writes().length
        keyClick(Qt.Key_F)
        wait(600)
        compare(writes().length, before, "after a conflict it stops saving on its own")
        compare(view.prompt, "", "and does not keep asking")
        mock.writeResult = null
        keyClick(Qt.Key_S, Qt.ControlModifier)
        tryVerify(function () { return writes().length === before + 1 })
        verify(writes()[before].args[3] === false)
        tryCompare(view, "autoSavePaused", false, 3000, "saving by hand turns auto save back on")

        keyClick(Qt.Key_G)
        keyClick(Qt.Key_Escape)
        compare(view.prompt, "", "closing saves instead of asking")
        tryCompare(view, "open", false)
        compare(writes()[writes().length - 1].args[1].slice(-1), "g", "the last keystroke is saved")

        browser.editText(Model.decodeEntry(["auto.txt", "f", 4, 100, 420, null], "/tmp"))
        tryCompare(view, "loading", false)
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorAutoSave"))
        compare(view.autoSave, false)
        compare(mock.settingNow("editorAutoSave", true), false, "the toggle is saved as a setting")
        tryCompare(area, "activeFocus", true)
        keyClick(Qt.Key_H)
        wait(500)
        var settled = writes().length
        keyClick(Qt.Key_Escape)
        compare(view.prompt, "unsaved", "with auto save off, closing asks again")
        compare(writes().length, settled)
        waitForRendering(browser)
        mouseClick(findChild(browser, "textEditorDiscard"))
        compare(view.open, false)
        view.autoSaveDelay = 1000
        mock.textFiles = ({})
      }

      function test_9kb_duplicates() {
        waitRows()
        var alpha = Model.decodeEntry(["alpha.yml", "f", 30, 300, 420, null], "/tmp")
        var docs = Model.decodeEntry(["docs", "d", 0, 200, 493, null], "/tmp")
        verify(menuLabels(browser.contextActions(alpha)).indexOf("Find duplicates…") >= 0)
        verify(menuLabels(browser.contextActions(docs)).indexOf("Find duplicates in this folder") >= 0)
        verify(menuLabels(browser.contextActions(null)).indexOf("Find duplicates here") >= 0)

        mock.duplicateResult = { scanned: 3, groups: [{ size: 30, items: [
          { path: "/tmp/alpha.yml", mtime: 300, size: 30 },
          { path: "/tmp/docs/alpha copy.yml", mtime: 400, size: 30 },
          { path: "/tmp/docs/old.yml", mtime: 100, size: 30 }] }] }
        var savedStat = mock.statItems
        mock.statItems = {
          "/tmp/alpha.yml": { kind: "f", size: 30, mtime: 300 },
          "/tmp/docs/alpha copy.yml": { kind: "f", size: 30, mtime: 400 },
          "/tmp/docs/old.yml": { kind: "f", size: 30, mtime: 100 }
        }
        mock.calls = []
        browser.menuEntry = alpha
        browser.runAction("duplicates")
        var view = findChild(browser, "duplicatesView")
        verify(view.open)
        var call = mock.called("findDuplicates")
        compare(call.args[0], "/tmp", "a file outside home is looked for in its own folder")
        compare(call.args[1], "/tmp/alpha.yml")
        tryCompare(view, "searching", false)
        compare(view.leftItem.path, "/tmp/alpha.yml", "the file you picked is on the left")
        compare(view.rightItem.path, "/tmp/docs/alpha copy.yml")
        compare(view.tagFor(view.rightItem), "Newest")
        compare(findChild(browser, "duplicatesTitle").text, "Copies of alpha.yml")
        verify(findChild(browser, "duplicatesSummary").text.indexOf("2 other copies found") === 0, findChild(browser, "duplicatesSummary").text)
        keyClick(Qt.Key_Right)
        compare(view.rightItem.path, "/tmp/docs/old.yml")
        compare(view.tagFor(view.rightItem), "Oldest")
        keyClick(Qt.Key_Right)
        compare(view.rightItem.path, "/tmp/docs/alpha copy.yml", "the arrows wrap around")

        mock.statItems["/tmp/docs/alpha copy.yml"] = { kind: "f", size: 31, mtime: 400 }
        mock.calls = []
        keyClick(Qt.Key_Delete)
        compare(mock.called("trashPaths"), null, "a copy that changed since the search is not trashed")
        verify(view.notice.indexOf("changed since the search") > 0, view.notice)
        mock.statItems["/tmp/docs/alpha copy.yml"] = { kind: "f", size: 30, mtime: 400 }
        mock.calls = []
        keyClick(Qt.Key_Delete)
        compare(mock.called("trashPaths").args[0], ["/tmp/docs/alpha copy.yml"], "Delete trashes the right copy")
        compare(view.items.length, 2)
        compare(view.rightItem.path, "/tmp/docs/old.yml")

        view.askKeepOnly(view.leftItem)
        verify(findChild(browser, "duplicatesConfirm").visible)
        mock.calls = []
        waitForRendering(browser)
        mouseClick(findChild(browser, "duplicatesConfirmKeep"))
        compare(mock.called("statPaths").args[0], ["/tmp/docs/old.yml", "/tmp/alpha.yml"], "the kept copy is checked too")
        compare(mock.called("trashPaths").args[0], ["/tmp/docs/old.yml"], "Keep only this trashes every other copy")
        compare(view.groups.length, 0)
        verify(findChild(browser, "duplicatesSummary").text.indexOf("No duplicates found") === 0)
        keyClick(Qt.Key_Escape)
        compare(view.open, false)

        mock.duplicateResult = { scanned: 9, groups: [
          { size: 500, items: [{ path: "/tmp/a.bin", mtime: 1, size: 500 }, { path: "/tmp/docs/a.bin", mtime: 2, size: 500 }] },
          { size: 20, items: [{ path: "/tmp/b.txt", mtime: 1, size: 20 }, { path: "/tmp/docs/b.txt", mtime: 1, size: 20 }] }] }
        mock.calls = []
        browser.menuEntry = null
        browser.runAction("duplicates")
        compare(mock.called("findDuplicates").args[1], "", "the folder menu looks for every duplicate")
        tryCompare(view, "searching", false)
        compare(findChild(browser, "duplicatesTitle").text, "Duplicates in tmp")
        verify(findChild(browser, "duplicateGroups").visible)
        compare(view.tagFor(view.leftItem), "Oldest")
        keyClick(Qt.Key_Down)
        compare(view.group.size, 20)
        compare(view.tagFor(view.leftItem), "", "copies with the same date get no tag")
        view.reveal("/tmp/docs/b.txt")
        compare(view.open, false, "Show in folder closes the finder")
        tryCompare(pane(), "path", "/tmp/docs")
        pane().navigate("/tmp")
        waitRows()

        mock.duplicateResult = { pending: true }
        mock.calls = []
        browser.findDuplicates(alpha)
        verify(view.searching)
        keyClick(Qt.Key_Escape)
        compare(view.open, false)
        compare(mock.called("cancel").args[0], 77, "closing stops the search")

        mock.duplicateResult = { error: { code: "EINVAL", message: "this file is empty, so every empty file would match" } }
        browser.findDuplicates(alpha)
        tryCompare(view, "searching", false)
        verify(view.error.indexOf("empty") > 0)
        view.close()
        mock.duplicateResult = null
        mock.statItems = savedStat
      }

      function test_9k_transcode() {
        waitRows()
        var png = Model.decodeEntry(["beta.png", "f", 10, 100, 420, null], "/tmp")
        var yml = Model.decodeEntry(["alpha.yml", "f", 30, 300, 420, null], "/tmp")
        var clip = Model.decodeEntry(["clip.mov", "f", 10, 100, 420, null], "/tmp")
        verify(menuLabels(browser.contextActions(png)).indexOf("Transcode…") >= 0, "pictures can be transcoded")
        verify(menuLabels(browser.contextActions(yml)).indexOf("Transcode…") < 0, "other files cannot")

        mock.calls = []
        browser.menuEntry = png
        browser.runAction("transcode")
        compare(browser.dialogMode, "transcode")
        compare(browser.transcodeFormat, "jpg")
        compare(browser.transcodeResolution, "medium")
        compare(findChild(browser, "dialogConfirmButton").text, "Transcode")
        findChild(browser, "transcodeFormat").changed("png")
        findChild(browser, "transcodeSize").changed("low")
        keyClick(Qt.Key_Return)
        compare(browser.dialogMode, "")
        var call = mock.called("transcodePaths")
        compare(call.args[0], ["/tmp/beta.png"])
        compare(call.args[1], "png")
        compare(call.args[2], "low")
        compare(browser.statusText, "Transcoded 1 file")

        browser.menuEntry = clip
        browser.runAction("transcode")
        compare(browser.transcodeFormat, "mp4", "a video gets video formats")
        compare(browser.transcodeResolution, "1080p")
        browser.closeDialog()

        browser.menuEntry = png
        browser.runAction("transcode")
        compare(browser.transcodeFormat, "png", "the last picture choice is kept")
        compare(browser.transcodeResolution, "low")
        var sizes = findChild(browser, "transcodeSize")
        verify(sizes.options.map(function (o) { return o.value }).indexOf("original") >= 0, "pictures can keep their size")
        sizes.changed("original")
        mock.calls = []
        browser.submitDialog()
        compare(mock.called("transcodePaths").args[2], "original")

        browser.menuEntry = clip
        browser.runAction("transcode")
        verify(findChild(browser, "transcodeSize").options.map(function (o) { return o.value }).indexOf("original") >= 0, "so can videos")
        browser.closeDialog()

        mock.transcodeResult = { error: "could not transcode this file", code: "EFAIL" }
        browser.menuEntry = png
        browser.runAction("transcode")
        browser.submitDialog()
        compare(browser.statusText, "Could not transcode: could not transcode this file")
        mock.transcodeResult = null
      }

      function test_9j_compress() {
        waitRows()
        var docs = { name: "docs", path: "/tmp/docs", isDir: true, ext: "" }
        var report = { name: "report.pdf", path: "/tmp/report.pdf", isDir: false, ext: "pdf" }
        verify(menuLabels(browser.contextActions(docs)).indexOf("Compress\u2026") >= 0)
        mock.calls = []
        browser.menuEntry = report
        browser.runAction("compress")
        compare(browser.dialogMode, "compress")
        var field = findChild(browser, "dialogField")
        tryCompare(field, "text", "report")
        var format = findChild(browser, "compressFormat")
        verify(format.visible)
        compare(format.value, ".zip")
        compare(findChild(browser, "dialogConfirmButton").text, "Compress")
        format.changed(".tar.xz")
        field.text = "Quarterly"
        browser.submitDialog()
        compare(browser.dialogMode, "")
        var call = mock.called("compressPaths")
        compare(call.args[0], ["/tmp/report.pdf"])
        compare(call.args[1], "Quarterly.tar.xz")
        compare(browser.statusText, "Compressed to Quarterly.tar.xz")

        browser.menuEntry = docs
        browser.runAction("compress")
        field.text = "a/b"
        browser.submitDialog()
        compare(browser.dialogError, "Name cannot contain a slash")
        browser.closeDialog()

        mock.compressResult = { error: "cancelled", code: "ECANCELED" }
        browser.compressNow([docs], "docs.zip")
        compare(browser.statusText, "Compressing docs.zip cancelled")
        mock.compressResult = null
        browser.compressFormat = ".zip"

        pane().navigate("recent:")
        compare(browser.compressTargets(report).length, 0, "nothing to compress in Recent")
        pane().navigate("/tmp")
        waitRows()
      }

      function test_8b_pickSaveNamesStayInTheFolder() {
        mock.calls = []
        browser.pickerRequest = { mode: "save", result: "/run/u.json", currentFolder: "/tmp", currentName: "x.txt" }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        findChild(browser, "pickNameField").text = ".."
        browser.acceptPick(null)
        compare(mock.called("finishPick"), null, "a name of .. is refused")
        compare(browser.statusText, "That name is not allowed")
        browser.cancelPick()

        mock.calls = []
        browser.pickerRequest = { mode: "savefiles", result: "/run/s.json", currentFolder: "/tmp", files: ["a.txt", "b.txt"] }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        browser.acceptPick(null)
        var call = mock.called("finishPick")
        compare(call.args[0].ok, true)
        compare(call.args[0].paths, ["/tmp/a.txt", "/tmp/b.txt"])

        mock.calls = []
        browser.pickerRequest = { mode: "savefiles", result: "/run/t.json", currentFolder: "/tmp", files: ["ok.txt", "../escape.txt"] }
        beginPick()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        browser.acceptPick(null)
        call = mock.called("finishPick")
        compare(call.args[0].ok, false, "a name that leaves the folder cancels the pick")
        verify(call.args[0].paths === undefined)
        verify(!browser.picking)
      }

      function test_8c_pickNewFolder() {
        mock.calls = []
        browser.pickerRequest = { mode: "open", directory: true, result: "/run/d.json", currentFolder: "/tmp" }
        beginPick()
        waitRows()
        waitForRendering(browser)
        browser.openToolbarMenu("main", findChild(browser, "mainMenuButton"))
        compare(menuLabels(browser.menuActions)[0], "New folder", "the main menu offers a new folder")
        browser.runAction("newfolder")
        compare(browser.dialogMode, "newfolder")
        var field = findChild(browser, "dialogField")
        tryCompare(field, "text", "untitled folder")
        browser.submitDialog()
        compare(mock.called("makeDirectory").args[0], "/tmp/untitled folder")
        compare(browser.dialogMode, "")
        compare(pane().path, "/tmp/untitled folder", "the new folder is entered")
        mouseClick(findChild(browser, "pickAccept"))
        compare(mock.called("finishPick").args[0].paths, ["/tmp/untitled folder"])
        pane().navigate("/tmp")
        waitRows()
      }

      function test_8d_pickerBlocksRiskyActions() {
        mock.calls = []
        browser.pickerRequest = { mode: "open", result: "/run/g.json", currentFolder: "/tmp", appId: "org.example.App" }
        beginPick()
        waitRows()
        verify(browser.pickTitle().indexOf("(for org.example.App)") > 0, "the chooser names the app that asked")
        verify(pane().picking, "the panes know they are picking, so no thumbnails are made")
        pane().setCursor(0, false, false)
        keyClick(Qt.Key_Delete)
        compare(mock.called("trashPaths"), null, "Delete does nothing while picking")
        verify(!findChild(browser, "confirmDialog") || !browser.confirmAction)
        keyClick(Qt.Key_Delete, Qt.ShiftModifier)
        compare(mock.called("deletePaths"), null)
        keyClick(Qt.Key_V, Qt.ControlModifier)
        browser.handleDrop(["file:///home/me/secret.txt"], "/tmp/docs", null)
        compare(mock.called("beginTransfer"), null, "paste and drop do not move files into the app's folder")
        keyClick(Qt.Key_F2)
        compare(browser.dialogMode, "", "rename is off")
        browser.runAction("properties")
        compare(browser.dialogMode, "", "properties is off")
        var keys = browser.contextActions(pane().cursorEntry()).map(function (a) { return a.key })
        verify(keys.indexOf("trash") < 0 && keys.indexOf("delete") < 0 && keys.indexOf("paste") < 0 && keys.indexOf("properties") < 0)
        verify(keys.indexOf("editor") < 0, "no editor while picking")
        verify(keys.indexOf("edittext") < 0 && keys.indexOf("duplicates") < 0, "no editing or duplicate finding while picking")
        var pngKeys = browser.contextActions(Model.decodeEntry(["beta.png", "f", 10, 100, 420, null], "/tmp")).map(function (a) { return a.key })
        verify(pngKeys.indexOf("transcode") < 0, "no transcoding while picking")
        verify(keys.indexOf("open") >= 0 && keys.indexOf("copy") >= 0)
        browser.acceptPick([Model.decodeEntry(["link.txt", "l", 1, 0, 0, "/etc/passwd"], "/tmp")])
        compare(mock.called("finishPick"), null, "a linked file is not handed to the app")
        verify(browser.statusText.indexOf("is a link") >= 0)
        browser.cancelPick()
        verify(!pane().picking)
      }

      function test_8e_conflictsWaitAndIgnoreEarlyKeys() {
        waitRows()
        mock.calls = []
        browser.showDialog("newfolder", "New folder", "draft", null)
        mock.conflictRaised(5, { dest: "/tmp/alpha.yml", seq: 3 })
        compare(browser.dialogMode, "newfolder", "a conflict does not replace an open dialog")
        browser.closeDialog()
        tryCompare(browser, "dialogMode", "conflict")
        keyClick(Qt.Key_R)
        compare(mock.called("resolveConflict"), null, "keys typed right as it appears are ignored")
        wait(browser.conflictKeyDelay + 100)
        keyClick(Qt.Key_R)
        compare(mock.called("resolveConflict").args, [5, "overwrite", false, 3], "the answer carries the conflict number")
        compare(browser.dialogMode, "")
      }

      function test_8f_networkAudioIsNotPlayedInTheShell() {
        mock.remoteRoots = ["/mnt/nas"]
        browser.showPreview(Model.decodeEntry(["song.mp3", "f", 1000, 100, 420, null], "/mnt/nas"))
        compare(browser.previewKind, "remoteaudio")
        compare(findChild(browser, "audioPreviewLoader").active, false)
        browser.closePreview()
        mock.remoteRoots = []
      }

      function test_8g_pickIgnoresTypingFromBeforeItOpened() {
        pane().navigate("/tmp")
        waitRows()
        mock.calls = []
        var name = findChild(browser, "pickNameField")
        browser.pickerRequest = { mode: "save", result: "/run/k.json", currentFolder: "/tmp", currentName: "report.txt" }
        browser.beginPickSession()
        verify(browser.pickInputHeld, "input waits while the chooser opens")
        verify(!name.activeFocus, "the name field does not take keys straight away")
        mouseClick(findChild(browser, "pickAccept"))
        browser.acceptPick(null)
        keyClick(Qt.Key_S)
        keyClick(Qt.Key_E)
        keyClick(Qt.Key_Return)
        compare(mock.called("finishPick"), null, "nothing typed or clicked as the chooser opens answers it")
        compare(name.text, "report.txt", "typing from before the chooser opened never reaches the name")
        verify(browser.pickInputHeld, "each early key restarts the wait")
        tryCompare(browser, "pickInputHeld", false)
        verify(!name.activeFocus, "after early typing the name needs a click")
        verify(browser.statusText.indexOf("Ignored typing") === 0, browser.statusText)
        mouseClick(name)
        verify(name.activeFocus, "a click lets the name take keys")
        browser.cancelPick()

        mock.calls = []
        browser.pickerRequest = { mode: "save", result: "/run/l.json", currentFolder: "/tmp", currentName: "report.txt" }
        beginPick()
        verify(name.activeFocus, "without early typing the name takes keys once the wait ends")
        compare(name.selectedText, "report")
        keyClick(Qt.Key_N)
        keyClick(Qt.Key_Return)
        compare(mock.called("finishPick").args[0].paths[0], "/tmp/n.txt")

        mock.calls = []
        var file = Model.decodeEntry(["beta.png", "f", 10, 100, 420, null], "/tmp")
        browser.pickerRequest = { mode: "open", result: "/run/m.json", currentFolder: "/tmp" }
        browser.beginPickSession()
        browser.handleOpenRequest(file)
        compare(mock.called("finishPick"), null, "a double click as the chooser opens hands over nothing")
        tryCompare(browser, "pickInputHeld", false)
        browser.handleOpenRequest(file)
        compare(mock.called("finishPick").args[0].paths[0], "/tmp/beta.png")
      }

      function test_zz_done() {
        if (failures > 0) return
        console.log("OMAFILE_BROWSER_FLOWS_PASSED")
        harness.passed = true
      }
    }
  }
  Timer { interval: 60000; running: true; onTriggered: { console.log("OMAFILE_BROWSER_FLOWS_TIMEOUT"); Qt.quit() } }
}
