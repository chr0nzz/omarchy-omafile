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
  property bool keyboardActive: false
  property int cursorIndex: 0

  readonly property var flatRows: buildFlatRows()

  readonly property string cursorKey: {
    if (cursorIndex < 0 || cursorIndex >= flatRows.length) return ""
    return rowKey(flatRows[cursorIndex])
  }

  function rowKey(row) {
    if (!row) return ""
    return String(row.key || "") + "|" + String(row.path || "") + "|" + String(row.uri || "")
  }

  function buildFlatRows() {
    var out = []
    var groups = sections()
    for (var g = 0; g < groups.length; g++) {
      var rows = groups[g].rows
      for (var r = 0; r < rows.length; r++) out.push(rows[r])
    }
    out.push({ key: "trash", label: "Trash", path: trashPath(), trash: true })
    return out
  }

  function trashPath() {
    if (service && typeof service.trashFilesPath === "function") return service.trashFilesPath()
    return (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/Trash/files"
  }

  function moveCursor(delta) {
    var count = flatRows.length
    if (count === 0) return
    cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + delta))
  }

  function cursorRow() {
    if (cursorIndex < 0 || cursorIndex >= flatRows.length) return null
    return flatRows[cursorIndex]
  }

  function activateCursor(inNewTab) {
    var row = cursorRow()
    if (!row) return
    if (row.connect === true) { sidebar.connectServer(""); return }
    if (row.server === true) { sidebar.connectServer(String(row.uri || "")); return }
    if (!row.path) return
    if (inNewTab) sidebar.openInNewTab(row.path)
    else sidebar.navigate(row.path)
  }

  function removeCursor() {
    var row = cursorRow()
    if (!row) return
    if (row.bookmark === true) sidebar.removeBookmark(row.path)
    else if (row.key === "drive" || row.key === "usb" || row.key === "networkdrive")
      sidebar.hideDrive(row.path)
  }



  signal navigate(string target)
  signal openInNewTab(string target)
  signal removeBookmark(string target)
  signal hideDrive(string key)
  signal showAllDrives()
  signal connectServer(string uri)
  signal disconnectServer(string path)
  signal dropRequested(var urls, string dest)
  signal placeMenuRequested(var row, real x, real y)
  signal bookmarkDropped(var paths)

  function acceptsBookmark(drag) {
    var paths = dropPaths(drag)
    if (paths.length === 0) return false
    var pinned = service ? service.pinned : []
    for (var i = 0; i < paths.length; i++) if (pinned.indexOf(paths[i]) < 0) return true
    return false
  }

  function handleBookmarkDrop(drop) {
    var paths = dropPaths(drop)
    if (paths.length === 0) return
    drop.accept(Qt.LinkAction)
    sidebar.bookmarkDropped(paths)
  }

  function dropPaths(event) {
    return event && event.hasUrls ? Model.localPathsFromUrls(event.urls) : []
  }

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
    places.push({ key: "recent", label: "Recent", path: "recent:" })
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
    {
      var pins = []
      for (var p = 0; p < pinned.length; p++)
        pins.push({
          key: "pinned", bookmark: true,
          label: service.bookmarkLabel ? service.bookmarkLabel(String(pinned[p])) : (Model.basename(String(pinned[p])) || "/"),
          path: String(pinned[p])
        })
      if (pins.length === 0)
        pins.push({ key: "pinned", label: "Drop folders here to bookmark", path: "", dropBookmark: true })
      out.push({ title: "Bookmarks", rows: pins, bookmarkTarget: true })
    }

    var drives = (sidebar.showDrives && service) ? service.drives : []
    if (drives && drives.length > 0) {
      var vols = []
      for (var d = 0; d < drives.length; d++) {
        var drive = drives[d]
        if (!mountableDrive(drive) || drive.network === true) continue
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
    var seen = {}
    var remembered = service ? service.servers : []
    var firstUri = {}
    for (var r = 0; r < remembered.length; r++) {
      var key = Model.serverKeyOf(String(remembered[r]))
      if (firstUri[key] === undefined) firstUri[key] = String(remembered[r])
    }
    var mounted = service ? service.networkMounts() : []
    for (var n = 0; n < mounted.length; n++) {
      var share = mounted[n]
      if (service && service.driveHidden(String(share.mount))) continue
      var shareKey = share.host ? Model.serverKey(share.user, share.host, share.port) : String(share.mount)
      seen[shareKey] = true
      net.push({
        key: "networkdrive", label: String(share.label || share.mount),
        path: String(share.mount), mounted: share.gvfs === true, connected: true,
        uri: firstUri[shareKey] || "", remembered: firstUri[shareKey] !== undefined,
        free: Number(share.free) || 0, total: Number(share.total) || 0
      })
    }

    for (var v = 0; v < remembered.length; v++) {
      var uri = String(remembered[v])
      var serverKey = Model.serverKeyOf(uri)
      if (seen[serverKey]) continue
      seen[serverKey] = true
      net.push({ key: "networkdrive", label: Model.serverLabel(uri), path: "", uri: uri,
        server: true, connected: false, remembered: true })
    }

    var found = service ? service.discovered : []
    for (var f = 0; f < found.length; f++) {
      var foundKey = Model.serverKeyOf(String(found[f].uri || ""))
      if (seen[foundKey]) continue
      seen[foundKey] = true
      net.push({
        key: "network", label: String(found[f].label || found[f].name),
        path: "", uri: String(found[f].uri || ""), server: true, connected: false
      })
    }

    net.push({ key: "network", label: "Connect to a server", path: "", connect: true })
    out.push({ title: "Network", rows: net })
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
              textFormat: Text.PlainText
              text: modelData.title
              leftPadding: Style.space(12)
              topPadding: Style.space(8)
              bottomPadding: Style.space(3)
              color: headerDrop.containsDrag ? Color.accent : Util.alpha(Color.foreground, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption

              DropArea {
                id: headerDrop
                anchors.fill: parent
                enabled: modelData.bookmarkTarget === true
                keys: ["text/uri-list"]
                onEntered: function (drag) { if (!sidebar.acceptsBookmark(drag)) drag.accepted = false }
                onDropped: function (drop) { sidebar.handleBookmarkDrop(drop) }
              }
            }

            Repeater {
              model: modelData.rows

              delegate: Rectangle {
                required property var modelData
                objectName: "place-" + String(modelData.key || "")
                readonly property bool cursored: sidebar.keyboardActive
                  && sidebar.rowKey(modelData) === sidebar.cursorKey
                width: column.width - Style.space(8)
                x: Style.space(4)
                height: Style.space(24)
                radius: Style.cornerRadius
                color: placeDrop.containsDrag ? Util.alpha(Color.accent, 0.3)
                  : sidebar.currentPath === modelData.path
                  ? Util.alpha(Color.accent, 0.18)
                  : (placeHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")
                border.width: cursored ? Math.max(1, Style.space(1)) : 0
                border.color: Util.alpha(Color.accent, 0.9)

                HoverHandler { id: placeHover }

                DropTarget {
                  id: placeDrop
                  anchors.fill: parent
                  target: modelData.path && String(modelData.path).indexOf(":") < 0
                    && modelData.connect !== true && modelData.server !== true ? String(modelData.path) : ""
                  onFilesDropped: function (urls, dest) { sidebar.dropRequested(urls, dest) }
                }

                DropArea {
                  anchors.fill: parent
                  enabled: modelData.dropBookmark === true
                  keys: ["text/uri-list"]
                  onEntered: function (drag) { if (!sidebar.acceptsBookmark(drag)) drag.accepted = false }
                  onDropped: function (drop) { sidebar.handleBookmarkDrop(drop) }
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton && modelData.key !== "drive" && modelData.key !== "usb"
                        && modelData.unhide !== true) {
                      var point = mapToItem(sidebar, mouse.x, mouse.y)
                      sidebar.placeMenuRequested(modelData, point.x, point.y)
                      return
                    }
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
                    else if (modelData.mounted === true && modelData.uri) sidebar.connectServer(String(modelData.uri))
                    else sidebar.navigate(modelData.path)
                  }
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    id: placeIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.placeGlyph(modelData.key)
                    color: sidebar.currentPath === modelData.path
                      ? Color.accent : Util.alpha(Color.foreground, modelData.connected === false ? 0.3 : 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.iconSmall
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: placeIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: trailing.left
                    anchors.rightMargin: trailing.width > 0 ? Style.space(6) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: modelData.dropBookmark === true || modelData.connected === false ? Util.alpha(Color.foreground, 0.5)
                      : (sidebar.currentPath === modelData.path
                        ? Color.foreground : Util.alpha(Color.foreground, 0.75))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.italic: modelData.dropBookmark === true
                    elide: Text.ElideMiddle
                  }

                  Row {
                    id: trailing
                    objectName: "placeTrailing"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
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
                      textFormat: Text.PlainText
                      objectName: "placeHide"
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
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      visible: modelData.removable === true || modelData.mounted === true
                      text: Icons.actionGlyph("eject")
                      color: ejectHover.hovered ? Color.accent : Util.alpha(Color.foreground, 0.45)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.iconSmall

                      HoverHandler { id: ejectHover }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: {
                          if (!sidebar.service) return
                          if (modelData.mounted === true) sidebar.disconnectServer(modelData.path)
                          else sidebar.service.ejectDrive(modelData.device)
                        }
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
          readonly property bool cursored: sidebar.keyboardActive
            && sidebar.cursorKey === sidebar.rowKey({ key: "trash", path: sidebar.trashPath() })
          width: column.width - Style.space(8)
          x: Style.space(4)
          height: Style.space(24)
          radius: Style.cornerRadius
          color: trashDrop.containsDrag ? Util.alpha(Color.urgent, 0.25)
            : (trashHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")
          border.width: cursored ? Math.max(1, Style.space(1)) : 0
          border.color: Util.alpha(Color.accent, 0.9)

          HoverHandler { id: trashHover }

          DropTarget {
            id: trashDrop
            anchors.fill: parent
            target: "trash:"
            onFilesDropped: function (urls, dest) { sidebar.dropRequested(urls, dest) }
          }

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
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Icons.placeGlyph("trash")
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Trash"
              color: Util.alpha(Color.foreground, 0.75)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            textFormat: Text.PlainText
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
