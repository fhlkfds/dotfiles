# Keybindings

All bindings in this file come from
`hypr/.config/hypr/conf/keybinding.conf` unless explicitly identified as browser
extension commands. `$mainMod` resolves to `SUPER`.

Hyprland's `bindd` descriptions also feed the live Quickshell keybinding palette,
opened with `SUPER+K`. The Rofi cheat sheet on `SUPER+H` is a separate fallback.

## Session and general tools

| Keys | Action | Command / behavior |
| --- | --- | --- |
| `SUPER+Return` | terminal | `kitty` |
| `SUPER+SHIFT+Return` | drop-down terminal | `Dropterminal.sh kitty` |
| `SUPER+Q` | close active window | `killactive` |
| `SUPER+SHIFT+Q` | exit Hyprland | `exit` dispatcher |
| `SUPER+L` | lock screen | start Hyprlock if not already running |
| `SUPER+P` | power menu | Waybar package's launcher-neutral power script |
| `SUPER+H` | help / cheat sheet | `KeyHints.sh` (Rofi) |
| `SUPER+K` | searchable bindings | Quickshell keybinding panel |
| `SUPER+I` | coding agent | `kitty -e ~/.local/bin/ai-agent` |
| `SUPER+SHIFT+G` | start Gaming VM | starts `Gaming-VM`, waits 15 seconds, then Looking Glass |

`SUPER+SHIFT+Q` exits the compositor immediately; it does not show the power-menu
confirmation.

## Applications and panels

| Keys | Action | Command / behavior |
| --- | --- | --- |
| `SUPER+A` | application menu | Rofi `drun` with current generated theme |
| `SUPER+SHIFT+A` | web-app manager | Quickshell web-app panel |
| `SUPER+W` | browser | `brave` |
| `SUPER+S` | Spotify | `spotify` |
| `SUPER+O` | Obsidian | `obsidian` |
| `SUPER+R` | voice dictation | `hyprvoice toggle` |
| `SUPER+SHIFT+H` | Hermes | `hermes` |
| `SUPER+E` | Files | `nautilus` through `$FileManager` |
| `SUPER+SHIFT+E` | Files | same as `SUPER+E` |
| `SUPER+SHIFT+ALT+F` | Files at terminal directory | `files-here.sh` |
| `SUPER+SHIFT+D` | Disks | `gnome-disks` through `$Disks` |
| `SUPER+CTRL+I` | network panel | Quickshell IPC |
| `SUPER+CTRL+D` | display panel | Quickshell IPC |
| `SUPER+CTRL+M` | media panel | Quickshell IPC |
| `SUPER+CTRL+A` | dashboard | Quickshell IPC |

## Clipboard, emoji, and calculator

| Keys | Action | Notes |
| --- | --- | --- |
| `SUPER+C` | universal copy | sends `CTRL+SHIFT+C` in terminals, `CTRL+C` elsewhere |
| `SUPER+X` | universal cut | terminal cut intentionally does nothing |
| `SUPER+V` | universal paste | sends terminal-appropriate shortcut |
| `SUPER+CTRL+V` | clipboard history | active Quickshell/cliphist panel |
| `SUPER+ALT+V` | legacy clipboard manager | Rofi script; its referenced theme file is missing |
| `SUPER+ALT+E` | emoji menu | Rofi script; its referenced theme file is missing |
| `SUPER+SHIFT+C` | calculator modes | Rofi chooser and its helpers lack executable bits, so the binding cannot start as checked in |

