import Quickshell
import QtQuick

// One PNG per caption state, rendered by the real VoiceCaptionPill over a
// dark desktop-like backdrop, bottom-centre as the popup places it.
Scope {
  id: shot
  property int failures: 0
  property int step: 0
  readonly property string outDir: Quickshell.env("VERIFY_SHOT_DIR")
  readonly property string longText: "so the plan for the next release is to move the caption pill above the volume slot and keep the newest words visible while the older ones fade out of the start of the line"
  readonly property var steps: [
    { name: "armed", visible: true, phase: "armed", settled: "", pending: "", hint: "Listening…", level: 0 },
    { name: "listening-short", visible: true, phase: "listening", settled: "and then we can ", pending: "ship it", hint: "", level: 0.78 },
    { name: "listening-long", visible: true, phase: "listening", settled: "…move the caption pill above the volume slot and keep the newest words visible while the older ones fade out of the ", pending: "start of the line", hint: "", level: 0.6 },
    { name: "typing", visible: true, phase: "typing", settled: "and then we can ship it on friday", pending: "", hint: "", level: 0 },
    { name: "loading", visible: true, phase: "listening", settled: "", pending: "", hint: "Loading speech model…", level: 0 }
  ]

  QtObject {
    id: fake
    property bool visible: false
    property string phase: "idle"
    property string settled: ""
    property string pending: ""
    property string hint: ""
    property real level: 0
  }

  function check(name, condition) { if (condition) console.log("ok   " + name); else { console.log("FAIL " + name); ++shot.failures } }

  FloatingWindow {
    id: window
    implicitWidth: 1000; implicitHeight: 220; visible: true
    color: "transparent"
    // grabToImage needs an item the QML engine owns, so the backdrop is grabbed.
    Rectangle {
      id: backdrop
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "#1a1b26" }
        GradientStop { position: 1; color: "#24283b" }
      }
      Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.fs(40)
        width: parent.width * 0.7; height: Theme.fs(60); radius: Theme.fs(8)
        color: "#16161e"
        border.width: 1; border.color: "#2f334d"
      }
      VoiceCaptionPill {
        id: pill
        caption: fake
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.gapL
        width: implicitWidth
        height: implicitHeight
      }
    }
  }

  Component.onCompleted: {
    check("the pill starts hidden", pill.targetOpacity === 0)
    applyTimer.start()
  }

  Timer { id: applyTimer; interval: 300; onTriggered: shot.applyStep() }

  function applyStep() {
    const s = shot.steps[shot.step]
    fake.visible = s.visible; fake.phase = s.phase; fake.settled = s.settled; fake.pending = s.pending; fake.hint = s.hint; fake.level = s.level
    grabTimer.start()
  }

  Timer {
    id: grabTimer
    interval: 600
    onTriggered: {
      const s = shot.steps[shot.step]
      console.log("text " + s.name + ": " + pill.markup + " | dimmed " + pill.dimmed + " | " + Math.round(pill.width) + "x" + Math.round(pill.height))
      check(s.name + ": pill is faded in", pill.opacity === pill.targetOpacity && pill.opacity > 0)
      const path = shot.outDir + "/voice-caption-" + s.name + ".png"
      backdrop.grabToImage(function (image) {
        check(s.name + ": saved " + path, image.saveToFile(path))
        if (++shot.step < shot.steps.length) shot.applyStep()
        else shot.finish()
      })
    }
  }

  function finish() {
    console.log(shot.failures === 0 ? "ok: voice caption shots" : ("FAIL: " + shot.failures + " shot check(s) failed"))
    Qt.quit()
  }

  Timer { interval: 15000; running: true; onTriggered: { console.log("FAIL voice caption shot timed out"); Qt.quit() } }
}
