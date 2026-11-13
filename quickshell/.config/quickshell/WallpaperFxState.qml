// WallpaperFxState.qml: the state machine behind WallpaperFx.qml, kept free of
// windows so WallpaperFxSmoke.qml can drive it headless. WallpaperFx.qml
// explains the hand-over with hyprpaper.
import Quickshell
import Quickshell.Io
import QtQuick
import "wallfx/WallpaperFxLogic.js" as Fx

Scope {
  id: root

  // ─── test hooks: a lab output, a stand-in hyprctl ───
  readonly property string onlyScreen: Quickshell.env("WALLFX_ONLY") || ""
  readonly property bool dry: Quickshell.env("WALLFX_DRY") === "1"
  property string hyprctl: Quickshell.env("WALLFX_HYPRCTL") || "hyprctl"

  // ─── tuning ───
  property int msContagion: 1800
  property int msOutline: 2000
  property int msFade: 130          // a cross-fade between two renders of the same image
  property int msWatchdog: 2500
  property real glow: 0.9
  property real lineW: 1.5
  readonly property var tunable: ["msContagion", "msOutline", "msFade", "msWatchdog", "glow", "lineW"]

  // ─── one change ───
  property string oldPath: ""
  property string newPath: ""
  property string kind: "contagion"
  property string fieldPath: ""
  property string linePath: ""
  property bool autoGo: true
  // idle → loading → run (→ held, until hyprpaper has switched) → fadeout → idle;
  // in the lab (dry) loading → ready, held there until `go`, then done.
  property string phase: "idle"
  property real t: 0
  property real fade: 0
  property bool swapped: false
  property int gen: 0               // one per change: late news from an older one is ignored
  // Captured from the theme when the change starts: the contagion's burning
  // edge (its most vivid colour) and the outline's line (its lightest tone).
  property color ember: Theme.accent
  property color ink: Theme.text
  property real seed: 0
  property int readyCount: 0
  property int screenCount: 1          // set by WallpaperFx.qml: windows that must load
  readonly property bool active: phase !== "idle"

  function lifted(c) {
    // A palette colour can be dark; the burning edge has to light up.
    return Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.55),
                   Math.min(Math.max(c.hslLightness, 0.62), 0.82), 1)
  }

  function prepare(o, n, k, f, l, go) {
    if (root.active) root.finish()
    root.oldPath = o; root.newPath = n
    root.kind = k === "outline" ? "outline" : "contagion"
    root.fieldPath = f; root.linePath = l || f
    root.autoGo = go
    root.t = 0; root.fade = 0; root.readyCount = 0; root.swapped = false
    root.gen++
    root.phase = "loading"
    watchdog.restart()
  }
  function screenReady() {
    if (root.phase !== "loading") return
    root.readyCount++
    if (root.readyCount < root.screenCount) return
    watchdog.stop()
    if (root.dry) { root.fade = 1; root.phase = "ready"; if (root.autoGo) root.go(); return }
    root.go()
  }
  function go() {
    if (root.phase !== "ready" && root.phase !== "loading") return
    // Captured now, not bound: a theme switch mid-change must not recolour the front.
    const pal = [Theme.background, Theme.accent, Theme.accentAlt, Theme.borderAccent,
                 Theme.selection, Theme.muted, Theme.foreground, Theme.foregroundBright]
    root.ember = root.lifted(Fx.mostVivid(pal))
    root.ink = Fx.lightest(pal)
    root.seed = Math.random() * 100
    root.phase = "run"
    run.duration = root.kind === "outline" ? root.msOutline : root.msContagion
    run.restart()
    if (!root.dry) fadeIn.restart()
  }
  // Uncover only when the transition has ended AND hyprpaper shows the new one.
  function maybeFinish() {
    if (root.dry) { if (!run.running) root.phase = "done"; return }
    if (run.running) return
    if (!root.swapped) { root.phase = "held"; watchdog.restart(); return }
    root.phase = "fadeout"
    fadeOut.restart()
  }
  // In the lab (WALLFX_ONLY) hyprpaper may only touch that output: the others
  // are the real desktop. An empty monitor field means every output.
  function hyprpaperSet(path) {
    return [root.hyprctl, "hyprpaper", "wallpaper", root.onlyScreen + "," + path + ",cover"]
  }
  function swap() {
    const p = swapProcess.createObject(root, { forGen: root.gen, forPath: root.newPath,
                                               command: root.hyprpaperSet(root.newPath) })
    p.running = true
  }
  // If hyprpaper did not switch, uncovering would bring the OLD one back: stop
  // here and let hyprpaper try once more on its own, even if the watchdog has
  // already stepped aside. A switch from a change that has since been replaced
  // is left alone: reacting to it would cut the new one.
  function swapExited(forGen, forPath, code) {
    if (forGen !== root.gen) return
    if (code === 0) { if (root.active) settle.restart(); return }
    if (root.active) root.finish()
    Quickshell.execDetached(root.hyprpaperSet(forPath))
  }
  function finish() {
    fadeIn.stop(); run.stop(); fadeOut.stop(); watchdog.stop(); settle.stop()
    root.phase = "idle"; root.fade = 0; root.t = 0
    root.oldPath = ""; root.newPath = ""; root.fieldPath = ""; root.linePath = ""
  }

  NumberAnimation { id: fadeIn; target: root; property: "fade"; from: 0; to: 1
    duration: root.msFade; easing.type: Easing.OutQuad
    onFinished: root.swap() }
  // `t` is TIME, so it runs linear; each phase eases its own stretch in the shader.
  NumberAnimation { id: run; target: root; property: "t"; from: 0; to: 1
    easing.type: Easing.Linear
    onFinished: root.maybeFinish() }
  // How the last transition ran: `quickshell ipc call wallfx stats`. A scene
  // change that stutters is worse than no transition, so it is measured.
  property int statFrames: 0
  property real statWorst: 0
  property string lastStats: ""
  FrameAnimation {
    running: root.phase === "run"
    onRunningChanged: if (running) { root.statFrames = 0; root.statWorst = 0 }
                      else if (root.statFrames > 0)
                        root.lastStats = root.kind + ": " + root.statFrames + " frames in "
                          + run.duration + " ms (" + Math.round(root.statFrames * 1000 / run.duration)
                          + " fps), worst " + Math.round(root.statWorst * 1000) + " ms"
    onTriggered: { root.statFrames++; if (root.statFrames > 2) root.statWorst = Math.max(root.statWorst, frameTime) }
  }

  NumberAnimation { id: fadeOut; target: root; property: "fade"; from: 1; to: 0
    duration: root.msFade; easing.type: Easing.OutQuad
    onFinished: root.finish() }

  // One process per switch, stamped with its change: a shared one could not
  // tell an older change's exit from the current one's.
  Component {
    id: swapProcess
    Process {
      property int forGen: -1
      property string forPath: ""
      onExited: (code) => { root.swapExited(forGen, forPath, code); destroy() }
    }
  }
  // hyprpaper has the new image; give it two frames to present it before
  // anything can uncover it.
  Timer { id: settle; interval: 40; onTriggered: { root.swapped = true; root.maybeFinish() } }

  // Two ways to get stuck, two ways out: the images never load (hyprpaper
  // switches on its own), or hyprpaper never answers (the effect, already
  // showing the new wallpaper, steps aside instead of staying on top).
  Timer {
    id: watchdog; interval: root.msWatchdog
    onTriggered: {
      const n = root.newPath, loading = root.phase === "loading"
      root.finish()
      if (loading && !root.dry && n)
        Quickshell.execDetached(root.hyprpaperSet(n))
    }
  }

  IpcHandler {
    target: "wallfx"
    function play(oldImg: string, newImg: string, kind: string, field: string, line: string): string {
      root.prepare(oldImg, newImg, kind, field, line, true); return "ok"
    }
    // For tests: load and hold the first frame; `go` starts it.
    function prepare(oldImg: string, newImg: string, kind: string, field: string, line: string): string {
      root.prepare(oldImg, newImg, kind, field, line, false); return "ok"
    }
    function go(): string { root.go(); return root.phase }
    function state(): string { return root.phase }
    function stats(): string { return root.lastStats }
    function stop(): string { root.finish(); return "ok" }
    function tune(key: string, value: string): string {
      if (root.tunable.indexOf(key) === -1) return "unknown key: " + key
      root[key] = Number(value)
      return key + "=" + root[key]
    }
  }
}
