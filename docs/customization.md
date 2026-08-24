# Customization guide

Make changes in this repository's Stow package paths, not in the live symlink
targets below `$HOME`.

## Common changes

| Goal | Edit |
| --- | --- |
| change terminal/file manager/disk utility | `hypr/.config/hypr/conf/var.conf` |
| change browser binding | literal `brave` command in `hypr/.config/hypr/conf/keybinding.conf` |
| change main modifier or shortcuts | `hypr/.config/hypr/conf/keybinding.conf` |
| add startup programs | `hypr/.config/hypr/conf/autostart.conf` |
| change app workspace assignments | `hypr/.config/hypr/conf/windows-rules.conf` |
| change input behavior | `hypr/.config/hypr/hyprland.conf` |
| change monitors/workspace outputs | files under `hypr/.config/hypr/monitor_profiles/` |
| change lock/DPMS/suspend timers | `hypr/.config/hypr/hypridle.conf` |
| change active lock layout | `hypr/.config/hypr/hyprlock.conf` and `hyprlock/.config/hyprlock/layouts/` |
| change bar layout/modules | QML below `quickshell/.config/quickshell/` |
| change notification policy | `quickshell/.config/quickshell/notifications/config.json` |
| change launcher layout | `rofi/.config/rofi/comet-glass.rasi` |
| change wallpaper search directory | `HYPR_WALLPAPER_DIR` or wallpaper backend default |
| change colors/gaps/borders/fonts | theme `colors.toml` and generator/templates |
| change default MIME applications | `xdg/.config/mimeapps.list` |

## Applications

`$Terminal`, `$FileManager`, and `$Disks` are variables. `$Browser` is declared
but the active `SUPER+W` binding and autostart use `brave` explicitly, so update
all intended browser references. Browser extensions also require browser-specific
flag/native-host installation.

When changing an autostarted application's workspace, update both the startup
line's requested workspace and any matching window rule if both exist.

## Keybindings

Add a described binding (`bindd`, `binded`, and related forms) so Quickshell's
live keybinding palette can display a useful action label. Check for duplicate
key/modifier pairs; the volume section demonstrates that duplicate registrations
can shadow later alternatives.

Custom script commands should resolve through `$scriptsDir` when possible. That
variable is currently an absolute personal path, so make it account-portable
before reusing it.

## Monitors and workspaces

Do not make lasting edits only to `monitors.conf` or `workspaces.conf`; the startup
watcher replaces them. Customize the paired profile files and detection logic as
described in [Monitors](./monitors.md#customizing-safely).

If you do not want dynamic profiles, remove/disable the watcher startup command
and maintain the two active files directly. Also remove any optional system udev
dispatcher so it cannot reapply a profile.

## Bar and panels

The active shell is Quickshell. Modify `Bar.qml`, components, and panel files below
`quickshell/.config/quickshell/`. Theme colors should continue to come from
`Theme.qml`/the generated active theme rather than hardcoded per-widget colors.

To switch to Waybar intentionally, add a Waybar startup command and remove or
adapt the Quickshell bar while deciding whether Quickshell should remain for
notifications/panels. Starting both unchanged produces two top bars.

## Notifications

Change timeouts, size, history limit, and DND bypass policy in the Quickshell
notification configuration. Keybindings call `notificationctl`; preserve that
IPC interface if replacing internals. Switching to SwayNC also requires changing
bindings that currently call `notificationctl`.

## Wallpapers

Set `HYPR_WALLPAPER_DIR` to a durable directory or change the picker default. The
picker currently expects a lowercase directory below `~/Pictures`. The current
`Wallpapers/` package does not create `~/Wallpapers` under standard Stow semantics;
fix or specially target that package before pointing the picker at it.

Theme wallpapers and interactive search are related but separate paths. Update
the theme asset resolver if a palette should choose a particular image.

## Appearance

Edit `hypr/.config/hypr/themes/<name>/colors.toml` for palette-specific changes.
Edit `generate.py` or its templates only for changes that should affect every
palette. Then validate and regenerate. Never commit a change only to ignored
`decorations.conf`, `colors.css`, or current-theme files.

Rofi's structural layout is in `comet-glass.rasi`; Wofi and Waybar styles are
generated from themes. Cursor theme and GTK/Qt themes are not managed here, so add
an explicit package/configuration if they should become repository-controlled.

## Applying changes

| Change | Typical application path |
| --- | --- |
| Hyprland config | `hyprctl reload` in the intended live session |
| Quickshell QML | its file watcher/reload behavior; restart only if necessary |
| theme palette | theme validation, then `theme set <name>` |
| Kitty theme | theme tool updates running Kitty where remote control is available |
| monitor profile | profile helper in a live session, after fixture/dry-run validation |
| browser extension/manifest | fully close and reopen browser; repair helper if needed |

Reloads and restarts mutate the live desktop. Run them deliberately after file
validation, not as part of a repository-only edit check.
