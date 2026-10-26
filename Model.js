.pragma library

// Pure helpers for the Shure MV7 and MV7+ plugin: the option lists shurectl's
// `--set` takes (and `--json` reports), value labels, meter maths, and the
// bar tooltip. No Qt objects in here so it can be unit-tested with any JS.

var OPTIONS = {
  mode: [{ value: "auto", label: "Auto Level" }, { value: "manual", label: "Manual" }],
  auto_position: [{ value: "near", label: "Near" }, { value: "far", label: "Far" }],
  auto_tone: [{ value: "dark", label: "Dark" }, { value: "natural", label: "Natural" }, { value: "bright", label: "Bright" }],
  auto_gain: [{ value: "quiet", label: "Quiet" }, { value: "normal", label: "Normal" }, { value: "loud", label: "Loud" }],
  eq_preset: [{ value: "flat", label: "Flat" }, { value: "high_pass", label: "High-pass" }, { value: "presence_boost", label: "Presence" }, { value: "high_pass_presence_boost", label: "Both" }],
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

function gainLabel(db) { return (Math.round((Number(db) || 0) * 10) / 10) + " dB" }
function snap(value, minimum, maximum, step) {
  return Math.max(minimum, Math.min(maximum, minimum + Math.round((value - minimum) / step) * step))
}
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

function modelLabel(state) {
  return state && state.model ? String(state.model) : "Shure microphone"
}

function ready(state) {
  if (!state || state.connected !== true || !state.state) return false
  if (state.model !== "Shure MV7" && state.model !== "Shure MV7+") return false
  // New shurectl distinguishes unread defaults from a failed command. Older
  // versions only expose error, so treat any error as unsafe to write.
  return state.state_ready === true || (state.state_ready === undefined && state.error === false)
}

function capabilities(state) {
  var f = state && state.features ? state.features : {}
  var mv7 = !!state && state.model === "Shure MV7"
  var plus = !!state && state.model === "Shure MV7+"
  return {
    mv7: mv7, plus: plus,
    playback: plus && f.playback_mix === true,
    gainLock: plus && f.gain_lock === true,
    hpf: plus && f.hpf === true,
    reverb: plus && f.reverb === true,
    led: plus && f.led === true,
    liveMeter: mv7 && f.led_live_meter === true,
    nightMode: mv7 && f.led_night_mode === true,
    rename: plus && f.device_rename === true,
    factoryReset: (mv7 || plus) && f.factory_reset === true,
    gainStep: Number(f.gain_step_db) || (mv7 ? 1.5 : 1),
    gainMax: Number(f.gain_max_db) || 36
  }
}

function canSet(state, key) {
  if (key === "refresh") return !!state && state.connected === true
  if (!ready(state)) return false
  var c = capabilities(state)
  var s = state.state
  if (["mute", "mode", "monitor_mix", "preset_save", "preset_load", "preset_delete", "preset_name"].indexOf(key) !== -1) return true
  if (key === "gain") return s.mode === "manual" && (!c.gainLock || s.gain_lock !== true)
  if (key === "lock") return c.mv7
  if (key === "auto_position" || key === "auto_tone") return c.mv7 && s.mode === "auto"
  if (key === "eq_preset") return c.mv7 && s.mode === "manual"
  if (key === "compressor") return c.plus || (c.mv7 && s.mode === "manual")
  if (key === "playback_mix") return c.playback
  if (key === "gain_lock") return c.gainLock
  if (key === "hpf") return c.hpf
  if (key === "device_name") return c.rename
  if (key === "factory_reset") return c.factoryReset
  if (key === "led_live_meter") return c.liveMeter
  if (key === "led_night_mode") return c.nightMode
  if (key.indexOf("reverb_") === 0) return c.reverb
  if (key.indexOf("led_") === 0) return c.led
  if (key === "mute_button_disabled") return c.plus && typeof s.mute_button_disabled === "boolean"
  return c.plus && ["limiter", "denoiser", "popper_stopper", "tone"].indexOf(key) !== -1
}

// One line for the bar icon's tooltip.
function tooltip(state) {
  var label = modelLabel(state)
  if (!state) return label + ": shurectl isn't running"
  if (state.connected !== true) return label + " not plugged in"
  if (!ready(state)) return label + ": " + statusLine(state)
  var s = state.state
  var parts = [label]
  parts.push(s.muted ? "MUTED" : "live")
  parts.push(s.mode === "auto" ? "Auto Level" : gainLabel(s.gain_db))
  parts.push(capabilities(state).playback
    ? "you " + percentLabel(s.monitor_mix) + ", computer " + percentLabel(s.playback_mix)
    : "monitor mix " + percentLabel(s.monitor_mix))
  return parts.join(" · ") + "\nClick: settings · middle: mute · scroll: "
    + (capabilities(state).mv7 ? "monitor mix (mic ↔ computer)" : "how loud you hear yourself")
}

function statusLine(state) {
  if (!state) return "Starting shurectl…"
  if (state.connected !== true) return String(state.status || "Not connected")
  if (state.model !== "Shure MV7" && state.model !== "Shure MV7+") return "This panel supports Shure MV7 and MV7+"
  if (!ready(state)) return String(state.status || "Waiting for device settings")
  var msg = String(state.status || "")
  return /state loaded/.test(msg) ? "" : msg
}
