.pragma library

// Pure helpers for the Shure MV7+ plugin: the option lists shurectl's
// `--set` takes (and `--state` reports), value labels, meter maths, and the
// bar tooltip. No Qt objects in here so it can be unit-tested with any JS.

var OPTIONS = {
  mode: [{ value: "auto", label: "Auto Level" }, { value: "manual", label: "Manual" }],
  auto_position: [{ value: "near", label: "Near" }, { value: "far", label: "Far" }],
  auto_tone: [{ value: "dark", label: "Dark" }, { value: "natural", label: "Natural" }, { value: "bright", label: "Bright" }],
  auto_gain: [{ value: "quiet", label: "Quiet" }, { value: "normal", label: "Normal" }, { value: "loud", label: "Loud" }],
  hpf: [{ value: "off", label: "Off" }, { value: "75", label: "75 Hz" }, { value: "150", label: "150 Hz" }],
  compressor: [{ value: "off", label: "Off" }, { value: "light", label: "Light" }, { value: "medium", label: "Medium" }, { value: "heavy", label: "Heavy" }],
  reverb_type: [{ value: "plate", label: "Plate" }, { value: "hall", label: "Hall" }, { value: "studio", label: "Studio" }],
  led_behavior: [{ value: "live", label: "Live" }, { value: "pulsing", label: "Pulsing" }, { value: "solid", label: "Solid" }],
  led_brightness: [{ value: "low", label: "Low" }, { value: "med", label: "Med" }, { value: "high", label: "High" }, { value: "max", label: "Max" }],
  led_live_theme: [{ value: "default", label: "Default" }, { value: "seaside", label: "Seaside" }, { value: "space", label: "Space" }, { value: "fruity", label: "Fruity" }, { value: "custom", label: "Custom" }],
  led_solid_theme: [{ value: "shure", label: "Shure green" }, { value: "custom", label: "Custom" }],
  led_pulsing_theme: [{ value: "shure", label: "Shure green" }, { value: "custom", label: "Custom" }]
}

// Which theme key and which custom colour keys go with an LED behaviour.
function ledTheme(behavior) {
  switch (String(behavior)) {
    case "solid": return { key: "led_solid_theme", colors: [["led_solid_rgb", "Colour"]] }
    case "pulsing": return { key: "led_pulsing_theme", colors: [["led_pulsing_rgb", "Colour"]] }
    default: return { key: "led_live_theme", colors: [["led_live_edge_rgb", "Edge"], ["led_live_middle_rgb", "Middle"], ["led_live_interior_rgb", "Interior"]] }
  }
}

function toneLabel(tone) {
  var t = Number(tone) || 0
  if (t < 0) return "Dark " + (-t * 10) + "%"
  if (t > 0) return "Bright " + (t * 10) + "%"
  return "Natural"
}

function gainLabel(db) { return (Math.round(Number(db) || 0)) + " dB" }
function percentLabel(v) { return (Math.round(Number(v) || 0)) + "%" }

function isHex(s) { return /^#[0-9a-fA-F]{6}$/.test(String(s || "")) }

// Linear peak (0..1) to dBFS, and to a 0..1 meter position over -60..0 dB.
function peakDb(peak) {
  var v = Number(peak) || 0
  return v > 0 ? 20 * Math.log(v) / Math.LN10 : -99
}
function meterPosition(peak) {
  var db = peakDb(peak)
  return Math.max(0, Math.min(1, (db + 60) / 60))
}
function dbLabel(peak) {
  var db = peakDb(peak)
  return db <= -90 ? "−∞" : (db > -0.5 ? "0" : Math.round(db).toString()) + " dB"
}

// One line for the bar icon's tooltip.
function tooltip(state) {
  if (!state) return "Shure MV7+: shurectl isn't running"
  if (state.connected !== true) return "Shure MV7+ not plugged in"
  var s = state.state || {}
  var parts = ["Shure MV7+"]
  parts.push(s.muted ? "MUTED" : "live")
  parts.push(s.mode === "auto" ? "Auto Level" : gainLabel(s.gain_db))
  parts.push("you " + percentLabel(s.monitor_mix) + ", computer " + percentLabel(s.playback_mix))
  return parts.join(" · ") + "\nClick: settings · middle: mute · scroll: how loud you hear yourself"
}

// A status line for the panel footer: the device's last word, or "".
function statusLine(state) {
  if (!state) return "Starting shurectl…"
  if (state.connected !== true) return String(state.status || "Not connected")
  var msg = String(state.status || "")
  return /state loaded/.test(msg) ? "" : msg
}
