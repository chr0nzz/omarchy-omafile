import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Icons.js" as Icons
import "components"

Panel {
  id: root
  moduleName: "xyzlab.omafile"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool openedFromHotkey: false
  property bool confirmEmpty: false
  readonly property var barIdentity: hostWidget || root
  readonly property string home: Quickshell.env("HOME") || ""

  function open() {
    openedFromHotkey = false
    confirmEmpty = false
    root.controller.show()
    refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    confirmEmpty = false
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
    confirmEmpty = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (!service) return
    service.refreshDrives()
    service.refreshTrash()
    service.freeSpace(home, function (m) {
      root.freeBytes = Number(m.free) || 0
      root.totalBytes = Number(m.total) || 0
    })
  }

  property real freeBytes: 0
  property real totalBytes: 0

  function usablePlace(value, homePath) {
    var p = String(value || "")
    if (!p) return ""
    if (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
    if (!p || p === homePath) return ""
    return p
  }

  function mountableDrive(drive) {
    if (!drive || !drive.mount) return false
    var mount = String(drive.mount)
    if (mount.charAt(0) === "[") return false
    if (String(drive.fstype || "") === "swap") return false
    return true
  }

  function placeRows() {
    var dirs = service ? service.userDirs : ({})
    var rows = []
    rows.push({ key: "home", label: "Home", path: home })
    var order = ["downloads", "documents", "pictures", "videos", "music", "desktop"]
    var labels = {
      downloads: "Downloads", documents: "Documents", pictures: "Pictures",
      videos: "Videos", music: "Music", desktop: "Desktop"
    }
    for (var i = 0; i < order.length; i++) {
      var k = order[i]
      var resolved = usablePlace(dirs ? dirs[k] : "", home)
      if (resolved) rows.push({ key: k, label: labels[k], path: resolved })
    }
    return rows
  }

  function recentRows() {
    var list = service ? service.recent : []
    var rows = []
    for (var i = 0; i < list.length && rows.length < 5; i++) {
      var p = String(list[i])
      if (p === home) continue
      rows.push({ key: "recent", label: Model.collapseTilde(p, home), path: p })
    }
    return rows
  }

  function driveRows() {
    var list = service ? service.drives : []
    var rows = []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (!mountableDrive(d)) continue
      rows.push({
        key: d.network === true ? "network" : (d.removable ? "usb" : "drive"),
        label: String(d.label || d.name || d.mount),
        path: String(d.mount),
        device: String(d.path || ""),
        removable: d.removable === true,
        free: Number(d.free) || 0,
        total: Number(d.total) || 0
      })
    }
    return rows
  }

  function openPath(path) {
    if (!service) return
    root.close()
    service.openWindow(path)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.placeGlyph("home")
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(30)
          text: "Omafile"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        width: parent.width
        text: "Places"
      }

      Repeater {
        model: root.placeRows()

        delegate: PlaceRow {
          required property var modelData
          width: column.width
          label: modelData.label
          glyph: Icons.placeGlyph(modelData.key)
          onClicked: root.openPath(modelData.path)
        }
      }

      PanelSectionHeader {
        width: parent.width
        visible: root.recentRows().length > 0
        text: "Recent"
      }

      Repeater {
        model: root.recentRows()

        delegate: PlaceRow {
          required property var modelData
          width: column.width
          label: modelData.label
          glyph: Icons.placeGlyph("recent")
          onClicked: root.openPath(modelData.path)
        }
      }

      PanelSectionHeader {
        width: parent.width
        visible: root.driveRows().length > 0
        text: "Drives"
      }

      Repeater {
        model: root.driveRows()

        delegate: Item {
          required property var modelData
          width: column.width
          implicitHeight: driveColumn.implicitHeight

          Column {
            id: driveColumn
            width: parent.width
            spacing: Style.space(2)

            PlaceRow {
              width: parent.width
              label: modelData.label
              glyph: Icons.placeGlyph(modelData.key)
              onClicked: root.openPath(modelData.path)
            }

            Row {
              width: parent.width
              spacing: Style.space(6)
              visible: modelData.total > 0

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(80)
                height: Style.space(3)
                radius: height / 2
                color: Util.alpha(Color.popups.text, 0.15)

                Rectangle {
                  width: parent.width * (modelData.total > 0
                    ? Math.max(0, Math.min(1, 1 - modelData.free / modelData.total)) : 0)
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Model.formatSize(modelData.free) + " free"
                color: Util.alpha(Color.popups.text, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      PanelSectionHeader {
        width: parent.width
        visible: root.service !== null && root.service.transfers.length > 0
        text: "Transfers"
      }

      Repeater {
        model: root.service ? root.service.transfers : []

        delegate: Column {
          required property var modelData
          width: column.width
          spacing: Style.space(2)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(30)
              text: modelData.label
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: modelData.state === "running" || modelData.state === "paused"
              text: Icons.actionGlyph("cancel")
              color: transferCancelHover.hovered ? Color.urgent : Util.alpha(Color.popups.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall

              HoverHandler { id: transferCancelHover }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (root.service) root.service.cancelTransfer(modelData.id)
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(3)
            radius: height / 2
            color: Util.alpha(Color.popups.text, 0.15)

            Rectangle {
              width: parent.width * (modelData.total > 0
                ? Math.max(0, Math.min(1, modelData.bytes / modelData.total)) : 0)
              height: parent.height
              radius: parent.radius
              color: modelData.state === "failed" ? Color.urgent : Color.accent
            }
          }
        }
      }

      PanelSeparator { width: parent.width }

      PlaceRow {
        width: parent.width
        label: root.confirmEmpty
          ? "Really empty the trash?"
          : (root.service && root.service.trashCount > 0
            ? "Trash" : "Trash is empty")
        trailing: root.service && root.service.trashCount > 0 && !root.confirmEmpty
          ? String(root.service.trashCount) : ""
        glyph: Icons.placeGlyph("trash")
        foreground: root.confirmEmpty ? Color.urgent : Color.popups.text
        enabled: root.service !== null && root.service.trashCount > 0
        onClicked: {
          if (!root.service) return
          if (root.service.trashCount === 0) return
          if (root.confirmEmpty) {
            root.service.emptyTrash(null)
            root.confirmEmpty = false
          } else root.confirmEmpty = true
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: root.totalBytes > 0

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.placeGlyph("drive")
          color: Util.alpha(Color.popups.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconSmall
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Model.formatSize(root.freeBytes) + " free of " + Model.formatSize(root.totalBytes)
          color: Util.alpha(Color.popups.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
