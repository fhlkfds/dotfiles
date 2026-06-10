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
stow fastfetch hypr hyprlock kitty noctalia rofi swaync waybar wofi zsh
```

**Or deploy packages individually:**

```bash
stow hypr        # ~/.config/hypr
stow hyprlock    # ~/.config/hyprlock
stow kitty       # ~/.config/kitty
stow waybar      # ~/.config/waybar
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

## What's Included

| Package | Tool | Description |
|---|---|---|
| `hypr` | [Hyprland](https://hyprland.org/) | Wayland compositor — keybinds, decorations, autostart, monitor profiles |
| `hyprlock` | [Hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen with music widget, weather, and multiple layouts |
| `kitty` | [Kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator with theme switcher (Catppuccin, Dracula, Nord, Rose Pine, Tokyo Night) |
| `waybar` | [Waybar](https://github.com/Alexays/Waybar) | Status bar with network, bluetooth, updates, and power menu scripts |
| `rofi` | [Rofi](https://github.com/davatorium/rofi) | App launcher (comet-glass theme) |
| `wofi` | [Wofi](https://hg.sr.ht/~scoopta/wofi) | Wayland-native app launcher |
| `swaync` | [SwayNC](https://github.com/ErikReider/SwayNotificationCenter) | Notification center with custom stylesheet |
| `fastfetch` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info — includes Pokémon colorscript layout |
| `noctalia` | Noctalia | Custom plugin system (clipper, wallcards, screen toolkit, etc.) |
| `zsh` | Zsh | Shell config — Oh My Zsh, Powerlevel10k, fzf-tab, eza aliases, autosuggestions |
| `Wallpapers` | — | Static and dynamic wallpapers |

---

## Dependencies

**Core:**
- `hyprland`, `hyprlock`, `hypridle`
- `kitty`
- `waybar`
- `rofi`, `wofi`
- `swaync`
- `fastfetch`

**Shell:**
- `zsh`, `oh-my-zsh`
- `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fzf`, `fzf-tab`
- `eza` (ls replacement)
- `powerlevel10k`

**Utilities used in scripts:**
- `playerctl` — media control
- `mpv` — video wallpapers
- `doas` — privilege escalation (used in place of sudo)
- `pokemon-colorscripts` — Pokémon in the terminal
- `grim`, `slurp` — screenshots
- `cliphist` / `wl-clipboard` — clipboard

Install AUR packages with your preferred helper (e.g. `paru` or `yay`).
