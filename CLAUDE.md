# CLAUDE.md

## Project overview

Personal Arch Linux dotfiles managed with GNU Stow. Each top-level directory is a Stow package that symlinks into `~` when run from `~/dotfiles`.

## Repo structure

```
dotfiles/
├── fastfetch/   → ~/.config/fastfetch
├── hypr/        → ~/.config/hypr
├── hyprlock/    → ~/.config/hyprlock
├── kitty/       → ~/.config/kitty
├── noctalia/    → ~/.config/noctalia
├── rofi/        → ~/.config/rofi
├── swaync/      → ~/.config/swaync
├── Wallpapers/  → ~/Wallpapers
├── waybar/      → ~/.config/waybar
├── wofi/        → ~/.config/wofi
└── zsh/         → ~/.zshrc, ~/.p10k.zsh, ~/.oh-my-zsh
```

## Key conventions

- Privilege escalation uses `doas`, not `sudo` — do not suggest sudo in scripts
- Shell is Zsh with Oh My Zsh + Powerlevel10k
- Editor is Neovim (`nvim`)
- `ls` is aliased to `eza` with icons
- Stow must be run from `~/dotfiles` with `~` as the implicit target

## Hyprland scripts

Live in `hypr/.config/hypr/scripts/`. They are called from keybindings defined in `hypr/.config/hypr/conf/keybinding.conf`. Keep scripts POSIX-compatible where possible, bash otherwise.

## Adding a new package

1. Create `<package>/.config/<package>/` (mirroring the `~/.config/` path)
2. Add config files inside
3. Run `stow <package>` from `~/dotfiles`
4. Document the package in README.md
