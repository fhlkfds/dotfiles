// WallpaperFx.qml: the wallpaper transitions, drawn by the shell over hyprpaper.
// Adapted from diegoMalagrida/pocket-dots (home/.config/quickshell/WallpaperFx.qml, GPL-3.0).
//
// Two transitions, in a shader (shaders/wallfx.frag) fed by the maps of
// ~/.local/bin/wallfx:
//
//   contagion  colonies landing at random places eat through the old wallpaper
//              in crisp 4 px cells, each burning for an instant in the theme's
//              most vivid colour.
//   outline    when the new wallpaper has a character: a thin quiet line draws
//              its outline, it fills in, and the rest spreads out of it.
//
// HOW IT HANDS OVER WITH HYPRPAPER. hyprpaper stays the wallpaper; this draws
// only for the length of a change, on the Bottom layer: hyprpaper rebuilds its
// Background surface on every change, which would land on top of anything else
// there. The windows stay mapped and draw nothing while idle, and shell.qml
// creates them before the desktop widgets, which therefore stay above them.
// The order is what makes it seamless:
//   1. load both images and the maps, off the main thread;
//   2. start the transition and, at the same time, fade in over hyprpaper. At
//      t≈0 the transition IS the old wallpaper, so nobody sees the fade;
//   3. once fully covered, switch hyprpaper underneath;
//   4. the transition ends on the new image, which hyprpaper now shows too;
//   5. fade out, and the textures are released.
// If anything fails to load within 2.5 s, hyprpaper switches on its own: the
// wallpaper must change even if the effect cannot be shown.
//
// IPC (hypr-wallpaper-picker calls it; `wallfx pick` chooses the kind and maps):
//   quickshell ipc call wallfx play OLD NEW contagion|outline MAP LINE
import Quickshell
import Quickshell.Wayland
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
  property int swapGen: -1
  // Captured from the theme when the change starts: the contagion's burning
  // edge (its most vivid colour) and the outline's line (its lightest tone).
  property color ember: Theme.accent
  property color ink: Theme.text
  property real seed: 0
  property int readyCount: 0
  readonly property int screenCount: screens.instances.length
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
    root.swapGen = root.gen
    hyprpaper.command = root.hyprpaperSet(root.newPath)
    hyprpaper.running = true
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

  Process {
    id: hyprpaper
    // If hyprpaper did not switch, uncovering would bring the OLD one back:
    // stop here and let hyprpaper try once more on its own. A switch from a
    // change that has since been replaced is left alone: reacting to it would
    // cut the new one.
    onExited: (code) => {
      if (root.swapGen !== root.gen) return
      if (code === 0) { settle.restart(); return }
      const n = root.newPath
      root.finish()
      Quickshell.execDetached(root.hyprpaperSet(n))
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

  Variants {
    id: screens
    model: Quickshell.screens.filter(s => !root.onlyScreen || s.name === root.onlyScreen)

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}                       // clicks go through to the desktop
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "quickshell-wallfx"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property bool loaded: oldImg.status === Image.Ready && newImg.status === Image.Ready
        && fieldImg.status === Image.Ready && lineImg.status === Image.Ready
      onLoadedChanged: if (loaded) root.screenReady()

      // Decoded at the size of the screen (covering it), not of the file: a
      // 6 MB wallpaper does not need 24 MB of texture.
      Image { id: oldImg; visible: false; asynchronous: true; cache: false
        source: Fx.fileUrl(root.oldPath)
        sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
      Image { id: newImg; visible: false; asynchronous: true; cache: false
        source: Fx.fileUrl(root.newPath)
        sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
      // The maps hold numbers, not colours: contagion's are read texel by
      // texel (no filtering), the outline's are interpolated on purpose.
      Image { id: fieldImg; visible: false; asynchronous: true; cache: false
        smooth: root.kind === "outline"
        source: Fx.fileUrl(root.fieldPath) }
      Image { id: lineImg; visible: false; asynchronous: true; cache: false
        source: Fx.fileUrl(root.linePath) }

      function cover(img) {
        const r = Fx.cover(img.implicitWidth, img.implicitHeight, win.width, win.height)
        return Qt.vector4d(r[0], r[1], r[2], r[3])
      }

      ShaderEffect {
        anchors.fill: parent
        visible: root.active && win.loaded
        opacity: root.fade
        property var oldTex: oldImg
        property var newTex: newImg
        property var fieldTex: fieldImg
        property var lineTex: lineImg
        property real t: root.t
        property real mode: root.kind === "outline" ? 1 : 0
        property real sw: win.width
        property real sh: win.height
        property real fw: Math.max(fieldImg.implicitWidth, 1)
        property real fh: Math.max(fieldImg.implicitHeight, 1)
        property real lw: Math.max(lineImg.implicitWidth, 1)
        property real lh: Math.max(lineImg.implicitHeight, 1)
        property real glow: root.glow
        property real lineW: root.lineW
        property real sdRange: 16
        property real seed: root.seed
        property vector4d cropOld: win.cover(oldImg)
        property vector4d cropNew: win.cover(newImg)
        property color ember: root.ember
        property color ink: root.ink
        // Versioned name: Qt caches compiled shaders by URL.
        fragmentShader: Qt.resolvedUrl("shaders/wallfx.v1.frag.qsb")
      }
    }
  }
}
