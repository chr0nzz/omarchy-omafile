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
    if (row.unmounted === true) { sidebar.mountDrive(row.device); return }
    if (!row.path) return
    if (inNewTab) sidebar.openInNewTab(row.path)
    else sidebar.navigate(row.path)
  }

  function moveCursorRow(delta) {
    var row = cursorRow()
    if (!row || !row.orderId) return
    var key = rowKey(row)
    moveRow(row, delta)
    var rows = flatRows
    for (var i = 0; i < rows.length; i++) if (rowKey(rows[i]) === key) cursorIndex = i
  }

  function sectionIds(section) {
    var groups = sections()
    for (var g = 0; g < groups.length; g++)
      if (groups[g].id === section) return Model.placeOrderIds(groups[g].rows)
    return []
  }

  function moveRow(row, delta) {
    if (!row || !row.orderId || !service) return
    var ids = sectionIds(row.section)
    var to = ids.indexOf(row.orderId) + delta
    if (ids.indexOf(row.orderId) < 0 || to < 0 || to >= ids.length) return
    service.setPlaceOrder(row.section, Model.movePlace(ids, row.orderId, to))
  }

  property string dragSection: ""
  property string dragId: ""
  property int dragFrom: -1
  property int dragCount: 0
  property real dragOffset: 0
  property bool dragSettling: false
  readonly property real rowStep: Style.space(24) + Style.space(1)
  readonly property int dragTo: dragId === "" ? -1
    : Math.max(0, Math.min(dragCount - 1, dragFrom + Math.round(dragOffset / rowStep)))

  function beginRowDrag(row) {
    dragSection = String(row.section || "")
    dragId = String(row.orderId || "")
    dragFrom = Number(row.orderIndex)
    dragCount = Number(row.orderCount)
    dragOffset = 0
    dragSettling = false
  }

  function updateRowDrag(offset) {
    if (!dragId || dragSettling) return
    dragOffset = Math.max(-dragFrom * rowStep, Math.min((dragCount - 1 - dragFrom) * rowStep, offset))
  }

  function endRowDrag() {
    if (!dragId || dragSettling) return
    dragSettling = true
    dragOffset = (dragTo - dragFrom) * rowStep
    settleTimer.restart()
  }

  function clearRowDrag() {
    dragSection = ""
    dragId = ""
    dragFrom = -1
    dragCount = 0
    dragOffset = 0
    dragSettling = false
  }

  function commitRowDrag() {
    var section = dragSection
    var id = dragId
    var to = dragTo
    clearRowDrag()
    if (!service || !id || to < 0) return
    var ids = sectionIds(section)
    if (ids.indexOf(id) < 0 || ids.indexOf(id) === to) return
    service.setPlaceOrder(section, Model.movePlace(ids, id, to))
  }

  function rowShift(row) {
    if (!dragId || !row || !row.orderId || row.section !== dragSection) return 0
    if (row.orderId === dragId) return dragOffset
    var index = Number(row.orderIndex)
    if (dragFrom < dragTo && index > dragFrom && index <= dragTo) return -rowStep
    if (dragFrom > dragTo && index >= dragTo && index < dragFrom) return rowStep
    return 0
  }

  Timer {
    id: settleTimer
    interval: 150
    onTriggered: sidebar.commitRowDrag()
  }

  property string sectionDragId: ""
  property var sectionDragIds: []
  property var sectionDragTops: []
  property var sectionDragHeights: []
  property int sectionDragFrom: -1
  property real sectionDragOffset: 0
  property bool sectionDragSettling: false
  property int sectionDragDrop: -1
  readonly property int sectionDragTo: sectionDragId === "" ? -1
    : sectionDragSettling ? sectionDragDrop
    : Model.sectionDropIndex(sectionDragTops, sectionDragHeights, sectionDragFrom, sectionDragOffset)

  function moveSection(section, delta) {
    if (!service) return
    var ids = Model.placeOrderIds(sections())
    var from = ids.indexOf(section)
    var to = from + delta
    if (from < 0 || to < 0 || to >= ids.length) return
    service.setPlaceOrder("sections", Model.movePlace(ids, section, to))
  }

  function beginSectionDrag(section) {
    var ids = []
    var tops = []
    var heights = []
    for (var i = 0; i < sectionRepeater.count; i++) {
      var item = sectionRepeater.itemAt(i)
      if (!item) return false
      ids.push(String(item.modelData.id || ""))
      tops.push(item.y)
      heights.push(item.height)
    }
    if (ids.indexOf(section) < 0 || ids.length < 2) return false
    sectionDragIds = ids
    sectionDragTops = tops
    sectionDragHeights = heights
    sectionDragFrom = ids.indexOf(section)
    sectionDragOffset = 0
    sectionDragSettling = false
    sectionDragId = section
    return true
  }

  function updateSectionDrag(offset) {
    if (!sectionDragId || sectionDragSettling) return
    sectionDragOffset = Model.clampSectionOffset(sectionDragTops, sectionDragHeights, sectionDragFrom, offset)
  }

  function endSectionDrag() {
    if (!sectionDragId || sectionDragSettling) return
    sectionDragDrop = sectionDragTo
    sectionDragSettling = true
    sectionDragOffset = Model.sectionSettleOffset(sectionDragTops, sectionDragHeights, sectionDragFrom, sectionDragDrop)
    sectionSettleTimer.restart()
  }

  function commitSectionDrag() {
    var ids = sectionDragIds
    var id = sectionDragId
    var from = sectionDragFrom
    var to = sectionDragTo
    sectionDragId = ""
    sectionDragIds = []
    sectionDragTops = []
    sectionDragHeights = []
    sectionDragFrom = -1
    sectionDragOffset = 0
    sectionDragSettling = false
    sectionDragDrop = -1
    if (!service || !id || to < 0 || to === from) return
    service.setPlaceOrder("sections", Model.movePlace(ids, id, to))
  }

  function sectionShift(section) {
    if (!sectionDragId) return 0
    if (section === sectionDragId) return sectionDragOffset
    var index = sectionDragIds.indexOf(section)
    if (index < 0) return 0
    return Model.sectionShift(sectionDragHeights, column.spacing, sectionDragFrom, sectionDragTo, index)
  }

  Timer {
    id: sectionSettleTimer
    interval: 150
    onTriggered: sidebar.commitSectionDrag()
  }

  function orderedSection(section, rows) {
    var saved = service && typeof service.placeOrderFor === "function" ? service.placeOrderFor(section) : []
    var ordered = Model.orderPlaces(rows, saved)
    var count = Model.placeOrderIds(ordered).length
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].section = section
      ordered[i].orderIndex = i
      ordered[i].orderCount = count
    }
    return ordered
  }

  function removeCursor() {
    var row = cursorRow()
    if (!row) return
    if (row.bookmark === true) sidebar.removeBookmark(row.path)
    else if (row.hideKey) sidebar.hideDrive(row.hideKey)
  }



  signal navigate(string target)
  signal openInNewTab(string target)
  signal removeBookmark(string target)
  signal hideDrive(string key)
  signal showAllDrives()
  signal connectServer(string uri)
  signal disconnectServer(string path)
  signal mountDrive(string device)
  signal dropRequested(var urls, string dest, var position)
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

  function userMount(mount) {
    var m = String(mount || "")
    return m.indexOf("/run/media/") === 0 || m.indexOf("/media/") === 0
  }

  function mountableDrive(drive) {
    if (!drive) return false
    if (!drive.mount) return drive.mountable === true
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
    places.push({ key: "home", label: "Home", path: home, orderId: "home" })
    places.push({ key: "recent", label: "Recent", path: "recent:", orderId: "recent" })
    var order = ["desktop", "documents", "downloads", "music", "pictures", "videos"]
    var labels = {
      desktop: "Desktop", documents: "Documents", downloads: "Downloads",
      music: "Music", pictures: "Pictures", videos: "Videos"
    }
    for (var i = 0; i < order.length; i++) {
      var k = order[i]
      var resolved = usablePlace(dirs ? dirs[k] : "", home)
      if (resolved) places.push({ key: k, label: labels[k], path: resolved, orderId: k })
    }
    places.push({ key: "root", label: "Filesystem", path: "/", orderId: "root" })
    out.push({ id: "places", title: "Places", rows: orderedSection("places", places) })

    var pinned = service ? service.pinned : []
    {
      var pins = []
      for (var p = 0; p < pinned.length; p++)
        pins.push({
          key: "pinned", bookmark: true,
          label: service.bookmarkLabel ? service.bookmarkLabel(String(pinned[p])) : (Model.basename(String(pinned[p])) || "/"),
          path: String(pinned[p]),
          orderId: String(pinned[p])
        })
      if (pins.length === 0)
        pins.push({ key: "pinned", label: "Drop folders here to bookmark", path: "", dropBookmark: true })
      out.push({ id: "bookmarks", title: "Bookmarks", rows: orderedSection("bookmarks", pins), bookmarkTarget: true })
    }

    var drives = (sidebar.showDrives && service) ? service.drives : []
    if (drives && drives.length > 0) {
      var vols = []
      for (var d = 0; d < drives.length; d++) {
        var drive = drives[d]
        if (!mountableDrive(drive) || drive.network === true) continue
        var isMounted = !!drive.mount
        var hideKey = isMounted ? String(drive.mount) : String(drive.path || "")
        if (service && service.driveHidden(hideKey)) continue
        vols.push({
          key: drive.removable ? "usb" : "drive",
          label: isMounted ? driveLabel(drive)
            : String(drive.label || Model.basename(String(drive.path || ""))),
          path: isMounted ? String(drive.mount) : "",
          device: String(drive.path || ""),
          hideKey: hideKey,
          orderId: hideKey,
          unmounted: !isMounted,
          unmountable: isMounted && (drive.removable === true || userMount(drive.mount)),
          removable: drive.removable === true,
          free: Number(drive.free) || 0,
          total: Number(drive.total) || 0
        })
      }
      if (vols.length > 0) out.push({ id: "drives", title: "Drives", rows: orderedSection("drives", vols) })
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
        path: String(share.mount), hideKey: String(share.mount), orderId: shareKey, mounted: share.gvfs === true, connected: true,
        uri: firstUri[shareKey] || "", remembered: firstUri[shareKey] !== undefined,
        free: Number(share.free) || 0, total: Number(share.total) || 0
      })
    }

    for (var v = 0; v < remembered.length; v++) {
      var uri = String(remembered[v])
      var serverKey = Model.serverKeyOf(uri)
      if (seen[serverKey]) continue
      seen[serverKey] = true
      net.push({ key: "networkdrive", label: Model.serverLabel(uri), path: "", uri: uri, orderId: serverKey,
        server: true, connected: false, remembered: true })
    }

    var found = service ? service.discovered : []
    for (var f = 0; f < found.length; f++) {
      var foundKey = Model.serverKeyOf(String(found[f].uri || ""))
      if (seen[foundKey]) continue
      seen[foundKey] = true
      net.push({
        key: "network", label: String(found[f].label || found[f].name),
        path: "", uri: String(found[f].uri || ""), orderId: foundKey, server: true, connected: false
      })
    }

    net.push({ key: "network", label: "Connect to a server", path: "", connect: true })
    out.push({ id: "network", title: "Network", rows: orderedSection("network", net) })
    for (var o = 0; o < out.length; o++) out[o].orderId = out[o].id
    var ordered = Model.orderPlaces(out, service && typeof service.placeOrderFor === "function"
      ? service.placeOrderFor("sections") : [])
    for (var x = 0; x < ordered.length; x++) {
      ordered[x].orderIndex = x
      ordered[x].orderCount = ordered.length
    }
    return ordered
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

      ScrollBar.vertical: ScrollHandle {}

      Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          id: sectionRepeater
          model: sidebar.sections()

          delegate: Column {
            id: sectionColumn
            required property var modelData
            readonly property bool dragging: sidebar.sectionDragId !== ""
              && sidebar.sectionDragId === String(modelData.id || "")
            width: column.width
            spacing: Style.space(1)
            z: dragging ? 1 : 0
            opacity: dragging ? 0.85 : 1
            transform: Translate {
              y: sidebar.sectionShift(String(sectionColumn.modelData.id || ""))
              Behavior on y {
                enabled: !sectionColumn.dragging || sidebar.sectionDragSettling
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }
            }

            Text {
              textFormat: Text.PlainText
              objectName: "section-" + String(modelData.id || "")
              width: parent.width
              text: modelData.title
              leftPadding: Style.space(12)
              topPadding: Style.space(8)
              bottomPadding: Style.space(3)
              color: headerDrop.containsDrag || sectionColumn.dragging ? Color.accent : Util.alpha(Color.foreground, 0.4)
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

              MouseArea {
                property real pressY: 0
                property bool reordering: false
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                cursorShape: reordering ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function (mouse) {
                  pressY = mapToItem(sidebar, mouse.x, mouse.y).y
                  reordering = false
                }
                onPositionChanged: function (mouse) {
                  if (!(pressedButtons & Qt.LeftButton) || sidebar.sectionDragSettling) return
                  var offset = mapToItem(sidebar, mouse.x, mouse.y).y - pressY
                  if (!reordering) {
                    if (Math.abs(offset) < Style.space(8)) return
                    reordering = sidebar.beginSectionDrag(String(sectionColumn.modelData.id || ""))
                    if (!reordering) return
                  }
                  sidebar.updateSectionDrag(offset)
                }
                onReleased: if (reordering) sidebar.endSectionDrag()
                onCanceled: if (reordering) sidebar.endSectionDrag()
                Component.onDestruction: if (reordering) sidebar.endSectionDrag()
                onClicked: function (mouse) {
                  if (reordering || mouse.button !== Qt.RightButton) return
                  var point = mapToItem(sidebar, mouse.x, mouse.y)
                  sidebar.placeMenuRequested({ header: true, section: String(sectionColumn.modelData.id || ""),
                    label: String(sectionColumn.modelData.title || ""),
                    sectionIndex: Number(sectionColumn.modelData.orderIndex),
                    sectionCount: Number(sectionColumn.modelData.orderCount) }, point.x, point.y)
                }
              }
            }

            Repeater {
              model: modelData.rows

              delegate: Rectangle {
                id: placeRow
                required property var modelData
                readonly property bool movable: !!modelData.orderId
                readonly property bool dragging: movable && sidebar.dragId === String(modelData.orderId)
                  && sidebar.dragSection === String(modelData.section || "")
                objectName: "place-" + String(modelData.key || "")
                z: dragging ? 1 : 0
                readonly property bool cursored: sidebar.keyboardActive
                  && sidebar.rowKey(modelData) === sidebar.cursorKey
                width: column.width - Style.space(8)
                x: Style.space(4)
                height: Style.space(24)
                radius: Style.cornerRadius
                transform: Translate {
                  y: sidebar.rowShift(placeRow.modelData)
                  Behavior on y {
                    enabled: !placeRow.dragging || sidebar.dragSettling
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                  }
                }
                color: placeDrop.containsDrag || dragging ? Util.alpha(Color.accent, 0.3)
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
                  onFilesDropped: function (urls, dest, position) { sidebar.dropRequested(urls, dest, position) }
                }

                DropArea {
                  anchors.fill: parent
                  enabled: modelData.dropBookmark === true
                  keys: ["text/uri-list"]
                  onEntered: function (drag) { if (!sidebar.acceptsBookmark(drag)) drag.accepted = false }
                  onDropped: function (drop) { sidebar.handleBookmarkDrop(drop) }
                }

                MouseArea {
                  id: rowMouse
                  property real pressY: 0
                  property bool reordering: false
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  preventStealing: placeRow.movable
                  onPressed: function (mouse) {
                    pressY = mapToItem(sidebar, mouse.x, mouse.y).y
                    reordering = false
                  }
                  onPositionChanged: function (mouse) {
                    if (!placeRow.movable || !(pressedButtons & Qt.LeftButton) || sidebar.dragSettling) return
                    var offset = mapToItem(sidebar, mouse.x, mouse.y).y - pressY
                    if (!reordering) {
                      if (Math.abs(offset) < Style.space(8)) return
                      reordering = true
                      sidebar.beginRowDrag(placeRow.modelData)
                    }
                    sidebar.updateRowDrag(offset)
                  }
                  onReleased: if (reordering) sidebar.endRowDrag()
                  onCanceled: if (reordering) sidebar.endRowDrag()
                  Component.onDestruction: if (reordering) sidebar.endRowDrag()
                  onClicked: function (mouse) {
                    if (reordering) return
                    if (mouse.button === Qt.RightButton && modelData.unhide !== true) {
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
                    if (modelData.unmounted === true) {
                      sidebar.mountDrive(modelData.device)
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
                    color: sidebar.currentPath === modelData.path && modelData.path !== ""
                      ? Color.accent
                      : Util.alpha(Color.foreground, modelData.connected === false || modelData.unmounted === true ? 0.3 : 0.6)
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
                    color: modelData.dropBookmark === true || modelData.connected === false || modelData.unmounted === true
                      ? Util.alpha(Color.foreground, 0.5)
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
                      visible: !!modelData.hideKey && placeHover.hovered
                      text: Icons.actionGlyph("hidden")
                      color: hideHover.hovered ? Color.urgent : Util.alpha(Color.foreground, 0.35)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.iconSmall

                      HoverHandler { id: hideHover }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: sidebar.hideDrive(modelData.hideKey)
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      visible: (modelData.removable === true && modelData.unmounted !== true) || modelData.mounted === true
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
            onFilesDropped: function (urls, dest, position) { sidebar.dropRequested(urls, dest, position) }
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
