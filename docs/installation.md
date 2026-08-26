# Installation and deployment

## Deployment model

The repository uses [GNU Stow](https://www.gnu.org/software/stow/) packages. A
path such as:

```text
hypr/.config/hypr/hyprland.lua
```

is intended to become:

```text
~/.config/hypr/hyprland.lua
```

when the `hypr` package is stowed from the repository root. The top-level
`README.md` shows cloning to `~/dotfiles` and running `stow <package>`.

There is no `install.sh`, bootstrap program, Makefile, or complete package list.
Package installation and system-level configuration therefore remain manual.

### Greetd session entrypoint

`system/greetd/config.toml` is the repository-owned system template. It launches
the default Hyprland session through `/usr/bin/start-hyprland`, which supplies
Hyprland's watchdog. This file is not a home-directory Stow package. Review the
diff, then deploy it explicitly:

```bash
sudo install -Dm0644 system/greetd/config.toml /etc/greetd/config.toml
```

Do not restart greetd from inside the graphical session. Let the change take
effect at the next reboot, or restart it deliberately from a TTY.

On Arch Linux, install the deployment tool, clone into the path expected by the
root README, and enter the repository:

```bash
sudo pacman -S stow
git clone <repository-url> ~/dotfiles
cd ~/dotfiles
```

The repository URL is intentionally a placeholder here because the tracked
README does not define a canonical public clone URL.

## Before installing

1. Review [Dependencies](./dependencies.md). At minimum the selected packages
   must have their corresponding applications installed.
2. Search for `/home/liam` and replace account-specific paths before using a
   different username. Important occurrences are summarized below.
3. Adapt the output names and modes in [monitor profiles](./monitors.md).
4. Back up or reconcile existing files under `~/.config`, `~/.local/bin`, and
   `~/.local/share/applications`; Stow will report conflicts rather than safely
   merging arbitrary existing files.
5. Generate a theme before first use; see [Theme bootstrap](./themes.md#theme-bootstrap).

## Stow packages

From the cloned repository root, deploy only the components you want. For the
currently active desktop, the relevant package names are:

```bash
stow hypr hyprlock quickshell rofi kitty cliphist browser xdg windows
```

Preview the exact links before deploying a selection:

```bash
stow --simulate --verbose hypr quickshell
```

Optional shell and startup-display packages are:

```bash
stow zsh fastfetch ai
```

The `zsh/.oh-my-zsh` entry is recorded as a Gitlink, but this repository has no
`.gitmodules` mapping for it. A fresh clone therefore cannot initialize it with
`git submodule update`. Install Oh My Zsh separately at `~/.oh-my-zsh`, or repair
the repository's submodule metadata before relying on the `zsh` package.

Alternative or retained desktop components may be deployed separately:

```bash
stow waybar swaync wofi noctalia
```

The wallpaper package is unusual. Despite the root `README.md` saying it creates
`~/Wallpapers`, the package currently contains `static/`, `dynamic/`, `theme/`,
and image files directly at its package root. Standard `stow Wallpapers`
therefore targets `~/static`, `~/dynamic`, `~/theme`, and individual files in
`~`, not a containing `~/Wallpapers` directory. A Stow simulation confirms this
layout. To keep them contained, either reorganize the package to contain a nested
`Wallpapers/` directory or deliberately use `~/Wallpapers` as that package's
Stow target. The active picker separately defaults to
`/home/liam/Pictures/wallpapers`, so it will not find either layout automatically.

The root `README.md` has an example “deploy everything” loop, but it omits the
tracked `cliphist`, `waybar`, and `xdg` packages. Prefer choosing packages
explicitly.

### Optional Windows VM

Stow `windows` together with `hypr`, then complete Docker access manually before
running the installer. The helper will not invoke sudo or alter system services:

```bash
sudo systemctl enable --now docker.service
sudo usermod -aG docker liam
# log out and back in, then verify:
docker info
windows-vm install
```

The installer confirms resources and credentials before downloading anything.
Its defaults on this machine are 8 GiB RAM, four CPU cores, and a 128 GiB disk.
Windows 11 media and the container image require additional space beyond the
virtual disk and may take substantial time to download.

## Required post-deployment work

### Generate appearance files

Run the theme tool from its deployed path after choosing one of the palette names:

```bash
~/.config/hypr/themes/theme set tokyo-night
```

This generates files intentionally excluded from Git, including Hyprland
decorations, Kitty/Rofi/Hyprlock colors, and the Quickshell active theme. Do not
hand-maintain those generated files; edit the source palette instead.

### Chromium/Brave integration

The `browser` package installs extension files, browser flag files, native host
manifests, native executables, and repair helpers. The checked-in files use
absolute `/home/liam` paths, so another account must update them first.

Close the browser before using the shortcut repair helper. Its normal mode is a
read-only dry run; `--apply` performs profile-state repair. Supported profile
families include Chromium, Chrome variants, Brave variants, and Edge. Details are
in [Browser integration](./components.md#browser-integration).

### Optional monitor hotplug helper

`hypr/.config/hypr/udev/` contains an optional system udev rule and root-owned
dispatcher. Stow does not install files into `/etc/udev/rules.d` or
`/usr/local/sbin`. The comments in those files describe the manual privileged
installation. This is optional because the active session already runs the
15-second user-space monitor watcher.

## Account and machine assumptions

The following are not portable without review:

| Assumption | Where it appears |
| --- | --- |
| `/home/liam/.config/hypr/scripts` | Hyprland variables, bindings, autostart |
| `/home/liam/.config/waybar/scripts/power-menu.sh` | Power-menu binding |
| `/home/liam/Pictures/wallpapers` | Wallpaper picker tool |
| `/home/liam/.config/hypr/scripts/capture/capture.sh` | Quickshell recording state |
| `/home/liam` native-host executable paths | Browser manifests and browser flags |
| DP/eDP connector names and exact resolutions | Monitor profiles |
| Personal VPN and GAM paths | `zsh/.zshrc` |
| User-specific location, display, and network state | retained `noctalia/` settings |

No credentials or private keys are required by the active desktop configuration.
The repository does contain personal path and local-state assumptions, so review
it before publishing a derived configuration.

## Updating the deployment

Edit the repository paths, not the live symlink targets. For example, change
`hypr/.config/hypr/conf/keybindings.lua`, not
`~/.config/hypr/conf/keybindings.lua`. Re-stow only when package topology changes;
ordinary edits are immediately visible through existing symlinks.

Restart/reload behavior is component-specific. See
[Customization](./customization.md#applying-changes) rather than restarting the
entire session by default.