See [Known script issues](./scripts.md#known-script-issues) before relying on the
three affected Rofi entries.

## Notifications

| Keys | Action |
| --- | --- |
| `SUPER+,` | dismiss newest notification |
| `SUPER+SHIFT+,` | dismiss all notifications |
| `SUPER+CTRL+,` | toggle do-not-disturb |
| `SUPER+ALT+,` | invoke the newest notification's default action |
| `SUPER+SHIFT+ALT+,` | open notification history |

These commands target the active Quickshell notification service through
`~/.local/bin/notificationctl`, not SwayNC.

## Capture

| Keys | Action | Capture command |
| --- | --- | --- |
| `SUPER+SHIFT+S` | smart screenshot | drag for region; click to snap window under pointer |
| `SUPER+CTRL+S` | active-window screenshot | `screenshot window` |
| `SUPER+ALT+S` | focused-monitor screenshot | `screenshot monitor` |
| `SUPER+ALT+CTRL+S` | screenshot monitor after 5 seconds | `--delay=5` |
| `SUPER+CTRL+SHIFT+S` | screenshot monitor after 10 seconds | `--delay=10` |
| `SUPER+SHIFT+R` | toggle screen recording | `record toggle` |
| `SUPER+SHIFT+P` | color picker | `color` |
| `SUPER+SHIFT+T` | OCR / extract text | `ocr` |
| `SUPER+CTRL+C` | capture menu | mode chooser |

The implementation and optional features are described in
[Capture suite](./scripts.md#capture-suite).

## Themes, wallpaper, and night light

| Keys | Action |
| --- | --- |
| `SUPER+T` | open cover-flow theme picker |
| `SUPER+CTRL+SHIFT+Space` | open the same theme picker |
| `SUPER+SHIFT+W` | open wallpaper picker/search |
| `SUPER+CTRL+N` | toggle night light between 1000 K and 6500 K |

## Workspaces

### Select a workspace

| Keys | Destination |
| --- | --- |
| `SUPER+1` … `SUPER+9` | workspaces 1 … 9 |
| `SUPER+ALT+1` … `SUPER+ALT+5` | workspaces 11 … 15 |

There is no direct select-workspace-10 binding.

### Move the active window

The number rows use physical key codes `code:10` through `code:19`, corresponding
to the physical `1` through `0` keys regardless of the displayed symbol.

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+1` … `SUPER+SHIFT+0` | move to workspace 1 … 10 and follow |
| `SUPER+CTRL+1` … `SUPER+CTRL+0` | move to workspace 1 … 10 without following |
| `SUPER+SHIFT+[` / `SUPER+SHIFT+]` | move and follow to previous / next workspace |
| `SUPER+CTRL+[` / `SUPER+CTRL+]` | move silently to previous / next workspace |

Output placement for these numbered workspaces is profile-dependent; see
[Workspace mapping](./monitors.md#workspace-mapping).

## Window management

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+F` | true fullscreen (Hyprland mode 0) |
| `SUPER+CTRL+F` | maximize while retaining bar/gaps (mode 1) |
| `SUPER+Arrow` | move focus in that direction |
| `SUPER+CTRL+Arrow` | move window in that direction |
| `SUPER+ALT+Arrow` | swap window in that direction |
| `SUPER+SHIFT+Left/Right` | resize width by −/+50 pixels |
| `SUPER+SHIFT+Up/Down` | resize height by −/+50 pixels |
| `SUPER+Left mouse drag` | move window |
| `SUPER+SHIFT+Right mouse drag` | resize window |

## Desktop zoom

| Keys | Action |
| --- | --- |
| `SUPER+ALT+wheel down` | multiply zoom by 1.1 |
| `SUPER+ALT+wheel up` | multiply zoom by 0.9, clamped to 1 |
| `SUPER+ALT+SHIFT+wheel` in either direction | reset zoom to 1 |

These bindings query and update `cursor:zoom_factor` with `hyprctl` and `jq`.

## Media, volume, and brightness

| Key | Action | Primary command |
| --- | --- | --- |
| `XF86AudioRaiseVolume` | volume +5%, repeatable | `wpctl`, capped at 100% |
| `XF86AudioLowerVolume` | volume −5%, repeatable | `wpctl` |
| `XF86AudioMute` | toggle mute | `wpctl` |
| `XF86AudioPlay` | play/pause | `playerctl play-pause` |
| `XF86AudioPause` | pause | `playerctl pause` |
| `XF86AudioNext` | next track | `playerctl next` |
| `XF86AudioPrev` | previous track | `playerctl previous` |
| `XF86AudioStop` | stop | `playerctl stop` |
| `XF86MonBrightnessUp` | brightness +5%, repeatable | `brightnessctl` |
| `XF86MonBrightnessDown` | brightness −5%, repeatable | `brightnessctl` |

The same three volume keys are also registered later with `pactl`. The config
states that the earlier `wpctl` definitions shadow those duplicate fallback
bindings. Both sets remain in the file, so remove one set rather than expecting
both to execute.

## Browser extension shortcuts

These are Chromium extension commands, not Hyprland bindings:

| Keys | Action | Source |
| --- | --- | --- |
| `ALT+SHIFT+L` | copy current tab URL to Wayland clipboard | Copy URL extension |
| `ALT+SHIFT+D` | download media from current page with yt-dlp | Download Video extension |

Chromium must grant/register the command and find its native host. See
[Browser integration](./components.md#browser-integration) and the corresponding
[troubleshooting](./troubleshooting.md#browser-shortcuts).
