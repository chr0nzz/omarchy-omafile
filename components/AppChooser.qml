import QtQuick 6.11
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

Item {
  id: chooser

  property string value: ""
  property var options: []
  property string placeholderText: "Search..."
  property string emptyText: "No matches"
  property string triggerLabel: ""
  property bool showLabel: false
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
  readonly property bool popupOpen: popup.opened
  property var filtered: options

  signal changed(string value)

  function open() { popup.open() }
  function close() { popup.close() }

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }

  function currentLabel() {
    for (var i = 0; i < options.length; i++) if (optionValue(options[i]) === value) return optionLabel(options[i])
    return value
  }

  function refilter() {
    var q = searchField.text.toLowerCase()
    if (!q) {
      filtered = options
      return
    }
    filtered = options.filter(function (o) { return chooser.optionLabel(o).toLowerCase().indexOf(q) !== -1 })
  }

  function choose(index) {
    if (index < 0 || index >= filtered.length) return
    var v = optionValue(filtered[index])
    value = v
    changed(v)
    popup.close()
  }

  onOptionsChanged: refilter()
  implicitHeight: Style.spacing.controlHeight

  BorderSurface {
    id: trigger
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.controlFill(trigger.activeFocus, triggerHover.hovered, chooser.foreground, chooser.accent)
    borderSpec: Border.controlSpec(trigger.activeFocus ? "focus" : (triggerHover.hovered ? "hover-cursor" : "normal"), chooser.foreground, chooser.accent)
    activeFocusOnTab: true

    HoverHandler { id: triggerHover }

    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        popup.opened ? popup.close() : popup.open()
        event.accepted = true
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: trigger.borderRight + Style.spacing.md
      text: chooser.currentLabel() || chooser.triggerLabel || chooser.placeholderText
      color: chooser.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        popup.opened ? popup.close() : popup.open()
      }
    }

    QQC.Popup {
      id: popup
      y: trigger.height + Style.spacing.xxs
      width: trigger.width
      implicitHeight: Math.max(Style.spacing.searchablePopupMinHeight,
        Math.min(resultList.contentHeight + Style.space(50), Style.spacing.popupRowHeight * 6 + Style.space(50)))
      padding: Style.spacing.hairline
      focus: true

      background: BorderSurface {
        color: chooser.background
        borderSpec: chooser.popupBorderSpec
        radius: Style.cornerRadius
      }

      onOpened: {
        searchField.text = ""
        chooser.refilter()
        Qt.callLater(function () { searchField.forceActiveFocus() })
      }
      onClosed: searchField.text = ""

      contentItem: Column {
        Item {
          id: searchHeader
          width: parent.width
          height: Style.spacing.popupRowHeight + Style.spacing.controlPaddingX

          EditField {
            id: searchField
            objectName: "appChooserSearch"
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            placeholderText: chooser.placeholderText
            foreground: chooser.foreground
            accent: chooser.accent
            onTextChanged: {
              chooser.refilter()
              resultList.currentIndex = resultList.count > 0 ? 0 : -1
            }
            keyFilter: function (event) {
              if (event.key === Qt.Key_Escape) popup.close()
              else if (event.key === Qt.Key_Down && resultList.count > 0) {
                resultList.currentIndex = 0
                resultList.forceActiveFocus()
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) chooser.choose(Math.max(0, resultList.currentIndex))
              else return false
              return true
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(chooser.foreground, 0.10)
        }

        Item {
          width: parent.width
          height: popup.height - searchHeader.height - Style.spacing.xxs - 1

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: resultList.count === 0
            text: chooser.emptyText
            color: Qt.darker(chooser.foreground, 1.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ListView {
            id: resultList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: chooser.filtered
            currentIndex: -1
            keyNavigationEnabled: false

            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) popup.close()
              else if (event.key === Qt.Key_Down) currentIndex = Math.min(count - 1, currentIndex + 1)
              else if (event.key === Qt.Key_Up) {
                if (currentIndex <= 0) searchField.forceActiveFocus()
                else currentIndex = currentIndex - 1
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) chooser.choose(currentIndex)
              else return
              event.accepted = true
            }

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: resultList.width
              height: Style.spacing.popupRowHeight
              color: index === resultList.currentIndex ? Style.hoverFillFor(chooser.foreground, chooser.accent) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: chooser.optionLabel(modelData)
                color: index === resultList.currentIndex ? Style.hoverStateColor(chooser.foreground, chooser.accent) : chooser.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: resultList.currentIndex = parent.index
                onClicked: chooser.choose(parent.index)
              }
            }
          }
        }
      }
    }
  }
}
