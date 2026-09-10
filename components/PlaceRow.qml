import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: place

  property string label: ""
  property string glyph: ""
  property string trailing: ""
  property color foreground: Color.popups.text
  property bool highlighted: false
  property bool enabled: true

  signal clicked()

  implicitHeight: Style.space(24)
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: place.highlighted
      ? Util.alpha(Color.accent, 0.18)
      : (rowHover.hovered && place.enabled ? Util.alpha(place.foreground, 0.09) : "transparent")

    HoverHandler { id: rowHover }

    MouseArea {
      anchors.fill: parent
      enabled: place.enabled
      onClicked: place.clicked()
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: place.glyph !== ""
        text: place.glyph
        color: place.highlighted ? Color.accent : Util.alpha(place.foreground, 0.65)
        font.family: Style.font.family
        font.pixelSize: Style.font.iconSmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(place.trailing === "" ? 30 : 90)
        text: place.label
        color: place.enabled ? place.foreground : Util.alpha(place.foreground, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      visible: place.trailing !== ""
      text: place.trailing
      color: Util.alpha(place.foreground, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
