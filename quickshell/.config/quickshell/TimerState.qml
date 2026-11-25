pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "timer" as TimerParts
import "timer/TimerLogic.js" as TimerLogic

// Countdown timer. timer/TimerLogic.js owns every transition; this holds the
// state, feeds it events, runs the effects it returns and keeps the file.
//
// One timer for now. `current` is one object so several timers later can
// become a list of them without changing the events or the file's version.
Singleton {
  id: root

  // Seams, replaced by TimerSmoke and the shot harness.
  property var clock: () => Date.now()
  property var launch: command => Quickshell.execDetached(command)
  property var isDnd: () => NotifyState.dnd

  readonly property string stateFilePath: Quickshell.env("TIMER_STATE_FILE")
    || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/timer.json"

  property var current: TimerLogic.initialState()
  // Epoch ms of the last event or tick; the readouts below are derived from it.
  property real now: 0
  readonly property string phase: current.phase
  readonly property real remainingMs: TimerLogic.remainingMs(current, now)
  readonly property real progress: TimerLogic.progress(current, now)
  readonly property var presets: TimerParts.TimerConfig.presets
  readonly property bool ticking: tickTimer.running

  property bool panelVisible: false
  property string panelScreen: ""

  function togglePanel(screenName) {
    if (screenName === "") return
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    // A finished timer is acknowledged by opening the panel to start another.
    if (current.phase === "done") dismiss()
    panelScreen = screenName
    panelVisible = true
  }

  function close() { panelVisible = false }

  function start(durationMs, label) {
    dispatch("start", { durationMs: durationMs, label: label || "" })
    close()
  }

  // Returns { ms } when it started, { error } when the text is not a time.
  function startText(text) {
    const parsed = TimerLogic.parseDuration(text)
    if (parsed.error === undefined) start(parsed.ms, "")
    return parsed
  }

  function addMinute() { dispatch("addMinute", {}) }
  function cancel() { dispatch("cancel", {}) }
  function dismiss() { dispatch("dismiss", {}) }
  function tick() { dispatch("tick", {}) }

  function dispatch(type, fields) {
    const time = root.clock()
    root.now = time
    const result = TimerLogic.reduce(root.current, Object.assign({ type: type, now: time }, fields))
    root.current = result.state
    runEffects(result.effects, result.state)
  }

  function runEffects(effects, state) {
    for (const effect of effects) {
      if (effect === "persist") save()
      else if (effect === "alert") alert(state.durationMs)
    }
  }

  function save() {
    stateFile.setText(JSON.stringify(root.current) + "\n")
  }

  // Silent under do-not-disturb: no popup and no chime. The pill still says
  // Done, which is the only sign.
  function alert(durationMs) {
    if (root.isDnd()) return
    root.launch(["notify-send", "-a", "Timer", "Time is up",
                 TimerLogic.describe(durationMs) + " timer finished"])
    root.launch(["pw-play", TimerParts.TimerConfig.sound])
  }

  // Reads the saved file. A timer that ran out while the shell was down comes
  // back done and alerts once. deferAlert waits for the notification server,
  // which is this same shell and may not be up yet at login.
  function restoreFrom(text, deferAlert) {
    const time = root.clock()
    root.now = time
    const result = TimerLogic.restore(text, time)
    root.current = result.state
    const alerts = result.effects.indexOf("alert") >= 0
    runEffects(result.effects.filter(effect => effect !== "alert" || !deferAlert), result.state)
    if (alerts && deferAlert) {
      lateAlert.durationMs = result.state.durationMs
      lateAlert.start()
    }
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    blockLoading: true
    atomicWrites: true
    blockWrites: true
    watchChanges: false
    printErrors: false
  }

  // The 1 s tick exists only while a timer runs. Each tick lands just past a
  // whole-second boundary, so the readout and the alert are on time.
  Timer {
    id: tickTimer
    interval: TimerLogic.nextTickDelay(root.current, root.now)
    repeat: true
    running: root.current.phase === "running"
    onTriggered: root.tick()
  }

  Timer {
    id: lateAlert
    property real durationMs: 0
    interval: 2000
    onTriggered: root.alert(durationMs)
  }

  Component.onCompleted: restoreFrom(stateFile.text(), true)
}
