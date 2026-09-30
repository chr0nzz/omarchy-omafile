import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Item {
  id: host

  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: "xyzlab.omafile"
  readonly property string popupMode: service ? service.windowMode : "window"
  readonly property bool asPopup: popupMode === "popup"

  property bool shown: false
  property bool closingFromHost: false
  property bool switchingSurface: false
  property var windowSlots: []
  property var slotPayloads: ({})
  property var browsers: ({})
  property string raiseTitle: "Omafile"
  property string raiseAnchor: ""
  property int raiseStep: 0

  function normalizePayload(payloadJson) {
    return payloadJson && String(payloadJson).length > 0 ? String(payloadJson) : "{}"
  }

  function setSlots(next) {
    windowSlots = next
    for (var i = slotModel.count - 1; i >= 0; i--) {
      if (next.indexOf(slotModel.get(i).slot) < 0) slotModel.remove(i)
    }
    for (var j = 0; j < next.length; j++) {
      var present = false
      for (var k = 0; k < slotModel.count; k++) {
        if (slotModel.get(k).slot === next[j]) present = true
      }
      if (!present) slotModel.append({ slot: next[j] })
    }
  }

  function openWindow(payloadJson) {
    var slot = Model.nextWindowSlot(windowSlots)
    slotPayloads[slot] = payloadJson
    raiseTitle = Model.windowTitle(slot)
    raiseAnchor = windowSlots.length > 0 ? Model.windowTitle(Math.min.apply(null, windowSlots)) : ""
    raiseStep = Model.cascadeOffset(windowSlots.length)
    setSlots(windowSlots.concat([slot]))
    raiseTimer.restart()
  }

  function focusExistingWindow(payloadJson) {
    var slot = Math.min.apply(null, windowSlots)
    if (browsers[slot]) browsers[slot].open(payloadJson)
    else slotPayloads[slot] = payloadJson
    raiseTitle = Model.windowTitle(slot)
    raiseAnchor = ""
    raiseTimer.restart()
  }

  function closeWindow(slot) {
    var index = windowSlots.indexOf(slot)
    if (index < 0) return
    var next = windowSlots.slice()
    next.splice(index, 1)
    delete slotPayloads[slot]
    setSlots(next)
    if (next.length === 0 && !closingFromHost) requestClose()
  }

  function open(payloadJson) {
    closingFromHost = false
    var payload = normalizePayload(payloadJson)
    if (asPopup) {
      shown = true
      Qt.callLater(function () {
        var item = popupLoader.item
        if (item) item.open(payload)
      })
    } else if (windowSlots.length > 0 && !Model.wantsNewWindow(payload)) {
      focusExistingWindow(payload)
    } else {
      openWindow(payload)
    }
  }

  function raiseCommand() {
    var target = "title:^" + raiseTitle + "$"
    var move = raiseAnchor === "" ? "" :
      "local anchor = nil "
      + "for _, w in ipairs(hl.get_windows()) do if w.title == \"" + raiseAnchor + "\" then anchor = w end end "
      + "if anchor then hl.dispatch(hl.dsp.window.move({ x = anchor.at.x + " + raiseStep
      + ", y = anchor.at.y + " + raiseStep + ", window = \"" + target + "\" })) end "
    return "(function() local p = hl.get_cursor_pos() " + move
      + "hl.dispatch(hl.dsp.focus({ window = \"" + target + "\" })) "
      + "return hl.dsp.cursor.move(p) end)()"
  }

  function raiseWindow() {
    if (host.asPopup) return
    Hyprland.dispatch(host.raiseCommand())
  }

  function close() {
    closingFromHost = true
    shown = false
    setSlots([])
    slotPayloads = ({})
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  onAsPopupChanged: {
    if (!shown && windowSlots.length === 0) return
    switchingSurface = true
    close()
    Qt.callLater(function () {
      host.open("{}")
      host.switchingSurface = false
    })
  }

  Timer {
    id: raiseTimer
    interval: 90
    repeat: false
    onTriggered: host.raiseWindow()
  }

  Component {
    id: browserComponent

    Browser {
      property var windowSlot: null
      shell: host.shell
      manifest: host.manifest
      service: host.service
      onDismissRequested: windowSlot === null ? host.requestClose() : host.closeWindow(windowSlot)
      onCloseRequested: windowSlot === null ? host.close() : host.closeWindow(windowSlot)
    }
  }

  ListModel { id: slotModel }

  Instantiator {
    model: slotModel

    delegate: FloatingWindow {
      id: window
      required property int slot
      visible: true
      title: Model.windowTitle(slot)
      color: Color.background
      implicitWidth: 1100
      implicitHeight: 720
      minimumSize: Qt.size(640, 420)

      onVisibleChanged: {
        if (visible) return
        if (host.closingFromHost || host.switchingSurface || host.asPopup) return
        host.closeWindow(slot)
      }

      Component.onDestruction: delete host.browsers[slot]

      Loader {
        anchors.fill: parent
        sourceComponent: browserComponent
        onLoaded: {
          item.windowSlot = window.slot
          host.browsers[window.slot] = item
          item.open(host.slotPayloads[window.slot] || "{}")
        }
      }
    }
  }

  PanelWindow {
    id: popup
    visible: host.shown && host.asPopup
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omafile-popup"
    WlrLayershell.keyboardFocus: host.shown && host.asPopup
      ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: host.requestClose()
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(80), Style.space(1100))
      height: Math.min(parent.height - Style.space(80), Style.space(760))
      color: Color.background
      radius: Style.cornerRadius
      border.width: Math.max(1, Style.space(1))
      border.color: Color.popups.border
      clip: true

      MouseArea { anchors.fill: parent }

      Loader {
        id: popupLoader
        anchors.fill: parent
        active: popup.visible
        sourceComponent: browserComponent
      }
    }
  }
}
