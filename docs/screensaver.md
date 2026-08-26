# ASCII screensaver

The `screensaver/` Stow package is an original terminal presentation component.
It draws animated rain, orbital traces, sparse signal noise, an editable logo,
and changing status text. It has no Omarchy dependency, branding, commands,
configuration, or assets.

## Responsibility boundaries

These are deliberately separate controls:

| Concern | Owner | Meaning |
| --- | --- | --- |
| Manual launch | `ascii-screensaver start` | show the scene immediately, regardless of automatic state |
| Automatic activation | `ascii-screensaver schedule` + `auto enable/disable` | permit or prevent startup after `idle_seconds` |
| Locking | primary `hypr/.config/hypr/hypridle.conf` | security boundary and Hyprlock timer, currently 660 seconds |
| Stay-awake | `desktop-mode stay-awake` condition | defers automatic screensaver and idle lock only |
| DPMS/suspend | primary Hypridle policy | unaffected at 1,200/1,800 seconds |
| Indicators | Quickshell modes UI | observed automatic-disabled/error state only |

`lock_handoff_seconds` is a validated documentation/diagnostic value. It reports
how long the scene is expected to be visible before the independently configured
lock timer, but it never invokes or configures a lock. Keep it synchronized with
the primary Hypridle lock timeout when changing that separate policy.

## Setup

From the repository root, deploy the package and Hyprland source package when
you choose to apply the change:

```bash
stow screensaver modes
stow hypr
```

No Stow command, Hyprland reload, service restart, package installation, or
system-wide write is performed by the implementation. A new login starts the
scheduler through Hyprland autostart. To start it in the current session without
reloading Hyprland:

```bash
ascii-screensaver schedule
```

Run that command only once; a runtime lock rejects duplicates.

## Usage

```bash
# Manual; starts now on every selected active monitor.
ascii-screensaver start

# Limit a manual run to named active outputs.
ascii-screensaver start --monitor DP-1 --monitor HDMI-A-1

# Inspect without launching terminals or changing compositor state.
ascii-screensaver start --dry-run
ascii-screensaver schedule --dry-run
ascii-screensaver doctor

# Automatic activation is persistent user-local state.
ascii-screensaver auto status
ascii-screensaver auto disable
ascii-screensaver auto enable

# Reload the dedicated scheduler after editing config.
ascii-screensaver auto reload

# Stop only the screensaver; locking and power policy continue unchanged.
ascii-screensaver stop

# Preview in the current terminal. Any key or reported mouse movement exits.
ascii-screensaver render
ascii-screensaver render --plain --frames 3
```

Runtime files live under `$XDG_RUNTIME_DIR/ascii-screensaver`. The persistent
automatic override lives under `$XDG_STATE_HOME/ascii-screensaver`; deleting
`automatic.json` restores `automatic_enabled` from the tracked configuration.
Both locations are user-local and created with private directory permissions.

## Configuration

Edit `screensaver/.config/ascii-screensaver/config.toml`, then run
`ascii-screensaver auto reload` after deploying it. `ASCII_SCREENSAVER_CONFIG`
can select a different file for testing or a machine-local override.

| Setting | Purpose |
| --- | --- |
| `automatic_enabled` | default automatic state when no state override exists |
| `idle_seconds` | inactivity before the dedicated scheduler launches the scene |
| `lock_handoff_seconds` | separate lock threshold reference; `0` means unspecified |
| `terminal` | `auto`, `kitty`, `foot`, `ghostty`, `alacritty`, or single-output `plain` |
| `[terminal_args]` | argument arrays inserted without shell evaluation |
| `frame_delay`, `effect_frames` | frame pacing and effect rotation interval |
| `seed` | optional integer for reproducible effect selection/output |
| `ascii_width`, `ascii_height` | maximum renderer/conversion dimensions |
| `glyphs` | printable effect density characters |
| `colors`, `ansi` | validated `#RRGGBB` palette and ANSI enable switch |
| `logo_path` | editable UTF-8 text asset; `~` and environment variables expand |
| `monitor_selection` | empty for all active monitors, otherwise exact output names |
| `[monitor."NAME"]` | optional `enabled` and terminal override per monitor |

