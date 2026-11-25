import Quickshell
import Quickshell.Io
import QtQuick

// Headless harness for the countdown timer: the real TimerState, TimerIcon and
// TimerPanelContent against a fake clock, a recording launcher and a fake
// do-not-disturb switch. Nothing starts notify-send or pw-play. The state file
// is wherever TIMER_STATE_FILE (tests/timer.test.sh sets it) or XDG_STATE_HOME
// points.
Scope {
  id: smoke
  property int failures: 0
  readonly property real base: new Date(2026, 0, 15, 14, 55, 0).getTime()
  property real fakeNow: base
  property bool dnd: false
  property var launched: []
  property var fileAtFirstLaunch: null

  // Items need a visible parent, or Qt reports them invisible whatever their
  // own binding says (the same reason BatterySmoke has one).
  Item { id: host; visible: true; TimerIcon { id: icon; screenName: "smoke" } }
  TimerPanelContent { id: content }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  // A fresh FileView per read: reload() on a blocking one is not synchronous.
  function savedText() {
    const reader = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', smoke)
    reader.path = TimerState.stateFilePath
    const text = reader.text()
    reader.destroy()
    return text
  }
  function savedState() { try { return JSON.parse(savedText()) } catch (error) { return null } }
  function advance(ms) { smoke.fakeNow += ms; TimerState.tick() }
  function alerts() { return smoke.launched.filter(command => command[0] === "notify-send").length }

  // Qt.quit() is lost if it fires before the shell finishes loading.
  Timer { interval: 1; running: true; onTriggered: smoke.main() }

  function main() {
    TimerState.clock = () => smoke.fakeNow
    TimerState.isDnd = () => smoke.dnd
    TimerState.launch = command => {
      if (smoke.launched.length === 0) smoke.fileAtFirstLaunch = smoke.savedState()
      smoke.launched = smoke.launched.concat([command])
    }
    TimerState.restoreFrom("")
    run()
    console.log(smoke.failures === 0 ? "ok: timer smoke" : "FAIL: " + smoke.failures + " timer smoke check(s) failed")
    Qt.quit()
  }

  function run() {
    check("starts idle with no pill", TimerState.phase === "idle" && !icon.visible)
    check("the idle tick is off", !TimerState.ticking)
    check("the shipped presets load", JSON.stringify(content.presets) === "[5,10,25,60]")
    check("the hint counts the presets", content.hintText === "1–4 pick a preset · Enter start · Esc close")
    check("the panel shows the idle view", !content.running && content.liveText === "")

    content.inputText = "abc"
    check("invalid text shows its error", content.liveText === "try 90s, 7m30s, 1h or 7:30")
    check("Enter on invalid text starts nothing", !content.submit() && TimerState.phase === "idle")
    content.inputText = "0"
    check("zero shows an error", content.liveText === "the time has to be longer than zero")
    content.inputText = "25h"
    check("over 24 h shows an error", content.liveText === "24 hours is the longest")
    content.inputText = ""

    TimerState.panelVisible = true
    check("preset 2 starts", content.pickPreset(1))
    check("a preset starts a 10 minute timer", TimerState.phase === "running" && TimerState.current.durationMs === 600000
          && TimerState.current.endsAt === smoke.fakeNow + 600000)
    check("starting closes the panel", !TimerState.panelVisible)
    check("a missing preset does nothing", !content.pickPreset(4) && !content.pickPreset(-1))
    check("the pill shows the countdown", icon.visible && !icon.finished && icon.label === "10:00")
    check("the tick runs while a timer runs", TimerState.ticking)
    check("the panel shows the running view", content.running && content.runningLabel === "10 min timer")
    check("start is saved", smoke.savedState().phase === "running" && smoke.savedState().endsAt === TimerState.current.endsAt)
    smoke.advance(2000)
    check("the pill counts down", icon.label === "9:58")
    check("the bar fills as time passes", Math.abs(TimerState.progress - 2 / 600) < 1e-9)
    smoke.advance(400)
    check("the readout rounds up to the second", icon.label === "9:58")

    TimerState.addMinute()
    check("+1 min extends the timer", TimerState.current.durationMs === 660000 && icon.label === "10:58")
    check("+1 min is saved", smoke.savedState().durationMs === 660000)
    TimerState.cancel()
    check("cancel goes idle", TimerState.phase === "idle" && !icon.visible && !TimerState.ticking)
    check("cancel is saved", smoke.savedState().phase === "idle")
    TimerState.addMinute()
    check("+1 min does nothing while idle", TimerState.phase === "idle")

    smoke.fakeNow = smoke.base
    content.inputText = "7m30s"
    check("typed text previews its length and end time", content.liveText === "→ 7 min 30 s · rings at 15:02:30")
    check("Enter starts the typed time", content.submit() && TimerState.current.durationMs === 450000 && icon.label === "7:30")
    check("no alert has fired yet", smoke.launched.length === 0)

    smoke.advance(450000 - 1)
    check("one millisecond early is still running", TimerState.phase === "running")
    smoke.advance(1)
    check("the end time finishes it", TimerState.phase === "done" && TimerState.current.notified)
    check("exactly one notification", smoke.alerts() === 1)
    check("exactly one chime", smoke.launched.length === 2)
    check("the notification names the timer",
          JSON.stringify(smoke.launched[0]) === JSON.stringify(["notify-send", "-a", "Timer", "Time is up", "7 min 30 s timer finished"]))
    check("the notification is not an urgent one", smoke.launched[0].indexOf("-u") < 0 && smoke.launched[0].indexOf("-h") < 0)
    check("the chime plays the configured sound",
          JSON.stringify(smoke.launched[1]) === JSON.stringify(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]))
    check("done was saved before the alert ran", smoke.fileAtFirstLaunch !== null && smoke.fileAtFirstLaunch.phase === "done")
    check("the pill reads Done", icon.visible && icon.finished && icon.label === "Done")
    check("the tick stops when it is done", !TimerState.ticking)
    smoke.advance(5000)
    check("later ticks never alert again", smoke.launched.length === 2)
    check("the panel shows the idle view when done", !content.running)

    TimerState.dismiss()
    check("dismiss goes idle", TimerState.phase === "idle" && !icon.visible && smoke.savedState().phase === "idle")
    check("dismiss does not alert", smoke.launched.length === 2)

    smoke.launched = []
    smoke.dnd = true
    check("a 5 minute timer starts", TimerState.startText("5").ms === 300000)
    smoke.advance(300000)
    check("do not disturb: no notification and no chime", smoke.launched.length === 0)
    check("do not disturb: the pill still says Done", TimerState.phase === "done" && icon.visible && icon.label === "Done")
    smoke.dnd = false

    TimerState.togglePanel("smoke")
    check("opening the panel dismisses a finished timer", TimerState.phase === "idle" && TimerState.panelVisible
          && TimerState.panelScreen === "smoke")
    TimerState.togglePanel("smoke")
    check("the key again closes the panel", !TimerState.panelVisible)
    TimerState.togglePanel("")
    check("an unknown screen opens nothing", !TimerState.panelVisible)

    const bad = TimerState.startText("later")
    check("startText reports a parse error and starts nothing", bad.error !== undefined && TimerState.phase === "idle")

    smoke.launched = []
    const past = JSON.stringify({ version: 1, phase: "running", durationMs: 600000, endsAt: smoke.fakeNow - 1000, label: "", notified: false })
    TimerState.restoreFrom(past)
    check("a past-due running timer restores as done", TimerState.phase === "done" && icon.label === "Done")
    check("and alerts once", smoke.alerts() === 1)
    check("and saves that it did", smoke.savedState().phase === "done" && smoke.savedState().notified === true)
    TimerState.restoreFrom(smoke.savedText())
    check("restoring the saved done timer never alerts again", smoke.alerts() === 1)
    TimerState.dismiss()

    TimerState.startText("90s")
    const running = smoke.savedText()
    smoke.advance(30000)
    TimerState.restoreFrom(running)
    check("a timer with time left restores running", TimerState.phase === "running" && icon.label === "1:00" && smoke.alerts() === 1)
    TimerState.restoreFrom("{ not json")
    check("a bad file restores idle", TimerState.phase === "idle" && !icon.visible)
    TimerState.cancel()
  }
}
