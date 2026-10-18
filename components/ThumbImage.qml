import QtQuick 6.11
import qs.Commons

Image {
  id: thumb

  property var service: null
  property var entry: null
  property bool active: true
  property bool generated: false
  property bool failed: false
  property int requestSize: 256

  property string cachedPath: ""
  property var ticket: null
  property bool started: false

  readonly property string bucket: requestSize <= 256 ? "large"
    : (requestSize <= 512 ? "x-large" : "xx-large")
  readonly property string requestKey: active && generated && entry && service
    ? bucket + "|" + entry.mtime + "|" + entry.path : ""

  source: !active || !entry || cachedPath === "" ? "" : Util.fileUrl(cachedPath)
  visible: String(source) !== "" && status === Image.Ready
  fillMode: Image.PreserveAspectFit
  asynchronous: true
  cache: true
  smooth: true
  mipmap: true

  function release() {
    if (ticket && service) service.releaseThumbnail(ticket)
    ticket = null
  }

  function refresh() {
    release()
    cachedPath = ""
    failed = false
    settleTimer.stop()
    if (requestKey === "") return
    if (Date.now() / 1000 - Number(entry.mtime || 0) < 3) {
      settleTimer.start()
      return
    }
    var key = requestKey
    ticket = service.thumbnailFor(entry.path, entry.mtime, bucket, function (path) {
      if (thumb.requestKey !== key) return
      thumb.ticket = null
      thumb.cachedPath = path
      thumb.failed = path === ""
    })
  }

  Timer {
    id: settleTimer
    interval: 3000
    onTriggered: thumb.refresh()
  }

  onRequestKeyChanged: if (started) refresh()
  Component.onCompleted: {
    started = true
    refresh()
  }
  Component.onDestruction: release()
}
