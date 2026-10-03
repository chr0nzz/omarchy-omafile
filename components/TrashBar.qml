import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Rectangle {
  id: trashBar

  property var service: null
  readonly property int count: service ? Number(service.trashCount) || 0 : 0
  readonly property real bytes: service && service.trashBytes !== undefined ? Number(service.trashBytes) || 0 : 0
  readonly property bool full: count > 0
  signal emptyRequested()

  height: Style.space(36)
  color: Util.alpha(Color.foreground, 0.03)

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: Math.max(1, Style.space(1))
    color: Util.alpha(Color.foreground, 0.08)
  }

  Row {
    anchors.left: parent.left
    anchors.right: emptyButton.left
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)
    clip: true

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: Icons.placeGlyph(trashBar.full ? "trashfull" : "trash")
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.iconSmall
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "Trash"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      textFormat: Text.PlainText
      objectName: "trashSummary"
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!trashBar.full) return "Empty"
        var label = Model.formatCount(trashBar.count, "item", "items")
        return trashBar.bytes > 0 ? label + ", " + Model.formatSize(trashBar.bytes) : label
      }
      color: Util.alpha(Color.foreground, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Button {
    id: emptyButton
    objectName: "emptyTrashButton"
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: "Empty trash"
    iconText: Icons.actionGlyph("delete")
    iconSize: Style.font.iconSmall
    fontSize: Style.font.bodySmall
    bordered: true
    enabled: trashBar.full
    opacity: enabled ? 1 : 0.35
    foreground: enabled ? Color.urgent : Color.foreground
    tooltipText: trashBar.full ? "Delete everything in the trash for good" : "The trash is already empty"
    onClicked: trashBar.emptyRequested()
  }
}
