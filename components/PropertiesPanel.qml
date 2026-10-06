import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Column {
  id: panel

  property var entry: null
  property var info: null
  property var identity: null
  property var service: null
  property real bytes: 0
  property int files: 0
  property int dirs: 0
  property bool usageDone: false
  property string openerMime: ""
  property string openerHandler: ""

  signal applied()

  readonly property real labelWidth: Style.space(100)
  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.55)
  readonly property bool isLink: info ? info.kind === "l" : false
  readonly property bool isRoot: identity ? identity.root === true : false
  readonly property bool isOwner: info && identity ? info.uid === identity.uid : false
  readonly property bool canChmod: info !== null && !info.error && !isLink && (isOwner || isRoot)
  readonly property bool canChgrp: canChmod && identity !== null
  readonly property bool canChown: isRoot && !isLink
  readonly property int originalBits: info ? (Number(info.mode) & 511) : 0

  property int editBits: 0
  property string editGroup: ""
  property string editOwner: ""
  property bool recursive: false
  property bool busy: false
  property string errorText: ""
  property string tab: "general"

  readonly property bool modeDirty: editBits !== originalBits
  readonly property bool groupDirty: info !== null && editGroup !== "" && editGroup !== String(info.group)
  readonly property bool ownerDirty: info !== null && editOwner !== "" && editOwner !== String(info.owner)
  readonly property bool dirty: modeDirty || groupDirty || ownerDirty

  spacing: Style.space(12)

  onInfoChanged: resetEdits()

  function resetEdits() {
    editBits = info ? (Number(info.mode) & 511) : 0
    editGroup = info ? String(info.group || "") : ""
    editOwner = info ? String(info.owner || "") : ""
    recursive = false
    errorText = ""
  }

  function bitFor(row, col) {
    return 1 << (8 - (row * 3 + col))
  }

  function toggleBit(row, col) {
    if (!canChmod || busy) return
    editBits = editBits ^ bitFor(row, col)
  }

  function groupOptions() {
    var names = identity && identity.groups ? identity.groups.slice() : []
    var current = info ? String(info.group || "") : ""
    if (current !== "" && names.indexOf(current) < 0) names.push(current)
    return names
  }

  function ownerOptions() {
    var names = identity && identity.users ? identity.users.slice() : []
    var current = info ? String(info.owner || "") : ""
    if (current !== "" && names.indexOf(current) < 0) names.push(current)
    return names
  }

  function fail(m) {
    busy = false
    errorText = m && m.code === "EPERM" ? "Operation not permitted"
      : String((m && m.message) || (m && m.code) || "Could not apply the change")
    applied()
  }

  function apply() {
    if (!service || !entry || busy || !dirty) return
    busy = true
    errorText = ""
    var path = entry.path
    var finishMode = function () {
      if (!modeDirty) {
        busy = false
        applied()
        return
      }
      var change = Model.modeChange(originalBits, editBits)
      service.changeMode(path, change.set, change.clear, recursive && entry.isDir, function () {
        busy = false
        applied()
      }, panel.fail)
    }
    if (groupDirty || ownerDirty) {
      service.changeOwner(path, ownerDirty ? editOwner : "", groupDirty ? editGroup : "",
        recursive && entry.isDir, finishMode, panel.fail)
    } else finishMode()
  }

  Row {
    id: tabBar
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: [{ key: "general", label: "General" }, { key: "security", label: "Security" }]

      delegate: Button {
        required property var modelData
        objectName: modelData.key + "Tab"
        text: modelData.label
        bordered: true
        selected: panel.tab === modelData.key
        onClicked: panel.tab = modelData.key
      }
    }
  }

  function generalGroups() {
    if (!entry) return []
    var groups = []
    var kind = []
    kind.push({ label: "Type of file", value: Model.kindLabel(entry) + (openerMime !== "" && !entry.isDir ? " (" + openerMime + ")" : "") })
    if (!entry.isDir) kind.push({ label: "Opens with", opener: true })
    if (entry.linkTarget) kind.push({ label: "Links to", value: String(entry.linkTarget) })
    groups.push(kind)

    var place = []
    place.push({ label: "Location", value: Model.dirname(entry.path) })
    if (!entry.isDir) {
      place.push({ label: "Size", value: Model.formatSize(entry.size) + "  (" + Model.formatExactSize(entry.size) + ")" })
    } else if (!entry.skipUsage) {
      place.push({ label: "Size", value: Model.formatSize(bytes) + "  (" + Model.formatExactSize(bytes) + ")" })
      place.push({ label: "Contains", value: Model.formatCount(files, "file", "files") + ", " + Model.formatCount(dirs, "folder", "folders") })
    }
    if (info && !info.error && info.disk !== undefined && !entry.isDir) {
      place.push({ label: "Size on disk", value: Model.formatSize(info.disk) + "  (" + Model.formatExactSize(info.disk) + ")" })
    }
    groups.push(place)

    var times = [{ label: "Modified", value: Model.formatFullDate(entry.mtime) }]
    if (info && !info.error) {
      if (info.atime) times.push({ label: "Accessed", value: Model.formatFullDate(info.atime) })
      if (info.ctime) times.push({ label: "Changed", value: Model.formatFullDate(info.ctime) })
    }
    groups.push(times)
    return groups
  }

  signal openerChosen(string handler)

  function openerApp() {
    if (openerHandler === "") return null
    return DesktopEntries.byId(openerHandler.replace(/\.desktop$/, ""))
  }

  function appOptions() {
    var out = []
    var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
    for (var i = 0; i < all.length; i++) {
      var app = all[i]
      if (!app || app.noDisplay || !app.id) continue
      out.push({ value: String(app.id) + ".desktop", label: String(app.name || app.id) })
    }
    out.sort(function (a, b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1 })
    return out
  }

  readonly property real tallest: Math.max(generalSection.implicitHeight, permissionsSection.implicitHeight)

  Column {
    id: generalSection
    width: parent.width
    visible: panel.tab === "general"
    spacing: Style.space(10)

    Row {
      width: parent.width
      spacing: Style.space(14)

      Text {
        textFormat: Text.PlainText
        width: Style.space(40)
        height: Style.space(40)
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: panel.entry ? Icons.glyphFor(panel.entry) : ""
        color: panel.entry && panel.entry.isDir ? Color.accent : Util.alpha(panel.fg, 0.8)
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Rectangle {
        width: parent.width - Style.space(54)
        height: Style.spacing.controlHeight
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        radius: Math.min(Style.cornerRadius, Style.space(5))
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(panel.fg, 0.3)

        Text {
          textFormat: Text.PlainText
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          verticalAlignment: Text.AlignVCenter
          text: panel.entry ? (panel.entry.placeLabel || panel.entry.name) : ""
          color: panel.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }
      }
    }

    Repeater {
      model: panel.generalGroups()

      delegate: Column {
        id: group
        required property var modelData
        width: generalSection.width
        spacing: Style.space(6)

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(panel.fg, 0.14)
        }

        Item { width: 1; height: Style.space(2) }

        Repeater {
          model: group.modelData

          delegate: Row {
            id: infoRow
            required property var modelData
            width: group.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              width: panel.labelWidth
              anchors.verticalCenter: parent.verticalCenter
              text: infoRow.modelData.label + ":"
              color: panel.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              visible: !infoRow.modelData.opener
              width: parent.width - panel.labelWidth - Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: infoRow.modelData.value || ""
              color: panel.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }

            Row {
              visible: infoRow.modelData.opener === true
              width: parent.width - panel.labelWidth - Style.space(10)
              spacing: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Image {
                width: Style.space(18)
                height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                visible: status === Image.Ready
                sourceSize: Qt.size(width * 2, height * 2)
                source: panel.openerApp() && panel.openerApp().icon ? Quickshell.iconPath(panel.openerApp().icon, true) : ""
              }

              SearchableDropdown {
                id: changeApp
                objectName: "changeOpener"
                width: parent.width - Style.space(26)
                anchors.verticalCenter: parent.verticalCenter
                showLabel: false
                triggerLabel: "Choose an application"
                placeholderText: "Search applications"
                options: panel.appOptions()
                value: panel.openerHandler
                onChanged: function (v) { panel.openerChosen(v) }
              }
            }
          }
        }

        Item { width: 1; height: Style.space(2) }
      }
    }
  }

  Column {
    id: permissionsSection
    width: parent.width
    visible: panel.tab === "security" && panel.info !== null && !panel.info.error
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(10)
      height: Style.spacing.controlHeight

      Text {
        textFormat: Text.PlainText
        width: panel.labelWidth
        anchors.verticalCenter: parent.verticalCenter
        text: "Owner:"
        color: panel.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Dropdown {
        objectName: "ownerDropdown"
        width: parent.width - panel.labelWidth - Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.canChown
        showLabel: false
        options: panel.ownerOptions()
        value: panel.editOwner
        onChanged: function (v) { panel.editOwner = v }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width - panel.labelWidth - Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: !panel.canChown
        text: panel.info ? String(panel.info.owner || "") : ""
        color: panel.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)
      height: Style.spacing.controlHeight

      Text {
        textFormat: Text.PlainText
        width: panel.labelWidth
        anchors.verticalCenter: parent.verticalCenter
        text: "Group:"
        color: panel.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Dropdown {
        objectName: "groupDropdown"
        width: parent.width - panel.labelWidth - Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.canChgrp
        showLabel: false
        options: panel.groupOptions()
        value: panel.editGroup
        onChanged: function (v) { panel.editGroup = v }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width - panel.labelWidth - Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: !panel.canChgrp
        text: panel.info ? String(panel.info.group || "") : ""
        color: panel.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Column {
      id: matrix
      width: parent.width
      spacing: Style.space(4)

      readonly property real cellWidth: (width - panel.labelWidth - Style.space(10)) / 3

      Row {
        width: parent.width
        spacing: Style.space(10)

        Item { width: panel.labelWidth; height: 1 }

        Repeater {
          model: ["Read", "Write", panel.entry && panel.entry.isDir ? "Open" : "Execute"]

          delegate: Text {
            required property string modelData
            textFormat: Text.PlainText
            width: matrix.cellWidth - Style.space(10) * 2 / 3
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            color: panel.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Repeater {
        model: ["Owner", "Group", "Others"]

        delegate: Row {
          id: matrixRow
          required property string modelData
          required property int index
          width: matrix.width
          spacing: Style.space(10)
          height: Style.space(26)

          Text {
            textFormat: Text.PlainText
            width: panel.labelWidth
            anchors.verticalCenter: parent.verticalCenter
                text: matrixRow.modelData
            color: panel.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: 3

            delegate: Item {
              id: cell
              required property int index
              readonly property int bit: panel.bitFor(matrixRow.index, cell.index)
              readonly property bool on: (panel.editBits & bit) !== 0
              readonly property bool changed: ((panel.originalBits & bit) !== 0) !== on
              width: matrix.cellWidth - Style.space(10) * 2 / 3
              height: matrixRow.height

              Rectangle {
                objectName: "permBox"
                anchors.centerIn: parent
                width: Style.space(18)
                height: Style.space(18)
                radius: Math.min(Style.cornerRadius, Style.space(5))
                color: cell.on ? Color.accent : "transparent"
                opacity: panel.canChmod ? 1 : 0.5
                border.width: Math.max(1, Style.space(1))
                border.color: cell.changed ? Color.accent : Util.alpha(panel.fg, 0.4)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: cell.on
                  text: "✓"
                  color: Color.popups.background
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: panel.canChmod
                cursorShape: panel.canChmod ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: panel.toggleBit(matrixRow.index, cell.index)
              }
            }
          }
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        width: panel.labelWidth
        text: "Mode:"
        color: panel.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        objectName: "modeText"
        textFormat: Text.PlainText
        width: parent.width - panel.labelWidth - Style.space(10)
        text: Model.formatOctal(panel.editBits) + "   "
          + Model.formatMode(((panel.info ? Number(panel.info.mode) : 0) & ~511) | panel.editBits)
        color: panel.modeDirty ? Color.accent : panel.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: !panel.canChmod
      text: panel.isLink ? "Open the link target to change its permissions"
        : "Only the owner can change these permissions"
      color: panel.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    Toggle {
      objectName: "recursiveToggle"
      width: parent.width
      visible: panel.canChmod && panel.entry !== null && panel.entry.isDir
      label: "Apply to enclosed items"
      description: "Also change everything inside this folder"
      checked: panel.recursive
      onClicked: panel.recursive = !panel.recursive
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: panel.errorText !== ""
      text: panel.errorText
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    Row {
      width: parent.width
      layoutDirection: Qt.RightToLeft
      spacing: Style.space(8)
      visible: panel.dirty

      Button {
        objectName: "applyPermissions"
        text: panel.busy ? "Applying" : "Apply"
        bordered: true
        onClicked: panel.apply()
      }

      Button {
        text: "Revert"
        bordered: true
        onClicked: panel.resetEdits()
      }
    }
  }

  Item {
    width: 1
    height: Math.max(0, panel.tallest - (panel.tab === "general" ? generalSection.implicitHeight : permissionsSection.implicitHeight))
  }
}
