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
      function test_headers() {
        wait(300)
        pane.entries = [["alpha.txt","f",30,300,0,null],["beta.csv","f",10,100,0,null],["gamma.log","f",20,200,0,null]]
        pane.rebuild()
        mouseClick(pane, 100, 10)
        compare(pane.descending, true)
        compare(pane.rows[0][0], "gamma.log")
        mouseClick(pane, 470, 10)
        compare(pane.sortBy, "size")
        compare(pane.rows[0][0], "beta.csv")
        mouseClick(pane, 585, 10)
        compare(pane.sortBy, "type")
        compare(pane.rows[0][0], "beta.csv")
        mouseClick(pane, 720, 10)
        compare(pane.sortBy, "modified")
        compare(pane.rows[0][0], "beta.csv")
        mouseClick(pane, 720, 10)
        compare(pane.descending, true)
        compare(pane.rows[0][0], "alpha.txt")
        mouseClick(pane, 100, 40)
        compare(pane.selectedCount, 1)
        mousePress(pane, 100, 150)
        mouseMove(pane, 150, 60, 50)
        mouseRelease(pane, 150, 60)
        verify(pane.selectedCount > 0)
        pane.view = "grid"
        wait(100)
        mouseClick(pane, 50, 50)
        compare(pane.selectedCount, 1)
        console.log("OMAFILE_PANE_CLICKS_PASSED")
        harness.passed = true
      }
    }
  }
  Timer { interval: 2000; running: true; onTriggered: { if (!harness.passed) console.log("OMAFILE_HEADER_TEST_FAILED"); Qt.quit() } }
}
