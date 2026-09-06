# ASCII screensaver

The `screensaver` Stow package opens one fullscreen terminal on every active
Hyprland monitor and runs a continuous sequence of random `ttfx` effects. A key
press or loss of focus closes the session. Pointer movement is ignored.

## Commands

```bash
ascii-screensaver force          # manual launch, including when automatic use is off
ascii-screensaver --dry-run      # print monitor focus and terminal spawn commands
toggle-screensaver               # toggle automatic use
toggle-screensaver status
screensaver-branding text
screensaver-branding image logo.png
screensaver-branding reset
screensaver-lock --dry-run       # show lock cleanup without changing session state
install-ttfx --dry-run           # show the package-helper or Cargo install
```

`SUPER+CTRL+Escape` force-launches the screensaver.
`SUPER+CTRL+SHIFT+Escape` toggles automatic launch. The same actions are in
`lmenu` under System and Trigger > Toggle.

The launcher uses the desktop-entry ID returned by
`xdg-terminal-exec --print-id`. Alacritty, Foot, Ghostty, and Kitty are
supported. Other IDs produce a desktop notification and exit with status 1.
Dedicated black, opaque, 18-point, zero-padding configurations live under
`screensaver/.config/ascii-screensaver/`.

## Idle and lock policy

The primary `hypr/.config/hypr/hypridle.conf` starts the screensaver after 180
idle seconds when no PipeWire output stream is running, and locks after 300
seconds. While audio is playing, Hypridle retries the condition every five
seconds. The persistent off flag is
`$XDG_STATE_HOME/toggles/screensaver-off` (normally
`~/.local/state/toggles/screensaver-off`). Manual force-launch ignores it.

The lock command terminates `ttfx`, waits up to one second for it to exit, closes
the screensaver terminals, and then starts Hyprlock. Hypridle cannot reproduce
the source implementation's conditional cancellation of the pending lock when
the screensaver loses focus: the 300-second timeout still fires unless real
input resets Hypridle's timers.

## Logo

The editable logo is `~/.config/branding/screensaver.txt`; its Stow source is
`screensaver/.config/branding/screensaver.txt`. Reset copies the repo-owned
default from `screensaver/.local/share/ascii-screensaver/default-logo.txt`.

Image conversion defaults to 80 columns by 26 rows in Unicode braille. Use
`--mode block`, `--width`, and `--height` after the image path to override it.
The converter detects real alpha, normalizes opaque light and dark backgrounds,
trims the image, writes through a temporary file, and rejects empty output.
Every branding command force-launches a preview after a successful change.

## Dependencies

Runtime dependencies are Bash, `ttfx`, `xdg-terminal-exec`, `socat`, `jq`,
Hyprland, Hypridle, Hyprlock, and one supported terminal. Image conversion needs
ImageMagick 7 (`magick`). `install-ttfx` tries `paru` or `yay` first and falls
back to a locked Cargo build from `omacom-io/ttfx`, installed under
`~/.local/bin`.
