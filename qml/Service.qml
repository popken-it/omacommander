// The only process this plugin owns: backend/filesd.py, one JSON object per
// line. The overlay paints; the backend lists, searches and mutates files.
// A mutation runs on one worker thread in the backend so the UI can keep
// painting and cancel it.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginDir: {
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    var here = Qt.resolvedUrl(".").toString()
    if (here.indexOf("file://") === 0) here = here.substring(7)
    return here.replace(/\/$/, "").replace(/\/qml$/, "")
  }
  readonly property string cli: pluginDir + "/backend/filesd.py"
  readonly property string trashPath: ":trash:"

  property bool ready: false
  property string home: ""
  property var places: []
  property var mounts: []
  property int seq: 0
  property var queue: []

  signal placesReady(var data)
  signal listing(var data)
  signal searchFinished(var data)
  signal jobEvent(var data)
  signal conflictAsked(var data)
  signal propsReady(var data)
  signal fileReady(var data)
  signal backendError(var data)
  signal backendFailed(string message)

  function ensureRunning() {
    if (!backend.running) backend.running = true
  }

  function request(op, fields) {
    seq += 1
    var message = fields || ({})
    message.op = op
    message.id = seq
    if (backend.running && ready) backend.write(JSON.stringify(message) + "\n")
    else queue.push(message)
    ensureRunning()
    return seq
  }

  function send(message) {
    if (!backend.running || !ready) return
    backend.write(JSON.stringify(message) + "\n")
  }

  function flush() {
    while (queue.length > 0) {
      var message = queue.shift()
      backend.write(JSON.stringify(message) + "\n")
    }
  }

  function open(payloadJson) {
    root.opened = true
    ensureRunning()
  }

  function close() {
    root.opened = false
  }

  function ingest(line) {
    var text = String(line || "").trim()
    if (text === "") return
    var event
    try {
      event = JSON.parse(text)
    } catch (error) {
      return
    }
    if (!event || typeof event !== "object") return

    switch (String(event.event)) {
    case "ready":
      root.ready = true
      root.home = String(event.home || root.home)
      root.flush()
      break
    case "places":
      root.home = String(event.home || root.home)
      root.places = event.places || []
      root.mounts = event.mounts || []
      root.placesReady(event)
      break
    case "listing":
      root.listing(event)
      break
    case "search":
      root.searchFinished(event)
      break
    case "job":
      root.jobEvent(event)
      break
    case "conflict":
      root.conflictAsked(event)
      break
    case "props":
      root.propsReady(event)
      break
    case "file":
      root.fileReady(event)
      break
    case "error":
      root.backendError(event)
      break
    }
  }

  Process {
    id: backend
    running: false
    command: ["python3", root.cli]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("[files]", line) }
    }
    onExited: {
      root.ready = false
      root.queue = []
      root.backendFailed("Files backend stopped")
      if (root.opened) reviveTimer.restart()
    }
  }

  // A crash should not leave a dead file manager behind, but do not spin.
  Timer {
    id: reviveTimer
    interval: 1500
    onTriggered: if (root.opened && !backend.running) backend.running = true
  }
}
