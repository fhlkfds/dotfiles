# Scripts and command-line tools

## Active Hyprland helpers

These scripts are below `hypr/.config/hypr/scripts/`.

| Script | Invocation | Purpose and effects | Main dependencies |
| --- | --- | --- | --- |
| `Dropterminal.sh` | `SUPER+SHIFT+Return` | toggles a Kitty scratchpad on a special workspace | `hyprctl`, Kitty |
| `KeyHints.sh` | `SUPER+H` | displays a static Rofi shortcut cheat sheet | Rofi |
| `RofiCalc.sh` | `SUPER+SHIFT+C` | selects classic/scientific/technical calculator mode | Rofi, calculator helpers |
| `RofiEmoji.sh` | `SUPER+ALT+E` | searches emoji data and copies the chosen glyph | Rofi, `wl-copy` |
| `universal-clipboard.sh` | `SUPER+C/X/V` | detects terminal classes and sends the correct copy/cut/paste shortcut | `hyprctl` |
| `files-here.sh` | `SUPER+SHIFT+ALT+F` | discovers a focused terminal's current directory and opens Nautilus there | terminal APIs, `hyprctl`, Nautilus |
| `night-light.sh` | `SUPER+CTRL+N` | toggles Hyprsunset between 1000 K and 6500 K; persists transient state and notifies | `hyprctl`, `hyprsunset`, notifications |
| `spotify-notify.sh` | autostart | watches Spotify metadata and sends track-change notifications | `playerctl`, `curl`, notification command |
| `clipboard-store.sh` | `wl-paste --watch` | stores text/images in cliphist | `cliphist` |
| `clipboard-wipe.sh` | manual | clears clipboard/history data | `wl-copy`, `cliphist` |
| `clipboard.sh` | `SUPER+ALT+V` | legacy Rofi cliphist selector | Rofi, `cliphist`, `wl-copy` |

`hypr/.config/hypr/scripts/lib/terminals.sh` is sourced by clipboard and
file-manager helpers. It centralizes terminal-class detection and terminal-specific
current-directory queries; it is not a standalone command.

`LayoutToggle.sh` can switch between master and dwindle layouts, but no current
binding invokes it. The older `Screenshot.sh`, `shot-copy.sh`, `shot-edit.sh`, and
`shot-save.sh` predate the active capture suite and are also not bound. `dnd.sh`
targets the retained SwayNC workflow; active DND uses `notificationctl` instead.

## Capture suite

Entry point: `hypr/.config/hypr/scripts/capture/capture.sh`.

It dispatches to `screenshot.sh`, `record.sh`, `ocr.sh`, `color.sh`, and `menu.sh`.
`select.sh` supplies transform-aware Hyprland geometry and frozen-screen region
selection; `common.sh` and `config.sh` are sourced libraries.

### Operations

| Command | Behavior | Outputs / modifications |
| --- | --- | --- |
| `capture.sh screenshot smart` | drag selects a region; a small click selects the smallest visible window under the pointer | saves/copies a PNG, then offers open/edit actions |
| `capture.sh screenshot window` | captures active window geometry | screenshot directory and clipboard |
| `capture.sh screenshot monitor [--delay=N]` | captures focused output, optionally delayed | screenshot directory and clipboard |
| `capture.sh record toggle` | starts/stops GPU screen recording with optional audio/webcam and post-processing | recording directory; runtime PID/state files |
| `capture.sh ocr` | selects/freeze-captures, preprocesses, runs Tesseract, copies text | Wayland clipboard |
| `capture.sh color` | picks a screen color | Wayland clipboard and notification |
| `capture.sh menu` | interactive operation chooser | depends on selection |
| `capture.sh doctor` | reports command availability | no desktop mutation intended |

### Configuration

Defaults are in `capture/config.sh` and can be overridden through environment
variables before launch.

| Variable | Default / purpose |
| --- | --- |
| `SCREENSHOT_DIR` | `~/Pictures/screenshot` |
| `SCREENSHOT_EDITOR` | `satty` |
| `SCREENRECORD_DIR` | `~/Videos/screenrecording` |
| capture FPS | 60 |
| maximum recording dimensions | 3840×2160 |
| `OCR_LANGS` | `eng` |
| OCR page segmentation / engine / DPI | 6 / 1 / 300 |
| webcam mode | auto, 1280×720, medium preset |
| smart-click threshold | 20 pixels |

Recording uses `gpu-screen-recorder`, selects an available GPU codec, stops it
with a graceful signal, and can use FFmpeg for normalization/trimming. Selection
and screenshots use `hyprctl`, `jq`, `slurp`, `hyprpicker`, and `grim`; OCR also
uses Tesseract and ImageMagick. `satty`, mpv, and `v4l2-ctl` enable editing,
playback, and webcam discovery respectively.

## Monitor tools

### `auto-monitor-profile.sh`

Inputs are live JSON from `hyprctl -j monitors`. It recognizes desktop, KVM, and
laptop output signatures, copies profile files to active `monitors.conf` and
`workspaces.conf`, reloads Hyprland, moves workspaces 1–15, and notifies. `--watch`
polls every 15 seconds and `--force` reapplies an unchanged profile. See
[Monitors](./monitors.md).

This script modifies tracked/Stowed configuration and live compositor state. Test
changes with mocked `hyprctl` and temporary target files rather than invoking it
against an unrelated live session.

### `set-monitor-scale.sh`

