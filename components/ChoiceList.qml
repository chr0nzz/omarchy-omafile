import QtQuick 6.11
import QtQuick.Controls
import qs.Commons

Rectangle {
  id: list

  property var options: []
  property string emptyLabel: "Nothing to choose from"
  signal picked(string value)

  height: Math.min(scroll.implicitHeight, Style.space(190)) + Style.space(8)
  color: Color.popups.background
  border.width: Math.max(1, Style.space(1))
  border.color: Color.popups.border
  radius: Style.cornerRadius

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: list.options.length === 0
    text: list.emptyLabel
    color: Util.alpha(Color.popups.text, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Flickable {
    id: scroll
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    height: Math.min(implicitHeight, Style.space(190))
    implicitHeight: choicesColumn.implicitHeight
    contentHeight: choicesColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollHandle {}

    Column {
      id: choicesColumn
      width: parent.width
      spacing: 0

      Repeater {
        model: list.options

        delegate: Item {
          required property var modelData
          readonly property bool needsAuth: modelData.needsAuth === true
          objectName: "choice-" + modelData.value
          readonly property bool hot: rowHover.hovered
          width: choicesColumn.width
          height: Style.space(24)

          Rectangle {
            anchors.fill: parent
            visible: rowHover.hovered
            radius: Style.cornerRadius
            color: Util.alpha(Color.popups.text, 0.1)
          }

          HoverHandler { id: rowHover }

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: hint.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(6)
            text: modelData.label
            color: modelData.needsAuth ? Util.alpha(Color.popups.text, 0.38)
              : (rowHover.hovered ? Color.popups.text : Util.alpha(Color.popups.text, 0.85))
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: hint
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(8)
            visible: modelData.needsAuth === true
            text: "no permission"
            color: Util.alpha(Color.popups.text, 0.38)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: list.picked(modelData.value)
          }
        }
      }
    }
  }
}
