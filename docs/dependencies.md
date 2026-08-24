# Dependencies

There is no package manifest or installer in the repository. The tables below are
derived from executable names, configuration references, imports, and scripts;
they are intentionally not claimed to be an exhaustive Arch package list.

“Required” means required for the currently configured session or the named
active path. An application bound to a key is listed separately because Hyprland
can run without it, but that feature cannot.

## Core active desktop

| Command / package | Status | Used by |
| --- | --- | --- |
| Hyprland | required | compositor and IPC |
| Quickshell | required for configured shell | bar, panels, notifications, OSD |
| Hyprpaper | required for wallpaper path | autostart, themes, picker |
| Hypridle | required for configured idle policy | autostart |
| Hyprlock | required for lock behavior | idle and `SUPER+L` |
| Hyprsunset | required for night light | autostart and toggle script |
| Kitty | configured terminal | bindings, panel helpers, XDG editor entry |
| Rofi | configured launcher | app menu and helper menus |
| `jq` | required by multiple active scripts | Hyprland JSON, native hosts, wallpaper |
| `wl-clipboard` | required for clipboard flow | `wl-copy`, `wl-paste` |
| `cliphist` | required for history | startup watchers and panel |
| `libnotify` / `notify-send` | required by several scripts | desktop feedback |
| Python 3.11+ | required by generated/theme/backends | theme, wallpaper, web apps, notification helper |
| `curl` | active network helpers | wallpaper, lyrics, weather, art |
| `playerctl` | media integration | bindings and Spotify/lock helpers |
| `udiskie` | configured startup tool | removable media |
| PipeWire/WirePlumber tools | configured audio path | `wpctl`, Quickshell PipeWire |
| NetworkManager | configured network path | `nmcli`, `nmtui` |
| `iputils` | dashboard/network checks | `ping` |
| `polkit` provider / `pkexec` | privileged panel action | DNS changes |

The system also needs a working Wayland session, D-Bus user bus, font stack, PAM
Hyprlock service, and ordinary core utilities (`bash`, `sh`, `realpath`, `flock`,
`setsid`, `find`, `sed`, and similar).

## Configured applications

| Command | Role / binding |
| --- | --- |
| `brave` | `SUPER+W`, browser autostart, browser extensions |
| `nautilus` | `SUPER+E`, file-manager helpers |
| `gnome-disks` | `SUPER+SHIFT+D` |
| `spotify` | `SUPER+S`, autostart/workspace rule |
| `obsidian` | `SUPER+O`, autostart/workspace rule |
| `virt-manager` | autostart/workspace rule |
| `hermes` | `SUPER+SHIFT+H`, autostart/workspace rule |
| `hyprvoice` | `SUPER+R` |
| `virsh`, `looking-glass-client` | Gaming VM binding |
| Helium | XDG default HTTP/HTML handler |
| `imv`, `mpv`, Zathura, Neovim | XDG MIME handlers |
| Cisco Packet Tracer, T3 Code, Claude Code handlers | externally referenced XDG file/URL handlers |

Helium and Brave serve different configured roles: Helium is the MIME default,
while Brave is the Hyprland binding/autostart browser.

## Feature-specific dependencies

### Capture

| Command | Feature |
| --- | --- |
| `grim`, `slurp`, `hyprpicker` | screenshots, frozen selection, colors |
| `gpu-screen-recorder` | screen recording |
| FFmpeg | post-processing and browser thumbnails |
| ImageMagick (`magick`) | OCR preprocessing, image validation/manipulation |
| Tesseract + selected language data | OCR |
| `satty` | screenshot editing |
| `v4l2-ctl` | webcam discovery |
| mpv | recording/video playback |

Run `capture.sh doctor` for the suite's own availability report.

### Display and monitors

| Command | Feature |
| --- | --- |
| `ddcutil` | external-monitor brightness |
| `hyprctl` | output discovery, profile application, scale changes |
| `systemd`/`loginctl` | suspend and pre-sleep lock behavior |

### Browser tools

| Command | Feature |
| --- | --- |
| Chromium-family browser | extension runtime/native messaging |
| yt-dlp | media detection and download |
| `jq` | native message JSON parsing |
| FFmpeg | completion thumbnail |
| mpv | notification action |
| Quickshell | progress OSD; failure notification still has fallback behavior |

### Wallpaper and themes

The active wallpaper tool uses Bash, `curl`, `jq`, ImageMagick, Hyprpaper,
Quickshell IPC, and notifications. The theme system uses Python 3.11+ and
can call Hyprland, Hyprpaper, Kitty, Waybar, SwayNC, and Quickshell to refresh
running components.

## Fonts and icon themes

| Asset | Referenced by |
| --- | --- |
| JetBrainsMono Nerd Font | Kitty, bar/panels, Rofi glyphs, lock screen |
| AlfaSlabOne | active Hyprlock layout |
| Papirus icons | Rofi |
| Powerlevel10k-compatible glyph font | Zsh prompt |

Missing Nerd Font glyphs typically appear as empty squares even when the command
itself works.

## Optional / retained stack

| Component | Why optional here |
| --- | --- |
| Waybar | configured but not autostarted |
| SwayNC | configuration retained; startup commented |
| Wofi, Fuzzel, Bemenu | fallback launchers for power menu; Wofi config retained |
| Noctalia | settings/plugins retained; startup commented |
| PulseAudio `pactl` | duplicate fallback volume bindings; `wpctl` is registered first |
| Fastfetch, Pokémon Color Scripts | interactive Zsh greeting |
| Oh My Zsh, Powerlevel10k, fzf-tab, eza, syntax highlighting/autosuggestions | optional tracked Zsh environment |
| Cava | inactive Hyprlock visualizer helper |
| mpvpaper | retained video-wallpaper paths |
| nwg-displays | origin of unsourced Lua monitor files, not required by active loader |
