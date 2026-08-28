# Troubleshooting

Start with repository-specific checks: confirm the Stow link points to this clone,
the active component is the one being edited, and generated files exist. Then use
ordinary Hyprland/Wayland diagnostics.

## Hyprland configuration does not change

1. Confirm `~/.config/hypr/hyprland.lua` resolves to
   `hypr/.config/hypr/hyprland.lua` in this repository.
2. Check that all seven sourced files shown in
   [Architecture](./architecture.md#active-hyprland-source-graph) exist.
3. Generate a theme if `conf/decorations.lua` is absent.
4. Inspect Hyprland's config error output before reloading.
5. Remember that the monitor watcher and theme generator overwrite derived files.

If a command built from `scripts_dir` fails on a different account, replace the
hardcoded `/home/liam` definition in `conf/variables.lua`.

## Quickshell bar or panels do not appear

The active bar is Quickshell, not Waybar. Check that `quickshell` exists and that
`quickshell/.config/quickshell/shell.qml` is deployed. Inspect Quickshell's log for
QML parse/runtime errors and verify the generated active theme JSON exists.

Panel-specific failures often indicate a missing external command:

- network: `nmcli`, `nmtui`, `ping`, and for DNS changes `pkexec`;
- display brightness: `ddcutil` and permission to access the DDC/I²C device;
- clipboard: `cliphist`, `wl-paste`, and `wl-copy`;
- keybinding palette: a responsive `hyprctl` socket;
- weather/lyrics/wallpaper: network access to the relevant public API.
- desktop modes: run `desktop-mode doctor --json`; the panel intentionally
  reports unavailable backends rather than claiming a toggle succeeded.

Starting Waybar will not repair Quickshell panels. Conversely, editing Waybar's
JSON/CSS does not change the active bar.

## Notifications do not appear

Use `notificationctl status --json` to determine whether the Quickshell service is
reachable and whether DND is enabled. Check that no second notification daemon is
competing for `org.freedesktop.Notifications`; SwayNC should remain stopped in the
current architecture.

## Screensaver does not cover the requested monitor

Run `ascii-screensaver start --dry-run` and confirm that every active output has
one assignment. Monitor names must exactly match `hyprctl -j monitors`. The
coordinator focuses the exact app-address, moves it with `movewindow mon:NAME`,
then applies true fullscreen. Use `ascii-screensaver stop` to clear an interrupted
session; it does not touch lock or power policy.

If the scene immediately closes without input, verify the installed files match
this repository: pointer tracking is deliberately armed after window placement
to ignore compositor-generated startup motion while keyboard exit is active
immediately.

Notification state is under
`$XDG_STATE_HOME/hyprland-desktop/notifications` or
`~/.local/state/hyprland-desktop/notifications`. Critical notifications are
persistent by design; ordinary timeout behavior comes from the notification
config.

## Browser shortcuts

### Copy URL or Download Video does nothing

1. Fully close and reopen the Chromium-family browser after changing flags or
   extension files.
2. Open the browser's extension shortcuts page and confirm `ALT+SHIFT+L` and
   `ALT+SHIFT+D` are assigned to the bundled extensions.
3. Confirm the browser launches with the checked-in `--load-extension` paths.
4. Confirm `NativeMessagingHosts/io.github.fhlkfds.copy_url.json` and
   `com.omarchy.ytdlp.json` exist below the actual browser profile root.
5. Inspect those manifests for `/home/liam` paths if using another account.
6. Check that the native host executables are executable and that `jq`,
   `wl-copy`, `yt-dlp`, and `notify-send` resolve in their restricted PATH.

If an obsolete Download Video extension owned the shortcut, run the repair helper
against the real profile root without `--apply` first. Completely close the
browser, review the proposed stale registrations, then rerun with `--apply`. It
backs up Preferences and refuses a detected live browser.

### Download Video says “unavailable” or “failed”

The notification body is the final yt-dlp error, truncated to 240 characters.
Reproduce it directly in a terminal for full diagnostics:

```bash
yt-dlp --no-playlist --simulate --verbose -- 'https://example.invalid/video-page'
```

Replace the placeholder with the exact page URL. Common causes are an outdated
yt-dlp extractor, authentication/cookies required by the site, DRM, regional
restrictions, network failure, or a page with no supported media.

Also verify that:

- `$CHROMIUM_YTDLP_DIR` or `~/Videos` exists or can be created;
- the target filesystem is writable and has space;
- only one worker holds
  `${XDG_RUNTIME_DIR:-/tmp}/chromium-ytdlp-${UID}.lock`;
- FFmpeg absence affects the preview but should not invalidate a completed file;
- Quickshell absence hides progress, but the worker should still send failure or
  completion notifications.

To stop a running worker without killing the browser, identify it first with
`pgrep -af 'chromium-ytdlp-host.*--download'`, then send `TERM` to the exact PID
with `kill <PID>`. Do not use a broad pattern that could terminate unrelated
browser processes.

## Wallpaper picker shows no local results

The tool defaults to `/home/liam/Pictures/wallpapers`, while tracked assets are in
the repository's `Wallpapers/` tree. Standard `stow Wallpapers` currently targets
that package's children directly below `$HOME`, not `~/Wallpapers` as the root
README claims. Correct/specially target the package and set
`HYPR_WALLPAPER_DIR` to the resulting directory. Local matching uses filenames
and recognizes JPEG/PNG files. Empty remote results additionally require `curl`,
`jq`, DNS/network access, and a successful Wallhaven API response.

If the menu says Wallhaven is blocked by Cisco Umbrella DNS, allow-list
`wallhaven.cc`, `th.wallhaven.cc`, and `w.wallhaven.cc` on the configured DNS
service, then retry. Do not disable TLS verification: Cisco's block-page address
is not the Wallhaven API or an image server.

If selecting a result fails, check ImageMagick validation and Hyprpaper. Applying
a wallpaper restarts Hyprpaper; an invalid download is rejected rather than sent
to it.

## Wrong monitor layout or missing workspaces

First ask what the applier thinks:

```sh
~/.config/hypr/scripts/auto-monitor-profile.sh --dry-run
journalctl -t hypr-monitor -n 50
```

The dry-run prints the selected profile and a desired-vs-actual table for every
monitor, plus whether the generated `monitors.lua`/`workspaces.lua` still match
the profile.

If workspaces have collapsed onto one screen, the `laptop` profile was applied
while the externals were connected: it pins workspaces 1–15 to `eDP-1`, which is
disabled when docked. That happens when detection fails. Confirm the EDID
descriptions still match `KVM_DESCS` in `auto-monitor-profile.sh`:

```sh
hyprctl monitors -j | jq -r '.[].description'
```

Do **not** diagnose by connector name — the KVM renumbers them on every switch.

If nothing reacts to a hotplug, the watcher is not running:

```sh
pgrep -af hypr-monitor-watch.py
hyprctl eval 'hl.exec_cmd("$HOME/.config/hypr/scripts/hypr-monitor-watch.py")'
```

Note `hyprctl dispatch exec` and `hyprctl keyword` are legacy dispatchers and do
nothing under the Lua config; use `hyprctl eval` instead.

Make durable corrections under `monitor_profiles/` via
`capture-monitor-profile.sh`, not in the active files, which are overwritten. The
display panel's scale helper persists only to the desktop profile.

## Launcher entry fails

| Symptom | Repository-specific cause |
| --- | --- |
| calculator reports a missing command | install `libqalculate`, Rofi, and `wl-clipboard` |
| HEIC transcode fails | install `libheif` so ImageMagick can load its HEIC/HEIF delegate |
| LocalSend or activity binding does nothing | install `localsend` or `btop` from Arch repositories |
| old wallpaper selector has theme error | missing `config-wallpaper.rasi` |
| Waybar network/Bluetooth action fails | scripts request `open-terminal.sh`, but only `open-terninal.sh` exists |

Rofi itself also needs the generated current theme. Run the theme bootstrap rather
than inventing an empty current-theme file.

## Windows VM does not start or connect

Run `windows-vm status`, then `windows-vm logs`. Common causes are an inactive
Docker daemon, a login session that has not picked up new `docker` group
membership, inaccessible `/dev/kvm` or `/dev/net/tun`, or ports 3389/8006 already
being used. The helper never falls back to sudo or exposes either port beyond
localhost.

During the first installation, open `http://127.0.0.1:8006` to see progress.
`windows-vm launch` waits for an authenticated RDP endpoint rather than sleeping
for a fixed interval. If readiness times out or FreeRDP exits with an error, the
VM remains running so its logs and web console can be inspected.

The helper uses non-interactive certificate handling for its loopback-only RDP
endpoint. If an older session left a “Certificate for 127.0.0.1:3389 has
changed” dialog open, dismiss that existing dialog once with Escape; subsequent
launches do not create it.

`windows-vm remove` is non-destructive. Permanent deletion requires
`windows-vm remove --purge-data` and exact-path confirmation; `~/Windows` is
always preserved.

## Capture failures

Run:

```bash
~/.config/hypr/scripts/capture/capture.sh doctor
```

The smart selector requires live Hyprland monitor/window JSON. Rotated/scaled
outputs particularly depend on `jq`, `slurp`, and the transform logic. Recording
requires `gpu-screen-recorder`; OCR requires Tesseract language data and
ImageMagick; editing requires Satty.

Check write permission and free space in `SCREENSHOT_DIR` and
`SCREENRECORD_DIR`. Runtime PID/state under `$XDG_RUNTIME_DIR` can explain a stale
“already recording” state, but inspect the files and process before removing
anything.

## Lock screen or idle behavior fails

- Confirm Hypridle and Hyprlock are installed and started.
- Confirm the generated `~/.config/hyprlock/colors.conf` exists.
- Run `hypr-wallpaper-picker current` and confirm it prints an existing image;
  missing wallpaper state should fall back to the active theme color.
- Check that Noto Sans and JetBrainsMono Nerd Font resolve through Fontconfig.
- Verify the `hyprlock` PAM service is installed correctly.
- For suspend, check `systemctl suspend` policy and inhibitors.
- Alternate layouts may assume `BAT0`, extra fonts, a profile image, playerctl,
  or network services that are not part of the active layout.

## Missing icons or incorrect fonts

Install JetBrainsMono Nerd Font, Noto Sans, and Papirus icons, then check the
exact family names exposed by Fontconfig. Empty squares in the bar or lock user
label usually mean a Nerd Font mismatch, not a QML logic failure.

## Shell startup is slow or noisy

The optional Zsh config runs Pokémon Color Scripts piped into Fastfetch for every
interactive shell and loads several plugin files. Missing commands can produce
startup errors. Disable that greeting or missing plugin source lines in
`zsh/.zshrc`. Also replace the personal GAM and VPN paths before reuse.

The tracked `zsh/.oh-my-zsh` path is a Gitlink without a `.gitmodules` mapping.
If a fresh clone leaves Oh My Zsh unavailable, install it independently or repair
the repository metadata; `git submodule update` cannot infer the missing URL.

## General diagnostic boundaries

This repository does not declare an Arch package list, GPU-specific environment,
or GTK/Qt/cursor theme. If a failure depends on those, the required system setup
could not be determined from the current repository. Use the compositor and
application logs, then add the discovered dependency/configuration to the
repository rather than relying on undocumented machine state.
