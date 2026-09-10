import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "components"

Item {
  id: host

  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: "xyzlab.omafile"
  readonly property string popupMode: service
    ? String(service.setting("windowMode", "window")) : "window"
  readonly property bool asPopup: popupMode === "popup"

  property bool shown: false
  property bool closingFromHost: false
  property string pendingPayload: "{}"

  function open(payloadJson) {
    closingFromHost = false
    pendingPayload = payloadJson && String(payloadJson).length > 0 ? String(payloadJson) : "{}"
    shown = true
    Qt.callLater(function () {
      var item = host.activeBrowser()
      if (item) item.open(host.pendingPayload)
      if (!host.asPopup) raiseTimer.restart()
    })
  }

  function raiseWindow() {
    if (host.asPopup) return
    Hyprland.dispatch("hl.dsp.focus({ window = \"title:^Omafile$\" })")
  }

  function close() {
    closingFromHost = true
    shown = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else shown = false
  }

  function activeBrowser() {
    if (asPopup) return popupLoader.item
    return windowLoader.item
  }

  onAsPopupChanged: {
    if (!shown) return
    Qt.callLater(function () {
      var item = host.activeBrowser()
      if (item) item.open("{}")
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
      shell: host.shell
      manifest: host.manifest
      service: host.service
      onDismissRequested: host.requestClose()
      onCloseRequested: host.close()
    }
  }

  FloatingWindow {
    id: window
    visible: host.shown && !host.asPopup
    title: "Omafile"
    color: Color.background
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(640, 420)

    onVisibleChanged: {
      if (!visible && !host.closingFromHost && !host.asPopup) host.requestClose()
    }

    Loader {
      id: windowLoader
      anchors.fill: parent
      active: window.visible
      sourceComponent: browserComponent
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
