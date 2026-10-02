import QtQuick

Item {
  id: proxy

  property var view: null
  property bool active: false

  width: 1
  height: 1

  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
  Drag.proposedAction: Qt.MoveAction
  Drag.mimeData: ({ "text/uri-list": view ? view.dragUriList : "" })
  Drag.imageSource: view && view.dragGrab ? view.dragGrab.url : ""
  Drag.active: active && view !== null && view.dragUriList !== ""

  Drag.onDragFinished: function (action) {
    proxy.x = 0
    proxy.y = 0
  }
}
