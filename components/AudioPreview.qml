import QtQuick 6.11
import QtMultimedia
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: audio
  objectName: "audioPreview"

  property var service: null
  property var entry: null
  property bool thumbnails: true
  property real volume: 1
  property bool muted: false
  property bool pendingPlay: false
  property int cleanId: 0
  property string cleanError: ""
  property var tags: ({})
  readonly property bool preparing: cleanId !== 0
  signal volumeMoved(real value)
  signal muteToggled()

  property alias player: player
  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property bool failed: cleanError !== "" || player.error !== MediaPlayer.NoError
    || player.mediaStatus === MediaPlayer.InvalidMedia
  readonly property real shownPosition: seek.dragging ? seek.liveValue : player.position
  readonly property string title: String(tags.title || "")
  readonly property string artist: String(tags.artist || "")
  readonly property string album: String(tags.album || "")
  readonly property bool coverArt: thumbnails && !!entry && !!service && !!service.thumbExts
    && entry.size > 0 && service.thumbExts[entry.ext] === true

  function load() {
    if (cleanId && service) service.cancel(cleanId)
    cleanId = 0
    cleanError = ""
    tags = ({})
    player.stop()
    player.source = ""
    pendingPlay = false
    if (!entry || !service) return
    var wanted = entry.path
    cleanId = service.previewAudio(wanted, function (m) {
      if (!audio.entry || audio.entry.path !== wanted) return
      audio.cleanId = 0
      audio.tags = { title: String(m.title || "").trim(), artist: String(m.artist || "").trim(), album: String(m.album || "").trim() }
      audio.pendingPlay = true
      player.source = Util.fileUrl(String(m.path || ""))
    }, function (m) {
      if (!audio.entry || audio.entry.path !== wanted) return
      audio.cleanId = 0
      audio.cleanError = m && m.code === "EUNSUPPORTED" ? "playing audio here needs ffmpeg" : String((m && m.message) || "could not read it")
    })
  }

  function togglePlay() {
    if (failed || !entry) return
    if (playing) player.pause()
    else player.play()
  }

  function seekBy(ms) {
    if (!player.seekable) return
    var next = player.position + ms
    if (player.duration > 0) next = Math.min(player.duration, next)
    player.setPosition(Math.max(0, next))
  }

  onEntryChanged: load()
  Component.onDestruction: {
    if (cleanId && service) service.cancel(cleanId)
    player.stop()
  }

  MediaPlayer {
    id: player
    audioOutput: AudioOutput {
      volume: Model.outputVolume(audio.volume)
      muted: audio.muted
    }
    onMediaStatusChanged: {
      if (mediaStatus !== MediaPlayer.LoadedMedia || !audio.pendingPlay) return
      audio.pendingPlay = false
      play()
    }
  }

  QtObject {
    id: sliderColors
    property color foreground: Color.popups.text
    property color background: Color.popups.background
  }

  TextMetrics {
    id: timeMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    text: Model.formatDuration(player.duration).replace(/[0-9]/g, "0")
  }

  Column {
    id: layout
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(520))
    spacing: Style.space(14)

    Rectangle {
      id: art
      anchors.horizontalCenter: parent.horizontalCenter
      readonly property real room: audio.height - info.height - seekRow.height - controls.height
        - hint.height - layout.spacing * 4
      width: Math.max(Style.space(64), Math.min(Style.space(260), layout.width, room))
      height: width
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.text, 0.06)
      clip: true

      ThumbImage {
        id: cover
        anchors.fill: parent
        service: audio.service
        entry: audio.entry
        generated: audio.coverArt
        requestSize: 512
      }

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: !cover.visible
        text: Icons.glyphForCategory("audio")
        color: Util.alpha(Color.popups.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Math.round(art.height * 0.4)
      }
    }

    Column {
      id: info
      width: parent.width
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: text !== ""
        text: audio.title
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: text !== ""
        text: [audio.artist, audio.album].filter(function (part) { return part !== "" }).join("  ·  ")
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }

    Item {
      id: seekRow
      width: parent.width
      height: seek.implicitHeight
      visible: !audio.failed

      Text {
        id: elapsed
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: timeMetrics.advanceWidth + Style.space(2)
        horizontalAlignment: Text.AlignRight
        text: Model.formatDuration(audio.shownPosition)
        color: Util.alpha(Color.popups.text, 0.6)
        font: timeMetrics.font
      }

      PanelSlider {
        id: seek
        objectName: "audioSeek"
        anchors.left: elapsed.right
        anchors.right: total.left
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        bar: sliderColors
        enabled: player.seekable
        minimum: 0
        maximum: Math.max(1, player.duration)
        step: 5000
        value: player.position
        onReleased: function (v) { player.setPosition(v) }
      }

      Text {
        id: total
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: timeMetrics.advanceWidth + Style.space(2)
        text: Model.formatDuration(player.duration)
        color: Util.alpha(Color.popups.text, 0.6)
        font: timeMetrics.font
      }
    }

    Item {
      id: controls
      width: parent.width
      height: audio.failed ? failure.implicitHeight : buttons.implicitHeight

      Row {
        id: buttons
        anchors.centerIn: parent
        spacing: Style.space(6)
        visible: !audio.failed

        Button {
          iconText: Icons.actionGlyph("seekBack")
          tooltipText: "Back 5 seconds (Shift+Left)"
          enabled: player.seekable
          onClicked: audio.seekBy(-5000)
        }

        Button {
          objectName: "audioPlay"
          bordered: true
          iconText: Icons.actionGlyph(audio.playing ? "pause" : "play")
          tooltipText: audio.playing ? "Pause (K)" : "Play (K)"
          onClicked: audio.togglePlay()
        }

        Button {
          iconText: Icons.actionGlyph("seekForward")
          tooltipText: "Forward 5 seconds (Shift+Right)"
          enabled: player.seekable
          onClicked: audio.seekBy(5000)
        }

        Item { width: Style.space(14); height: 1 }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          iconText: Icons.actionGlyph(audio.muted ? "muted" : "volume")
          tooltipText: audio.muted ? "Unmute (M)" : "Mute (M)"
          onClicked: audio.muteToggled()
        }

        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(96)
          bar: sliderColors
          minimum: 0
          maximum: 1
          step: 0.05
          value: audio.muted ? 0 : audio.volume
          onMoved: function (v) { audio.volumeMoved(v) }
        }
      }

      Text {
        id: failure
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width
        visible: audio.failed
        text: "Can't play this file" + (audio.cleanError !== "" ? ": " + audio.cleanError
          : (player.errorString !== "" ? ": " + player.errorString : ""))
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }
    }

    Text {
      id: hint
      textFormat: Text.PlainText
      width: parent.width
      visible: !audio.failed
      text: audio.preparing ? "Getting the audio ready" : "K play or pause     Shift+Arrows skip 5 seconds     M mute"
      color: Util.alpha(Color.popups.text, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
