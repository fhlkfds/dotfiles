import Quickshell
import Quickshell.Io
import QtQuick

// Drives OsdState through a fake sink and a fixture backlight directory
// (OSD_BACKLIGHT_ROOT, set by tests/osd.test.sh), with real timers.
Scope {
  id: smoke
  property int failures: 0
  property int step: 0
  readonly property var osd: OsdState
  readonly property string backlight: Quickshell.env("OSD_BACKLIGHT_ROOT") + "/fixture_backlight"

  QtObject {
    id: fakeAudio
    property int volumePct: 40
    property bool muted: false
    property string glyph: "vol"
    property QtObject sink: QtObject {
      property bool ready: true
      property string name: "fake-sink"
    }
  }
  Item { visible: true; OsdPill { id: pill; osd: OsdState } }
  FileView { id: brightnessWriter; path: smoke.backlight + "/actual_brightness"; atomicWrites: false }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  // [delay before the step in ms, step]
  readonly property var steps: [
    [0, function () {
      osd.audio = fakeAudio
      check("the first sink reading is a baseline, not a change", !osd.visible)
      fakeAudio.volumePct = 45
      check("a volume change shows the pill", osd.visible && osd.kind === "volume" && osd.level === 45)
      check("the pill reads the level", pill.osd.text === "45%" && Math.abs(pill.fill - 0.45) < 0.001)
    }],
    [400, function () {
      const screen = osd.screenName
      fakeAudio.volumePct = 50
      check("a second change inside the hold updates the same pill", osd.visible && osd.level === 50 && osd.screenName === screen)
    }],
    [1000, function () {
      check("the second change extends the hold past the first deadline", osd.visible && pill.opacity > 0)
    }],
    [600, function () {
      check("the pill hides after the hold", !osd.visible && osd.level === 50)
    }],
    [300, function () {
      check("the pill fades out", pill.opacity === 0)
      fakeAudio.muted = true
      check("muting shows the pill", osd.visible && pill.osd.text === "Muted" && pill.fill === 0)
      check("the backlight fixture is found", osd.backlightDir.indexOf("fixture_backlight") >= 0)
      brightnessWriter.setText("150\n")
    }],
    [400, function () {
      check("a brightness change takes over the pill", osd.visible && osd.kind === "brightness" && osd.level === 75)
      check("the brightness pill uses its own glyph", osd.glyph !== fakeAudio.glyph)
    }]
  ]

  Timer {
    id: runner
    running: true
    interval: 1
    onTriggered: {
      smoke.steps[smoke.step][1]()
      ++smoke.step
      if (smoke.step < smoke.steps.length) {
        interval = smoke.steps[smoke.step][0]
        start()
      } else {
        console.log("osd smoke done: " + smoke.failures + " failures")
        Qt.quit()
      }
    }
  }
}
