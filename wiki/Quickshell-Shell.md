# Quickshell shell

Quickshell is the bar, the panels, the notification daemon, the clipboard
browser, the theme picker, and the on-screen displays. It is the only bar. There
are 95 QML files in `quickshell/.config/quickshell/`.

## Root

Hyprland starts `quickshell`, which loads `shell.qml`:

```qml
Scope {
  readonly property var batteryState: BatteryState
  Bar {}
  Variants {
    model: Quickshell.screens
    DesktopClock { required property var modelData; output: modelData }
  }
  Variants {
    model: Quickshell.screens
    DesktopNowPlaying { required property var modelData; output: modelData }
  }
  Notifications.NotificationRoot {}
  VideoDownloadRoot {}
}
```

Six things: battery monitoring, the bar, one desktop clock and one Spotify
now-playing card per screen, the notification service, and the browser-video
progress service.

## Bar layout

One top-layer bar per screen. The bar strip itself is transparent and paints
nothing: everything you see is an **island** — a black stadium-shaped capsule
(`BarIsland.qml`) floating over the wallpaper, holding a group of **modules**.
The strip still reserves its full height, so windows tile below it and never
slide underneath a capsule.

Content scales with `barScale` (`Theme.barScaleFor`), capped at 1.25×, which is
what makes the tallest chrome (the 26 design-px workspace cell) sit at 33 px
inside a 40 px island. The reserved height is that island plus a 5 px gap above
and below.

Narrow bars scale down. If that still leaves too little room, the clock shifts
off centre (`centerGroup.collisionShift`) to keep the capsules apart.

Islands are spread to the two edges rather than clustered: workspaces hard left,
the clock centred, the tray and power hard right.

| Island | Holds |
| --- | --- |
| `leftIsland` | `WorkspacesModule` |
| `centerIsland` | recording and mode indicators, pending updates, clock (time with seconds over the date), current weather in °F |
| `trayIsland` | launcher, agent, VM, Bluetooth, network, audio, battery when present |
| `powerIsland` | the power button, alone, circular |

An island is sized to its content, so it shrinks when a module hides itself —
the battery on a desktop, the VM icon when the container is down. Its colour is
`Theme.bgDeep`, not a hardcoded black, so a light palette still gets a legible
bar. Its radius is deliberately *not* `Theme.hyprRounding`: the capsule is the
design, and a theme setting rounding to 4 would flatten it back into a slab.

`powerIsland` is separate on purpose. Power is the only destructive control on
the bar, so it does not share a capsule with the icon a mis-aimed click would
otherwise be one pixel away from.

**Left** — `WorkspacesModule` has fixed cells for workspaces 1–10. A cell is
shown only while its workspace is focused or has at least one window; empty
workspaces are hidden. Until Hyprland reports a focused workspace, all ten are
shown. Icons take their colour from the theme's text roles, and the bundled
SVG icons are repainted with that colour so they read on light themes. Clicking
a cell switches to it.

