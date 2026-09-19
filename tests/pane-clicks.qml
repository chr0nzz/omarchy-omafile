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
    }
  }
  Timer { interval: 15000; running: true; onTriggered: { console.log("OMAFILE_PANE_CLICKS_TIMEOUT"); Qt.quit() } }
}