Accepts a monitor name and numeric scale, validates both, then atomically updates
the active monitor file and desktop profile. The Quickshell display panel applies
the resulting setting. It does not persist to laptop/KVM profiles.

### Optional udev dispatcher

`hypr/.config/hypr/udev/hyprland-monitor-hotplug.sh` is designed for a root-owned
system path. It discovers a graphical user session and drops privileges before
calling the user profile script. The paired udev rule is not installed by Stow.

## Wallpaper tools

| Tool | Purpose |
| --- | --- |
| `hypr/.local/bin/hypr-wallpaper-picker` | with no arguments, toggles the Quickshell panel; subcommands list/search local and Wallhaven images, cache previews, and download/validate/apply images |
| `WallpaperSwitch.sh` | retained older image/video picker using Hyprpaper/mpvpaper and autostart edits |
| `WallpaperEffects.sh` | retained effect helper; not currently bound |

The active tool depends on Bash, `curl`, `jq`, ImageMagick, Hyprpaper,
Hyprland IPC, and desktop notifications. It honors `HYPR_WALLPAPER_DIR` and
`HYPR_WALLPAPER_RUNTIME_DIR`.

## Theme tools

| Tool | Purpose |
| --- | --- |
| `hypr/.local/bin/theme` | convenience launcher for the theme CLI |
| `hypr/.config/hypr/theme/generate.py` | render all component outputs atomically from `colors.toml` |

Selection can update the wallpaper and live applications as well as files. See
[Themes](./themes.md).

## Notification and web-app tools

| Tool | Purpose and state |
| --- | --- |
| `hypr/.local/bin/notificationctl` | IPC client for dismiss, DND, action, history, and status operations against Quickshell |
| `hypr/.local/bin/webapp` | create/remove browser-style web application launchers |
| `hypr/.local/bin/webapp-launch` | launch a stored web app with the configured browser profile/options |

The Quickshell notification service owns state; the helper does not implement a
second notification daemon. The web-app tools write user application data and are
surfaced by `SUPER+SHIFT+A`.

## Browser native tools

| Tool | Input | Output / side effects |
| --- | --- | --- |
| `browser/.local/bin/chromium-copy-url-host` | length-framed native JSON with URL | Wayland clipboard and success/error notification |
| `browser/.local/bin/chromium-ytdlp-host` | length-framed native JSON or `--download URL` worker mode | video file, progress OSD, thumbnail, completion/failure notification |
| `browser/.local/bin/chromium-repair-download-video-shortcut` | browser profile and optional `--apply` | diagnostic report or repaired Chromium Preferences/command state |

The repair tool is intentionally a dry run unless `--apply` is supplied, and it
refuses unsafe live-profile editing when the browser is running. Browser fixture
coverage is in `tests/browser-native-tools.test.sh`.

## Waybar scripts

These are below `waybar/.config/waybar/scripts/` and matter only when the retained
Waybar configuration is used.

| Script | Purpose |
| --- | --- |
| `power-menu.sh` | launcher-neutral lock/logout/suspend/reboot/shutdown menu with confirmation |
| `update-system.sh` | opens a terminal and dispatches to a detected distribution package manager |
| `updates.sh` | counts repository/AUR updates; not used by the current Waybar JSON |
| `network-menu.sh` | network helper; currently references a missing terminal wrapper |
| `bluetooth-manager.sh` | Bluetooth helper; currently references a missing terminal wrapper |
| `open-terninal.sh` | terminal wrapper with a misspelled filename |

`power-menu.sh` chooses Fuzzel, then Rofi, Wofi, or Bemenu. The active
`SUPER+P` binding invokes it through `bash`, even though Waybar itself is inactive.

## AI launcher

`ai/.local/bin/ai-agent` preserves the caller's working directory and launches
Claude, Codex, or OpenCode. Selection precedence is an explicit `--agent`, then
`AI_AGENT_DEFAULT`, then the configured value in `AI_AGENT_CONFIG` (defaulting to
`~/.config/ai-agent/config`). Shell aliases in `zsh/.zshrc` call this launcher.

## Hyprlock helper collection

Scripts below `hyprlock/.config/hyprlock/scripts/` provide battery status, Cava
visualization, MPRIS metadata/artwork/progress, player controls, stopwatch,
weather/location lookup, and alternate-layout switching. Most are referenced only
by inactive layouts. They may depend on `BAT0`, `playerctl`, `curl`, `ipinfo.io`,
`wttr.in`, ImageMagick, Cava, or extra assets. Read the chosen layout and helper
before enabling it.

`hyprlock_notify_widget.sh` can modify the active lock config and restart the lock
screen. It is not part of normal startup and should not be used as a read-only
preview command.

## Known script issues

- `RofiEmoji.sh` references `~/.config/rofi/config-emoji.rasi`, which is not
  tracked.
- `clipboard.sh` references `~/.config/rofi/config-clipboard.rasi`, which is not
  tracked.
- retained `WallpaperSwitch.sh` references a missing
  `~/.config/rofi/config-wallpaper.rasi`.
- `RofiCalc.sh`, `CalcClassic.sh`, `CalcScientific.sh`, and `CalcTechnical.sh` are
  all mode `0644`. The binding executes `RofiCalc.sh` directly, and that chooser
  in turn directly executes the selected helper, so the calculator path fails
  with “permission denied” as checked in.
- Waybar's network and Bluetooth scripts call `open-terminal.sh`, but the tracked
  file is named `open-terninal.sh`.

These findings describe the current repository; the documentation task does not
alter the scripts or their permissions.
