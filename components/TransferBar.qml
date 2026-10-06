import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: transferBar

  property var service: null
  property var expanded: ({})
  readonly property var transfers: service ? service.transfers : []
  readonly property var byId: indexTransfers(transfers)
  property var ids: []

  onTransfersChanged: syncIds()
  Component.onCompleted: syncIds()

  function indexTransfers(list) {
    var out = {}
    for (var i = 0; i < list.length; i++) out[list[i].id] = list[i]
    return out
  }

  function syncIds() {
    var next = []
    for (var i = transfers.length - 1; i >= 0; i--) next.push(transfers[i].id)
    if (next.length === ids.length && next.every(function (id, n) { return id === ids[n] })) return
    ids = next
  }
  readonly property int running: service ? service.activeTransfers : 0
  readonly property int finished: service ? service.finishedTransfers : 0

  signal minimizeRequested()

  implicitWidth: Style.space(360)
  implicitHeight: card.height
  width: implicitWidth
  height: implicitHeight

  function toggle(id) {
    var next = {}
    for (var k in expanded) next[k] = expanded[k]
    next[id] = !next[id]
    expanded = next
  }

  function shortPath(path) {
    return Model.collapseTilde(String(path || ""), service ? service.home : "")
  }

  function active(t) {
    return t.state === "running" || t.state === "paused"
  }

  function fraction(t) {
    if (t.state === "done") return 1
    return t.total > 0 ? Math.max(0, Math.min(1, t.bytes / t.total)) : 0
  }

  function statusLine(t) {
    if (t.state === "done") {
      var skipped = Number(t.skipped) || 0
      var errors = t.errors ? t.errors.length : 0
      if (errors > 0) return "Finished with " + Model.formatCount(errors, "error", "errors")
      if (skipped > 0) return "Finished, " + Model.formatCount(skipped, "item skipped", "items skipped")
      return "Finished"
    }
    if (t.state === "failed") return String(t.message || "Failed")
    if (t.state === "cancelled") return "Cancelled"
    if (t.state === "paused") return "Waiting for a decision"
    if (t.op === "extract" && t.total <= 0) return "Extracting"
    var line = Model.formatSize(t.bytes) + " of " + Model.formatSize(t.total)
    if (t.rate > 0) {
      line += "   " + Model.formatRate(t.rate)
      if (t.total > t.bytes) line += "   " + Model.formatEta((t.total - t.bytes) / t.rate) + " left"
    }
    return line
  }

  function details(t) {
    var out = []
    if (t.op === "extract") {
      out.push({ key: "What", value: "Extracting " + String(t.label || "") })
      out.push({ key: "To", value: shortPath(t.result || t.dest) })
      if (t.files > 0) out.push({ key: "Files", value: String(t.files) })
      if (t.total > 0) out.push({ key: "Read", value: Model.formatSize(t.bytes) + " of " + Model.formatSize(t.total) })
    } else {
      var verb = t.op === "move" ? "Moving" : "Copying"
      out.push({ key: "What", value: verb + " " + Model.formatCount(Number(t.count) || 1, "item", "items") })
      if (t.from) out.push({ key: "From", value: shortPath(t.from) })
      out.push({ key: "To", value: shortPath(t.dest) })
      if (t.filesTotal > 0) out.push({ key: "Files", value: t.files + " of " + t.filesTotal })
      if (t.total > 0) out.push({ key: "Size", value: Model.formatSize(t.bytes) + " of " + Model.formatSize(t.total) })
    }
    if (active(t) && t.current) out.push({ key: "Now", value: Model.basename(t.current) })
    var end = t.finishedMs || Date.now()
    if (t.startedMs) out.push({ key: active(t) ? "Running" : "Took", value: Model.formatEta((end - t.startedMs) / 1000) })
    var errors = t.errors || []
    for (var i = 0; i < Math.min(errors.length, 5); i++) {
      var e = errors[i]
      var text = typeof e === "string" ? e : (Model.basename(String(e.path || "")) + ": " + String(e.message || e.code || "error"))
      out.push({ key: i === 0 ? "Errors" : "", value: text })
    }
    if (errors.length > 5) out.push({ key: "", value: "and " + (errors.length - 5) + " more" })
    return out
  }

  Rectangle {
    id: card
    width: parent.width
    height: header.height + Math.min(list.implicitHeight, Style.space(320)) + Style.space(14)
    color: Color.popups.background
    border.width: Math.max(1, Style.space(1))
    border.color: Color.popups.border
    radius: Style.cornerRadius

    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      height: Style.space(32)

      Column {
        anchors.left: parent.left
        anchors.right: headerButtons.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          textFormat: Text.PlainText
          text: "Transfers"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          text: transferBar.running > 0
            ? Model.formatCount(transferBar.running, "running", "running")
              + (transferBar.finished > 0 ? ", " + transferBar.finished + " done" : "")
            : "All done"
          color: Util.alpha(Color.popups.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: headerButtons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Button {
          objectName: "clearCompleted"
          text: "Clear completed"
          enabled: transferBar.finished > 0
          opacity: enabled ? 1 : 0.35
          onClicked: if (transferBar.service) transferBar.service.clearFinishedTransfers()
        }

        Button {
          objectName: "minimizeTransfers"
          iconText: Icons.actionGlyph("chevronDown")
          tooltipText: "Minimize to the status bar"
          onClicked: transferBar.minimizeRequested()
        }
      }
    }

    Rectangle {
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Util.alpha(Color.popups.text, 0.1)
    }

    Flickable {
      id: flick
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottomMargin: Style.space(8)
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      contentHeight: list.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

      Column {
        id: list
        width: flick.width
        spacing: Style.space(10)

        Repeater {
          model: transferBar.ids

          delegate: Column {
            id: entry
            required property var modelData
            readonly property var item: transferBar.byId[modelData] || ({ id: modelData, state: "done", bytes: 0, total: 0 })
            readonly property bool open: transferBar.expanded[modelData] === true
            readonly property bool live: transferBar.active(item)
            objectName: "transfer-" + modelData
            width: list.width
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: Style.space(26)

              MouseArea {
                anchors.fill: parent
                onClicked: transferBar.toggle(entry.item.id)
              }

              Text {
                textFormat: Text.PlainText
                id: opGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.actionGlyph(entry.item.op === "extract" ? "extract" : (entry.item.op === "move" ? "cut" : "copy"))
                color: Util.alpha(Color.popups.text, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconSmall
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: opGlyph.right
                anchors.leftMargin: Style.space(6)
                anchors.right: rowButtons.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: entry.item.label
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
              }

              Row {
                id: rowButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  visible: entry.live
                  text: Math.round(transferBar.fraction(entry.item) * 100) + "%"
                  color: Util.alpha(Color.popups.text, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: Icons.actionGlyph(entry.open ? "chevronUp" : "chevronDown")
                  color: Util.alpha(Color.popups.text, 0.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconSmall
                }

                Button {
                  objectName: entry.live ? "cancelTransfer" : "clearTransfer"
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Icons.actionGlyph(entry.live ? "cancel" : "close")
                  tooltipText: entry.live ? "Cancel" : "Clear"
                  onClicked: {
                    if (!transferBar.service) return
                    if (entry.live) transferBar.service.cancelTransfer(entry.item.id)
                    else transferBar.service.clearTransfer(entry.item.id)
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Util.alpha(Color.popups.text, 0.15)

              Rectangle {
                width: parent.width * transferBar.fraction(entry.item)
                height: parent.height
                radius: parent.radius
                color: entry.item.state === "failed" ? Color.urgent
                  : (entry.live ? Color.accent : Util.alpha(Color.accent, 0.45))

                Behavior on width { NumberAnimation { duration: 120 } }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: transferBar.statusLine(entry.item)
              color: entry.item.state === "failed" ? Color.urgent : Util.alpha(Color.popups.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Column {
              width: parent.width
              visible: entry.open
              spacing: Style.space(1)
              topPadding: Style.space(2)

              Repeater {
                model: entry.open ? transferBar.details(entry.item) : []

                delegate: Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(58)
                    text: modelData.key
                    color: Util.alpha(Color.popups.text, 0.45)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width - Style.space(64)
                    text: modelData.value
                    color: Util.alpha(Color.popups.text, 0.8)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
