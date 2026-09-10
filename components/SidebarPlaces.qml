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

  property bool showDrives: true

  signal navigate(string target)
  signal openInNewTab(string target)
  signal removeBookmark(string target)
  signal hideDrive(string key)
  signal showAllDrives()
  signal connectServer(string uri)
  signal disconnectServer(string path)

  function usablePlace(value, homePath) {
    var p = String(value || "")
    if (!p) return ""
    if (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
    if (!p || p === homePath) return ""
    return p
  }

  function redundantMount(mount) {
    var m = String(mount || "")
    if (!m) return true
    if (m === "/" || m === "/home") return true
    if (m === home) return true
    return false
  }

  function driveLabel(drive) {
    var mount = String(drive.mount || "")
    var name = String(drive.label || "")
    if (!name || name === "root") return Model.basename(mount) || mount
    return name
  }

  function mountableDrive(drive) {
    if (!drive || !drive.mount) return false
    var mount = String(drive.mount)
    if (mount.charAt(0) === "[") return false
    if (String(drive.fstype || "") === "swap") return false
    if (redundantMount(mount)) return false
    return true
  }

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
      var resolved = usablePlace(dirs ? dirs[k] : "", home)
      if (resolved) places.push({ key: k, label: labels[k], path: resolved })
    }
    places.push({ key: "root", label: "Filesystem", path: "/" })
    out.push({ title: "Places", rows: places })

    var pinned = service ? service.pinned : []
    if (pinned && pinned.length > 0) {
      var pins = []
      for (var p = 0; p < pinned.length; p++)
        pins.push({
          key: "pinned", bookmark: true,
          label: Model.basename(String(pinned[p])) || "/",
          path: String(pinned[p])
        })
      out.push({ title: "Bookmarks", rows: pins })
    }

    var drives = (sidebar.showDrives && service) ? service.drives : []
    if (drives && drives.length > 0) {
      var vols = []
      for (var d = 0; d < drives.length; d++) {
        var drive = drives[d]
        if (!mountableDrive(drive)) continue
        if (service && service.driveHidden(String(drive.mount))) continue
        vols.push({
          key: drive.network === true ? "networkdrive" : (drive.removable ? "usb" : "drive"),
          label: driveLabel(drive),
          path: String(drive.mount),
          device: String(drive.path || ""),
          removable: drive.removable === true,
          free: Number(drive.free) || 0,
          total: Number(drive.total) || 0
        })
      }
      if (vols.length > 0) out.push({ title: "Drives", rows: vols })
    }

    var net = []
    var mounted = service ? service.networkMounts() : []
    for (var n = 0; n < mounted.length; n++) {
      var share = mounted[n]
      if (service && service.driveHidden(String(share.mount))) continue
      net.push({
        key: "networkdrive", label: String(share.label || share.mount),
        path: String(share.mount), mounted: true,
        free: Number(share.free) || 0, total: Number(share.total) || 0
      })
    }

    var found = service ? service.discovered : []
    for (var f = 0; f < found.length; f++) {
      net.push({
        key: "network", label: String(found[f].label || found[f].name),
        path: "", uri: String(found[f].uri || ""), server: true
      })
    }

    var previous = service ? service.servers : []
    for (var v = 0; v < previous.length; v++) {
      var uri = String(previous[v])
      if (alreadyMounted(mounted, uri)) continue
      net.push({ key: "recent", label: uri, path: "", uri: uri, server: true })
    }

    net.push({ key: "network", label: "Connect to a server", path: "", connect: true })
    out.push({ title: "Network", rows: net })
    return out
  }

  function alreadyMounted(mounted, uri) {
    for (var i = 0; i < mounted.length; i++) {
      var label = String(mounted[i].label || "")
      var host = String(uri).replace(/^[a-z]+:\/\//, "").replace(/\/$/, "")
      if (host && label.indexOf(host.split("/")[0]) >= 0) return true
    }
    return false
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
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  onClicked: function (mouse) {
                    if (modelData.unhide === true) {
                      sidebar.showAllDrives()
                      return
                    }
                    if (modelData.connect === true) {
                      sidebar.connectServer("")
                      return
                    }
                    if (modelData.server === true) {
                      sidebar.connectServer(String(modelData.uri || ""))
                      return
                    }
                    if (mouse.button === Qt.RightButton && modelData.mounted === true) {
                      sidebar.disconnectServer(modelData.path)
                      return
                    }
                    if (mouse.button === Qt.RightButton) {
                      if (modelData.key === "drive" || modelData.key === "usb"
                        || modelData.key === "networkdrive")
                        sidebar.hideDrive(modelData.path)
                      else if (modelData.bookmark === true)
                        sidebar.removeBookmark(modelData.path)
                      return
                    }
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
                    width: parent.width - Style.space(
                      (modelData.removable === true || modelData.bookmark === true
                        || modelData.key === "drive" || modelData.key === "usb"
                        || (modelData.key === "network" && modelData.mounted === true))
                      ? 46 : 30)
                    text: modelData.label
                    color: sidebar.currentPath === modelData.path
                      ? Color.foreground : Util.alpha(Color.foreground, 0.75)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideMiddle
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.bookmark === true
                    text: Icons.actionGlyph("close")
                    color: unpinHover.hovered ? Color.urgent : Util.alpha(Color.foreground, 0.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.iconSmall

                    HoverHandler { id: unpinHover }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: sidebar.removeBookmark(modelData.path)
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (modelData.key === "drive" || modelData.key === "usb"
                      || modelData.key === "networkdrive")
                      && modelData.connect !== true && modelData.server !== true
                      && modelData.unhide !== true && placeHover.hovered
                    text: Icons.actionGlyph("hidden")
                    color: hideHover.hovered ? Color.urgent : Util.alpha(Color.foreground, 0.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.iconSmall

                    HoverHandler { id: hideHover }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: sidebar.hideDrive(modelData.path)
                    }
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
