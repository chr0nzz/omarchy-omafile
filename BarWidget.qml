import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Icons.js" as Icons

BarWidget {
  id: root
  moduleName: "xyzlab.omafile"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("xyzlab.omafile") : null
  readonly property string customGlyph: String(setting("glyph", "") || "").trim()
  readonly property string glyph: customGlyph || Icons.placeGlyph("home")
  readonly property bool showBadge: boolSetting("showTransferBadge", true)
  readonly property int activeTransfers: service ? service.activeTransfers : 0
  readonly property real transferFraction: service ? service.transferFraction : 0
  readonly property bool busy: showBadge && activeTransfers > 0
  readonly property bool failed: hasFailedTransfer()
  readonly property bool helperDown: service ? (service.helperError !== "" && !service.helperReady) : false

  readonly property color glyphColor: {
    if (failed || helperDown) return root.bar ? root.bar.urgent : Color.urgent
    if (busy) return Color.accent
    return button.foreground
  }

  readonly property string tooltip: {
    var parts = []
    if (helperDown) parts.push("File helper is not running")
    else if (busy) parts.push(Model.formatCount(activeTransfers, "transfer running", "transfers running"))
    else parts.push("Omafile")
    if (service && service.trashCount > 0)
      parts.push(Model.formatCount(service.trashCount, "item in trash", "items in trash"))
    return parts.join("  ")
  }

  function hasFailedTransfer() {
    if (!service) return false
    var list = service.transfers
    for (var i = 0; i < list.length; i++)
      if (list[i].state === "failed") return true
    return false
  }

  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "boolean") return v
    var s = String(v).toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Popup.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltip
    horizontalMargin: 0
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function (b) {
      if (b === Qt.RightButton) root.togglePanel()
      else if (b === Qt.MiddleButton) {
        if (root.service) root.service.openWindow(root.service.startPath())
      } else {
        if (root.service) root.service.toggleWindow()
      }
    }

    Item {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas

      Text {
        id: glyphText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.glyph
        color: root.glyphColor
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
        visible: !root.busy

        Behavior on color { ColorAnimation { duration: 160 } }
      }

      Canvas {
        id: ring
        anchors.centerIn: parent
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        visible: root.busy

        property real fraction: root.transferFraction
        property color trackColor: Util.alpha(button.foreground, 0.2)
        property color fillColor: root.glyphColor

        onFractionChanged: requestPaint()
        onTrackColorChanged: requestPaint()
        onFillColorChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var radius = Math.max(2, Math.min(width, height) / 2 - 2)
          ctx.lineWidth = 2
          ctx.strokeStyle = trackColor
          ctx.beginPath()
          ctx.arc(cx, cy, radius, 0, Math.PI * 2)
          ctx.stroke()
          if (fraction <= 0) return
          ctx.strokeStyle = fillColor
          ctx.beginPath()
          ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fraction)
          ctx.stroke()
        }
      }
    }
  }
}
