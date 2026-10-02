import QtQuick

DropArea {
  id: area

  property string target: ""

  signal filesDropped(var urls, string target, var position)

  function urlsOf(ev) {
    var out = []
    var list = ev.urls || []
    for (var i = 0; i < list.length; i++) out.push(String(list[i]))
    if (out.length === 0 && typeof ev.getDataAsString === "function") {
      var raw = String(ev.getDataAsString("text/uri-list") || "")
      var lines = raw.split(/\r?\n/)
      for (var j = 0; j < lines.length; j++) {
        var line = lines[j].trim()
        if (line && line.charAt(0) !== "#") out.push(line)
      }
    }
    return out
  }

  function blocked(urls) {
    if (area.target === "") return true
    if (area.target === "trash:") return false
    for (var i = 0; i < urls.length; i++) {
      try {
        if (decodeURIComponent(String(urls[i]).replace(/^file:\/\//, "")) === area.target) return true
      } catch (e) { return true }
    }
    return false
  }

  onEntered: function (drag) {
    if (!drag.hasUrls || blocked(urlsOf(drag))) {
      drag.accepted = false
      return
    }
    drag.accept(Qt.CopyAction)
  }

  onDropped: function (drop) {
    var urls = urlsOf(drop)
    if (urls.length === 0 || blocked(urls)) return
    drop.accept(Qt.CopyAction)
    area.filesDropped(urls, area.target, area.mapToGlobal(drop.x, drop.y))
  }
}
