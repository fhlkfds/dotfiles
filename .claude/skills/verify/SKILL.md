---
name: verify
description: Drive this Arch + Hyprland dotfiles repo's real surfaces headless and capture proof. Covers Quickshell bar islands, modules and panels (offscreen smokes and PNG shots), the lmenu tree (--dry-run), scripts (--dry-run and env-override fixtures), the keybind palette's collector, and theme palettes (validate). Use it to prove that a change to the shell, a menu, a script, a keybinding or a theme works. Use it when you need evidence for a PR, or when you need to see what a dry-run really does. It never touches the live desktop.
---

# Verify the dotfiles

The thing a user touches here is a desktop: a Quickshell bar with islands,
panels that open from it, the `lmenu` launcher, keybindings, and themes. You
cannot drive it live. Agents have no Hyprland session of their own, and the
machine you run on may be running the user's. AGENTS.md also forbids GNU
Stow, `theme set`, `shell-reload.sh` and Hyprland reloads without the user's
say-so. So every check runs the real code headless, inside a sandbox, through
one helper:

    V=.claude/skills/verify/bin/verify     # from the repo root; run "$V --help"

Each command runs inside bubblewrap (a lightweight sandbox). Inside it:

- Only what programs need shows through, read-only: `/usr`, `/etc`, `/opt`,
  `/sys`, the pacman database, the font cache, the repo and its git
  directory. The run's own folder is the one writable place. The rest of
  the host, the real home included, is hidden. A read-only mount still lets
  a program connect to a socket in it, so hiding is the guard.
- `/dev` and `/run` are private. `/run/user/$UID` is the run's own folder:
  no Wayland, Hyprland, PipeWire or session D-Bus socket.
- IPC (shared memory, message queues), network and process IDs are separate
  from the host.
- The system bus, the docker socket and the network are gone.
- `HOME` and `XDG_*` point into a throwaway tree.
- The user's real environment variables `WAYLAND_DISPLAY`,
  `HYPRLAND_INSTANCE_SIGNATURE`, `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` are
  removed. A private session bus and `QT_QPA_PLATFORM=offscreen` take their place.

Each command also runs in its own PID namespace (its own set of process IDs),
so when it exits, everything it started dies with it.

The feature map in [features/README.md](features/README.md) is the source of
journeys. Read it before you drive a feature. When the map lists more than
one entry point, a proof covers all of them.

## Launch

    $V launch                    # or: $V launch --palette catppuccin-latte

This creates a run under `${XDG_STATE_HOME:-~/.local/state}/dotfiles-verify/<run-id>/`.
Override the location with `VERIFY_ROOT`, which must not be under `/tmp`. The
run starts from nothing:

- `sandbox/home/`: an empty home. The only seeded file is
  `.config/hypr/themes/.active/theme.json`, the palette `Theme.qml` reads.
  It is rendered by the generator's own `themelib.render`. Nothing is
  installed or reloaded.
- `sandbox/home/.local/bin/`: every `<package>/.local/bin/*` from **this
  checkout**, linked in. Code that calls `$HOME/.local/bin/theme` runs the
  worktree copy, not the deployed one.
- `sandbox/bin/`: stand-ins (stubs) placed first on `PATH`. Each one appends
  its argv to the command's `calls.log` and exits. The stubbed commands:
  `hyprctl`, `hyprpm`, `hyprshade`, `notify-send` (exits 0), `gsettings`
  (exits 0), `systemctl`, `loginctl`, `stow`, `swww`, `awww`, `hyprpaper`,
  `pkill`, `killall`, `shell-reload.sh`, `qs`, `playerctl`, `brightnessctl`,
  `powerprofilesctl`, `swaync-client`, `makoctl`, `wpctl`, `pactl`, `nmcli`,
  `bluetoothctl`, `sudo`, `pkexec`, `curl`, `wget`, `xdg-open`,
  `notificationctl`, `wl-copy`, `wl-paste`, `grim`, `slurp`, `hyprlock` and
  `hypridle`. All exit 1 except where noted. `theme` is a gate:
  `list|index|validate|current|mode` pass through to the worktree CLI, and
  `set|next|previous|cycle` are refused.
- `evidence/`: one folder per command, plus `INDEX` with one verdict per line.

It is ready when it prints `ready: run <id>`. Nothing keeps running between
commands. There is no server, so there is nothing to tear down except files.

## Doctor

    $V doctor

