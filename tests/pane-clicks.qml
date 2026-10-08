import QtQuick
import QtTest
import Quickshell
import "FilePlugin/components" as Plugin
ShellRoot {
  id: harness
  property bool passed: false
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 800; implicitHeight: 400
    Plugin.PaneView { id: pane; anchors.fill: parent; path: "/tmp"; dirsFirst: false }
    TestCase {
      id: tests
      name: "HeaderSorting"
      when: window.visible
      onCompletedChanged: {
        if (!harness.passed) console.log("OMAFILE_PANE_CLICKS_FAILED")
        Qt.quit()
      }
      function clickHeader(key) {
        var cell = findChild(pane, "header-" + key)
        verify(cell !== null, "header cell " + key)
        mouseClick(cell)
      }
      function rowY(index) {
        var cell = findChild(pane, "header-name")
        var bottom = cell.mapToItem(pane, 0, 0).y + cell.height + 1
        return bottom + pane.rowHeight * index + pane.rowHeight / 2
      }
      function test_headers() {
        tryVerify(function () { return findChild(pane, "header-name") !== null })
        pane.entries = [["alpha.txt","f",30,300,0,null],["beta.csv","f",10,100,0,null],["gamma.log","f",20,200,0,null]]
        pane.rebuild()
        clickHeader("name")
        compare(pane.descending, true)
        compare(pane.rows[0][0], "gamma.log")
        clickHeader("size")
        compare(pane.sortBy, "size")
        compare(pane.rows[0][0], "beta.csv")
        clickHeader("type")
        compare(pane.sortBy, "type")
        compare(pane.rows[0][0], "beta.csv")
        clickHeader("modified")
        compare(pane.sortBy, "modified")
        compare(pane.rows[0][0], "beta.csv")
        clickHeader("modified")
        compare(pane.descending, true)
        compare(pane.rows[0][0], "alpha.txt")
        mouseClick(pane, 100, rowY(0))
        compare(pane.selectedCount, 1)
        verify(pane.dragUriList !== "", "a left press readies the drag")
        mouseClick(pane, 100, rowY(1), Qt.RightButton)
        compare(pane.dragUriList, "", "a right press drags nothing")
        var below = rowY(pane.rows.length) + pane.rowHeight
        verify(below < pane.height, "empty space below the rows")
        mousePress(pane, 100, below)
        mouseMove(pane, 150, rowY(1), 50)
        mouseRelease(pane, 150, rowY(1))
        verify(pane.selectedCount > 0)
        pane.path = "recent:"
        pane.entries = [["gamma.log","f",20,200,0,null],["alpha.txt","f",30,300,0,null]]
        pane.rebuild()
        compare(pane.rows[0][0], "gamma.log")
        clickHeader("name")
        compare(pane.sortBy, "modified")
        compare(pane.rows[0][0], "gamma.log")
        pane.path = "/tmp"
        pane.view = "grid"
        wait(100)
        mouseClick(pane, 50, 50)
        compare(pane.selectedCount, 1)
        console.log("OMAFILE_PANE_CLICKS_PASSED")
        harness.passed = true
      }
      function test_wheel() {
        harness.passed = false
        pane.path = "/tmp"
        pane.view = "list"
        var many = []
        for (var i = 0; i < 300; i++) many.push(["file" + i + ".txt", "f", i, i, 0, null])
        pane.entries = many
        pane.rebuild()
        var lv = pane.activeView()
        var notch = pane.rowHeight * pane.wheelLines
        lv.contentY = 0
        mouseWheel(pane, 300, 200, 0, -120)
        tryCompare(lv, "contentY", notch, 2000, "one notch scrolls a full step")
        lv.contentY = 0
        for (var j = 0; j < 5; j++) mouseWheel(pane, 300, 200, 0, -120)
        tryCompare(lv, "contentY", notch * 5, 2000, "fast notches add up instead of restarting")
        lv.contentY = 0
        for (var k = 0; k < 16; k++) { mouseWheel(pane, 300, 200, 0, -15); wait(4) }
        tryCompare(lv, "contentY", notch * 2, 2000, "a high resolution wheel scrolls as far as a notched one")
        for (var n = 0; n < 200; n++) mouseWheel(pane, 300, 200, 0, 120)
        tryCompare(lv, "contentY", lv.originY, 2000, "scrolling stops at the top")
        console.log("OMAFILE_PANE_WHEEL_PASSED")
        harness.passed = true
      }
    }
  }
  Timer { interval: 15000; running: true; onTriggered: { console.log("OMAFILE_PANE_CLICKS_TIMEOUT"); Qt.quit() } }
}