Numeric values, monitor identifiers, terminal names, colors, arrays, paths, and
unknown keys are validated before a window or child scheduler is launched.
Logo control characters are replaced, and terminal commands are argument arrays
rather than evaluated shell strings.

## Terminals and displays

Automatic terminal selection is Kitty, Foot, Ghostty, then Alacritty. Each
receives its native app-id/title and fullscreen startup option. On Hyprland, the
coordinator identifies each new window by its exact address, focuses it, moves
it to the assigned monitor, and applies true compositor fullscreen so bars and
gaps are covered. If one window closes or its renderer receives input, the
coordinator terminates every sibling so a partial screensaver is not left behind.

Kitty 0.48.2 was detected locally and its fullscreen/app-id options were checked
from the installed help. Foot, Ghostty, and Alacritty command generation is
fixture-tested but those executables were not installed for live verification.

The renderer uses UTF-8, true-color ANSI, the alternate screen, a hidden cursor,
and xterm SGR any-motion mouse reporting. It restores every mode on key/mouse
exit, normal exit, SIGINT, SIGTERM, or SIGHUP. The scheduler's Hypridle
`on-resume` stop action is the compositor-level fallback for automatic sessions,
so activity still closes all windows if a terminal does not deliver mouse motion.

`plain` is the no-terminal fallback and can cover only one selected output; it
cannot provide compositor-directed multi-monitor fullscreen windows. On X11,
the terminal fullscreen flags remain usable, but Hyprland-specific exact monitor
assignment is unavailable. Use `--monitor` plus window-manager rules or select a
Wayland/Hyprland session. Unsupported/missing terminals and monitor queries fail
with an explicit error rather than silently launching an unrelated program.

## Logo and image conversion

Edit `screensaver/.config/ascii-screensaver/logo.txt` directly; renderer logic
does not contain the artwork. High-contrast silhouettes and transparent logos
convert much better than photographs.

ImageMagick provides a reproducible offline PNG/SVG pipeline:

```bash
ascii-screensaver convert logo.svg converted.txt \
  --mode blocks --width 72 --height 24 --threshold 96

ascii-screensaver convert logo.png converted-braille.txt \
  --mode braille --width 72 --height 24 --threshold 128 --invert
```

`blocks` maps grayscale intensity to the configured-style density ramp;
`braille` samples a deterministic 2×4 dot grid per output character. Width,
height, threshold, inversion, and ImageMagick's fixed Lanczos resize are explicit.
The command refuses to overwrite an output. `--force` first creates a timestamped
`.bak.YYYYMMDD-HHMMSS` copy, then atomically replaces it. Copy the chosen result
into `logo.txt` or point `logo_path` at it.

## Diagnostics, troubleshooting, and recovery

Start with:

```bash
ascii-screensaver doctor
ascii-screensaver start --dry-run
ascii-screensaver schedule --dry-run
```

The first reports validated timing and detected commands. The launch dry-run
prints selected terminal command arrays for every monitor. The scheduler dry-run
prints its one-listener generated config and never starts Hypridle.

The listener permits launch when `desktop-mode` is absent. When installed, its
condition blocks automatic launch while stay-awake is active or automatic
screensaver behavior is disabled, retrying every five seconds while still idle.

- If no window appears, check that the selected terminal and `hyprctl` are on
  `PATH`, then inspect the dry-run monitor names.
- If an output was renamed or unplugged, remove it from `monitor_selection` or
  use an active name from `hyprctl -j monitors`.
- If configuration changed, run `ascii-screensaver auto reload`; a malformed
  file is rejected before replacing the running scheduler.
- If a terminal crashes, the coordinator closes the remaining terminal children.
- If startup partially fails, launched children and PID files are cleaned in the
  same exit path.
- To recover immediately, run `ascii-screensaver stop`. If necessary, terminate
  the user-owned scheduler process and remove only
  `$XDG_RUNTIME_DIR/ascii-screensaver`; never remove the broad runtime directory.
- To roll back, remove the two screensaver scheduler autostart lines and unstow
  the `screensaver` package. The original lock, DPMS, and suspend policy remains
  intact throughout.

The component performs no network access, telemetry, root operation, package
installation, authentication, lock mutation, power mutation, or destructive
system-wide change.