This is read-only. Run it first, and again whenever a result looks wrong. It
checks the run: it exists and isn't cleaned up, it came from this checkout,
and `bwrap` is installed. It also notes when HEAD has moved and which
optional tools are missing. A missing `quickshell` is a note, not a failure:
`smoke` and `shot` then refuse with `quickshell is not installed`, while
lmenu, script and theme journeys still drive. Report every Quickshell
journey as unverified on such a machine. `VERIFY_QUICKSHELL` overrides the
binary.

Then it **proves the isolation from inside the sandbox**: `mounts-readonly`,
`home-readonly`, `home-hidden`, `repo-readonly`, `runtime-private`,
`namespaces-private`, `sockets-unreachable` (it tries to connect to every
socket it can see), `system-bus-hidden`, `network-down`, `docker-hidden`,
`hyprctl-stubbed` and `session-env-clear`. Drive only after
`doctor: ok to drive`. A line `note a live Hyprland session is running`
is expected on the user's machine. The sandbox hides that session.

## Drive

Every command prints a verdict line and an evidence summary: exit status, the
stand-ins called, the processes seen, and the file count changed.

| Surface | Command |
| --- | --- |
| A Quickshell smoke | `$V smoke Battery --expect 'ok: Battery widget projections'` runs `quickshell/.config/quickshell/BatterySmoke.qml` |
| A smoke in fixture mode | `$V smoke Battery --env BATTERY_SMOKE_TEST=1 --expect 'ok: BatteryState logic'` |
| A smoke that never quits | `$V smoke OmakubBar --expect 'omakub bar smoke: ok' --timeout 5` |
| A panel, clicked and pictured | `$V shot battery-panel` or `$V shot timer`. Frames and extra env: `$V shot timer --env TIMER_SHOT_FRAMES=1` |
| The dictation pill, pictured | `$V shot voice-caption` (five states, one PNG each) |
| An lmenu view | `$V lmenu style.bar` lists rows with their fields. `$V lmenu style.bar --display` prints the exact lines Rofi would get. No route means the root. |
| A script's dry-run | `$V run --label night-light-dry -- hypr/.config/hypr/scripts/night-light.sh --dry-run on` |
| A fixture test | `$V run --label battery-test -- bash tests/battery-widget.test.sh` |
| A palette | `$V run --label theme-validate -- python3 hypr/.config/hypr/theme/generate.py validate --all` |
| Anything else | `$V run [--label L] [--env K=V]... [--timeout S] -- <cmd> [args]`, with the repo root as the working directory |

Smoke verdicts:

- **PASS** needs the `--expect` line, no `FAIL`, and exit 0. Exit 124 (the
  `--timeout` ran out) also passes when the `--expect` line printed.
- **LOADED** means there was no `--expect` line, no `FAIL`, no QML load
  error, and exit 0. The file compiled, which proves nothing about behaviour.
- **FAIL** is anything else.

Get the expected line from the smoke's own `console.log("ok: ...")` or from
its `tests/*.test.sh`.

How a dry-run proof works: run the dry-run and the real action, each in its
own `$V run`, and compare the evidence. The dry-run's `calls.log` should be
empty, and its `fs-changes.txt` should show no state file. Here is what that
looked like for `night-light.sh`:

- `--dry-run on`: 0 stand-in calls, and `fs-changes.txt` holds only `M tmp`.
- `on`: `hyprctl eval …` appears in `calls.log`, and `fs-changes.txt` gains
  `A home/.local/state/hyprland-desktop/night-light-shader`.

Don't trust a flag's name. Some dry-runs here still reach out:
- `lmenu --dry-run` runs every menu guard for real.
- `keybinds-collector --dry-run` still calls `hyprctl binds -j` when you don't pass `--binds-json`.

## Evidence

Each command writes to `evidence/NN-<label>/`:

| File | Holds |
| --- | --- |
| `command.txt` | argv, extra env, repo path, git rev, dirty-file count |
| `stdout.txt`, `stderr.txt`, `exit-code` | the raw run (`log.txt` merges them for smokes and shots) |
| `calls.log` | every stand-in call: time, name and argv, each argument shell-quoted |
| `processes.txt` | every process seen in the sandbox: `comm` (process name) and argv. A 20 ms `/proc` sampler can miss a process that lives under 20 ms; `calls.log` misses nothing it stands in for. |
| `fs-changes.txt` | `A`/`M`/`D` (added, modified, deleted) per path in the sandbox, before vs after |
| `blocked.txt` | lines showing an attempt to leave the sandbox (read-only file system, network unreachable, …) |
| `verdict.txt` | the verdict line, also appended to `evidence/INDEX` |
| `*.png`, `checks.txt` | shots: images and the harness's `ok`/`FAIL`/`text` lines |

