# Monitors and workspaces

## Overview

Monitor configuration is dynamic. Hyprland sources:

- `hypr/.config/hypr/monitors.lua`
- `hypr/.config/hypr/workspaces.lua`

At startup, `hypr/.config/hypr/scripts/auto-monitor-profile.sh --watch` examines
the connected outputs every 15 seconds, chooses a profile, copies that profile's
monitor/workspace files over the active files, reloads Hyprland, and redistributes
existing workspaces.

Because these paths are Stowed, profile switching also changes files inside the
Git working tree.

## Profile selection

Profiles live below `hypr/.config/hypr/monitor_profiles/`.

| Profile | Detection | Output arrangement |
| --- | --- | --- |
| `kvm` | DP-5, DP-7, and DP-9 present | eDP-1 disabled; DP-5 horizontal, DP-7 and DP-9 rotated |
| `desktop` | DP-4 and HDMI-A-3 present | DP-4 rotated at left; 2560×1080 HDMI-A-3 to its right; DP-1 disabled |
| `laptop` | fallback | eDP-1 at 2256×1504 |

The exact positions, rates, transforms, and scales are stored in each
`*.monitors.lua`. Output names are kernel/driver-specific and must be adapted for
other hardware.

The watcher prefers `kvm`, then `desktop`, then `laptop`. Its state lives under
`$XDG_RUNTIME_DIR`; `--force` bypasses the unchanged-profile check.

## Workspace mapping

| Profile | Workspaces |
| --- | --- |
| `desktop` | 1–5 on HDMI-A-3; 6–15 on DP-4 |
| `kvm` | 1–5 on DP-5; 6–10 on DP-7; 11–15 on DP-9 |
| `laptop` | 1–15 on eDP-1 |

When applying a profile, the script dispatches `hl.dsp.workspace.move()` for
workspaces 1 through 15. The desktop profile then focuses HDMI-A-3 through
`hl.dsp.focus()`.

The currently tracked active `workspaces.lua` maps all workspaces to eDP-1,
while the currently tracked `monitors.lua` describes the desktop outputs. This
inconsistency should normally be corrected by the startup watcher. If the watcher
cannot run, workspace pinning can target a disabled or absent output.

## Other monitor files

- `hypr/.config/hypr/monitors.lua` and `workspaces.lua` are required by the
  entry point and replaced from the selected profile at runtime.
- The retained, user-modified `monitors.conf` is inactive compatibility output
  from nwg-displays; Hyprland no longer sources it.
- `hypr/.config/hypr/udev/` contains an optional DRM-hotplug dispatcher. It is not
  installed into system directories by Stow.

## Display panel and scale changes

The Quickshell display panel reads outputs through `hyprctl`. It can adjust DDC/CI
brightness through `ddcutil` and offers scale presets. Scale persistence calls
`hypr/.config/hypr/scripts/set-monitor-scale.sh`.

That script validates the output and scale, then updates both the active
`monitors.lua` and `monitor_profiles/desktop.monitors.lua` atomically. It does
not update the laptop or KVM profile. A scale chosen while another profile is
conceptually active can therefore be overwritten at the next profile switch.

## Customizing safely

1. Run `hyprctl monitors all` in the target session to obtain real output names
   and supported modes.
2. Edit the matching files under
   `hypr/.config/hypr/monitor_profiles/`, including the corresponding workspace
   map.
3. If the hardware signature differs, update the profile-detection conditions in
   `auto-monitor-profile.sh`.
4. Validate with `tests/hyprland-lua.test.sh` or use `--dry-run`; normal mode
   rewrites active config and dispatches Hyprland commands.

Do not make durable edits only to active `monitors.lua` or `workspaces.lua`; the
watcher will replace them.
