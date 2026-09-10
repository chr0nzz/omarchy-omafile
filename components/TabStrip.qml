import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: strip

  property var tabs: []
  property int activeIndex: 0

  signal selectTab(int index)
  signal closeTab(int index)
  signal addTab()

  implicitHeight: Style.space(26)
  height: Style.space(26)

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.foreground, 0.02)

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      spacing: Style.space(2)

      Repeater {
        model: strip.tabs

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: Style.space(150)
          height: Style.space(22)
          radius: Style.cornerRadius
          color: index === strip.activeIndex
            ? Util.alpha(Color.accent, 0.18)
            : (tabHover.hovered ? Util.alpha(Color.foreground, 0.07) : "transparent")

          HoverHandler { id: tabHover }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function (mouse) {
              if (mouse.button === Qt.MiddleButton) strip.closeTab(index)
              else strip.selectTab(index)
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(28)
              text: Model.basename(modelData.path) || "/"
              color: index === strip.activeIndex ? Color.foreground : Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: strip.tabs.length > 1 && (tabHover.hovered || index === strip.activeIndex)
              text: Icons.actionGlyph("close")
              color: closeHover.hovered ? Color.urgent : Util.alpha(Color.foreground, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.iconSmall

              HoverHandler { id: closeHover }

              MouseArea {
                anchors.fill: parent
                onClicked: strip.closeTab(index)
              }
            }
          }
        }
      }

      Rectangle {
        width: Style.space(22)
        height: Style.space(22)
        radius: Style.cornerRadius
        color: addHover.hovered ? Util.alpha(Color.foreground, 0.12) : "transparent"

        HoverHandler { id: addHover }

        Text {
          anchors.centerIn: parent
          text: Icons.actionGlyph("add")
          color: addHover.hovered ? Color.accent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconSmall
        }

        MouseArea {
          anchors.fill: parent
          onClicked: strip.addTab()
        }
      }
    }
  }
}
