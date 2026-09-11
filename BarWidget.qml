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
  readonly property string glyph: customGlyph || Icons.actionGlyph("app")
  readonly property bool showBadge: boolSetting("showTransferBadge", true)
  readonly property int activeTransfers: service ? service.activeTransfers : 0
  readonly property real transferFraction: service ? service.transferFraction : 0
  readonly property bool busy: showBadge && activeTransfers > 0
  readonly property bool failed: hasFailedTransfer()
  readonly property bool helperDown: service ? (service.helperError !== "" && !service.helperReady) : false

  readonly property int trashCount: service ? service.trashCount : 0
  readonly property bool trashFull: trashCount > 0
  readonly property bool askBeforeEmptying: boolSetting("trashConfirm", true)
  property bool emptyArmed: false
  readonly property string countText: trashCount > 99 ? "99+" : String(trashCount)
  readonly property bool showTrash: boolSetting("showTrash", false)
  readonly property bool countVisible: showTrash && !vertical && trashFull
  readonly property string trashGlyph: Icons.placeGlyph(trashFull ? "trashfull" : "trash")

  readonly property color trashColor: {
    if (emptyArmed) return root.bar ? root.bar.urgent : Color.urgent
    return button.foreground
  }

  readonly property string trashTip: {
    if (emptyArmed) return "Right click again to empty the trash"
    if (!trashFull) return "Trash is empty"
    return Model.formatCount(trashCount, "item in trash", "items in trash")
      + "  Left click opens it, right click empties it"
  }

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
    if (showTrash && trashFull) parts.push(trashTip)
    else if (trashFull) parts.push(Model.formatCount(trashCount, "item in trash", "items in trash"))
    return parts.join("  ")
  }

  function openTrash() {
    if (!service) return
    service.openWindow(service.trashFilesPath())
  }

  function emptyTrashNow() {
    if (!service || !trashFull) return
    emptyArmed = false
    armTimer.stop()
    service.emptyTrash(null)
  }

  function requestEmpty() {
    if (!service || !trashFull) return
    if (!askBeforeEmptying) { emptyTrashNow(); return }
    if (emptyArmed) { emptyTrashNow(); return }
    emptyArmed = true
    armTimer.restart()
  }

  onTrashCountChanged: {
    if (trashCount === 0) { emptyArmed = false; armTimer.stop() }
  }

  Timer {
    id: armTimer
    interval: 4000
    repeat: false
    onTriggered: root.emptyArmed = false
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
    readonly property bool wideContent: !root.vertical && root.showTrash
    horizontalMargin: wideContent ? 6 : 0
    fixedWidth: root.vertical
      ? -1
      : (wideContent ? content.implicitWidth + Style.spaceReal(12) : Style.bar.iconSlot)
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
      width: content.implicitWidth
      height: Style.bar.iconCanvas

      Row {
        id: content
        anchors.centerIn: parent
        spacing: Style.space(4)
        visible: !root.busy

        Text {
          id: glyphText
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.glyph
          color: root.glyphColor
          font.family: button.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 160 } }
        }

        Row {
          id: trashPart
          visible: root.showTrash
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.trashGlyph
            color: root.trashColor
            font.family: button.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 160 } }
          }

          Text {
            visible: root.countVisible
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.countText
            color: root.trashColor
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }
      }

      MouseArea {
        visible: root.showTrash
        enabled: root.showTrash
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: trashPart.x + content.x
        width: trashPart.width
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: false
        onPressed: function (event) {
          if (event.button === Qt.RightButton) root.requestEmpty()
          else root.openTrash()
          event.accepted = true
        }
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
