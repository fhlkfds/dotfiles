import QtQuick
import Quickshell
import "notifications" as Notifications

// Headless check of the centre island. Mounts the real BarCenter between two
// stand-in neighbours, feeds IslandState a fake player and fake notifications
// through the real NotificationService, and measures the clock and capsule
// before, during and after a glance. Run under a private D-Bus session.
FloatingWindow {
  id: window
  implicitWidth: 1600
  implicitHeight: Theme.barHeight

  property int failures: 0
  property int step: 0
  property real restCentre: 0
  property real restWidth: 0
  property int cardsBefore: 0
  readonly property var service: Notifications.NotificationService

  QtObject {
    id: fakeMedia
    property bool hasTrack: false
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackKey: ""
  }

  // Only the fields NotificationService.receive reads.
  function fakeNotification(id, summary, body, urgency) {
    return { id: id, tracked: false, appName: "Mail", summary: summary, body: body,
             urgency: urgency, actions: [], hints: ({}), image: "",
             closed: { connect: function() {} } }
  }

  BarCenter {
    id: center
    anchors.fill: parent
    screenName: "fixture"
    leftEdge: 200
    rightEdge: 1400
    Rectangle { width: 40; height: 20; color: Theme.accent }
  }

  IslandPanelContent {
    id: panelContent
    width: 300
    media: QtObject { property bool hasTrack: true; property string trackTitle: "Song"; property string trackArtist: "Band" }
    lyricLine: "a sung line"
    recent: [{ glyph: "n", title: "One", body: "" }, { glyph: "n", title: "Two", body: "detail" }]
  }

  function check(name, ok) {
    if (ok) console.log("ok   " + name)
    else { console.log("FAIL " + name); window.failures++ }
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (let i = 0; i < item.children.length; i++) {
      const match = find(item.children[i], name)
      if (match) return match
    }
    return null
  }
  function count(item, name) {
    let n = item.objectName === name && item.visible ? 1 : 0
    for (let i = 0; i < item.children.length; i++) n += count(item.children[i], name)
    return n
  }
  function clockCentre() { return center.clock.x + center.clock.width / 2 }
  function capsule() { return center.capsule }
  function settle() { return IslandState.animationMs + 250 }

  Component.onCompleted: IslandState.media = fakeMedia

  Timer {
    id: driver
    interval: 400
    running: true
    onTriggered: {
      const gap = Theme.barIslandGap
      switch (window.step++) {
      case 0:
        window.restCentre = window.clockCentre()
        window.restWidth = window.capsule().width
        check("collapsed island shows the clock", center.clock.visible && IslandState.current === null)
        check("resting capsule wraps the clock", window.capsule().x < center.clock.x
              && window.capsule().x + window.capsule().width > center.clock.x + center.clock.width)
        fakeMedia.trackTitle = "A Long Song Title That Needs Room"
        fakeMedia.trackArtist = "Some Band"
        fakeMedia.hasTrack = true
        fakeMedia.trackKey = "Some Band|A Long Song Title"
        check("a track change becomes a media glance", IslandState.current
              && IslandState.current.kind === "media"
              && IslandState.current.title === "A Long Song Title That Needs Room")
        driver.interval = window.settle()
        driver.restart()
        break
      case 1:
        check("clock centre does not drift during a glance",
              Math.abs(window.clockCentre() - window.restCentre) < 0.5)
        check("capsule grows for the glance", window.capsule().width > window.restWidth)
        check("capsule grows about the clock centre", Math.abs(
              window.capsule().x + window.capsule().width / 2 - window.restCentre) < 1)
        check("capsule stays clear of the neighbouring islands",
              window.capsule().x >= center.leftEdge + gap - 0.5
              && window.capsule().x + window.capsule().width <= center.rightEdge - gap + 0.5)
        check("capsule swells in height", window.capsule().height > Theme.barIslandHeight)
        check("glance replaces the clock", find(center, "islandGlance").visible && !center.clock.visible)

        window.cardsBefore = service.popupModel.count
        service.receive(fakeNotification(41, "New mail", "From Ada\nsecond line", 1))
        check("a plain notification does not open a card", service.popupModel.count === window.cardsBefore)
        check("a plain notification queues behind the track glance",
              IslandState.current.kind === "media" && IslandState.queue.pending.length === 1
              && IslandState.queue.pending[0].title === "New mail"
              && IslandState.queue.pending[0].body === "From Ada")
        check("a plain notification is listed for the expanded island",
              IslandState.recent.length === 1 && IslandState.recent[0].title === "New mail")
        service.receive(fakeNotification(42, "Battery critical", "", 2))
        check("a critical notification keeps its card", service.popupModel.count === window.cardsBefore + 1)
        check("a critical notification is not a glance", IslandState.queue.pending.length === 1)

        IslandState.hover("fixture", true)
        check("hovering a glance expands it on that screen", IslandState.expandedScreen === "fixture")
        const paused = IslandState.holdRemaining
        check("hovering pauses the hold with the elapsed time taken off",
              paused > 0 && paused < IslandState.kinds.media.holdMs)
        check("the expanded island keeps the lyric clock running", MediaState.timelineShown)
        IslandState.collapse()
        check("collapse folds the expansion", IslandState.expandedScreen === "")
        check("leaving resumes the hold instead of restarting it",
              IslandState.holdRemaining === paused)

        IslandState.advance()
        check("the queued notification shows next", IslandState.current.title === "New mail")
        check("a notification glance carries the screen it arrived on",
              IslandState.current.screen === service.focusedScreenName())
        IslandState.showNotification({ app: "Mail", summary: "Elsewhere", body: "", image: "",
                                       screenName: "other-monitor" })
        check("a notification glance for another screen leaves this clock alone",
              IslandState.current.title === "Elsewhere" && !center.glancing)
        IslandState.showNotification({ app: "Mail", summary: "Here", body: "", image: "",
                                       screenName: "fixture" })
        check("a notification glance for this screen shows here", center.glancing)
        IslandState.advance()
        check("an empty queue folds back to the clock", IslandState.current === null)
        driver.interval = window.settle()
        driver.restart()
        break
      case 2:
        check("capsule folds back to its resting width",
              Math.abs(window.capsule().width - window.restWidth) < 0.5)
        check("clock centre is unchanged after the fold",
              Math.abs(window.clockCentre() - window.restCentre) < 0.5)
        check("clock is back", center.clock.visible)
        check("expanded surface lists now playing with the lyric line",
              find(panelContent, "islandNowPlaying").visible
              && find(panelContent, "islandLyric").text === "a sung line")
        check("expanded surface lists recent notifications", count(panelContent, "islandRecent") === 2)
        console.log(window.failures === 0 ? "island smoke: ok" : "island smoke: " + window.failures + " failed")
        Qt.quit()
      }
    }
  }
}
