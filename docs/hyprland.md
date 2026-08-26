# Hyprland configuration

## Entry point and variables

The entry point is `hypr/.config/hypr/hyprland.lua`; its source graph is shown in
[Architecture](./architecture.md#active-hyprland-source-graph).

The retained `hyprland.conf` and its sourced modules are a transition fallback
for the session that was running during migration. They are not the preferred
entry point for a fresh login.

`hypr/.config/hypr/conf/variables.lua` defines:

| Variable | Value | Use |
| --- | --- | --- |
| `scripts_dir` | `/home/liam/.config/hypr/scripts` | script bindings and startup |
| `terminal` | `kitty` | terminal bindings |
| `browser` | `brave` | declared browser preference |
| `file_manager` | `nautilus` | file-manager bindings |
| `disks` | `gnome-disks` | disk utility binding |

The current browser binding invokes `brave` literally rather than using
`browser`. Changing the variable alone therefore does not change `SUPER+W`.

## Monitors

The main file supplies a fallback:

```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
```

and then sources the more specific `monitors.lua`. A startup watcher selects one
of three hardware profiles and updates both monitor and workspace files. See
[Monitors and workspaces](./monitors.md).

## Input and gestures

The active settings in `hyprland.lua` are:

- US keyboard layout.
- Pointer focus follows the mouse (`follow_mouse = 1`).
- Global pointer sensitivity is `0`.
- Touchpad natural scrolling is disabled.
- A three-finger horizontal gesture changes workspace.
- The example device named `epic-mouse-v1` has sensitivity `-0.5`; it only has an
  effect when a device with that Hyprland name exists.

No repository setting establishes tap-to-click, repeat rate, keyboard variant,
or keyboard options. Their resulting behavior could not be determined from the
current repository alone.

The configuration exports cursor sizes of 24 for both XCursor and Hyprcursor.
No cursor theme is selected in the tracked Hyprland files.

## Appearance

Hyprland appearance is sourced from generated
`hypr/.config/hypr/conf/decorations.lua`. Its durable inputs are the theme
palettes and `style` section in
`hypr/.config/hypr/themes/<theme>/colors.toml`.

Border width, rounding, opacity, shadow, and blur values are rendered from the
selected palette. The generator template keeps inner/outer/float gaps at 6/12/12
across themes so a palette switch does not reflow window placement. Other values
can change whenever a different palette is generated; see [Themes](./themes.md).

There are no separately tracked animation, layout, or `misc` blocks. Resulting
values not emitted by the current generated decoration file could not be
determined from the repository and should not be assumed to be intentional
Hyprland defaults.

## Startup behavior

`hypr/.config/hypr/conf/autostart.lua` registers the active commands on
`hyprland.start`. `hl.exec_cmd()` starts them asynchronously, so this is a
functional grouping rather than a guaranteed serial timeline.

| Program / script | Purpose |
| --- | --- |
| `hypr-wallpaper-picker restore` | restore wallpaper state and start Hyprpaper |
| two `wl-paste --watch` processes | capture text and image clipboard changes |
| `quickshell` | active bar, panels, notifications, clipboard UI, OSD |
| `hypridle` | lock, display power, and suspend policy |
| `ascii-screensaver schedule` | presentation-only idle listener; no lock or power actions |
| `desktop-mode daemon` | session mode expiry and backend reconciliation |
| `spotify-notify.sh` | player change notifications |
| `auto-monitor-profile.sh --watch` | select/apply the connected-output profile |
| `brave` | browser, assigned to workspace 2 |
| `spotify` | music application, assigned to workspace 9 |
| `virt-manager` | VM manager, assigned to workspace 6 |
| `hermes` | application assigned to workspace 6 |
| `obsidian` | notes application, assigned to workspace 3 |
| `kitty` | terminal, assigned to workspace 1 |
| `udiskie --automount --notify --no-tray` | removable-media automounting |
| `hyprsunset` | color-temperature service |

SwayNC and Noctalia are not started by this module.

## Window rules

Rules are defined in `hypr/.config/hypr/conf/window_rules.lua`.

### General floating behavior

- Windows reporting themselves as modal float and are centered.
- Every floating window receives 10-pixel rounding, a 2-pixel border, and dims
  the content behind it.
- Fullscreen windows use the configured gradient border.

### Application opacity and workspace assignment

| Match | Behavior |
| --- | --- |
| Brave browser | opacity 1.0 active, 0.95 inactive, 1.0 fullscreen; workspace 2 |
| Obsidian | workspace 3 |
| virt-manager | workspace 6 |
| `org.kde.neochat` | workspace 7 |
| Spotify | workspace 9 |

## Workspace behavior

Hyprland defines numbered workspace bindings for 1–15: `SUPER+1` through
`SUPER+0` select workspaces 1–10, and `SUPER+ALT+1` through `SUPER+ALT+5`
select workspaces 11–15. The monitor profile maps all workspaces 1–15 to outputs.
See [Keybindings](./keybindings.md#workspaces) and
[Monitors](./monitors.md#workspace-mapping).

## Lock, idle, and power behavior

`hypr/.config/hypr/hypridle.conf` configures:

| Idle time | Action |
| --- | --- |
| 660 seconds | lock the session unless selective stay-awake is active |
| 1,200 seconds | turn displays off with DPMS; restore them on activity |
| 1,800 seconds | suspend the system through `systemctl` |

Before system sleep it locks the login session; after resume it turns displays
back on. `inhibit_sleep = 3` is also set. `SUPER+L` provides immediate manual
locking.

The separate `ascii-screensaver schedule` autostart command creates a runtime
Hypridle configuration containing only the screensaver timeout and input-resume
stop action. Its default 300-second delay and user-controlled enabled state are
documented in [ASCII screensaver](./screensaver.md). It does not source or alter
the primary policy above.

Both lock and screensaver listeners use five-second conditional retries while
stay-awake is active. The condition is not attached to DPMS, suspend, or
before-sleep locking. Missing or malformed mode configuration permits locking
rather than weakening the security boundary. See
[Desktop modes](./desktop-modes.md).

The active lock wrapper is `hypr/.config/hypr/hyprlock.conf`. It sources generated
colors and `layouts/hyprlock.conf` from the `hyprlock` package, which provides a
clock/date, wallpaper background, greeting, and password field. Alternate layouts
and music helpers are tracked but not sourced by the current file.

## Wallpaper and night light

`hypr/.config/hypr/hyprpaper.conf` enables IPC and disables the splash; it does
not preload a fixed wallpaper. The theme tool or wallpaper picker supplies the
image.

Hyprsunset starts with an identity configuration. `SUPER+CTRL+N` runs
`desktop-mode toggle night-light`, switching between 1000 K and 6500 K through
the same observed-state backend used by Quickshell. The retained
`night-light.sh` path is a compatibility wrapper.
