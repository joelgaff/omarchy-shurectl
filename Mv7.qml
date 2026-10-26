pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The one owner of `shurectl --json --follow`. A bar widget is made once per
// monitor; two of them would each open the mic's HID device and read each
// other's replies. So the process, its last state and the writes live here,
// and every bar and panel reads the same thing. shurectl prints the mic's
// state whenever something changes (its own mute button included) and takes
// KEY=VALUE writes on stdin.
QtObject {
  id: root

  property string shurectl: Quickshell.env("HOME") + "/.local/bin/shurectl"
  property int pollMs: 400
  readonly property string lockPath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("HOME")) + "/.omarchy-shurectl.lock"
  property bool terminalActive: false
  property bool terminalLaunchPending: false

  property var state: null              // last JSON line from shurectl
  property string processError: ""       // why shurectl itself isn't running
  readonly property bool connected: state !== null && state.connected === true
  readonly property bool ready: Model.ready(state)
  readonly property var s: ready && state.state ? state.state : ({})
  readonly property bool muted: ready && s.muted === true

  // Called by each widget with its settings; the first call starts the process,
  // a changed path or interval restarts it.
  function configure(path, ms) {
    var p = String(path || "") !== "" ? String(path) : Quickshell.env("HOME") + "/.local/bin/shurectl"
    var m = Math.max(100, parseInt(ms, 10) || 400)
    var changed = p !== root.shurectl || m !== root.pollMs
    root.shurectl = p
    root.pollMs = m
    if (terminalActive) return
    if (changed && follow.running) follow.running = false   // onExited restarts it
    else if (!follow.running) follow.running = true
  }

  function set(key, value) {
    if (terminalActive || !Model.canSet(state, key)) return
    if (!follow.running) { follow.running = true; return }
    follow.write(key + "=" + value + "\n")
  }
  function nudgeMicLevel(delta) {
    if (!ready) return
    var v = Math.max(0, Math.min(100, (Number(s.monitor_mix) || 0) + delta))
    set("monitor_mix", v)
  }
  // The TUI in a terminal, for anything the panel doesn't show.
  function openTui() {
    if (terminalActive || tui.running) return
    terminalActive = true
    terminalLaunchPending = true
    restart.stop()
    state = null
    processError = "Settings paused while shurectl is open in the terminal"
    if (follow.running) follow.running = false
    else launchTui()
  }
  function launchTui() {
    if (!terminalActive || !terminalLaunchPending) return
    terminalLaunchPending = false
    tui.running = true
  }
  function resumeTui() {
    if (!terminalActive) return
    terminalActive = false
    terminalLaunchPending = false
    processError = ""
    if (!follow.running) follow.running = true
  }

  property Process follow: Process {
    // Keep the lock in shurectl itself: --no-fork makes stopping this Process
    // stop the device owner, and locks survive a shell/plugin reload.
    command: ["flock", "--nonblock", "--no-fork", "--conflict-exit-code", "75", root.lockPath, root.shurectl, "--json", "--follow", String(root.pollMs)]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (root.terminalActive) return
        var t = String(line).trim()
        if (t === "") return
        var d = null
        try { d = JSON.parse(t) } catch (e) { return }
        root.state = d
        root.processError = ""
      }
    }
    stderr: SplitParser {
      onRead: function(line) { if (root.terminalActive) return; var t = String(line).trim(); if (t !== "") root.processError = t }
    }
    onExited: function(code) {
      root.state = null
      if (root.terminalActive) { root.launchTui(); return }
      if (code === 75) root.processError = "Settings paused: another shurectl panel or terminal owns the microphone"
      if (root.processError === "") root.processError = "shurectl exited (" + code + ")"
      restart.start()
    }
  }
  // An old shurectl without --json exits at once; don't spin on it.
  property Timer restart: Timer { interval: 5000; onTriggered: if (!root.terminalActive) follow.running = true }

  property Process tui: Process {
    // The launcher may exit before the terminal command. The child shell owns
    // completion and passes the binary path as an argument, never shell code.
    command: ["xdg-terminal-exec", "sh", "-c",
      "trap 'omarchy-shell joelgaff.shurectl resumeTui' EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; flock --nonblock --no-fork --conflict-exit-code 75 \"$2\" \"$1\"",
      "shurectl-tui", root.shurectl, root.lockPath]
    onExited: function(code) { if (code !== 0) root.resumeTui() }
  }
}
