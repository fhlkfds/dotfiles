# dotfiles

Personal Hyprland dotfiles for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

### Prerequisites

Install GNU Stow:

```bash
sudo pacman -S stow
```

Clone the repo into your home directory:

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

> The repo must live at `~/dotfiles` for Stow to symlink correctly into `~`.

---

### Deploy with Stow

Each top-level directory is a Stow package. Run `stow <package>` to symlink its contents into `~`.

**Deploy everything at once:**

```bash
stow fastfetch hypr hyprlock kitty noctalia rofi swaync Wallpapers wofi zsh
```

**Or deploy packages individually:**

```bash
stow hypr        # ~/.config/hypr
stow hyprlock    # ~/.config/hyprlock
stow kitty       # ~/.config/kitty
stow rofi        # ~/.config/rofi
stow wofi        # ~/.config/wofi
stow swaync      # ~/.config/swaync
stow fastfetch   # ~/.config/fastfetch
stow noctalia    # ~/.config/noctalia
stow zsh         # ~/.zshrc, ~/.p10k.zsh, ~/.oh-my-zsh
```

**Wallpapers** (optional — symlinks `~/Wallpapers`):

```bash
stow Wallpapers
```

**Remove a package:**

```bash
stow -D hypr
```

**Preview without making changes:**

```bash
stow --simulate hypr
```

---

## Theme Switcher

This repo includes a **10-theme system** with a Rofi menu switcher. Press **`SUPER + T`** to open the theme selector.

### How It Works

1. **`hypr/.config/hypr/themes/themes.json`** — Central database of all 10 themes with complete color palettes, Hyprland decoration settings, and per-component color mappings.
2. **`hypr/.config/hypr/themes/apply.sh`** — Reads `themes.json`, generates all per-component config files, copies the theme wallpaper, and reloads services.
3. **`hypr/.config/hypr/scripts/theme-switcher.sh`** — Rofi menu that lists available themes and calls `apply.sh`.

### Available Themes

| Theme | Vibe | Accent Colors |
|---|---|---|
| Catppuccin Mocha 🟣 | Warm purple-pink pastel on deep dark | Mauve + Blue |
| Tokyo Night 🌃 | Deep blue-black with vibrant electric | Blue + Purple |
| Gruvbox Dark 🟤 | Warm retro amber-brown | Orange + Yellow |
| Nord ❄️ | Cool arctic blue-grey with icy teal | Teal + Blue |
| Rose Pine 🌹 | Soft dusty rose and pine | Rose + Pine |
| Everforest 🌲 | Soft earthy greens and warm browns | Green + Teal |
| Cyberpunk Neon 🌆 | Dark base with blazing neon | Magenta + Cyan |
| Monochrome Minimal ⚪ | Clean greyscale with soft blue | Blue + Grey |
| Solarized Dark ☀️ | Warm scientific balanced palette | Blue + Teal |
| Warm Pastel 🎨 | Soft warm pastels — peach, mint, lavender | Pink + Green |

### What Changes Per Theme

Each theme consistently updates:

- **Hyprland** — Active/inactive border colors, gaps, rounding, opacity, shadow, blur
- **Hyprlock** — Lock screen colors (time, date, input field, accent highlights)
- **Rofi** — Full color theme (bg, fg, accent, selection, urgency)
- **Wofi** — Window, input, entry, and text colors
- **Kitty** — Terminal 16-color ANSI palette, foreground, background, selection, cursor
- **SwayNC** — Notification center CSS (base, surface, accent, border, urgency)
- **Noctalia** — QML shell color scheme (primary, surface, error, hover)
- **Fastfetch** — Section key icon colors (distro, system, audio groups)
- **Zsh/Powerlevel10k** — OS icon foreground color
- **Wallpaper** — Theme-specific wallpaper from `Wallpapers/theme/`

### Dependencies

The theme switcher requires:

