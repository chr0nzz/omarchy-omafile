import QtQuick
import QtQuick.Templates as T
import qs.Commons

T.ScrollBar {
  id: bar

  readonly property bool wide: hovered || pressed
  readonly property real thin: Math.max(2, Style.space(4))
  readonly property real thick: Math.max(6, Style.space(8))
  readonly property real length: vertical ? height : width

  policy: T.ScrollBar.AsNeeded
  hoverEnabled: true
  visible: policy === T.ScrollBar.AlwaysOn || (policy === T.ScrollBar.AsNeeded && size > 0 && size < 1)
  minimumSize: length > 0 ? Math.min(1, Style.space(32) / length) : 0
  padding: Style.space(2)
  implicitWidth: vertical ? thick + Style.space(6) : 0
  implicitHeight: vertical ? 0 : thick + Style.space(6)

  contentItem: Item {
    implicitWidth: bar.thick
    implicitHeight: bar.thick

    Rectangle {
      objectName: "scrollThumb"
      readonly property real across: bar.wide ? bar.thick : bar.thin
      x: bar.vertical ? parent.width - across : 0
      y: bar.vertical ? 0 : parent.height - across
      width: bar.vertical ? across : parent.width
      height: bar.vertical ? parent.height : across
      radius: Math.min(Style.cornerRadius, across / 2)
      color: bar.pressed ? Util.alpha(Color.accent, 0.85)
        : Util.alpha(Color.foreground, bar.wide ? 0.5 : 0.3)

      Behavior on width { enabled: bar.vertical; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on height { enabled: !bar.vertical; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on x { enabled: bar.vertical; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: !bar.vertical; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  background: Item {}
}
