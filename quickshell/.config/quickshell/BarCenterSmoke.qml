import QtQuick
import Quickshell

// Headless check of the bar's centre. Mounts the real BarCenter between two
// stand-in neighbours: the clock sits at the centre inside a fixed-height
// capsule, and on a crowded bar it shifts just enough to clear them.
FloatingWindow {
  id: window
  implicitWidth: 1600
  implicitHeight: Theme.barHeight

  property int failures: 0

  BarCenter {
    id: roomy
    anchors.fill: parent
    leftEdge: 200
    rightEdge: 1400
    Rectangle { width: 40; height: 20; color: Theme.accent }
  }

  // The left neighbour reaches past the centre's natural left edge.
  BarCenter {
    id: crowded
    anchors.fill: parent
    leftEdge: 700
    rightEdge: 1500
    Rectangle { width: 40; height: 20; color: Theme.accent }
  }

  function check(name, ok) {
    if (ok) console.log("ok   " + name)
    else { console.log("FAIL " + name); window.failures++ }
  }
  function clockCentre(c) { return c.clock.x + c.clock.width / 2 }
  function clearOf(c) {
    const gap = Theme.barIslandGap
    return c.capsule.x >= c.leftEdge + gap - 0.5
           && c.capsule.x + c.capsule.width <= c.rightEdge - gap + 0.5
  }

  Timer {
    interval: 400
    running: true
    onTriggered: {
      check("clock is shown", roomy.clock.visible && roomy.clock.width > 0)
      check("clock sits at the bar centre", Math.abs(window.clockCentre(roomy) - window.width / 2) < 0.5)
      check("capsule wraps the indicators and the clock",
            roomy.capsule.x < roomy.clock.x - 40
            && roomy.capsule.x + roomy.capsule.width > roomy.clock.x + roomy.clock.width)
      check("capsule keeps the island height", roomy.capsule.height === Theme.barIslandHeight)
      check("capsule stays clear of the neighbouring islands", window.clearOf(roomy))
      check("a crowded bar shifts the clock right", window.clockCentre(crowded) > window.width / 2)
      check("the shifted capsule still clears its neighbours", window.clearOf(crowded))
      console.log(window.failures === 0 ? "bar centre smoke: ok"
                                        : "bar centre smoke: " + window.failures + " failed")
      Qt.quit()
    }
  }
}