**Centre** — the clock is the anchor. The indicator row grows left, so changing
it does not nudge the time. Clicking the clock, or the weather beside it, opens
the [clock dashboard](#clock-dashboard).

| Position | Widget |
| --- | --- |
| left of the clock | `RecordIcon`, `UpdatesIcon`, `ModeIndicators` |
| the anchor | the clock itself |

The `MediaPanel` anchors to the clock and opens through the `media` IPC target.

**Right** — `AppLauncher`, `WindowsVmIcon`, `BluetoothIcon`, `NetworkIcon`,
`AudioIcon`, `BatteryIcon` when present, then the power button. The coding
agent has no bar icon; `SUPER+I` opens it.

`tests/omakub-bar-layout.test.sh` asserts the bar still mounts this component
set, so adding or removing a widget means updating that list. It also asserts
the island structure: that the strip stays transparent, that the four islands
exist, that power stays out of the tray capsule, and that the reserved height
still clears the island on both sides.

## Bar interactions

- **Empty bar space**: inert. The bar is pinned to the top edge and cannot be
  moved.
- **Display**: Super+Ctrl+D opens the display panel.
- **Network**: opens the themed NetworkManager panel.
- **Bluetooth**: connected devices as hero cards, paired devices below, discovery
  folded behind a scan button. Pointer-driven; Escape closes.
- **Audio**: panel on left or middle click, mute on right click, 3% wheel steps.
- **Clipboard**: Super+Ctrl+V opens the cliphist browser.
- **Recording indicator**: only present while recording; clicking stops it.
- **Mode indicators**: pills for active night light, DND, stay-awake,
  automatic-screensaver-disabled, and error states. Clicking opens the modes
  panel. They show *observed* state, so an error appears instead of a false
  success.
- **Updates**: one combined count, hidden when a check finds nothing; hover
  for the pacman and AUR split and package names. A failed check keeps the icon
  visible (`!` when there is no count) so a missing `pacman-contrib` or an AUR
  rate limit cannot pass for an up-to-date system. Checked every 90 minutes
  through `scripts/arch-updates`, whose shared 10-minute cache keeps every
  caller from re-querying the mirrors or the AUR. Clicking opens a "System
  Update" terminal silently on workspace 1 (the bar shows an ellipsis) that
  asks for both, pacman, or AUR (Enter = both) and runs it through `yay`
  unattended: prompt defaults throughout, so package removals are declined and
  abort rather than happen. `paru` is not used. A partial update only clears
  the count for the side it upgraded; an existing failed-check marker remains
  until both sides are verified. Cancelling the menu or entering an invalid
  choice runs nothing, and failed upgrades preserve the counts.
- **Battery**: shows charge percentage and state; hidden when no laptop battery
  is present. Clicking opens the battery panel.
- **Windows VM icon**: appears while the container runs. Pulses amber while
  installation or startup waits for RDP, then goes solid accent when RDP is
  ready. Disappears when the VM stops.

## Clock dashboard

`DashboardPanel.qml` drops a four-tab panel under the bar clock. Clicking the
time or the weather opens it on **Overview**; clicking again, clicking outside,
or Escape closes it. Left/Right (or Tab), the number keys 1–4, and the mouse
wheel over the tab strip switch tabs. `quickshell ipc call dashboard toggle`
opens it on the focused monitor.

| Tab | Shows |
| --- | --- |
| Overview | clock with ISO week and day of year, current weather and the next few hours, a month calendar with US federal holidays, the next holiday countdown, now playing with a spectrum, and CPU / memory / GPU / disk / uptime rings |
| Media | the active MPRIS player over its blurred cover, a radial spectrum round the art, a seekable wave timeline, transport and volume, and synced lyrics |
| System | hostname and kernel, CPU with history, per-core bars, temperature, clock and load; memory and swap; root filesystem; GPU with history, VRAM and power; network rates and totals; a Mission Center button |
| Weather | conditions, humidity, wind, rain, UV, sunrise and sunset; a 24-hour temperature curve with rain chance; seven days of ranges on a shared scale |

It is built to feel instant. Every page is created with the bar and kept
alive, so opening only maps the window and switching tabs only flips
`visible`. The window is one fixed size for every tab, so a switch never
resizes the Wayland surface, and nothing fades or grows on open or close; the
tab underline is the one animation. The wave timeline is drawn once and slid
sideways rather than repainted.

The panel and its cards follow the active palette and its corner rounding
live, including cached charts and playback waves; a theme switch does not
rebuild pages. On narrow or short screens the tab strip fits the screen and
the fixed-size page body scrolls in either direction.

Closing the dashboard stops its system polling and animations. `SysState` polls `/proc` and `/sys` only
while it is open (once a second, `df` every 30 s), the media position ticks
only while a timeline is on screen, and each page stops its spectrum bindings
and animations whenever it is not the visible tab. Reopening shows the last
readings at once and refreshes them within a second; CPU delta sampling is
reseeded after 250 ms. Removing the owning monitor stops dashboard polling.

Temperatures come from `k10temp`, `zenpower` or `coretemp`, and from `amdgpu`
for an AMD card. An NVIDIA card is read through `nvidia-smi`, but only while
it is awake: a hybrid laptop's dGPU that is runtime-suspended shows as asleep
rather than being queried. Queries target the selected PCI device and have a
two-second timeout. AMD sensors and the GPU name come from the same device.
System file reads are asynchronous, and invalid or failed sensor reads show
unavailable. Hardware that exposes nothing reads as
unavailable, never as a made-up number. Holidays are computed locally
(`Holidays.js`), so the calendar needs no network.

Forecast hours and days follow the weather location's UTC offset from
Open-Meteo and advance with a minute clock. Malformed responses keep the
previous good forecast, and results for a location changed during a request
are discarded. Holiday markers use actual holiday dates, not observed
workday substitutes.

## Desktop clock

`DesktopClock.qml` is a separate full-screen layer per output on the
**background** layer — above the wallpaper, below application windows. It has an
empty input mask and `ExclusionMode.Ignore`, so it is entirely click-through, and
it requests no keyboard focus. It draws in the bottom-right corner.

## Desktop now-playing card

`DesktopNowPlaying.qml` puts a Spotify card in the bottom-left corner of every
output, on the same **background** layer as the clock: a record carrying the
album art, the title and artist, previous / play-pause / next, elapsed time,
and a progress line. It follows **Spotify only**, through `SpotifyState.qml`,
so a browser tab playing a video never takes it over; the bar's media module
still follows any player. The card is hidden while Spotify is closed, stopped,
or has no track, and stays up while paused.

Unlike the clock the window is sized to the card, not the whole screen, so its
buttons take clicks and the rest of the desktop is untouched. Like anything on
the background layer it is only visible on a workspace with no windows over
it; the record stops spinning whenever the monitor's active workspace has
windows, so a hidden card does not keep the output redrawing.

Where the output is too narrow for the card and the clock to share the bottom
edge (a portrait monitor, or a large text scale), the card moves up to sit
above the clock's band instead of running into it. With more than one Spotify
client on the bus, the one playing wins. On Qt Quick's software renderer,
where `MultiEffect` draws nothing, the card drops the round art mask and the
text shadow rather than going blank.

It deliberately has no queue, sleep timer, or volume control: Spotify does not
publish its queue over MPRIS, and ignores MPRIS volume on Linux.

## Panels and their backends

| Panel | Backed by |
| --- | --- |
| Network | `scripts/network-control` over `nmcli`; Wi-Fi scan and connect, per-profile DNS (up to four servers, saved to the profile so they persist across reboots) and IPv4 overrides, and runtime-only `qrencode` Wi-Fi sharing |
| Bluetooth | `scripts/bluetooth-control` over `bluetoothctl` |
| Audio | Quickshell's PipeWire API |
| Media | Quickshell MPRIS; recent and pinned players; lyrics from `lrclib.net` |
| Display | Hyprland's monitor model, `ddcutil`, and `set-monitor-scale.sh` |
| Dashboard | `/proc`, `/sys`, `df`, `lspci`, `nvidia-smi` while the GPU is awake, MPRIS, cava, Open-Meteo |
| Clipboard | `cliphist`, `wl-copy`, plus a local image preview index |
| Keybindings | live `hyprctl binds -j`; destructive entries are not invokable from the UI |
| Theme | the Hyprland theme generator |
| Wallpaper | the local/Wallhaven backend in `hypr-wallpaper-picker` |
| Web apps | the `webapp` shell backend |
| Modes | `desktop-mode` |

Secured Wi-Fi connections hand off to an interactive `nmtui` prompt, so the
password never crosses the panel boundary. The Wi-Fi QR is rendered at runtime
and never written to disk as a plaintext secret.

## IPC targets

Every panel is reachable over `quickshell ipc call <target> <function>`, which is
how the keybindings toggle them without spawning anything:

```text
audio      bar        bluetooth   clipboard   dashboard
display    keybinds   media       modes       network     notifications
theme      videoDownload           visualizer
wallpaper  webapps
```

Example:

```bash
quickshell ipc call media toggle
quickshell ipc call notifications statusJson
```

## Theming

`Theme.qml` watches `~/.config/hypr/themes/.active/theme.json` and updates live —
no restart when you switch themes. It exposes the palette plus `Theme.fs()` for
font scaling (persisted through `gsettings`), a sans-serif UI family, and
JetBrainsMono Nerd Font for glyphs.

Widget code should read `Theme.*` rather than hardcoding colours. See
[Theming](Theming.md).

## Component map

Most widgets follow a three-file pattern: a singleton `XState.qml` holding data
and process calls, an `XIcon.qml` for the bar, and an `XPanel.qml` for the
dropdown.

| Area | Files |
| --- | --- |
| Bar shell | `Bar.qml`, `WorkspacesModule.qml`, `IconButton.qml`, `Card.qml` |
| Clock and calendar | `ClockState.qml`, `ClockWidget.qml`, `DesktopClock.qml`, `CalendarGrid.qml`, `CalendarPopup.qml`, `TimezonePopup.qml`, `DateTimeCard.qml` |
| Clock dashboard | `DashboardState.qml`, `DashboardPanel.qml`, `DashboardView.qml`, `DashOverview.qml`, `DashMedia.qml`, `DashSystem.qml`, `DashWeather.qml`, `DashCard.qml`, `WaveProgress.qml`, `Sparkline.qml`, `Gauge.qml`, `Holidays.js`, `SysState.qml` |
| Unmounted (the old dashboard drawer's pages) | `MediaTab.qml`, `PerfTab.qml`, `WorkspacesTab.qml`, `WeatherTab.qml`, `MetricCard.qml`, `HeroGauge.qml`, `ProfileCard.qml` |
| Network | `NetworkState/Icon/Panel.qml`, `SpeedTestOverlay.qml`, `SpeedTestGauge.qml` |
| Disk speed test | `DiskState.qml`, `DiskSpeedOverlay.qml` (reuses `SpeedTestGauge.qml`) |
| Audio and media | `AudioState/Icon/Panel.qml`, `AudioPanelContent.qml`, `VolumeSlider.qml`, `MediaState/Icon/Panel.qml`, `MediaPreviewCard.qml`, `LyricsState.qml`, `LyricsView.qml`, `SpotifyState.qml`, `DesktopNowPlaying.qml`, `DesktopNowPlayingCard.qml` |
| Visualiser | `CavaState.qml`, `CavaBars.qml`, `CavaEdgeVisualizer.qml`, `VisualizerState.qml` |
| Bluetooth | `BluetoothState/Icon/Panel/HeroCard/DeviceRow/Battery.qml` |
| Display | `DisplayState/Icon/Panel.qml` |
| Clipboard | `ClipboardState/Icon/Panel.qml` |
| Notifications | `notifications/` (see [Notifications](Notifications.md)), `NotifyState.qml`, `NotifyIcon.qml`, `DndIcon.qml` |
| Battery | `BatteryState.qml`, `battery/BatteryLogic.js`, `battery/BatteryConfig.qml`, `battery/config.json` |
| Modes | `ModesState.qml`, `ModesPanel.qml`, `ModeIndicators.qml` |
| Theme | `Theme.qml`, `ThemeState.qml`, `ThemePicker.qml`, `ThemePreview.qml`, `ThemeSlice.qml` |
| Wallpaper | `WallpaperState.qml` |
| Web apps | `WebAppState.qml`, `WebAppPanel.qml` |
| Capture | `RecordState.qml`, `RecordIcon.qml` |
| Updates | `UpdatesState.qml`, `UpdatesIcon.qml` |
| Video download | `VideoDownloadRoot/State/Overlay/Card.qml` |
| Windows VM | `WindowsVmState.qml`, `WindowsVmIcon.qml` |
| Keybindings | `KeybindsState.qml`, `KeybindsPanel.qml` |
| Misc | `SystemTrayWidget.qml`, `KeyboardLayoutWidget.qml`, `WeatherState.qml`, `WeatherMiniCard.qml` |

## Smoke tests

Several components ship a headless smoke config that loads them, waits a few
seconds, and quits:

```bash
QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/OmakubBarSmoke.qml
```

Available: `OmakubBarSmoke`, `NotificationSmoke`, `BatterySmoke` (requires
`BATTERY_SMOKE_TEST=1`), `BluetoothSmoke`,
`NetworkSmoke`, `ModesSmoke`, `UpdatesSmoke`,
`VideoDownloadSmoke`, `WindowsVmSmoke`, `ClockWidgetSmoke`, `AudioPanelSmoke`,
`SpeedTestSmoke`, `DiskSpeedSmoke`.

## Reloading

Quickshell watches its files and hot-reloads QML edits. When that is not enough:

```bash
quickshell log                       # concise service logs
quickshell kill && quickshell --daemonize
```

If the bar does not appear at all, check that the generated
`~/.config/hypr/themes/.active/theme.json` exists — see
[Troubleshooting](Troubleshooting.md#quickshell-bar-or-panels-do-not-appear).
