import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
  id: panel
  required property var output
  property bool anchorTop: false
  screen: output

  visible: VisualizerState.visible
  implicitHeight: Theme.fs(96)
  color: "transparent"
  anchors {
    top: panel.anchorTop
    bottom: !panel.anchorTop
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: panel.anchorTop
                           ? "quickshell-cava-top" : "quickshell-cava-bottom"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Timer {
    interval: 33
    repeat: true
    running: panel.visible
    triggeredOnStart: true
    onTriggered: canvas.requestPaint()
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      const ctx = getContext("2d")
      const w = width
      const h = height
      const baseline = panel.anchorTop ? 0.5 : h - 1.5
      ctx.clearRect(0, 0, w, h)
      ctx.strokeStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 1)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, baseline)
      ctx.lineTo(w, baseline)
      ctx.stroke()

      if (!CavaState.available || !MediaState.isPlaying || CavaState.levels.length === 0)
        return

      const slot = w / CavaState.levels.length
      const barWidth = Math.max(1, slot * 0.7)
      ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 1)
      for (let i = 0; i < CavaState.levels.length; i++) {
        const barHeight = Math.max(1, CavaState.levels[i] * (h - 4))
        const x = i * slot + (slot - barWidth) / 2
        ctx.fillRect(x, panel.anchorTop ? baseline : baseline - barHeight,
                     barWidth, barHeight)
      }
    }
  }
}