`$V evidence` prints the folder and `INDEX`.

Proof standards:

- **Drive the real path.** Load the real QML file, run the real script and
  the real CLI. The fakes are only the ones that stand in for hardware or the
  compositor: fake UPower devices, fake power profiles, stand-in `hyprctl`.
- **Show the action and the result.** A shot clicks the icon with a synthesized
  mouse event, and `checks.txt` records that the panel opened, what it said,
  and that Escape closed it. A final picture alone is not proof.
- **Check side effects.** Look at `calls.log` and `fs-changes.txt` next to
  stdout, every time.
- **A `skip:` line is not a pass.** Neither is LOADED, and neither is a test
  that ran no assertions. Report each as unverified, with the reason.
- **Say what you couldn't reach.** Report an unreachable path with the
  command you tried and the missing precondition. Don't report it as
  verified through some other path.

## Cleanup

    $V cleanup                   # or: $V cleanup --run <id>

This deletes `sandbox/` and writes `CLEANED`. It keeps `evidence/` and
`run.env`, and the evidence stays at the path above. There are no processes
to kill: each command's PID namespace already took its processes down. Run it
after every attempt, including failed ones. Delete old evidence only when the
user asks.

## Isolation and parallel runs

- **Separate runs are fully isolated.** Agents working in parallel each
  `launch` their own run and pass `--run <id>` (or `VERIFY_RUN=<id>`) on every
  command, because `current` points at the last launch from any agent.
- **One command at a time per run.** Evidence folders are numbered by count.
- **Never drive the live shell.** Never point a command at the real
  `$HOME/.config`, `/run/user/$UID` or `hyprctl`. The live session is the
  user's. Seeing changes live needs `shell-reload.sh`, `theme set` or Stow, and
  each one needs the user's approval first (AGENTS.md "Boundaries").

## Helpers

All three are executable, live in `bin/`, and pass `shellcheck`:

- `bin/verify` is the CLI used above. `--help` lists every command and option.
- `bin/sandbox-exec` is called by `verify`, never directly. It runs as process
  1's child inside the sandbox, samples `/proc` into `processes.txt`, and runs
  the command.
- `bin/sandbox-probe` is called by `verify doctor`. It prints one word for
  each isolation property.

`harness/BatteryPanelShot.qml`, `harness/VoiceCaptionShot.qml` and
`harness/TimerShot.qml` are the shot harnesses. `verify shot` copies
`quickshell/.config/quickshell/` from the working tree into `sandbox/shell/`,
puts the harness beside it, and runs it there. The copy is needed because
Quickshell resolves components and singletons from the loaded file's
directory, and the repo is read-only. To add a shot, write
`harness/<Name>Shot.qml` the same way, then add a case to `cmd_shot`.

## Gotchas

- **Tools must come from the system.** A tool installed under the real home
  (`~/.npm-global`, `~/.local/bin`, pnpm) is hidden. The sandbox's own
  `~/.local/bin` links this checkout's package commands instead. If a test
  needs a tool that only lives in the home, report that, and don't widen
  the sandbox to reach it.
- `quickshell` warns that it was built against an older Qt (6.11.2 against
  6.12.0 when this skill was written). It is a packaging warning, not a test
  failure. Mention it if a smoke crashes.
- **PanelWindow smokes can't run headless.** `KeybindsSmoke`, `ModesSmoke`,
  `LmenuPanelSmoke` and `NightLightPanelSmoke` stop with
  `No PanelWindow backend loaded`: they need a Wayland layer-shell backend.
  They FAIL here. CI waives that error only for
  `tests/keybinds-collector.test.py` (`.github/workflows/ci.yml:133`), and
  the panel tests skip unless `WAYLAND_DISPLAY` is set. Report them as
  unverified.
- **Some smokes never quit.** `OmakubBarSmoke` never calls `Qt.quit()`, so give
  it `--timeout 5`. Its exit code becomes 124, and the expect line decides
  the verdict.
- **Sandbox runtime errors are expected.** Errors like
  `Failed to connect pipewire context` come from the hidden sockets. Smokes
  that depend on those services already use fakes.
- **`calls.log` only sees what the test's own stubs miss.** Fixture tests
  put their own stubs first on `PATH`.
- **A run reads the working tree when each command starts,** not at launch.
  `command.txt` records the rev and dirty-file count for each command.