- `jq` — JSON parsing (reads `themes.json`)
- `rofi` — Theme selection menu
- `sed` — Fastfetch config patching

Optional (for live reload):

- `hyprctl` — Reloads Hyprland decorations
- `kitty` — Live-applies theme to running terminals
- `swaync` / `swaync-client` — Reloads notification CSS
- `qs` (quickshell) — Reloads Noctalia color scheme

### Switching Manually

```bash
# Apply a specific theme
~/.config/hypr/themes/apply.sh "Catppuccin Mocha"

# Check current theme
cat ~/.config/hypr/themes/current-theme
```

### Rollback

Each theme application writes generated config files. To revert:

```bash
# Restore the default stash
stow -D hypr && stow hypr

# Or manually re-source a known-good theme
~/.config/hypr/themes/apply.sh "Catppuccin Mocha"
```

### Adding a New Theme

1. Add your color palette and Hyprland settings to `hypr/.config/hypr/themes/themes.json`
2. Place a wallpaper at `Wallpapers/theme/<your-theme-slug>.jpg`
3. Run `apply.sh "Your Theme Name"`

### Troubleshooting

**Theme doesn't apply:**
- Verify `jq` is installed
- Check the theme name is exactly right (case-sensitive)
- Run `apply.sh` directly to see error output

**Kitty colors don't update:**
- Open a new terminal window or restart kitty
- The live `kitty @ set-colors` only affects existing windows

**Hyprland borders don't change:**
- The apply script calls `hyprctl reload` — this should reload decorations.conf
- If it doesn't, toggle a window or restart Hyprland

**SwayNC doesn't update:**
- Run `swaync-client --reload-config`
- Or restart swaync: `pkill swaync && swaync &`

---

## What's Included

| Package | Tool | Description |
|---|---|---|
| `hypr` | [Hyprland](https://hyprland.org/) | Wayland compositor — keybinds, decorations, autostart, monitor profiles, theme switcher |
| `hyprlock` | [Hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen with music widget, weather, and multiple layouts |
| `kitty` | [Kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator with 10 theme colorsets |
| `rofi` | [Rofi](https://github.com/davatorium/rofi) | App launcher with 10 color themes on comet-glass layout |
| `wofi` | [Wofi](https://hg.sr.ht/~scoopta/wofi) | Wayland-native app launcher with themed colors |
| `swaync` | [SwayNC](https://github.com/ErikReider/SwayNotificationCenter) | Notification center with 10 themed stylesheets |
| `fastfetch` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info with themed key colors |
| `noctalia` | Noctalia | Custom plugin system with themed color scheme |
| `zsh` | Zsh | Shell config — Oh My Zsh, Powerlevel10k, fzf-tab, eza aliases |

---

## Dependencies

**Core:**
- `hyprland`, `hyprlock`, `hypridle`
- `kitty`
- `rofi`, `wofi`
- `swaync`
- `fastfetch`

**Shell:**
- `zsh`, `oh-my-zsh`
- `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fzf`, `fzf-tab`
- `eza` (ls replacement)
- `powerlevel10k`

**Theme switcher:**
- `jq`
- `rofi`

**Utilities used in scripts:**
- `playerctl` — media control
- `mpv` — video wallpapers
- `doas` — privilege escalation (used in place of sudo)
- `grim`, `slurp` — screenshots
- `cliphist` / `wl-clipboard` — clipboard

Install AUR packages with your preferred helper (e.g. `paru` or `yay`).

---

## Wallpaper Licensing

Wallpapers in `Wallpapers/theme/` are sourced from [Unsplash](https://unsplash.com/license) — free for commercial and non-commercial use (Unsplash License). Each is a unique image selected to match its theme's color palette.

Wallpapers in `Wallpapers/static/` and `Wallpapers/dynamic/` are sourced from various free wallpaper communities. If you are the copyright holder of any image and would like it removed, please open an issue.
