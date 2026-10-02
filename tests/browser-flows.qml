import QtQuick
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
        var call = mock.called("openWith")
        verify(call !== null, "openWith called by click")
        compare(call.args[1], "/tmp/alpha.yml")
        compare(browser.dialogMode, "")
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
          if (mock.calls[i].name === "thumbnailFor") verify(mock.calls[i].args[0] !== "/tmp/beta.png", "images load directly")
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

      function menuLabels(items) { return items.filter(function (i) { return i.label !== "" }).map(function (i) { return i.label }) }

      function test_3i_sidebarMenu() {
        compare(browser.placeMenuActions({ key: "drive", path: "/mnt" }).length, 0)
        compare(browser.placeMenuActions({ key: "usb", path: "/media/usb" }).length, 0)
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
        keyClick(Qt.Key_Space)
        verify(!browser.previewOpen)
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
      }

      function test_7_pickOpen() {
        waitRows()
        mock.pickRequest = { mode: "open", multiple: false, directory: false, result: "/run/x.json",
          filters: [{ name: "Images", patterns: ["*.png"] }, { name: "All", patterns: ["*"] }], currentFilter: 0 }
        browser.beginPickSession()
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
        verify(!browser.picking)
      }

      function test_8_pickSaveAndCancel() {
        mock.calls = []
        mock.pickRequest = { mode: "save", result: "/run/y.json", currentFolder: "/tmp", currentName: "new.txt", filters: [] }
        browser.beginPickSession()
        tryVerify(function () { return !pane().loading && pane().rows.length === 3 })
        waitForRendering(browser)
        mouseClick(findChild(browser, "pickAccept"))
        compare(mock.called("finishPick").args[0].paths[0], "/tmp/new.txt")
        mock.calls = []
        mock.pickRequest = { mode: "save", result: "/run/z.json", currentFolder: "/tmp", currentName: "alpha.yml" }
        browser.beginPickSession()
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
        mock.pickRequest = { mode: "open", result: "/run/w.json" }
        browser.beginPickSession()
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
        var opened = mock.calls.filter(function (c) { return c.name === "openExternally" })
        compare(opened.length, 2, "both files open")
        compare(browser.tabsA.length, 2, "the folder opens in a new tab")
        keyClick(Qt.Key_W, Qt.ControlModifier)
        pane().clearSelection()
      }

      function test_9bb_openManyAsksFirst() {
        waitRows()
        mock.calls = []
        var limit = browser.openConfirmLimit
        browser.openConfirmLimit = 2
        pane().selectAll()
        keyClick(Qt.Key_Return)
        compare(mock.called("openExternally"), null, "asks before opening more than the limit")
        keyClick(Qt.Key_Escape)
        compare(mock.called("openExternally"), null, "cancel opens nothing")
        compare(browser.tabsA.length, 1)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Return)
        var opened = mock.calls.filter(function (c) { return c.name === "openExternally" })
        compare(opened.length, 2, "confirming opens both files")
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

      function test_zz_done() {
        if (failures > 0) return
        console.log("OMAFILE_BROWSER_FLOWS_PASSED")
        harness.passed = true
      }
    }
  }
  Timer { interval: 60000; running: true; onTriggered: { console.log("OMAFILE_BROWSER_FLOWS_TIMEOUT"); Qt.quit() } }
}
