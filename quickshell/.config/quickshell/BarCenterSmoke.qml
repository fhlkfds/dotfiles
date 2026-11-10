import QtQuick
import Quickshell
import "notifications" as Notifications

// Headless check of the bar centre. Mounts the real BarCenter between two
// stand-in neighbours and sends fake notifications through the real
// NotificationService. The capsule wraps the clock, stays clear of the
// neighbours, and keeps its size when notifications arrive: they open cards
// and nothing pops out of the bar. Run under a private D-Bus session.
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
    id: center
    anchors.fill: parent
    leftEdge: 200
    rightEdge: 1400
    Rectangle { width: 40; height: 20; color: Theme.accent }
  }

  function check(name, ok) {
    if (ok) console.log("ok   " + name)
    else { console.log("FAIL " + name); window.failures++ }
  }
  function clockCentre() { return center.clock.x + center.clock.width / 2 }
  function capsule() { return center.capsule }

  Timer {
    id: driver
    interval: 400
    running: true
    property int step: 0
    onTriggered: {
      const gap = Theme.barIslandGap
      if (step++ === 0) {
        window.restCentre = window.clockCentre()
        window.restX = window.capsule().x
        window.restWidth = window.capsule().width
        window.restHeight = window.capsule().height
        check("the clock shows", center.clock.visible && center.clock.width > 0)
        check("the clock sits at the bar centre", Math.abs(window.restCentre - window.width / 2) < 0.5)
        check("the capsule wraps the clock", window.capsule().x < center.clock.x
              && window.capsule().x + window.capsule().width > center.clock.x + center.clock.width)
        check("the capsule wraps the indicator row", window.capsule().x < center.clock.x - 40)
        check("the capsule stays clear of the neighbouring islands",
              window.capsule().x >= center.leftEdge + gap - 0.5
              && window.capsule().x + window.capsule().width <= center.rightEdge - gap + 0.5)
        check("the capsule is island height", window.capsule().height === Theme.barIslandHeight)

        const cardsBefore = service.popupModel.count
        service.receive(fakeNotification(41, "New mail", "From Ada\nsecond line", 1))
        service.receive(fakeNotification(42, "Battery critical", "", 2))
        check("notifications open cards", service.popupModel.count === cardsBefore + 2)
        driver.restart()
        return
      }
      check("the capsule keeps its size after notifications",
            Math.abs(window.capsule().x - window.restX) < 0.5
            && Math.abs(window.capsule().width - window.restWidth) < 0.5
            && window.capsule().height === window.restHeight)
      check("the clock stays put after notifications",
            center.clock.visible && Math.abs(window.clockCentre() - window.restCentre) < 0.5)
      console.log(window.failures === 0 ? "bar centre smoke: ok"
                                        : "bar centre smoke: " + window.failures + " failed")
      Qt.quit()
    }
  }
}
