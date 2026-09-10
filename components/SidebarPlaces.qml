import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: sidebar

  property var service: null
  property string currentPath: ""
  readonly property string home: Quickshell.env("HOME") || ""

  signal navigate(string target)
  signal openInNewTab(string target)

  function sections() {
    var out = []
    var dirs = service ? service.userDirs : ({})
    var places = []
    places.push({ key: "home", label: "Home", path: home })
    var order = ["desktop", "documents", "downloads", "music", "pictures", "videos"]
    var labels = {
      desktop: "Desktop", documents: "Documents", downloads: "Downloads",
      music: "Music", pictures: "Pictures", videos: "Videos"
    }
    for (var i = 0; i < order.length; i++) {
      var k = order[i]
      if (dirs && dirs[k]) places.push({ key: k, label: labels[k], path: String(dirs[k]) })
    }
    places.push({ key: "root", label: "Filesystem", path: "/" })
    out.push({ title: "Places", rows: places })

    var pinned = service ? service.pinned : []
    if (pinned && pinned.length > 0) {
      var pins = []
      for (var p = 0; p < pinned.length; p++)
        pins.push({ key: "pinned", label: Model.basename(String(pinned[p])) || "/", path: String(pinned[p]) })
      out.push({ title: "Pinned", rows: pins })
    }

    var drives = service ? service.drives : []
    if (drives && drives.length > 0) {
      var vols = []
      for (var d = 0; d < drives.length; d++) {
        var drive = drives[d]
        if (!drive || !drive.mount) continue
        vols.push({
          key: drive.removable ? "usb" : "drive",
          label: String(drive.label || drive.name || drive.mount),
          path: String(drive.mount),
          device: String(drive.path || ""),
          removable: drive.removable === true,
          free: Number(drive.free) || 0,
          total: Number(drive.total) || 0
        })
      }
      if (vols.length > 0) out.push({ title: "Drives", rows: vols })
    }
    return out
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.foreground, 0.03)

    Flickable {
      anchors.fill: parent
      anchors.topMargin: Style.space(6)
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: sidebar.sections()

          delegate: Column {
            required property var modelData
            width: column.width
            spacing: Style.space(1)

            Text {
              text: modelData.title
              leftPadding: Style.space(12)
              topPadding: Style.space(8)
              bottomPadding: Style.space(3)
              color: Util.alpha(Color.foreground, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: modelData.rows

              delegate: Rectangle {
                required property var modelData
                width: column.width - Style.space(8)
                x: Style.space(4)
                height: Style.space(24)
                radius: Style.cornerRadius
                color: sidebar.currentPath === modelData.path
                  ? Util.alpha(Color.accent, 0.18)
                  : (placeHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")

                HoverHandler { id: placeHover }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.MiddleButton) sidebar.openInNewTab(modelData.path)
                    else sidebar.navigate(modelData.path)
                  }
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.placeGlyph(modelData.key)
                    color: sidebar.currentPath === modelData.path
                      ? Color.accent : Util.alpha(Color.foreground, 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.iconSmall
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(46)
                    text: modelData.label
                    color: sidebar.currentPath === modelData.path
                      ? Color.foreground : Util.alpha(Color.foreground, 0.75)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideMiddle
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.removable === true
                    text: Icons.actionGlyph("eject")
                    color: ejectHover.hovered ? Color.accent : Util.alpha(Color.foreground, 0.45)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.iconSmall

                    HoverHandler { id: ejectHover }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (sidebar.service) sidebar.service.ejectDrive(modelData.device)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Item {
          width: column.width
          height: Style.space(10)
        }

        Rectangle {
          width: column.width - Style.space(8)
          x: Style.space(4)
          height: Style.space(24)
          radius: Style.cornerRadius
          color: trashHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent"

          HoverHandler { id: trashHover }

          MouseArea {
            anchors.fill: parent
            onClicked: sidebar.navigate((Quickshell.env("XDG_DATA_HOME") || sidebar.home + "/.local/share") + "/Trash/files")
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Icons.placeGlyph("trash")
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Trash"
              color: Util.alpha(Color.foreground, 0.75)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            visible: sidebar.service !== null && sidebar.service.trashCount > 0
            text: sidebar.service ? String(sidebar.service.trashCount) : ""
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: column.width
          height: Style.space(10)
        }
      }
    }
  }
}
