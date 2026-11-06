pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "island/IslandLogic.js" as Logic

// The centre island's glances: a track change briefly widens the capsule
// around the clock, then it folds back. Notifications stay in the card stack.
// The queue rules live in island/IslandLogic.js; this file feeds them events
// and runs the clock.
Singleton {
  id: root

  property var config: ({})
  readonly property var kinds: Logic.kindTable(config.kinds)
  readonly property int animationMs: Number.isInteger(config.animationMs) ? config.animationMs : 220
  readonly property int glanceMaxWidth: Number.isInteger(config.glanceMaxWidth) ? config.glanceMaxWidth : 420

  property var queue: Logic.emptyQueue()
  readonly property var current: queue.current
  // Hovering a glance expands it on that screen's bar and pauses its hold.
  property string expandedScreen: ""
  // What is left of the current glance's hold, kept across a hover pause.
  property int holdRemaining: 0
  property real holdStartedMs: 0

  // IslandSmoke swaps in a fake with the same properties.
  property var media: MediaState

  readonly property string glyphMusic: String.fromCodePoint(0xf075a) // md-music

  function show(glance) { root.queue = Logic.enqueue(root.queue, glance, root.kinds) }
  function advance() { root.queue = Logic.advance(root.queue) }

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

  onCurrentChanged: {
    root.holdRemaining = Logic.holdFor(root.queue, root.kinds)
    root.holdStartedMs = Date.now()
    if (holdTimer.running) holdTimer.restart()
  }

  Timer {
    id: holdTimer
    interval: Math.max(1, root.holdRemaining)
    running: root.current !== null && root.expandedScreen === ""
    onRunningChanged: {
      if (running) root.holdStartedMs = Date.now()
      else if (root.current)
        root.holdRemaining = Math.max(0, root.holdRemaining - (Date.now() - root.holdStartedMs))
    }
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
                    title: root.media.trackTitle, body: root.media.trackArtist,
                    screen: "" })
    }
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
