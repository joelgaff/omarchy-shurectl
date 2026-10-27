pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The one owner of `shurectl --follow`. A bar widget is made once per
// monitor; two of them would each open the mic's HID device and read each
// other's replies. So the process, its last state and the writes live here,
// and every bar and panel reads the same thing. shurectl prints the mic's
// state whenever something changes (its own mute button included) and takes
// KEY=VALUE writes on stdin.
QtObject {
  id: root

  property string shurectl: Quickshell.env("HOME") + "/.local/bin/shurectl"
  property int pollMs: 400

  property var state: null              // last JSON line from shurectl
  property string processError: ""       // why shurectl itself isn't running
  readonly property bool connected: state !== null && state.connected === true
  readonly property var s: connected && state.state ? state.state : ({})
  readonly property bool muted: connected && s.muted === true

  // Called by each widget with its settings; the first call starts the process,
  // a changed path or interval restarts it.
  function configure(path, ms) {
    var p = String(path || "") !== "" ? String(path) : Quickshell.env("HOME") + "/.local/bin/shurectl"
    var m = Math.max(100, parseInt(ms, 10) || 400)
    var changed = p !== root.shurectl || m !== root.pollMs
    root.shurectl = p
    root.pollMs = m
    if (changed && follow.running) follow.running = false   // onExited restarts it
    else if (!follow.running) follow.running = true
  }

  function set(key, value) {
    if (!follow.running) { follow.running = true; return }
    follow.write(key + "=" + value + "\n")
  }
  function nudgeMicLevel(delta) {
    if (!connected) return
    var v = Math.max(0, Math.min(100, (Number(s.monitor_mix) || 0) + delta))
    set("monitor_mix", v)
  }
  // The TUI in a terminal, for anything the panel doesn't show.
  function openTui() { tui.running = true }

  property Process follow: Process {
    command: [root.shurectl, "--follow", String(root.pollMs)]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line).trim()
        if (t === "") return
        var d = null
        try { d = JSON.parse(t) } catch (e) { return }
        root.state = d
        root.processError = ""
      }
    }
    stderr: SplitParser {
      onRead: function(line) { var t = String(line).trim(); if (t !== "") root.processError = t }
    }
    onExited: function(code) {
      root.state = null
      if (root.processError.indexOf("unexpected argument") >= 0)
        root.processError = "This shurectl has no --follow: run install.sh from the plugin's folder"
      else if (root.processError === "") root.processError = "shurectl exited (" + code + ")"
      restart.start()
    }
  }
  // A shurectl without --follow (upstream's) exits at once; don't spin on it.
  property Timer restart: Timer { interval: 5000; onTriggered: follow.running = true }

  property Process tui: Process { command: ["xdg-terminal-exec", root.shurectl] }
}
