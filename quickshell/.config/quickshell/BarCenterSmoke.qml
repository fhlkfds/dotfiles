import QtQuick
import Quickshell
import "notifications" as Notifications

// Headless check of the bar's centre. Mounts the real BarCenter between two
// stand-in neighbours: the clock sits at the centre inside a fixed-height
// capsule, and on a crowded bar it shifts just enough to clear them. Then it
// sends fake notifications through the real NotificationService: they open
// cards, and the capsule keeps its size because nothing pops out of the bar.
// Run under a private D-Bus session.
FloatingWindow {
  id: window
  implicitWidth: 1600
  implicitHeight: Theme.barHeight

  property int failures: 0
  property real restCentre: 0
  property real restX: 0
  property real restWidth: 0
  property real restHeight: 0
  readonly property var service: Notifications.NotificationService

  // Only the fields NotificationService.receive reads.
  function fakeNotification(id, summary, body, urgency) {
    return { id: id, tracked: false, appName: "Mail", summary: summary, body: body,
             urgency: urgency, actions: [], hints: ({}), image: "",
             closed: { connect: function() {} } }
  }

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
    id: driver
    interval: 400
    running: true
    property int step: 0
    onTriggered: {
      if (step++ === 0) {
        window.restCentre = window.clockCentre(roomy)
        window.restX = roomy.capsule.x
        window.restWidth = roomy.capsule.width
        window.restHeight = roomy.capsule.height
        check("clock is shown", roomy.clock.visible && roomy.clock.width > 0)
        check("clock sits at the bar centre", Math.abs(window.restCentre - window.width / 2) < 0.5)
        check("capsule wraps the indicators and the clock",
              roomy.capsule.x < roomy.clock.x - 40
              && roomy.capsule.x + roomy.capsule.width > roomy.clock.x + roomy.clock.width)
        check("capsule keeps the island height", roomy.capsule.height === Theme.barIslandHeight)
        check("capsule stays clear of the neighbouring islands", window.clearOf(roomy))
        check("a crowded bar shifts the clock right", window.clockCentre(crowded) > window.width / 2)
        check("the shifted capsule still clears its neighbours", window.clearOf(crowded))

        const cardsBefore = service.popupModel.count
        service.receive(fakeNotification(41, "New mail", "From Ada\nsecond line", 1))
        service.receive(fakeNotification(42, "Battery critical", "", 2))
        check("notifications open cards", service.popupModel.count === cardsBefore + 2)
        driver.restart()
        return
      }
      check("the capsule keeps its size after notifications",
            Math.abs(roomy.capsule.x - window.restX) < 0.5
            && Math.abs(roomy.capsule.width - window.restWidth) < 0.5
            && roomy.capsule.height === window.restHeight)
      check("the clock stays put after notifications",
            roomy.clock.visible && Math.abs(window.clockCentre(roomy) - window.restCentre) < 0.5)
      console.log(window.failures === 0 ? "bar centre smoke: ok"
                                        : "bar centre smoke: " + window.failures + " failed")
      Qt.quit()
    }
  }
}
