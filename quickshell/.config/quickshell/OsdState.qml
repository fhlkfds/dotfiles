// Volume and brightness OSD. The keybinds still call wpctl and brightnessctl
// directly; this singleton only reacts to state the shell already watches, so
// a keypress spawns nothing new.
pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import "osd/OsdLogic.js" as OsdLogic

Singleton {
  id: root

  // Swappable so the smoke can drive a fake sink.
  property var audio: AudioState
  // brightnessctl writes sysfs, and the kernel notifies actual_brightness on
  // every write, so a FileView watch sees key presses without polling.
  property string backlightRoot: Quickshell.env("OSD_BACKLIGHT_ROOT") || "/sys/class/backlight"
  readonly property string backlightDir: backlights.count > 0
    ? String(backlights.get(0, "filePath")) : ""

  property var model: OsdLogic.initialState()
  property string screenName: ""
  readonly property bool visible: model.visible
  readonly property string kind: model.kind
  readonly property int level: model.level
  readonly property bool muted: model.muted
  readonly property string text: OsdLogic.levelText(level, muted)
  readonly property string glyph: kind === "brightness"
    ? String.fromCodePoint(0xf00e0) // md-brightness_7
    : root.audio.glyph

  readonly property var sink: root.audio ? root.audio.sink : null
  readonly property string sinkDevice: sink && sink.ready ? String(sink.name) : ""

  function focusedScreenName() {
    const monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return monitor.name
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function report(kind, device, level, muted) {
    const result = OsdLogic.change(root.model, {kind: kind, device: device, level: level, muted: muted}, Date.now())
    if (result.shown && !root.model.visible)
      root.screenName = root.focusedScreenName()
    root.model = result.state
    if (result.shown) {
      hideTimer.interval = OsdLogic.HOLD_MS
      hideTimer.restart()
    }
  }

  function reportVolume() {
    root.report("volume", root.sinkDevice, root.audio.volumePct, root.audio.muted)
  }

  function reportBrightness() {
    const max = parseInt(maxFile.text(), 10)
    const current = parseInt(actualFile.text(), 10)
    if (!(max > 0) || isNaN(current))
      root.report("brightness", "", 0, false)
    else
      root.report("brightness", root.backlightDir, current * 100 / max, false)
  }

  onSinkDeviceChanged: reportVolume()
  Component.onCompleted: reportVolume()

  Connections {
    target: root.audio
    function onVolumePctChanged() { root.reportVolume() }
    function onMutedChanged() { root.reportVolume() }
  }

  Timer {
    id: hideTimer
    repeat: false
    // Coarse timers can fire a little early; re-arm for what is left.
    onTriggered: {
      const now = Date.now()
      root.model = OsdLogic.expire(root.model, now)
      if (root.model.visible) {
        interval = Math.max(1, root.model.hideAt - now)
        restart()
      }
    }
  }

  FolderListModel {
    id: backlights
    folder: "file://" + root.backlightRoot
    showFiles: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
  }

  FileView {
    id: maxFile
    path: root.backlightDir === "" ? "" : root.backlightDir + "/max_brightness"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: actualFile
    path: root.backlightDir === "" ? "" : root.backlightDir + "/actual_brightness"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.reportBrightness()
    onLoadFailed: root.report("brightness", "", 0, false)
  }
}
