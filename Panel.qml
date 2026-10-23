import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Every MV7+ setting shurectl knows, in two columns:
//   left   Mic (mute, Auto Level / gain), Headphones (you / computer),
//          Processing (high-pass, compressor, limiter, denoiser, popper
//          stopper, tone)
//   right  Reverb, LEDs, Presets, Device (name, firmware, factory reset)
// Reads come from the host BarWidget's `shurectl --json --follow`; writes go
// back through host.set(key, value) onto that process's stdin.
Panel {
  id: root
  moduleName: "joelgaff.shurectl"
  ipcTarget: "joelgaff.shurectl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var host: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool connected: host ? host.connected === true : false
  readonly property var st: connected ? host.s : ({})
  readonly property var info: connected && host.state.info ? host.state.info : ({})
  readonly property var features: connected && host.state.features ? host.state.features : ({})
  readonly property var presets: connected && host.state.presets ? host.state.presets : []
  readonly property bool auto: st.mode === "auto"
  readonly property bool muted: st.muted === true
  readonly property string statusText: host && host.processError !== "" && !connected
    ? host.processError : Model.statusLine(host ? host.state : null)
  readonly property bool statusIsError: host && host.state ? host.state.error === true : true

  function set(key, value) { if (host) host.set(key, value) }
  function flag(v) { return v ? "on" : "off" }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.6)
  readonly property color accent: Color.accent
  readonly property color danger: Color.urgent
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.15)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int colW: Style.space(300)

  // ---- Level meter: the MV7+'s PipeWire capture node, read only while open.
  readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var micNode: {
    for (var i = 0; i < allNodes.length; i++) {
      var n = allNodes[i]
      if (n && !n.isStream && !n.isSink && String(n.name).indexOf("Shure_Inc_Shure_MV7") !== -1) return n
    }
    return null
  }
  PwObjectTracker { objects: root.micNode ? [root.micNode] : [] }
  PwNodePeakMonitor {
    id: peaks
    node: root.micNode
    enabled: root.opened && root.micNode !== null
  }
  property real held: 0
  Timer {
    interval: 60; repeat: true; running: peaks.enabled
    onTriggered: root.held = Math.max(peaks.peak, root.held * 0.9)
  }

  // ---- Two-click guard for factory reset.
  property bool resetArmed: false
  Timer { id: disarm; interval: 5000; onTriggered: root.resetArmed = false }
  function factoryReset() {
    if (!resetArmed) { resetArmed = true; disarm.restart(); return }
    resetArmed = false
    set("factory_reset", "yes")
  }

  // ---- Inline rename of a preset slot (1-based slot number, 0 = none).
  property int renaming: 0

  // ---- Open/close lifecycle (same shape as the other panels).
  function open() { root.controller.show() }
  function openFromHotkey() { root.controller.show() }
  function close() { root.controller.hide(); root.renaming = 0; root.resetArmed = false }
  function toggle() { if (root.opened) root.close(); else root.openFromHotkey() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function mute(): void { root.set("mute", "toggle") }
    function preset(slot: int): void { root.set("preset_load", slot) }
  }

  // ---- Building blocks -----------------------------------------------------
  component Label: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    color: root.foreground
    elide: Text.ElideRight
  }
  component Dim: Label { color: root.dim }

  component Section: Column {
    property string title: ""
    default property alias content: body.data
    width: parent.width
    spacing: Style.spacing.sm
    PanelSectionHeader { text: parent.title; foreground: root.foreground; fontFamily: root.fontFamily }
    Column { id: body; width: parent.width; spacing: Style.spacing.md }
  }

  component SliderRow: Column {
    id: sr
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool active: true
    property var format: function(v) { return Math.round(v) }
    signal commit(real v)
    width: parent.width
    spacing: 0
    opacity: active ? 1 : 0.45
    Item {
      width: parent.width; height: Style.font.bodySmall + Style.spacing.xs
      Label { text: sr.label; anchors.left: parent.left; anchors.right: val.left; anchors.rightMargin: 8 }
      Dim { id: val; anchors.right: parent.right; text: sr.format(slider.dragging ? slider.liveValue : sr.value) }
    }
    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sr.minimum; maximum: sr.maximum; step: sr.step
      integer: true
      value: sr.value
      enabled: sr.active
      onReleased: function(v) { sr.commit(v) }
    }
  }

  component Choice: Column {
    id: ch
    property string label: ""
    property string key: ""
    property var options: []
    property string current: ""
    property bool active: true
    width: parent.width
    spacing: Style.spacing.xs
    opacity: active ? 1 : 0.45
    Label { text: ch.label; visible: ch.label !== "" }
    ButtonGroup {
      width: parent.width
      options: ch.options
      value: ch.current
      enabled: ch.active
      foreground: root.foreground
      background: bar ? bar.background : Color.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onChanged: function(v) { if (v !== ch.current) root.set(ch.key, v) }
    }
  }

  component Switch: Toggle {
    property string key: ""
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    titleSize: Style.font.bodySmall
    onClicked: root.set(key, root.flag(!checked))
  }

  component Action: Button {
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
  }

  // A hex colour with a swatch; Enter sends it.
  component ColorField: Row {
    id: cf
    property string label: ""
    property string key: ""
    property string current: "#000000"
    width: parent.width
    spacing: Style.spacing.md
    Dim { text: cf.label; width: Style.space(60); anchors.verticalCenter: parent.verticalCenter }
    Rectangle {
      width: Style.spacing.controlHeight - 6; height: width; radius: 4
      anchors.verticalCenter: parent.verticalCenter
      color: Model.isHex(field.text) ? field.text : cf.current
      border.color: root.track; border.width: 1
    }
    TextField {
      id: field
      width: parent.width - Style.space(60) - (Style.spacing.controlHeight - 6) - parent.spacing * 2
      text: cf.current
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onAccepted: if (Model.isHex(text)) root.set(cf.key, text)
      // The device's value wins once a write came back.
      Connections { target: cf; function onCurrentChanged() { if (!field.activeFocus) field.text = cf.current } }
    }
  }

  // ---- The panel -------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(column.implicitWidth + panel.padding * 2 + Style.space(8))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.renaming !== 0 || nameField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "m") root.set("mute", "toggle")
        else if (k === "r") root.set("refresh", "1")
        else if (k >= "1" && k <= "4") root.set("preset_load", k)
      }
    }

    Column {
      id: column
      spacing: Style.spacing.lg
      width: root.colW * 2 + Style.spacing.huge

      // Header: name, firmware, mute, meter.
      Row {
        width: parent.width
        spacing: Style.spacing.lg
        Column {
          width: parent.width - muteBtn.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: root.connected ? (String(root.info.device_name || "") || "Shure MV7+") : "Shure MV7+"
            textFormat: Text.PlainText
            font.family: root.fontFamily; font.bold: true; font.pixelSize: Style.font.title
            color: root.foreground
          }
          Dim {
            text: root.connected
              ? "firmware " + root.info.firmware_version + " · S/N " + root.info.factory_serial
              : (root.statusText || "Not connected")
            width: parent.width
          }
        }
        Action {
          id: muteBtn
          anchors.verticalCenter: parent.verticalCenter
          text: root.muted ? "Muted" : "Live"
          iconText: root.muted ? "󰍭" : "󰍬"
          active: root.muted
          enabled: root.connected
          tooltipText: "Mute the mic (M, or middle-click the bar icon)"
          onClicked: root.set("mute", "toggle")
        }
      }

      // Meter: what the MV7+ is picking up right now.
      Item {
        width: parent.width
        height: Style.space(14)
        visible: root.connected
        Rectangle {
          anchors.fill: parent; radius: 3; color: root.track
          Rectangle {
            width: parent.width * Model.meterPosition(root.held)
            height: parent.height; radius: 3
            color: root.held >= 0.98 ? root.danger : (Model.peakDb(root.held) > -12 ? root.accent : root.foreground)
            Behavior on width { NumberAnimation { duration: 50 } }
          }
        }
        Dim {
          anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
          text: root.micNode ? Model.dbLabel(root.held) : "no PipeWire input"
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.3)
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.huge
        enabled: root.connected
        opacity: root.connected ? 1 : 0.5

        // ---------------- Left column ----------------
        Column {
          width: root.colW
          spacing: Style.spacing.lg

          Section {
            title: "MIC"
            Choice {
              key: "mode"; options: Model.OPTIONS.mode; current: String(root.st.mode || "manual")
            }
            SliderRow {
              label: root.auto ? "Gain (Auto Level is setting it)" : "Gain"
              value: Number(root.st.gain_db) || 0
              minimum: 0; maximum: Number(root.features.gain_max_db) || 36; step: Number(root.features.gain_step_db) || 1
              active: !root.auto && root.st.gain_lock !== true
              format: function(v) { return Model.gainLabel(v) }
              onCommit: function(v) { root.set("gain", v) }
            }
            Switch {
              visible: root.features.gain_lock === true
              key: "gain_lock"; label: "Gain lock"; description: "The mic ignores gain changes"
              checked: root.st.gain_lock === true
            }
            Switch {
              visible: root.st.mute_button_disabled !== null && root.st.mute_button_disabled !== undefined
              key: "mute_button_disabled"; label: "Ignore the touch panel"; description: "So a brush doesn't mute you"
              checked: root.st.mute_button_disabled === true
            }
          }

          Section {
            title: "HEADPHONES (the jack on the mic)"
            SliderRow {
              label: "You"
              value: Number(root.st.monitor_mix) || 0
              format: function(v) { return Model.percentLabel(v) }
              onCommit: function(v) { root.set("monitor_mix", v) }
            }
            SliderRow {
              label: "Computer"
              value: Number(root.st.playback_mix) || 0
              format: function(v) { return Model.percentLabel(v) }
              onCommit: function(v) { root.set("playback_mix", v) }
            }
          }

          Section {
            title: "PROCESSING"
            Choice { label: "High-pass"; key: "hpf"; options: Model.OPTIONS.hpf; current: String(root.st.hpf || "off") }
            Choice { label: "Compressor"; key: "compressor"; options: Model.OPTIONS.compressor; current: String(root.st.compressor || "off") }
            Switch { key: "limiter"; label: "Limiter"; checked: root.st.limiter === true }
            Switch { key: "denoiser"; label: "Denoiser"; description: "Real-time noise reduction"; checked: root.st.denoiser === true }
            Switch { key: "popper_stopper"; label: "Popper stopper"; description: "Softens P and B pops"; checked: root.st.popper_stopper === true }
            SliderRow {
              label: "Tone"
              value: Number(root.st.tone) || 0
              minimum: -10; maximum: 10; step: 1
              format: function(v) { return Model.toneLabel(v) }
              onCommit: function(v) { root.set("tone", v) }
            }
          }
        }

        // ---------------- Right column ----------------
        Column {
          width: root.colW
          spacing: Style.spacing.lg

          Section {
            title: "REVERB"
            Switch { key: "reverb_output"; label: "On the recording"; checked: root.st.reverb_output === true }
            Switch { key: "reverb_monitoring"; label: "In the headphones"; checked: root.st.reverb_monitoring === true }
            Choice { key: "reverb_type"; options: Model.OPTIONS.reverb_type; current: String(root.st.reverb_type || "plate") }
            SliderRow {
              label: "Intensity"
              value: Number(root.st.reverb_intensity) || 0
              format: function(v) { return Model.percentLabel(v) }
              onCommit: function(v) { root.set("reverb_intensity", v) }
            }
          }

          Section {
            title: "LEDS"
            Choice { key: "led_behavior"; options: Model.OPTIONS.led_behavior; current: String(root.st.led_behavior || "live") }
            Choice { label: "Brightness"; key: "led_brightness"; options: Model.OPTIONS.led_brightness; current: String(root.st.led_brightness || "high") }
            Choice {
              readonly property var theme: Model.ledTheme(root.st.led_behavior)
              label: "Theme"; key: theme.key; options: Model.OPTIONS[theme.key]; current: String(root.st[theme.key] || "")
            }
            Repeater {
              model: String(root.st[Model.ledTheme(root.st.led_behavior).key]) === "custom" ? Model.ledTheme(root.st.led_behavior).colors : []
              ColorField {
                required property var modelData
                label: modelData[1]; key: modelData[0]; current: String(root.st[modelData[0]] || "#000000")
              }
            }
          }

          Section {
            title: "PRESETS (1–4 loads)"
            Repeater {
              model: root.presets
              Row {
                id: slotRow
                required property var modelData
                readonly property int slot: Number(modelData.slot)
                readonly property bool saved: modelData.name !== null && modelData.name !== undefined
                width: parent.width
                spacing: Style.spacing.sm
                Item {
                  width: parent.width - loadBtn.width - saveBtn.width - delBtn.width - parent.spacing * 3
                  height: Style.spacing.controlHeight
                  Label {
                    visible: root.renaming !== slotRow.slot
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    text: slotRow.slot + "  " + (slotRow.saved ? modelData.name : "empty")
                    color: slotRow.saved ? root.foreground : root.dim
                    MouseArea {
                      anchors.fill: parent
                      enabled: slotRow.saved
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { root.renaming = slotRow.slot; renameField.text = modelData.name; renameField.forceActiveFocus() }
                    }
                  }
                  TextField {
                    id: renameField
                    visible: root.renaming === slotRow.slot
                    anchors.fill: parent
                    foreground: root.foreground; accent: root.accent
                    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                    onAccepted: { if (text.trim() !== "") root.set("preset_name", slotRow.slot + ":" + text.trim()); root.renaming = 0 }
                    Keys.onEscapePressed: root.renaming = 0
                  }
                }
                Action { id: loadBtn; text: "Load"; enabled: slotRow.saved; tooltipText: slotRow.saved ? modelData.summary : ""; onClicked: root.set("preset_load", slotRow.slot) }
                Action { id: saveBtn; text: "Save"; tooltipText: "Save the current settings here"; onClicked: root.set("preset_save", slotRow.slot) }
                Action { id: delBtn; iconText: "󰆴"; enabled: slotRow.saved; tooltipText: "Delete"; onClicked: root.set("preset_delete", slotRow.slot) }
              }
            }
          }

          Section {
            title: "DEVICE"
            Row {
              width: parent.width
              spacing: Style.spacing.sm
              TextField {
                id: nameField
                width: parent.width - renameBtn.width - parent.spacing
                text: String(root.info.device_name || "")
                placeholderText: "Device name"
                foreground: root.foreground; accent: root.accent
                font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                onAccepted: if (text.trim() !== "" && text !== root.info.device_name) root.set("device_name", text.trim())
                Connections { target: root; function onInfoChanged() { if (!nameField.activeFocus) nameField.text = String(root.info.device_name || "") } }
              }
              Action { id: renameBtn; text: "Rename"; onClicked: nameField.accepted() }
            }
            Row {
              width: parent.width
              spacing: Style.spacing.sm
              Action { text: "Refresh"; iconText: "󰑐"; onClicked: root.set("refresh", "1") }
              Action { text: "shurectl"; iconText: "󰆍"; tooltipText: "The full terminal UI"; onClicked: if (root.host) root.host.openTui() }
              Action {
                text: root.resetArmed ? "Really reset?" : "Factory reset"
                iconText: "󰜉"
                active: root.resetArmed
                visible: root.features.factory_reset === true
                tooltipText: "Puts every setting back to Shure's defaults (click twice)"
                onClicked: root.factoryReset()
              }
            }
          }
        }
      }

      // Footer: the device's last word.
      Dim {
        width: parent.width
        visible: root.statusText !== ""
        text: root.statusText
        color: root.statusIsError ? root.danger : root.dim
        wrapMode: Text.Wrap
      }
    }
  }
}
