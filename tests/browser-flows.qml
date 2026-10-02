import QtQuick
import QtTest
import Quickshell
import "FilePlugin/components" as Plugin
import "FilePlugin/tests" as Mocks
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
        mouseClick(findChild(browser, "sortButton"))
        verify(browser.menuOpen)
        compare(browser.menuKind, "sort")
        menuItem("Z to A")
        verify(!browser.menuOpen)
        compare(pane().sortBy, "name")
        compare(pane().descending, true)
        browser.setView("grid")
        mouseClick(findChild(browser, "sortButton"))
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

      function test_zz_done() {
        if (failures > 0) return
        console.log("OMAFILE_BROWSER_FLOWS_PASSED")
        harness.passed = true
      }
    }
  }
  Timer { interval: 60000; running: true; onTriggered: { console.log("OMAFILE_BROWSER_FLOWS_TIMEOUT"); Qt.quit() } }
}
