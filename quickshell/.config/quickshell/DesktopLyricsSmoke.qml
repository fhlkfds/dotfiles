import Quickshell
import QtQuick
import "DesktopCover.js" as DesktopCover

// Headless harness for the desktop lyrics. A stand-in LyricsState and a fake
// Hyprland monitor replace the real ones, so nothing reaches lrclib or a live
// session. Toggles the saved switch once; the .sh test reads the file after.
// With DESKTOP_LYRICS_SMOKE_SAVED_OFF=1 it instead checks that a saved "off"
// is already read when the first binding asks for it.
Scope {
  id: smoke
  property int failures: 0
  readonly property bool savedOff: Quickshell.env("DESKTOP_LYRICS_SMOKE_SAVED_OFF") === "1"

  QtObject {
    id: fakeLyrics
    property string status: "synced"
    property var lines: [
      { ms: 0, text: "First line" },
      { ms: 4000, text: "Second line" },
      { ms: 8000, text: "Third line" }
    ]
    property int activeIndex: 1
  }

  QtObject {
    id: fakeToplevels
    property var values: []
  }
  QtObject {
    id: fakeWorkspace
    property var toplevels: fakeToplevels
  }
  QtObject {
    id: fakeScratchToplevels
    property var values: [{}]
  }
  QtObject {
    id: fakeScratch
    property string name: "special:scratch"
    property var toplevels: fakeScratchToplevels
  }
  QtObject {
    id: fakeMonitor
    property var activeWorkspace: fakeWorkspace
    property var lastIpcObject: ({ specialWorkspace: { id: 0, name: "" } })
  }

  Item {
    visible: true
    DesktopLyricsContent {
      id: view
      lyrics: fakeLyrics
      playing: true
      covered: DesktopCover.covered(fakeMonitor, [fakeWorkspace, fakeScratch])
    }
  }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  Component.onCompleted: {
    check("shows the active line", view.activeText === "Second line")
    check("shows the next line", view.nextText === "Third line")
    check("visible on an empty desktop while playing", view.shown)
    check("a shown view keeps the position timer running", MediaState.timelineShown)

    fakeLyrics.activeIndex = -1
    check("before the first line only the next line shows",
      view.activeText === "" && view.nextText === "First line")
    fakeLyrics.activeIndex = 2
    check("the last line has no next line", view.activeText === "Third line" && view.nextText === "")

    view.playing = false
    check("hidden while paused", !view.shown && !MediaState.timelineShown)
    view.playing = true

    fakeToplevels.values = [{}]
    check("hidden when a window covers the desktop", view.covered && !view.shown)
    check("a covered view lets the position timer stop", !MediaState.timelineShown)
    fakeToplevels.values = []
    check("back when the window goes", !view.covered && view.shown && MediaState.timelineShown)

    fakeMonitor.lastIpcObject = { specialWorkspace: { id: -98, name: "special:scratch" } }
    check("hidden under a visible scratchpad with a window", view.covered && !view.shown)
    fakeScratchToplevels.values = []
    check("an empty scratchpad does not cover", !view.covered)
    fakeScratchToplevels.values = [{}]
    fakeMonitor.lastIpcObject = { specialWorkspace: { id: 0, name: "" } }
    check("back when the scratchpad closes", !view.covered && view.shown)

    fakeLyrics.status = "notfound"
    fakeLyrics.lines = []
    check("hidden when no lyrics were found", !view.shown)
    fakeLyrics.status = "plain"
    check("hidden for unsynced lyrics", !view.shown)
    fakeLyrics.status = "loading"
    check("hidden while lyrics load", !view.shown)

    check("no monitor counts as uncovered", !DesktopCover.covered(null))

    const mask = view.clickMask
    check("window mask is empty, so clicks pass through",
      mask !== null && mask.item === null && mask.width === 0 && mask.height === 0
        && mask.regions.length === 0)

    if (smoke.savedOff)
      check("a saved off is read before the shell builds", !DesktopLyricsState.enabled)
    else
      check("desktop lyrics are on by default", DesktopLyricsState.enabled)
  }

  // Let the state file's first load settle before flipping it, then give the
  // write time to land before quitting.
  Timer {
    interval: 300
    running: true
    onTriggered: {
      if (!smoke.savedOff) {
        DesktopLyricsState.toggle()
        smoke.check("toggle turns desktop lyrics off", !DesktopLyricsState.enabled)
      }
      quitTimer.start()
    }
  }
  Timer {
    id: quitTimer
    interval: 500
    onTriggered: {
      console.log(smoke.failures === 0 ? "ok: Desktop lyrics" : "FAIL: " + smoke.failures + " failures")
      Qt.quit()
    }
  }
}
