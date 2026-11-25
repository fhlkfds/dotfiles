import Quickshell
import QtQuick
import QtTest

// The timer journey, offscreen: the real BarCenter with the real TimerIcon
// beside the clock, and the real TimerPanelContent under the clock while the
// panel is open. A fake clock moves time, TestEvent types and clicks, and a
// recording launcher stands in for notify-send and pw-play.
//
// TIMER_SHOT_FRAMES=1 also writes frames/frame-NNNN.png, ten per second of
// story, from the first idle bar to the dismissed pill.
Scope {
  id: shot
  property int failures: 0
  readonly property string outDir: Quickshell.env("VERIFY_SHOT_DIR")
  readonly property bool wantFrames: Quickshell.env("TIMER_SHOT_FRAMES") === "1"
  readonly property int frameMs: 100
  readonly property real base: new Date(2026, 0, 15, 14, 55, 0).getTime()
  property real fakeNow: base
  property var launched: []
  property int frameCount: 0
  property bool frameFailed: false
  property bool dnd: false

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++shot.failures }
  }

  FloatingWindow {
    id: win
    implicitWidth: 1280
    implicitHeight: 360
    visible: true
    color: "transparent"

    Rectangle {
      id: scene
      anchors.fill: parent
      color: Theme.bg

      Item {
        id: barStrip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight

        BarCenter {
          id: center
          anchors.fill: parent
          barScale: Theme.barScaleFor(scene.width)

          TimerIcon { id: timerIcon; screenName: "shot"; barScale: center.barScale }
        }
      }

      Rectangle {
        id: card
        x: center.clock.x + center.clock.width / 2 - width / 2
        y: barStrip.height + Theme.gapS
        width: content.width + 2 * Theme.gapL
        height: content.height + 2 * Theme.gapL
        radius: Theme.menuRadius
        color: Theme.bg
        border.width: Theme.menuBorderWidth
        border.color: Theme.borderActive1
        visible: TimerState.panelVisible && TimerState.panelScreen === "shot"

        TimerPanelContent {
          id: content
          x: Theme.gapL
          y: Theme.gapL
          width: implicitWidth
          height: implicitHeight
          onCloseRequested: TimerState.close()
        }
      }
    }
  }

  TestEvent { id: input }

  Timer {
    id: later
    property var callback: null
    onTriggered: { const run = callback; callback = null; run() }
  }
  function after(ms, run) { later.callback = run; later.interval = ms; later.restart() }

  function pad4(number) { return ("0000" + number).slice(-4) }

  function grab(item, name, done) {
    item.grabToImage(result => {
      shot.check("saved " + name + ".png", result.saveToFile(shot.outDir + "/" + name + ".png"))
      done()
    })
  }

  function frame(done) {
    scene.grabToImage(result => {
      const path = shot.outDir + "/frames/frame-" + shot.pad4(++shot.frameCount) + ".png"
      if (!result.saveToFile(path)) shot.frameFailed = true
      done()
    })
  }

  // Shows `count` frames of story. `each(k)` runs before frame k. Without
  // TIMER_SHOT_FRAMES the same calls run back to back, so the state ends up
  // identical and only the pictures are skipped.
  function hold(count, each, done) {
    if (!shot.wantFrames) {
      for (let k = 0; k < count; ++k) if (each) each(k)
      shot.after(80, done)
      return
    }
    let k = 0
    const step = () => {
      if (k >= count) { done(); return }
      if (each) each(k)
      ++k
      shot.after(shot.frameMs, () => shot.frame(step))
    }
    step()
  }

  function advance() { shot.fakeNow += shot.frameMs; TimerState.tick() }
  // keyClick reads a numeric string as a key code, so characters go in as keys.
  function press(key, modifiers) {
    const code = typeof key === "string" ? key.charCodeAt(0) : -1
    const resolved = code >= 48 && code <= 57 ? Qt.Key_0 + code - 48
      : code >= 97 && code <= 122 ? Qt.Key_A + code - 97
      : typeof key === "string" ? Qt.Key_Colon : key
    input.keyClick(resolved, modifiers || Qt.NoModifier, -1)
  }
  function clickPill() { input.mouseClick(timerIcon, timerIcon.width / 2, timerIcon.height / 2, Qt.LeftButton, Qt.NoModifier, -1) }
  function typeText(text, done) { shot.hold(text.length, k => shot.press(text[k]), done) }
  function quiet(ms, done) { shot.after(ms, done) }

  function preflight(done) {
    TimerState.togglePanel("shot")
    shot.quiet(150, () => {
      shot.check("preflight: the panel opens with an empty box", card.visible && content.inputText === "")
      shot.press("2", Qt.AltModifier)
      shot.check("preflight: Alt+2 starts the 10 minute preset",
                 TimerState.phase === "running" && TimerState.current.durationMs === 600000)
      shot.check("preflight: starting closes the panel", !card.visible)
      TimerState.cancel()
      TimerState.togglePanel("shot")
      shot.quiet(150, () => {
        shot.press("1"); shot.press("0")
        shot.check("preflight: a bare 1 types instead of picking a preset", content.inputText === "10" && TimerState.phase === "idle")
        shot.check("preflight: and previews as 10 min", content.liveText.indexOf("→ 10 min · rings at 15:05:00") === 0)
        shot.press(Qt.Key_Escape)
        shot.check("preflight: Escape in the box closes the panel", !card.visible)
        shot.fakeNow = shot.base
        shot.launched = []
        done()
      })
    })
  }

  function journey() {
    const steps = [
      done => shot.preflight(done),
      done => {
        shot.check("idle: the pill is hidden", !timerIcon.visible && TimerState.phase === "idle")
        shot.hold(8, null, () => shot.grab(barStrip, "timer-idle-bar", done))
      },
      done => {
        TimerState.togglePanel("shot")
        shot.hold(8, null, () => {
          shot.check("the key opens the panel on this screen", card.visible && TimerState.panelVisible)
          shot.check("idle panel offers four presets", content.presets.length === 4 && !content.running)
          console.log("text panel: " + content.hintText)
          shot.grab(scene, "timer-panel", done)
        })
      },
      done => shot.typeText("7m30s", () => shot.hold(8, null, () => {
        shot.check("typing fills the box", content.inputText === "7m30s")
        shot.check("the live line previews the time", content.liveText === "→ 7 min 30 s · rings at 15:02:30")
        console.log("text typed: " + content.inputText + " | " + content.liveText)
        shot.grab(scene, "timer-typed", done)
      })),
      done => {
        shot.press(Qt.Key_Return)
        shot.hold(6, null, () => {
          shot.check("Enter starts the timer", TimerState.phase === "running" && TimerState.current.durationMs === 450000)
          shot.check("starting closes the panel", !card.visible)
          shot.check("the pill counts down from 7:30", timerIcon.visible && timerIcon.label === "7:30")
          console.log("text running pill: " + timerIcon.label)
          shot.grab(barStrip, "timer-running-bar", done)
        })
      },
      done => {
        shot.clickPill()
        shot.hold(8, null, () => {
          shot.check("clicking the running pill opens the panel", card.visible && content.running)
          shot.check("the panel shows the running timer", content.runningLabel === "7 min 30 s timer")
          console.log("text running panel: " + content.runningLabel + " | " + timerIcon.label)
          shot.grab(scene, "timer-running-panel", done)
        })
      },
      done => shot.hold(25, shot.advance, () => {
        shot.check("the countdown ticks", timerIcon.label === "7:28")
        done()
      }),
      done => {
        shot.press(Qt.Key_Escape)
        shot.hold(5, shot.advance, () => {
          shot.check("Escape closes the running panel", !card.visible && TimerState.phase === "running")
          done()
        })
      },
      done => {
        shot.fakeNow = TimerState.current.endsAt - 5000
        TimerState.tick()
        shot.check("fast-forwarded to the last five seconds", timerIcon.label === "0:05")
        shot.hold(55, shot.advance, done)
      },
      done => {
        shot.check("time is up: the pill reads Done", TimerState.phase === "done" && timerIcon.label === "Done")
        shot.check("exactly one notification and one chime", shot.launched.length === 2 && shot.launched[0][0] === "notify-send"
                   && shot.launched[1][0] === "pw-play")
        console.log("text alert: " + shot.launched.map(command => command.join(" ")).join(" ; "))
        shot.grab(barStrip, "timer-done-bar", done)
      },
      done => shot.hold(20, null, done),
      done => {
        shot.clickPill()
        shot.hold(8, null, () => {
          shot.check("clicking the Done pill dismisses it", TimerState.phase === "idle" && !timerIcon.visible)
          done()
        })
      }
    ]
    let index = 0
    const next = () => index < steps.length ? steps[index++](next) : shot.finish()
    next()
  }

  function finish() {
    if (shot.wantFrames) {
      shot.check("frames written (" + shot.frameCount + ")", shot.frameCount > 0 && !shot.frameFailed)
      console.log("text frames: " + shot.frameCount)
    }
    console.log(shot.failures === 0 ? "ok: timer shots" : "FAIL: " + shot.failures + " shot check(s) failed")
    Qt.quit()
  }

  Component.onCompleted: {
    TimerState.clock = () => shot.fakeNow
    TimerState.isDnd = () => shot.dnd
    TimerState.launch = command => { shot.launched = shot.launched.concat([command]) }
    TimerState.restoreFrom("")
    shot.after(300, shot.journey)
  }

  Timer { interval: 100000; running: true; onTriggered: { console.log("FAIL timer shot timed out"); Qt.quit() } }
}
