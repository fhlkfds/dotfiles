import Quickshell
import QtQuick

// Headless harness for WallpaperFx.qml. tests/wallpaper-fx.test.sh provides
// fixture images in WALLFX_SMOKE_DIR and two stand-in hyprctl scripts that log
// their arguments there (one succeeds, one fails); the real hyprpaper is never
// touched. The test checks those logs after this exits.
Scope {
  id: smoke
  property int failures: 0
  readonly property string dir: Quickshell.env("WALLFX_SMOKE_DIR") || ""
  property var seen: []
  property int step: -1
  property real stepStarted: 0

  function check(ok, name) {
    console.log((ok ? "ok   " : "FAIL ") + name)
    if (!ok) failures++
  }
  function img(name) { return smoke.dir + "/" + name }
  function play(newName, kind) {
    smoke.seen = []
    fx.prepare(img("old.png"), img(newName), kind, img("field.png"), img("line.png"), true)
  }
  function saw(phases) { return JSON.stringify(smoke.seen) === JSON.stringify(phases) }

  WallpaperFx {
    id: fx
    msContagion: 300
    msOutline: 300
    msFade: 40
    msWatchdog: 600
    onPhaseChanged: smoke.seen = smoke.seen.concat([phase])
  }

  readonly property var steps: [
    {
      name: "a change covers, switches hyprpaper, then uncovers",
      start: () => { fx.hyprctl = smoke.img("hyprctl-ok"); smoke.play("new.png", "contagion") },
      check: () => {
        smoke.check(smoke.saw(["loading", "run", "fadeout", "idle"]) || smoke.saw(["loading", "run", "held", "fadeout", "idle"]),
              "phases: " + JSON.stringify(smoke.seen))
        smoke.check(fx.ember.hslLightness >= 0.61 && fx.ember.hslSaturation >= 0.54,
              "the burning edge is lifted so it lights up")
        smoke.check(fx.fade === 0 && fx.newPath === "", "an idle effect holds no images and draws nothing")
      }
    },
    {
      name: "an outline change runs as an outline",
      start: () => { smoke.play("new.png", "outline"); smoke.check(fx.kind === "outline", "kind outline is kept") },
      check: () => smoke.check(smoke.seen.indexOf("fadeout") !== -1, "the outline change finished its fade-out")
    },
    {
      name: "a failed switch steps aside and lets hyprpaper retry alone",
      start: () => { fx.hyprctl = smoke.img("hyprctl-fail"); smoke.play("fail.png", "contagion") },
      check: () => smoke.check(smoke.saw(["loading", "run", "idle"]), "phases: " + JSON.stringify(smoke.seen))
    },
    {
      name: "a wallpaper that never loads still changes",
      start: () => { fx.hyprctl = smoke.img("hyprctl-ok"); smoke.play("missing.png", "contagion") },
      check: () => smoke.check(smoke.saw(["loading", "idle"]), "phases: " + JSON.stringify(smoke.seen))
    },
    {
      name: "a change replaced mid-load is dropped",
      start: () => { smoke.play("replaced.png", "contagion"); smoke.play("new.png", "contagion") },
      check: () => smoke.check(fx.phase === "idle", "the replacing change finished")
    }
  ]

  Timer {
    interval: 20
    repeat: true
    running: smoke.dir !== ""
    onTriggered: {
      const now = Date.now()
      const current = smoke.steps[smoke.step]
      if (current && fx.phase !== "idle") {
        if (now - smoke.stepStarted < 5000) return
        smoke.check(false, current.name + ": stuck in " + fx.phase)
      } else if (current) {
        current.check()
      }
      smoke.step++
      if (smoke.step >= smoke.steps.length) {
        running = false
        console.log(smoke.failures === 0 ? "ok: WallpaperFx smoke" : "FAIL WallpaperFx smoke: " + smoke.failures)
        Qt.quit()
        return
      }
      smoke.stepStarted = now
      smoke.steps[smoke.step].start()
    }
  }
}
