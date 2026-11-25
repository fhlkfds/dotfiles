# Timer

A countdown timer. A pill left of the bar clock counts down while it runs,
turns red and reads Done when it rings, and a panel under the clock starts,
extends and cancels it. At zero the shell sends a notification and plays a
chime, unless do-not-disturb is on. Then nothing pops up or plays, and the
Done pill is the only sign. One timer runs at a time.

## Sub-features

- `timer-open`: SUPER+ALT+Z, the bar pill or lmenu opens the panel; Escape, a click outside, the key again and SUPER+Q close it.
- `timer-start`: a preset chip or number key 1 to 4, or a typed time (`7m30s`, `90s`, `1h`, `10`, `7:30`) with Enter. The live line shows the length and the clock time it rings.
- `timer-pill`: accent pill with the remaining time while running, pulsing critical pill reading Done once it rings. Click: panel while running, dismiss when done.
- `timer-adjust`: `+1 min` and `Cancel` in the running panel.
- `timer-alert`: one notification and one chime at zero. None under do-not-disturb.
- `timer-persist`: the end time is saved to `$XDG_STATE_HOME/quickshell/timer.json`. A timer past due at restore comes back Done and rings once.
- `timer-lmenu`: Trigger, Timer: 5, 10, 25 and 60 minutes, and Custom time….

## How to get to it (user POV)

- Press SUPER+ALT+Z. Pick a preset, or type a time and press Enter.
- Look left of the clock for the pill. Click it for the panel while it runs, or to clear Done.
- Open lmenu (SUPER+SHIFT+A), Trigger, Timer. The preset rows run
  `quickshell ipc call timer start 10m`. Custom time… opens the panel.
- Scripts: `quickshell ipc call timer toggle|start <time>|cancel`.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `quickshell` and `node` are installed. `doctor` notes any that are missing.

- **Walk the whole journey and picture it.** Run `$V shot timer`. Expect
  `PASS timer: typed 7m30s, started, counted down, rang and was dismissed; 6 PNGs`.
  `checks.txt` must hold, in order, `ok   the key opens the panel on this
  screen`, `ok   typing fills the box`, `ok   Enter starts the timer`, `ok
  clicking the running pill opens the panel`, `ok   the countdown ticks`, `ok
  time is up: the pill reads Done`, `ok   exactly one notification and one
  chime` and `ok   clicking the Done pill dismisses it`, plus these text lines:
  - `text typed: 7m30s | → 7 min 30 s · rings at 15:02:30`
  - `text running pill: 7:30`
  - `text alert: notify-send -a Timer Time is up 7 min 30 s timer finished ; pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`

  The folder holds `timer-idle-bar.png`, `timer-panel.png`, `timer-typed.png`,
  `timer-running-bar.png`, `timer-running-panel.png` and `timer-done-bar.png`.
  Open them. The panel sits under the clock. The running pill is the accent
  colour with `7:30`. The Done pill is critical red.
- **Watch it as frames.** Run `$V shot timer --env TIMER_SHOT_FRAMES=1`. It adds
  `frames/frame-0001.png` onward, ten per second of story, from the idle bar
  to the dismissed pill (about 156 frames, 20 s). Step through them to see the
  typing, the countdown, the pulsing Done pill and the dismissal.
- **Check every transition.** Run `$V smoke Timer --expect 'ok: timer smoke'`.
  Expect PASS with 55 ok lines. It covers a preset start, a typed start, parse
  errors, `+1 min`, cancel, the tick to Done firing exactly one alert, do-not-disturb
  firing none while the pill still says Done, dismiss, and restoring a past-due timer.
- **Run the repo's checks.** `$V run --label timer-test -- bash tests/timer.test.sh`
  prints `ok: timer logic` and `ok: TimerSmoke.qml (… assertions)`.
- **See the menu rows.** `$V lmenu trigger.timer` lists the five rows and their
  `quickshell ipc call timer …` actions. `$V lmenu trigger --display` shows the
  Timer row with its submenu mark.
- **See the key in the palette.** The `timer` rank rule must sit in both
  ladders, `KeybindsState.qml` and `keybinds-collector`. Run
  `python3 tests/keybinds-collector.test.py` on the host: it compares the
  ladders and checks that every description in `keybindings.lua` ranks. Under
  `$V run` its last step stops with `No PanelWindow backend loaded`, so report
  that step as unverified there.

## Gotchas

- The shot and the smoke fake the clock and the launcher. No notification or
  sound happens, so the real `notify-send` and `pw-play` calls are unverified
  here. `calls.log` holds only the shot's `curl` stand-in call from the weather
  state.
- The panel is a layer-shell `PanelWindow`, which cannot load headless
  (`No PanelWindow backend loaded`). The shot places the real
  `TimerPanelContent` under the real clock instead, so `TimerPanel.qml`, the
  `GlobalShortcut` and `SUPER+Q` stay unverified without a Wayland session.
- Number keys pick a preset only while the box is empty. The shot checks that
  `2` starts 10 minutes and that `01h` types as a time. A time starting with
  1 to 4 needs a leading 0.
- The clock in the pictures is the machine's real time. Only the timer's own
  clock is fake, so `rings at 15:02:30` is stable and the bar clock is not.
- `$V shot` copies `quickshell/.config/quickshell/` when the shot runs. Re-run
  it after every edit.
