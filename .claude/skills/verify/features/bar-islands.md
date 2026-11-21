# Bar islands

The bar is a transparent strip along the top of each screen. Everything
visible on it is an island: a rounded capsule sized to its modules.
`Bar.qml` places four of them:
- the **left island** with the workspaces module;
- the **centre group** (`BarCenter`): the clock and weather, which open the
  dashboard, with the record, updates and mode indicators to their left;
- the **tray island**: system tray, pinned apps, Windows VM, Bluetooth,
  network, audio and battery;
- a round **power island**, whose button opens the power popup.

## Sub-features

- `island-chrome`: capsule shape, height, spacing, and the scale curve for narrow or rotated monitors.
- `island-left-workspaces`: workspace cells and their occupied and active states.
- `island-centre`: the clock stays centred while indicators grow to its left, with no process spawns or polling.
- `island-tray-modules`: the system tray, app launcher, Bluetooth, network, audio and battery icons.
- `island-power`: the power button and its popup.

## How to get to it (user POV)

- Look at the top of any screen. The bar is always there.
- Click a workspace cell, a tray icon, the clock, or the power button.
- Rotate a monitor to get a narrow bar.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `dbus-run-session` is installed. `BarCenter` and the tray need a session bus.

- **Check the island chrome.** Run
  `$V smoke OmakubBar --expect 'omakub bar smoke: ok' --timeout 5`. Expect
  PASS, and `log.txt` holding `assertions: 10`: stadium shape, theme height,
  sized to modules, a round power island, the strip clearing the islands, and
  the four scale-curve checks. Exit code 124 is normal, because the smoke
  never quits.
- **Check the left island.** Run
  `$V smoke Workspaces --expect 'ok: workspaces smoke'`. Expect PASS with 10
  ok lines. The workspace logic also has
  `$V run --label workspaces-test -- bash tests/workspaces-module.test.sh`.
- **Check the centre group.** Run
  `$V smoke BarCenter --expect 'bar centre smoke: ok'`. Expect PASS with 10
  ok lines. Then run
  `$V run --label bar-center-test -- bash tests/bar-center.test.sh`. It adds
  the static checks: no hard-coded colours, and no `Process` or polling in
  `BarCenter.qml`.
- **Check the tray island's modules, one smoke each:**
  - `$V smoke SystemTray --expect 'ok: system tray smoke'` (12 ok)
  - `$V smoke AppLauncher --expect 'ok: App launcher clicks'` (4 ok)
  - `$V smoke Bluetooth --expect 'ok: BluetoothState logic'` (42 ok)
  - `$V smoke Network --expect 'ok: NetworkState logic'` (15 ok)
  - `$V smoke AudioPanel --expect 'ok: AudioPanel fixture rendering'` (13 ok)
  - battery: the whole [Battery panel](./battery-panel.md) journey.

  Each must PASS.
- **Check the modules that only have load-only smokes.** Run
  `$V smoke WindowsVm`, `$V smoke Updates` and `$V smoke ClockWidget`. Each
  gives LOADED: it compiled with no QML errors, and nothing more is proven.
  Report them as unverified.
- **Check the power island.** No smoke opens `PowerPopup`. Report it as
  unverified, with no headless harness.

## Gotchas

- `Bar.qml` itself can't load headless. Its `PanelWindow` needs Wayland
  layer shell, and its `IpcHandler`s would clash with the user's running
  shell. `OmakubBarSmoke` stands in: it puts the same modules in the same
  `BarIsland` capsules inside a `FloatingWindow`.
- `ModeIndicators` has `ModesSmoke`, which stops with
  `No PanelWindow backend loaded` because it builds `ModesPanel`. It is
  unverified headless. `RecordIcon` has no smoke.
- `OmakubBarSmoke`, `UpdatesSmoke`, `ClockWidgetSmoke` and `WindowsVmSmoke`
  aren't run by any test in `tests/` or CI. A failure in them shows up only
  through this map.
- The tray and network smokes use fake devices. The sandbox hides real
  StatusNotifier items, NetworkManager, BlueZ and PipeWire, so log lines like
  `Failed to connect pipewire context` are expected.
