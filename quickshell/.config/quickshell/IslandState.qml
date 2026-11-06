pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "island/IslandLogic.js" as Logic
import "notifications/NotificationLogic.js" as NotificationLogic
import "notifications" as Notifications

// The centre island's glances: a track change or a non-critical notification
// briefly widens the capsule around the clock, then it folds back. Critical
// and actionable notifications stay in NotificationStack. The queue rules live
// in island/IslandLogic.js; this file feeds them events and runs the clock.
Singleton {
  id: root

  property var config: ({})
  readonly property var kinds: Logic.kindTable(config.kinds)
  readonly property int animationMs: Number.isInteger(config.animationMs) ? config.animationMs : 220
  readonly property int glanceMaxWidth: Number.isInteger(config.glanceMaxWidth) ? config.glanceMaxWidth : 420
  readonly property int recentLimit: Number.isInteger(config.recentLimit) ? config.recentLimit : 3

  property var queue: Logic.emptyQueue()
  readonly property var current: queue.current
  // Newest first, notifications only: the expanded surface lists them.
  property var recent: []
  // Hovering a glance expands it on that screen's bar and pauses its hold.
  property string expandedScreen: ""

  // IslandSmoke swaps in a fake with the same properties.
  property var media: MediaState

  readonly property string glyphMusic: String.fromCodePoint(0xf075a) // md-music
  readonly property string glyphBell: String.fromCodePoint(0xf009a)  // md-bell

  function show(glance) { root.queue = Logic.enqueue(root.queue, glance, root.kinds) }
  function advance() { root.queue = Logic.advance(root.queue) }

  function showNotification(entry) {
    const isMedia = NotificationLogic.isMediaNotification(entry.app, entry.image)
    const glance = {
      kind: isMedia ? "media" : "notification",
      glyph: entry.glyph || (isMedia ? root.glyphMusic : root.glyphBell),
      title: entry.summary || entry.app,
      body: String(entry.body || "").split("\n")[0] || entry.app
    }
    root.show(glance)
    if (!isMedia) root.recent = Logic.remember(root.recent, glance, root.recentLimit)
  }

  function hover(screenName, hovered) {
    if (hovered && root.current) {
      leaveTimer.stop()
      root.expandedScreen = screenName
    } else if (!hovered && root.expandedScreen === screenName) {
      leaveTimer.restart()
    }
  }

  function collapse() {
    leaveTimer.stop()
    root.expandedScreen = ""
  }

  onCurrentChanged: if (holdTimer.running) holdTimer.restart()

  Timer {
    id: holdTimer
    interval: Logic.holdFor(root.queue, root.kinds)
    running: root.current !== null && root.expandedScreen === ""
    onTriggered: root.advance()
  }

  // Grace period for the pointer to cross from the capsule to the panel.
  Timer {
    id: leaveTimer
    interval: 250
    onTriggered: root.expandedScreen = ""
  }

  Connections {
    target: root.media
    function onTrackKeyChanged() {
      if (root.media.hasTrack)
        root.show({ kind: "media", glyph: root.glyphMusic,
                    title: root.media.trackTitle, body: root.media.trackArtist })
    }
  }

  Connections {
    target: Notifications.NotificationService
    function onGlanced(entry) { root.showNotification(entry) }
  }

  FileView {
    path: Qt.resolvedUrl("island/config.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.config = JSON.parse(text()) || ({})
      } catch (e) {
        console.warn("island: invalid config.json:", e)
        root.config = ({})
      }
    }
    onLoadFailed: root.config = ({})
  }
}
