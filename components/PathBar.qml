import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: bar

  property string path: ""
  property string home: ""
  property bool findMode: false
  property bool editing: false
  property bool filterOpen: false
  readonly property var crumbs: Model.breadcrumbs(Model.collapseTilde(path, home))
  readonly property alias filterText: filterInput.text
  readonly property bool filterFocused: filterInput.activeFocus
  readonly property bool pathFocused: pathInput.activeFocus

  signal navigate(string target)
  signal filterEdited(string text)
  signal searchSubmitted(string text)
  signal dismissed()
  signal editingFinished()

  onPathChanged: {
    if (bar.editing) bar.endEdit()
  }

  implicitHeight: Style.space(28)

  function beginEdit() {
    editing = true
    pathInput.text = Model.collapseTilde(bar.path, bar.home)
    pathInput.forceActiveFocus()
    pathInput.selectAll()
  }

  function endEdit() {
    if (!editing) return
    editing = false
    pathInput.focus = false
    bar.editingFinished()
  }

  function openFilter() {
    bar.filterOpen = true
    filterInput.forceActiveFocus()
    filterInput.selectAll()
  }

  function closeFilter() {
    filterInput.text = ""
    bar.filterOpen = false
    filterInput.focus = false
    bar.filterEdited("")
  }

  function focusFilter() {
    bar.openFilter()
  }

  function clearFilter() {
    filterInput.text = ""
    bar.filterEdited("")
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.foreground, 0.05)
    border.width: (barHover.hovered || bar.pathFocused || bar.filterFocused) ? Math.max(1, Style.space(1)) : 0
    border.color: bar.findMode && bar.filterFocused
      ? Util.alpha(Color.urgent, 0.55) : Util.alpha(Color.accent, 0.4)

    HoverHandler { id: barHover }

    Row {
      anchors.fill: parent
      spacing: 0

      Item {
        id: locationZone
        width: parent.width - collapsedFilter.width
        height: parent.height

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onClicked: bar.beginEdit()
          enabled: !bar.editing
        }

        Item {
          id: viewport
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(4)
          height: parent.height
          clip: true
          visible: !bar.editing

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
                  color: crumbHover.hovered ? Util.alpha(Color.foreground, 0.12) : "transparent"

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

        TextInput {
          id: pathInput
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(4)
          visible: bar.editing
          color: Color.foreground
          selectionColor: Util.alpha(Color.accent, 0.45)
          selectedTextColor: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          clip: true
          selectByMouse: true

          onAccepted: {
            var value = String(text || "").trim()
            bar.endEdit()
            if (value) bar.navigate(value)
          }

          Keys.onEscapePressed: {
            bar.endEdit()
            bar.dismissed()
          }

          onActiveFocusChanged: {
            if (!activeFocus) bar.endEdit()
          }
        }
      }

      Item {
        id: collapsedFilter
        width: Style.space(32)
        height: parent.height

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(24)
          height: Style.space(20)
          radius: Style.cornerRadius
          color: iconHover.hovered ? Util.alpha(Color.foreground, 0.12) : "transparent"

          HoverHandler { id: iconHover }

          Text {
            anchors.centerIn: parent
            text: Icons.actionGlyph("search")
            color: Util.alpha(Color.foreground, iconHover.hovered ? 0.8 : 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
          }

          MouseArea {
            anchors.fill: parent
            onClicked: bar.openFilter()
          }
        }
      }
    }

    Rectangle {
      id: filterOverlay
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: bar.filterOpen ? parent.width : 0
      height: parent.height
      radius: Style.cornerRadius
      clip: true
      color: Color.background
      border.width: Math.max(1, Style.space(1))
      border.color: bar.findMode ? Util.alpha(Color.urgent, 0.6) : Util.alpha(Color.accent, 0.5)

      Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)
        visible: bar.filterOpen

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.actionGlyph("search")
          color: bar.findMode ? Color.urgent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconSmall
        }

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(56)
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: filterInput.text.length === 0
            text: bar.findMode ? "Search this folder and everything in it" : "Filter this folder"
            color: Util.alpha(Color.foreground, 0.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
          }

          TextInput {
            id: filterInput
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            color: bar.findMode ? Color.urgent : Color.foreground
            selectionColor: Util.alpha(Color.accent, 0.45)
            selectedTextColor: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            clip: true
            selectByMouse: true

            onTextChanged: bar.filterEdited(text)
            onAccepted: bar.searchSubmitted(text)

            onActiveFocusChanged: {
              if (!activeFocus && text.length === 0 && bar.filterOpen) bar.closeFilter()
            }

            Keys.onEscapePressed: {
              if (text.length > 0) {
                text = ""
                bar.filterEdited("")
                return
              }
              bar.closeFilter()
              bar.dismissed()
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.actionGlyph("close")
          color: closeHover.hovered ? Color.urgent : Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconSmall

          HoverHandler { id: closeHover }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              bar.closeFilter()
              bar.dismissed()
            }
          }
        }
      }
    }
  }
}
