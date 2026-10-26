import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point. The mic's state and the one shurectl process live in the
// Mv7 singleton (shared by every bar); this draws the icon, a side-view mic
// that is red while muted and hollow while the mic is unplugged, and hosts
// the panel. Middle-click mutes, scrolling changes the headphone mix, right-click opens the shurectl terminal UI.
BarWidget {
  id: root
  moduleName: "joelgaff.shurectl"

  readonly property int wheelStep: settings && settings.wheelStep ? Math.max(1, parseInt(settings.wheelStep, 10) || 5) : 5
  function configure() { Mv7.configure(settings ? settings.shurectl : "", settings ? settings.pollMs : 400) }
  Component.onCompleted: configure()

  // What the panel reads, kept on the widget so Panel.qml needs only `host`.
  readonly property var state: Mv7.state
  readonly property string processError: Mv7.processError
  readonly property bool connected: Mv7.connected
  readonly property bool ready: Mv7.ready
  readonly property var s: Mv7.s
  readonly property bool muted: Mv7.muted
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function set(key, value) { Mv7.set(key, value) }
  function openTui() { Mv7.openTui() }
  function resumeTui() { Mv7.resumeTui() }

  // ---- panel ---------------------------------------------------------------
  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
    if ("host" in t) t.host = root
  }
  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
  function open() { if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); configure() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // ---- icon ----------------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    active: root.muted
    dimmed: !root.ready
    tooltipText: root.opened ? "" : (!root.connected && root.processError !== "" ? root.processError : Model.tooltip(root.state))
    iconComponent: Component {
      // A dynamic mic seen from the side, on a short stand: the MV7+ shape,
      // not the generic mic glyph. Solid when connected, outline when not.
      Canvas {
        id: icon
        readonly property color ink: button.active && button.useActiveColor ? button.activeColor : button.foreground
        readonly property color paper: button.bar ? button.bar.background : Color.background
        readonly property bool outline: !root.connected
        onInkChanged: requestPaint()
        onOutlineChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          var w = width, h = height
          ctx.reset()
          ctx.clearRect(0, 0, w, h)
          ctx.lineCap = "round"
          // body: a capsule, grille end up, tilted like a mic on a desk arm
          ctx.save()
          ctx.translate(w * 0.58, h * 0.42)
          ctx.rotate(-0.55)
          var bw = w * 0.36, bh = h * 0.74, r = bw / 2
          ctx.beginPath()
          ctx.moveTo(-r, -bh / 2 + r)
          ctx.arc(0, -bh / 2 + r, r, Math.PI, 0)
          ctx.lineTo(r, bh / 2 - r)
          ctx.arc(0, bh / 2 - r, r, 0, Math.PI)
          ctx.closePath()
          ctx.strokeStyle = ink
          ctx.fillStyle = ink
          ctx.lineWidth = Math.max(1.2, w / 11)
          if (outline) ctx.stroke(); else ctx.fill()
          // grille: three lines across the head
          ctx.strokeStyle = outline ? ink : paper
          ctx.lineWidth = Math.max(1, w / 14)
          for (var i = 0; i < 3; i++) {
            var y = -bh / 2 + r * 0.8 + i * r * 0.55
            ctx.beginPath(); ctx.moveTo(-r * 0.7, y); ctx.lineTo(r * 0.7, y); ctx.stroke()
          }
          ctx.restore()
          // stand: stem from the tail and a foot
          ctx.strokeStyle = ink
          ctx.lineWidth = Math.max(1.2, w / 11)
          ctx.beginPath()
          ctx.moveTo(w * 0.36, h * 0.68)
          ctx.lineTo(w * 0.28, h * 0.90)
          ctx.moveTo(w * 0.12, h * 0.90)
          ctx.lineTo(w * 0.46, h * 0.90)
          ctx.stroke()
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.set("mute", "toggle")
      else if (b === Qt.RightButton) root.openTui()
      else root.togglePanel()
    }
    onWheelMoved: function(delta) { Mv7.nudgeMicLevel(delta > 0 ? root.wheelStep : -root.wheelStep) }
  }
}
