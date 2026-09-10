import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: transferBar

  property var service: null
  readonly property var rows: service ? service.transfers : []

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: card
    width: parent.width
    implicitHeight: list.implicitHeight + Style.space(16)
    height: implicitHeight
    color: Color.popups.background
    border.width: Math.max(1, Style.space(1))
    border.color: Color.popups.border
    radius: Style.cornerRadius

    Column {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Repeater {
        model: transferBar.rows

        delegate: Column {
          required property var modelData
          width: list.width
          spacing: Style.space(3)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Icons.actionGlyph(modelData.op === "move" ? "cut" : "copy")
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(70)
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
              color: cancelHover.hovered ? Color.urgent : Util.alpha(Color.popups.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall

              HoverHandler { id: cancelHover }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (transferBar.service) transferBar.service.cancelTransfer(modelData.id)
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
              width: parent.width * (modelData.total > 0
                ? Math.max(0, Math.min(1, modelData.bytes / modelData.total)) : 0)
              height: parent.height
              radius: parent.radius
              color: modelData.state === "failed" ? Color.urgent : Color.accent

              Behavior on width { NumberAnimation { duration: 120 } }
            }
          }

          Text {
            width: parent.width
            text: {
              if (modelData.state === "done") return "Finished"
              if (modelData.state === "failed") return String(modelData.message || "Failed")
              if (modelData.state === "cancelled") return "Cancelled"
              if (modelData.state === "paused") return "Waiting for a decision"
              return Model.formatSize(modelData.bytes) + " of " + Model.formatSize(modelData.total)
                + "   " + Model.formatRate(modelData.rate)
            }
            color: Util.alpha(Color.popups.text, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
