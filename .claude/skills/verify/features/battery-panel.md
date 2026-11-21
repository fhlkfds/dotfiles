# Battery panel

The battery icon sits at the right end of the bar's tray island. It shows a
glyph and the charge percentage. It fills with the accent colour while
charging, and turns the critical colour at or below the critical threshold
or when the battery is empty. Clicking it opens a panel under the icon with:
- the percentage and a supply line ("On battery · 1 h 30 min left");
- a power tile in W ("coming out" or "going in");
- a charge tile in Wh against full capacity;
- a Saver / Balanced / Performance switch.

Escape closes the panel. Low-battery alerts arrive as critical, persistent
notifications that break through Do Not Disturb.

## Sub-features

- `battery-icon`: glyph, percentage and colour on the bar. Hidden when no battery is present.
- `battery-panel-open`: a click on the icon opens the panel, and Escape closes it.
- `battery-readouts`: percentage, supply line, power tile and charge tile in each supply state.
- `battery-profile`: the profile switch, with Performance offered only when a driver provides it.
- `battery-alerts`: warn / severe / critical notifications at 20 / 10 / 5 % (`battery/config.json`).

## How to get to it (user POV)

- Look at the right end of the tray island on the bar.
- Left-click the battery icon to open the panel. Click again, or press Escape, to close it.
- Pick a profile in the panel. SUPER+SHIFT+B opens the separate power-profile
  menu (`power-profile.sh menu`), which the [lmenu](./lmenu.md) and script
  journeys cover.
- Wait for the charge to cross a threshold while discharging, to get an alert.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `quickshell`, `node` and `dbus-run-session` are installed. `doctor` notes any that are missing.

- **Open the panel by clicking the icon, and picture each state.** Run
  `$V shot battery-panel`. Expect `PASS battery panel: clicked icon opened
  panel, 6 PNGs, Escape closed it`. `checks.txt` must contain
  `ok   clicking the bar icon opens the panel` and `ok   Escape closes the
  panel`, plus these three text lines:
  - `text discharging: 54% | On battery · 1 h 30 min left | 13.3 W coming out | 26.2 Wh of 48.5 Wh full`
  - `text charging: 81% | Charging · 45 min to full | 21.7 W going in | 26.2 Wh of 48.5 Wh full`
  - `text critical: 7% | On battery · 1 h 30 min left | 9.8 W coming out | 26.2 Wh of 48.5 Wh full`

  The folder holds `battery-icon-{discharging,charging,critical}.png` and
  `battery-panel-{discharging,charging,critical}.png`. Open them. In the
  charging icon the accent pill sits behind the glyph. In the critical icon
  the glyph and `7%` are the critical colour. The panel shows the two tiles
  and the three profile buttons.
- **Check every readout state.** Run
  `$V smoke Battery --expect 'ok: Battery widget projections'`. Expect PASS
  with 57 ok lines. It covers charging, discharging, pending charge
  ("Plugged in · Not charging"), full, unknown, an unknown capacity, a zero
  rate, the critical threshold, and an absent battery that hides the icon.
- **Switch the power profile.** Covered by the same smoke: `ok   choosing a
  profile switches it`, `ok   performance can be chosen when offered` and
  `ok   performance is hidden without a driver for it`. They run against a
  fake profile object.
- **Get the alerts.** Run
  `$V smoke Battery --env BATTERY_SMOKE_TEST=1 --expect 'ok: BatteryState logic'`.
  Expect PASS. The smoke must print `ok   fake discharging device queues
  warning` and `ok   fixture mode never starts notification Process`. Check
  that `calls.log` has no `notify-send` line. Then run
  `$V run --label battery-alerts-test -- bash tests/battery-alerts.test.sh`.
  Its stdout must hold `ok: battery threshold alert fixtures (warn:20,
  severe:10, critical:5, warn:20)`.
- **Run the repo's own checks.** Run
  `$V run --label battery-widget-test -- bash tests/battery-widget.test.sh`.
  Expect PASS, and stdout holding `ok: BatterySmoke.qml (… assertions)` and
  `ok: battery widget static checks`. That test also fails on any hard-coded
  hex colour in the Battery QML.

## Gotchas

- Every journey uses a fake UPower device. The system bus is hidden, so the
  machine's real battery is never read. A change to how `BatteryState` binds
  `UPower.displayDevice` is unverified until a live session runs it.
- Picking a profile in the real panel goes to power-profiles-daemon over the
  system bus. Here it changes a fake object. The real switch is unverified,
  and must stay that way: proving it would change the machine's profile.
- The `critical` shot keeps the fake's 5400 s estimate, so it still reads
  "1 h 30 min left". That comes from the fake; the panel's formatting is fine.
- `$V shot` copies `quickshell/.config/quickshell/` when the shot runs.
  Re-run it after every edit; an older PNG shows older code.
- Running `BatterySmoke.qml` without `BATTERY_SMOKE_TEST` never reaches the
  alert engine. Alerts need their own step.
