import QtQuick

// Squiggly playback timeline: a sine wave up to the playhead, a flat track
// after it. Click or drag to seek.
//
// The wave is painted once into a canvas one wavelength wider than the bar,
// and "moves" by sliding that canvas inside a clip. Animating it is a
// translation, not a repaint, so a playing timeline costs no Canvas work.
Item {
  id: root
  property real value: 0           // 0..1
  property bool animating: false   // only while playing *and* on screen
  property bool seekable: true
  property color color: Theme.accent
  property color trackColor: Theme.withAlpha(Theme.foreground, 0.18)
  property real amplitude: Theme.fs(4)
  property real wavelength: Theme.fs(22)
  property real lineWidth: Theme.fs(3)
  readonly property bool dragging: area.pressed
  signal moved(real fraction)

  implicitHeight: Theme.fs(18)
  readonly property real playhead: Math.max(0, Math.min(1, value)) * width

  Rectangle {
    x: root.playhead
    width: Math.max(0, root.width - root.playhead)
    height: Math.max(1, root.lineWidth - 1)
    radius: height / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.trackColor
  }

  Item {
    width: root.playhead
    height: parent.height
    clip: true

    Canvas {
      id: wave
      width: root.width + root.wavelength
      height: root.height
      property color stroke: root.color
      onStrokeChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.strokeStyle = stroke
        ctx.lineWidth = root.lineWidth
        ctx.lineCap = "round"
        ctx.beginPath()
        const mid = height / 2
        for (var x = 0; x <= width; x += 2) {
          const y = mid + Math.sin(x / root.wavelength * Math.PI * 2) * root.amplitude
          if (x === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()
      }

      NumberAnimation on x {
        from: 0
        to: -root.wavelength
        duration: 1200
        loops: Animation.Infinite
        running: root.animating
      }
    }
  }

  // Playhead tick.
  Rectangle {
    x: root.playhead - width / 2
    width: Theme.fs(3)
    height: root.amplitude * 2 + Theme.fs(8)
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.color
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.seekable
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / width)))
    onPositionChanged: mouse => {
      if (pressed)
        root.moved(Math.max(0, Math.min(1, mouse.x / width)))
    }
  }
}
