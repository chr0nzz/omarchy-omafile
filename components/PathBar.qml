import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: bar

  property string path: ""
  property string home: ""
  readonly property var crumbs: Model.breadcrumbs(Model.collapseTilde(path, home))

  signal navigate(string target)
  signal editRequested()

  implicitHeight: Style.space(26)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.foreground, 0.05)
    border.width: hover.hovered ? Math.max(1, Style.space(1)) : 0
    border.color: Util.alpha(Color.accent, 0.35)

    HoverHandler { id: hover }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton | Qt.MiddleButton
      onClicked: bar.editRequested()
    }

    Item {
      id: viewport
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      height: parent.height
      clip: true

    Row {
      id: crumbRow
      anchors.verticalCenter: parent.verticalCenter
      x: crumbRow.implicitWidth > viewport.width ? viewport.width - crumbRow.implicitWidth : 0
      spacing: 0

      Repeater {
        model: bar.crumbs

        delegate: Row {
          required property var modelData
          required property int index
          spacing: 0

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: index > 0
            text: " " + Icons.actionGlyph("chevronRight") + " "
            color: Util.alpha(Color.foreground, 0.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            width: crumbLabel.implicitWidth + Style.space(8)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: crumbHover.hovered ? Util.alpha(Color.foreground, 0.1) : "transparent"

            HoverHandler { id: crumbHover }

            Text {
              id: crumbLabel
              anchors.centerIn: parent
              text: modelData.label
              color: index === bar.crumbs.length - 1
                ? Color.foreground : Util.alpha(Color.foreground, 0.65)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              anchors.fill: parent
              onClicked: bar.navigate(modelData.path)
            }
          }
        }
      }
    }
    }
  }
}
