import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../TextEditing.js" as TextEditing

TextField {
  id: field

  property var clipboardSource: null
  property var keyFilter: null
  property var editUndo: []
  property var editRedo: []
  readonly property var editKeys: ({
    ControlModifier: Qt.ControlModifier, ShiftModifier: Qt.ShiftModifier,
    AltModifier: Qt.AltModifier, MetaModifier: Qt.MetaModifier,
    Key_V: Qt.Key_V, Key_X: Qt.Key_X, Key_Z: Qt.Key_Z, Key_Y: Qt.Key_Y,
    Key_Insert: Qt.Key_Insert, Key_Backspace: Qt.Key_Backspace, Key_Delete: Qt.Key_Delete,
    Normal: TextInput.Normal
  })

  readOnly: true
  onVisibleChanged: if (!visible) { editUndo = []; editRedo = [] }
  onPressed: forceActiveFocus()

  Keys.onPressed: function (event) {
    if (field.keyFilter && field.keyFilter(event)) event.accepted = true
    else if (TextEditing.handleKey(field, event, field.editKeys)) event.accepted = true
  }

  Rectangle {
    id: caret
    objectName: "editCaret"
    property bool lit: true
    visible: field.activeFocus && lit && field.selectionStart === field.selectionEnd
    x: field.cursorRectangle.x
    y: field.cursorRectangle.y
    width: Math.max(1, Style.space(1))
    height: field.cursorRectangle.height
    color: field.color

    Timer {
      interval: 530
      repeat: true
      running: field.activeFocus
      onTriggered: caret.lit = !caret.lit
      onRunningChanged: caret.lit = true
    }

    Connections {
      target: field
      function onCursorPositionChanged() { caret.lit = true }
    }
  }
}
