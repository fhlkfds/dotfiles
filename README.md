# dotfiles

Personal Hyprland dotfiles for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

**[Read the wiki](wiki/Home.md)** for the full reference: setup, architecture, the
complete keybinding list, where to customize each part, and how to provision a
whole machine with Ansible. This page is the feature tour.

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

Most top-level directories are Stow packages. Run `stow <package>` to symlink its
contents into `~`.

> **`docs/`, `wiki/`, `tests/` and `system/` are not packages — never stow them.**
> `system/` holds root-owned `/etc` templates that `yubikey-auth` deploys;
> stowing it would create `~/greetd` and `~/pam.d`.
> Never stow `wallpaper` either: it would put the images in `~`.
> `wallpaper-sync` owns `~/Pictures/Wallpapers` (see **Wallpapers** below).

**Deploy the standard packages at once:**

```bash
stow ai browser cliphist fastfetch greeter hypr hyprlock kitty modes \
     menu quickshell rofi screensaver security ssh systemd windows xdg zsh
```

**Or deploy packages individually:**

```bash
stow ai          # ~/.local/bin/ai-agent, ~/.config/ai-agent
stow screensaver # screensaver commands, terminal configs, and editable logo
stow modes       # ~/.local/bin/desktop-mode, temporary mode policy/config
stow security    # ~/.local/bin/yubikey-auth, safe YubiKey PAM setup/addition;
                 # ~/.local/bin/fingerprint-auth, laptop fingerprint sign-in;
                 # ~/.config/gnupg-conf gpg/gpg-agent examples
stow ssh         # ~/.local/bin/sshpersist, SSH keepalive config fragment
stow browser     # Chromium extensions, flags, and native messaging hosts
stow hypr        # ~/.config/hypr
stow hyprlock    # ~/.config/hyprlock
stow kitty       # ~/.config/kitty
stow rofi        # ~/.config/rofi
stow fastfetch   # ~/.config/fastfetch
stow menu        # ~/.config/lmenu, ~/.local/bin/lmenu
stow quickshell  # ~/.config/quickshell
stow windows     # Windows VM helper, Compose template, and application entry
stow cliphist    # ~/.config/cliphist
stow xdg         # ~/.config/mimeapps.list, ~/.local/share/applications
stow zsh         # ~/.zshrc, ~/.p10k.zsh (see Shell setup below)
```

## Persistent SSH sessions

The `sshpersist` launcher provides reconnecting SSH sessions through autossh and
tmux on the remote host.
Install the required Arch packages without changing any configuration:

```bash
sudo pacman -S --needed autossh tmux
```

After stowing `ssh` and optionally `zsh` for the `sshp` shortcut, add this line
at the end of `~/.ssh/config`:

```sshconfig
Include ~/.config/ssh/conf.d/*.conf
```

SSH uses the first obtained value for each parameter, so keeping the included
`Host *` defaults last lets per-host blocks above it retain precedence. That
manual include keeps the existing `~/.ssh/config` under user control. Start or
return to a host-named remote session with `sshpersist <host>` or `sshp <host>`.
An optional second argument selects another safe session name:

```bash
sshpersist server.example.com
sshp server.example.com maintenance
```

`autossh -M 0` relies on SSH keepalives instead of a legacy monitor port. If a
plain SSH connection is already open, reattach its session with
`tmux attach -t <host>`; punctuation in the automatic host-derived session name
is replaced with underscores (for example, `server.example.com` becomes
`server_example_com`). The remote host also needs `tmux` installed.

`btop` deploys automatically with `dots deploy`/`dots update`, which passes
`--no-folding` for it. `wallpaper` is not stowed at all; `wallpaper-sync` owns
it (see **Wallpapers** below). `neovim` and `obsidian` stay opt-in
because they write into trees this repository does not own; deploy them without
directory folding so application-created files stay outside the Git checkout:

```bash
stow --no-folding neovim obsidian
```

Their package-level `.gitignore` files keep accidental app state untracked, but
do not prevent Stow from folding a missing target directory into one symlink.
Without `--no-folding`, a later `git clean -xfd` could therefore delete app
state written through that symlink.

## ASCII Screensaver

The `screensaver` package runs an original `ttfx` ASCII logo on each active
Hyprland monitor. The default Balanced profile attempts automatic launch after
20 idle minutes when enabled and no audio is playing. It also locks and turns
displays off at 20 minutes, so the automatic screensaver normally has no
visible interval. Audio only defers the screensaver; it does not defer locking.

```bash
ascii-screensaver force                 # manual fullscreen launch
ascii-screensaver --dry-run             # print planned monitor spawns
toggle-screensaver                      # enable/disable automatic launch
screensaver-branding text               # edit and preview the logo
screensaver-branding image logo.png     # convert and preview an image
```

See [the complete screensaver guide](docs/screensaver.md) for terminal support,
logo conversion, idle behavior, and recovery.

## Desktop Modes

The independent `modes` package unifies night light, Quickshell DND,
stay-awake, and automatic-screensaver state without owning lock, suspend, DPMS,
or authentication policy.

Night light, DND and stay-awake can run for a set time: the panel offers 30m,
1h, 3h and 8h (`duration_presets` in `~/.config/desktop-mode/config.toml`)
plus a Custom box that takes `45m`, `2h` or `1h30m`. While stay-awake is on,
the daemon holds a `systemd-inhibit --what=idle` block, so Hypridle skips the
screensaver, screen off, lock and suspend. Each Hypridle listener also runs
`desktop-mode condition`, so this holds even when the daemon is down. Idle
time does not count while stay-awake is on: when it ends, those timers start
over (20 minutes to lock, 30 to suspend) rather than firing at once. A manual
suspend or a closed lid still sleeps.

```bash
desktop-mode status
desktop-mode enable stay-awake --for 3h
desktop-mode enable night-light --for 1h30m
desktop-mode toggle do-not-disturb
desktop-mode action screensaver
desktop-mode doctor --json
```

Open the Quickshell panel with `SUPER+ALT+M`. Close it with `SUPER+Q` or
`Escape`; `SUPER+Q` closes the focused application when this panel is closed. See the
[desktop modes guide](docs/desktop-modes.md) for boundaries, timers, recovery,
and all commands.

## AirPods battery in the Bluetooth panel

Keep LibrePods running (its `--hide` option starts it in the background). When
BlueZ and UPower have no battery reading, the panel reads LibrePods' tray tooltip
over the user D-Bus and displays left, right, and case percentages. The bar and
low-battery alerts use the higher earbud reading because LibrePods may report
zero for an absent bud. No additional AirPods connection is opened.

The fallback requires `busctl`, one connected AirPods device identified by its
Apple identity and service UUID, and one LibrePods process. Missing, malformed,
or ambiguous readings stay unknown. The tooltip format is specific to the
installed LibrePods version; a future change to it may need a parser update.

Validate with `bash tests/librepods-battery.test.sh` and
`bash tests/bluetooth-control.test.sh`.

## Volume and brightness OSD

The volume, mute, and brightness keys still call `wpctl` and `brightnessctl`
directly. The resident shell notices the change on its own (PipeWire for the
sink, a file watch on `/sys/class/backlight/<device>/actual_brightness`) and
shows a pill at the bottom of the focused screen. It fades after about 1.2 s,
and further presses update the same pill instead of stacking. Machines with no
backlight device only get the volume pill.

Validate with `bash tests/osd.test.sh`.

## Voice dictation

`SUPER+R` toggles dictation. It runs through
[Hyprvoice](https://github.com/leonardotrapani/hyprvoice) and the
`voice-dictation` script. The Hyprvoice service gets wrappers from
`~/.local/libexec/hyprvoice-gpu` (Stow package `systemd`) through a drop-in that
puts that directory first on its `PATH`.

### GPU acceleration

GPU use is a per-machine choice, so the same dotfiles work on an AMD desktop,
an Intel laptop, and a machine with no supported GPU. Whisper runs on the CPU
unless `~/.local/share/hyprvoice-gpu/device.env` exists, and it falls back to
the CPU whenever a GPU run fails.

```bash
hyprvoice-gpu-install --dry-run   # show the detected GPU, driver and files; change nothing
hyprvoice-gpu-install --enable    # verify the installed GPU build and turn it on
hyprvoice-gpu-install --install   # build whisper.cpp with Vulkan, verify it, turn it on
```

The script supports AMD (RADV) and Intel (ANV) GPUs. It picks AMD first when a
machine has both, and `--vendor amd|intel` overrides that. It writes
`device.env` only after a sample transcription ran on that vendor's GPU through
Vulkan. A failed `--enable` removes `device.env`, so dictation stays on the CPU
until the check passes.

A successful run also renames older hand-made drop-ins that pin a GPU, such as
a copied `10-amd-gpu.conf`, to `*.disabled`. It then tells you to run
`dots deploy`, `systemctl --user daemon-reload` and a Hyprvoice restart. The
script never runs those itself.

### Clipboard mode

Choose how text is delivered in the menu under Setup, Voice dictation: "Type
automatically" (the default) or "Copy to clipboard". The commands behind them
are `voice-dictation use-typing` and `voice-dictation use-clipboard`;
`voice-dictation delivery` prints the current mode. Typing mode never falls
back to the clipboard, so a failed typing attempt cannot replace what you
copied. Each dictation start keeps it typing-only and leaves clipboard mode
alone.

In clipboard mode you paste the text yourself. One notification covers the
whole dictation. It reads "Recording Started", then "Transcribing…", then
"Dictation copied — ready to paste" once the clipboard has been read back and
matches. If anything fails it reads "Dictation failed" instead, with
"No speech was recognized." when the recording had no words.

Validate with `bash tests/hyprvoice-gpu.test.sh`,
`bash tests/hyprvoice-clipboard.test.sh` and `bash tests/voice-dictation.test.sh`.

## Wallpaper transitions

Picking a wallpaper (`SUPER+SHIFT+W`, or a Wallhaven download) plays an
animated transition, drawn by the shell over hyprpaper. The transitions,
shader and maps are adapted from
[pocket-dots](https://github.com/diegoMalagrida/pocket-dots) (GPL-3.0):

- **Contagion**, for any wallpaper: colonies land at random places and eat
  through the old wallpaper in crisp 4 px cells, each burning for an instant in
  the theme's most vivid colour.
- **Outline**, for a wallpaper with a character: a thin line draws the
  character's outline, the character fills in, and the rest spreads out of it.

`hypr-wallpaper-picker` asks `wallfx pick` which transition the new wallpaper
gets, then hands it to `WallpaperFx.qml` over IPC. The shell covers the screen,
switches hyprpaper underneath, and uncovers. Restoring the wallpaper at login,
re-applying the wallpaper already on screen, and `theme set --wallpaper` switch
directly. If the shell is not running or the maps cannot be made, the picker
falls back to a direct switch, so the wallpaper always changes.

Contagion needs `python-numpy` and `python-pillow`, which `dots` installs
(see **Script dependencies** below). Outline is opt-in. It cuts characters out with BiRefNet, in a venv of
about 1 GB:

```bash
wallfx install          # venv + rembg under ~/.local/share/wallfx (needs uv)
wallfx warm             # cut out every wallpaper ahead of time
wallfx pick <image>     # print the transition and maps the picker would use
```

After each change the picker also runs `wallfx warm` in the background, so a
new download gets its outline the next time. A wallpaper picked before it was
warmed is cut out on the spot, for up to 25 seconds, with a notification. List
a file name in `~/.config/wallfx/no-outline` to always give that wallpaper
contagion, for when the model outlines a building or a bridge. Maps are cached
in `~/.cache/wallfx`. `quickshell ipc call wallfx stats` reports the frame
rate of the last transition.

Validate with `bash tests/wallpaper-fx.test.sh`, `python3 tests/wallfx.test.py`
and `bash tests/hypr-wallpaper-picker.test.sh`.

## Network speed test

`network-speedtest` resolves the active interface through `ip route`, runs eight
parallel fast.com transfers for five seconds in each direction, and calculates
Mbps from the interface's kernel byte counters. It prints the interface,
download speed, and upload speed to stdout. The Quickshell entry points stream
each one-second sample into a full-screen, themed gauge overlay.

`SUPER+ALT+T`, the Quickbar network panel, and lmenu run the overlay.
`SUPER+SHIFT+T` remains assigned to OCR. The tool is part of the `hypr` Stow
package. Press Escape to close the overlay; use Run again after a test finishes.

Install its Arch dependencies with:

```bash
paru -S --needed curl jq gawk iproute2
```

`gawk` provides `awk`.

The fast.com token is public and hardcoded. Netflix can rotate or restrict it,
which may make the API return HTTP 403. That is a known fragility of the
unofficial API, not a script failure.

## Timer

A countdown that shows in the bar, left of the clock, and rings when it ends.
One timer runs at a time.

- **Keys:** `SUPER+ALT+Z` opens the panel on the focused monitor. Press `Alt+1` to
  `Alt+4` for the presets (5, 10, 25 and 60 minutes, set in
  `quickshell/.config/quickshell/timer/config.json`), or type a time and press
  Enter. Escape, a click outside, `SUPER+ALT+Z` again and `SUPER+Q` close the
  panel.
- **Menu:** lmenu (`SUPER+SHIFT+A`), Trigger → Timer: 5, 10, 25 or 60 minutes,
  or Custom time… to open the panel. Scripts can run
  `quickshell ipc call timer start 7m30s`.
- **Time formats:** a bare number is minutes (`10`), `90s`, `7m30s`, `1h`,
  `1h30m`, or `7:30` for minutes and seconds. The longest is 24 hours.
- **In the bar:** the pill counts down while it runs. Click it for the panel,
  where `+1 min` adds a minute and `Cancel` stops it. When time is up it turns
  red and reads Done. Click it, or open the panel, to clear it.
- **Do not disturb:** when it ends the shell sends a notification and plays
  `alarm-clock-elapsed.oga`, unless do-not-disturb is on. Then nothing pops up
  or plays, and the red Done pill is the only sign.
- **Restarts:** the end time is saved in
  `${XDG_STATE_HOME:-~/.local/state}/quickshell/timer.json`, so a reload or
  suspend does not lose it. A timer that ended while the shell was down shows
  Done and rings once.

Test it with `bash tests/timer.test.sh`. It runs `node tests/timer.logic.test.js`
for the state machine, then `TimerSmoke.qml` with a fake clock, so nothing
notifies or plays a sound.

## Disk speed test

`disk-speedtest` measures a disk's sequential write, sequential read, and
random 4K read speed in MB/s. It writes a temporary file of up to 1 GiB on a
mounted filesystem, runs each phase for eight seconds, and deletes the file
afterwards. It never touches the raw device and never needs root. The
Quickshell overlay fills three gauges in run order: Write, Read, and 4K
Random. The 4K gauge also shows IOPS and average latency.

Open it from lmenu (`SUPER+SHIFT+A`, Trigger → Disk Speed Test). It has no
keybinding. With one testable disk the test starts at once. With more, the
overlay lists them first and preselects the system disk; pick one with the
arrow keys and Enter. The script mounts an unmounted drive with `udisksctl`
and unmounts it when the test ends. The overlay greys out read-only, locked,
and unwritable drives and says why. Escape stops the test and closes the
overlay. Run again and Change disk appear once a test finishes.

On the disk that holds your home directory the test file goes in
`${XDG_CACHE_HOME:-~/.cache}/disk-speedtest/`. Other drives get a hidden
`.disk-speedtest/` folder at their mount point. The script creates the file
NOCOW, which turns off btrfs compression and checksums for it, then reads and
writes it with direct I/O so the page cache cannot inflate the numbers. If a
filesystem refuses direct I/O, the script falls back to buffered I/O and the
overlay labels the result as cached. On a nearly full disk the test file
shrinks to half the free space, and the overlay says so. Below 512 MiB free
the test refuses to run.

```bash
disk-speedtest                  # test the system disk and print a summary
disk-speedtest --list-json      # show every disk and why it can or cannot be tested
disk-speedtest --disk sdc --dry-run   # plan a test of drive sdc without mounting or writing
```

It requires Python 3 and `lsblk`. Mounting unmounted drives also needs
`udisksctl` from `udisks2`.

## YubiKey authentication

The optional `security` package provides a guarded setup command for the
YubiKey Bio, sudo, and Hyprlock. It never stores the registered credential in
Git and keeps password authentication as the final fallback.

The same commands are available from `SUPER+SHIFT+A` under Setup > Security >
YubiKey. Status and setup run in a held terminal, so an incomplete setup leaves
its error on screen instead of closing the window.

```bash
yubikey-auth status
yubikey-auth setup --enroll-fingerprint  # first key and PAM deployment
yubikey-auth add --enroll-fingerprint    # additional YubiKey Bio
yubikey-auth add --dry-run               # inspect without changing anything
```

After opening a new Zsh session, the conflict-safe shortcuts are `yubi`,
`yubi-status`, `yubi-setup`, and `yubi-add`. The last two include Bio
fingerprint enrollment automatically.

The command validates mappings, creates timestamped `/etc` backups, installs
sudo first, and waits for explicit confirmation after key/password testing
before installing Hyprlock PAM. See [installation and recovery](docs/installation.md#yubikey-authentication).

## Fingerprint sign-in

Separate from the YubiKey Bio, and only for laptops with their own sensor — the
Goodix reader in a Framework 13 power button, for instance. `fingerprint-auth`
ships in the same `security` package and is a no-op on desktops:

```bash
fingerprint-auth status                        # reader, tools, prints, wiring
fingerprint-auth setup                         # install fprintd, enroll, configure Hyprlock and PAM
fingerprint-auth enroll --finger left-thumb    # one more finger
fingerprint-auth setup --dry-run               # inspect without changing anything
```

It is also the **Setup → Security → Fingerprint** entry in the Super+Shift+A
menu, which only appears once the command is on `PATH`.

Hyprlock unlock uses its own fprintd support (`auth:fingerprint:enabled`) so
the scan runs alongside the password field. Setup also deploys fingerprint PAM
templates for sudo, doas, and greetd. It asks you to test escalation before
installing the greetd template; use `--no-pam` to leave system PAM alone.

Enrollment needs `fprintd`, which is in the `optional` setup group. If it is
missing and a reader is present, `setup` installs it with
`doas pacman -S --needed fprintd`, or sudo when doas is absent. Pacman lists
the packages and asks before installing anything. On a host with no reader
every subcommand explains that and exits without installing or touching
anything.

**Wallpapers** sync between every machine running these dotfiles, with
nothing to run by hand. `~/Pictures/Wallpapers` is a symlink to the
`wallpaper/` directory of a sparse worktree at `~/Pictures/.wallpaper-sync`,
detached at `origin/main`. Hyprland's autostart starts `wallpaper-sync.path`,
which pushes after a top-level change and a 30-second quiet period, and
`wallpaper-sync.timer`, which pulls at login and every 15 minutes. Each change
is committed as `wallpaper: sync from <host>` and pushed straight to `main`;
the branch checked out in `~/dotfiles` is never touched.

- Deleting a wallpaper on one machine deletes it on all of them.
- A different image under a name another machine already pushed is kept as
  `<name>-<host>.<ext>` (then `-2`, `-3`, etc. if needed); the same image is not duplicated.
- Partial downloads (`*.part`, `*.crdownload`, hidden files) and files over
  50 MB stay local, including oversized edits of tracked files. Only recognized
  image/video extensions are uploaded.
- Changes inside existing subdirectories are picked up by the 15-minute timer;
  the path watch covers the top-level directory. Copies still changing after
  two minutes are deferred to a later run.
- Conflicting edits to an existing image stop with a notification for manual
  resolution; both different additions with the same filename are kept.
- Pushing runs unattended, so the SSH key for `origin` must be loaded in an
  agent the user systemd manager can see, or have no passphrase. Failures are
  in `journalctl --user -u wallpaper-sync`.
- The repository is public: every synced wallpaper is published and stays in
  Git history.

The first run on a machine replaces an existing `~/Pictures/Wallpapers`: links
the old `stow wallpaper` made are removed, and any other images in it are added
as new wallpapers. A folder containing unrelated files or links is refused
before its contents are changed. To sync now instead of at next login:

```bash
systemctl --user start wallpaper-sync.timer wallpaper-sync.path
```

**Remove a package:**

```bash
stow -D hypr
```

**Preview without making changes:**

```bash
stow --simulate hypr
```

### Deploy changed packages with `dots`

Stow the `dots` package once to install the deployment helper, then use it from
any directory. The first run restows every package; later runs restow only
packages changed since the last successful deployment.

```bash
stow dots
dots deploy --dry-run  # show packages and actions without changing anything
dots deploy            # restow changed packages and reload live Hyprland if needed
dots deploy --all      # restow every package
dots deploy --system   # also install the greetd and PAM templates via sudo
dots update            # fast-forward pull, then restow packages changed upstream
```

**Script dependencies.** `setup/manifests/scripts.txt` lists the small
packages the repository's own scripts need: Python libraries such as
`python-pillow`, and helpers such as `grim`, `slurp` and `tesseract`. It does not
list the desktop itself (Hyprland, Quickshell). Every `dots deploy` and
`dots update` checks the list with `pacman -T`, which needs no root. It installs
anything missing with `pacman -S --needed` through `doas` or `sudo` before
restowing, and pacman asks before installing. A run with no terminal, or a
declined or failed install, still deploys. It then exits with an error that
names the missing packages and the command to install them. `--dry-run` lists
them under Actions. Add a package to the list when a script starts needing it.
`SUPER+CTRL+U` runs `dots update` in a terminal, so it can ask for your password.

`dots update` pulls the branch's upstream. A branch pushed without `-u` has
none, so it pulls the same-named branch on `origin` instead; a branch that only
exists locally skips the pull and deploys the checkout as it is.

System templates are opt-in and are never stowed. Stow conflicts stop the
deployment without adopting or overwriting files. Unresolved merge conflicts
in the checkout (for example, from an autostash that popped back with
conflicts) also stop it, including `--dry-run`, and the conflicted files are
listed. The successful commit is
recorded in `~/.local/state/dots/last-deployed`.

### Automated checks

[Dotfiles CI](.github/workflows/ci.yml) runs on pull requests, pushes to `main`,
and manual dispatch. The workflow contains the CI commands; no extra test
helper scripts are needed. In an Arch Linux container it checks source syntax,
whitespace, changed shell scripts with ShellCheck, and the existing fixture
tests. Checks requiring a desktop backend or Wayland session are reported as
skipped; missing required test tools fail CI. Docker Compose fixture checks run
on the Ubuntu runner, which already provides Docker.

Deployment checks run `dots deploy --all --dry-run` and GNU Stow's simulation
against an empty temporary target. They never apply dotfiles to a desktop.
Separate jobs validate the workflow with actionlint, scan Git history for
secrets with Gitleaks, and scan source with Semgrep's security rules. `arch-audit`
checks the packages installed in the CI container for known vulnerabilities;
it does not inventory your desktop. Findings fail CI and may include existing
issues in the repository or its history.

---

## AI Agent Launcher

The standalone `ai` package provides one launcher for Claude Code through
TeamClaude, Codex, OpenCode, and T3 Code. It does not install or authenticate
any agent and has no Omarchy dependency.

The default is configured in `ai/.config/ai-agent/config`:

```text
default_agent=t3code
```

Selection priority is `--agent`, then `AI_AGENT_DEFAULT`, then the config file.
Setup > Defaults > Coding agent in lmenu rewrites that file, offering only the
agents that are installed, plus every installed [web app](#web-apps). A web app
is stored as `default_agent=webapp:<id>` (for example `webapp:chatgpt`) and
opens in its own window through `webapp-launch`; it takes no agent arguments. The same menu sets the default browser, editor
and terminal.
Invalid names and unavailable executables fail clearly; the launcher never
silently switches to another agent.

After stowing both `ai` and `zsh`, these commands are available in a new shell:

```bash
ai                         # configured default
ai-claude                  # Claude Code through TeamClaude
ai-codex                   # Codex directly
ai-opencode                # OpenCode directly
ai-t3code                  # T3 Code directly
ai-agent --agent claude    # one-invocation override
ai-agent --agent codex -- --help  # pass --help to the selected agent
```

The aliases are only defined when their names are otherwise unused. The
launcher preserves the current working directory and passes agent arguments
through unchanged. The Claude selection requires `teamclaude` on `PATH` and
invokes `teamclaude run --` with those arguments. Install and configure
TeamClaude before using `ai-claude`; the launcher does not install it.

`SUPER + I` opens the configured default. T3 Code is assigned to workspace 4
by its `t3code` window class. `CTRL + SHIFT + 2` triggers T3 Code's
`capture-window` global shortcut, which attaches a window screenshot to the
active thread. Change or remove that binding in
`hypr/.config/hypr/conf/keybindings.lua` to alter or disable it. It is not active
until the relevant packages are stowed and Hyprland is reloaded by the user.

### Answer permission prompts from a notification

`agent-permission-hook` shows an agent's permission request as a notification
with **Deny** and **Allow once** buttons. **Deny** is the filled button, so the
prominent choice is the safe one. A click answers the agent. The card
shows the whole command exactly as the agent sent it.

A bar along the bottom of the card counts down the time left. If you don't
click before the time limit, the hook closes the card and gives no answer. The agent then waits at its own prompt. A timeout, a dismissed card
or any error never counts as approval.

The two agents treat their own prompt differently while the card is up:

- **Claude Code** shows its terminal prompt at the same time as the card. If
  you answer in the terminal first, Claude Code stops the hook and the card
  closes.
- **Codex** shows its terminal prompt only after the hook ends. To answer in
  the terminal instead, dismiss the card (its close button or `Super+,`). The
  Codex prompt then appears at once. Codex uses a 60-second limit for this
  reason.

| Agent | Supported | Hook event |
|---|---|---|
| Claude Code | Yes | `PermissionRequest` |
| Codex | Yes | `PermissionRequest` |
| Grok CLI | No | Its hooks can block a call but can't approve one |

Add the hook to Claude Code in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "agent-permission-hook claude", "timeout": 130 }
        ]
      }
    ]
  }
}
```

Add the hook to Codex in `~/.codex/hooks.json`, then trust it in Codex's hook
review:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "agent-permission-hook --timeout 60 codex", "timeout": 70 }
        ]
      }
    ]
  }
}
```

Keep each agent's `timeout` above the hook's own limit. If the agent kills the
hook first, the card still closes, but the hook gives no answer. Set the limit
with `--timeout SECONDS` or `AGENT_PERMISSION_TIMEOUT`. The default is 120
seconds.

A wrong argument in the hook command makes the hook exit with code 2, and
both agents read exit code 2 as **Deny**. If every request is denied at
once, check the hook command.

A request longer than 8000 bytes shows no card, because the card can't show
all of it. Answer that request in the terminal.

Preview a card without showing it:

```bash
echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}' |
  agent-permission-hook --dry-run claude
```

The card is a critical notification with the `desktop-verbatim` hint (see
[Notifications](#notifications)). It also shows while Do Not Disturb is on:
`Claude Code` and `Codex` are on the `dndBypassApps` list in
`quickshell/.config/quickshell/notifications/config.json`, and the hook sends
the `desktop-bypass-dnd` hint. Remove both names from the list to let DND hold
these cards.

---

## Windows VM

The optional `windows` package provides a Dockur Windows 11 VM managed through
one command:

```bash
windows-vm install
windows-vm launch
windows-vm launch --keep-alive
windows-vm status
windows-vm stop
windows-vm logs
windows-vm remove
```

`SUPER+ALT+W` starts or connects to it, and `SUPER+CTRL+ALT+W` stops it
gracefully. RDP and the installation web UI bind to localhost only; `~/Windows`
is the sole shared host directory. Persistent VM data lives in `~/.windows`,
while credentials and resource settings remain host-local under
`~/.config/windows` rather than in this repository. Successful container starts
and stops send desktop notifications; readiness, installation, and error states
continue to use the same notification path. Since RDP is loopback-only, FreeRDP
uses non-interactive certificate handling so a regenerated VM certificate cannot
leave a hidden modal dimming and blocking another window.

New Windows installations also use Dockur's OEM hook to ensure WinGet, then
install Sysinternals, Everything, Helium, and PuTTY. Its transcript is saved at
`C:\OEM\post-install.log` inside the VM.

### Pin and verify the image digest

The tracked Compose template and newly generated settings intentionally use
`dockurr/windows@sha256:DIGEST` as a fail-closed placeholder. Before launching
the VM, pull the current `latest` image on the target machine and capture its
immutable repository digest:

```bash
docker pull dockurr/windows:latest
docker image inspect dockurr/windows:latest --format '{{index .RepoDigests 0}}'
```

Alternatively, after pulling, `docker image ls --digests dockurr/windows` shows
the digest. Replace the complete `WINDOWS_IMAGE` value in
`~/.config/windows/settings.env` with the returned
`dockurr/windows@sha256:<64-hex-digest>` reference. To update the repository
default for future installs, make the same one-line replacement in
`windows/.local/share/windows-vm/compose.yaml` and the installer default in
`windows/.local/bin/windows-vm`.

This pull-then-pin workflow is trust on first use: the digest preserves the
exact image first retrieved from the registry, but it does not establish that
the image was reviewed, authentic, or safe. Pinning that captured digest only
prevents later tag changes from silently selecting different image content.

Before trusting a new digest, compare it with publisher release metadata,
signatures, or attestations when those are available. After pulling the pinned
reference, verify Docker resolved that exact digest:

```bash
docker image inspect 'dockurr/windows@sha256:<64-hex-digest>' --format '{{json .RepoDigests}}'
```

---

## Theme System

This repo includes a **semantic, switchable theme system** with **23 themes**.

| Open with | What you get |
|---|---|
| **`SUPER + CTRL + SHIFT + SPACE`** | Fullscreen cover-flow picker — one large preview, skewed slices either side |
| **`SUPER + CTRL + D`** → THEME | The Display panel's launcher row, opens the same visual picker |
| `theme set <slug>` | The CLI, and what everything above ends up calling |

### How It Works

1. **`hypr/.config/hypr/themes/<slug>/colors.toml`** — One palette per theme. This is the single source of truth: semantic colour roles (`background`, `surface`, `accent`, `red`, …), a complete 16-colour ANSI terminal palette, and optional `[style]` overrides (rounding, border width, opacity, blur).
2. **`hypr/.config/hypr/theme/generate.py`** (+ `themelib.py`) — Validates the palette (including WCAG AA contrast checks), renders every application's config from `hypr/.config/hypr/theme/templates/*`, and installs it atomically. A broken theme leaves the previous one running.
3. **`quickshell/.config/quickshell/ThemePicker.qml`** — the fullscreen cover-flow
   picker, reached from `Super+Ctrl+Shift+Space` or the Display panel's THEME
   row. Every entry point is only a front-end: they both hand a slug
   to `theme set`, which stays the single source of truth for what is active.

### `theme` CLI

```bash
theme list              # list themes (active marked *)
theme index             # themes + wallpapers, human readable
theme index --json      # same as JSON; this is what the visual picker reads
theme validate --all    # check every palette
theme current           # print the active slug
theme mode              # print dark|light
theme set <slug>        # apply a theme
theme next              # cycle to the next theme
theme previous          # cycle to the previous theme
```

### Available Themes

**23 themes** — the 18 designed for this system, plus 5 carried over from
the previous `themes.json` so nothing that was in use was lost.

| Slug | Theme | Mode |
|---|---|---|
| `tokyo-night` | Tokyo Night | dark |
| `catppuccin` | Catppuccin Mocha | dark |
| `lumon` | Lumon | dark |
| `ethereal` | Ethereal | dark |
| `everforest` | Everforest | dark |
| `gruvbox` | Gruvbox | dark |
| `miasma` | Miasma | dark |
| `hackerman` | Hackerman | dark |
| `osaka-jade` | Osaka Jade | dark |
| `kanagawa` | Kanagawa | dark |
| `nord` | Nord | dark |
| `matte-black` | Matte Black | dark |
| `vantablack` | Vantablack | dark |
| `ristretto` | Ristretto | dark |
| `retro-82` | Retro 82 | dark |
| `flexoki-light` | Flexoki Light | light |
| `rose-pine` | Rosé Pine | dark |
| `catppuccin-latte` | Catppuccin Latte | light |

Carried over from the previous theme set:

| Slug | Theme | Mode |
|---|---|---|
| `windows-7` | Windows 7 Aero | dark |
| `cyberpunk-neon` | Cyberpunk Neon | dark |
| `monochrome-minimal` | Monochrome Minimal | dark |
| `solarized-dark` | Solarized Dark | dark |
| `warm-pastel` | Warm Pastel | dark |

### Visual Theme Picker

`SUPER + CTRL + SHIFT + SPACE` opens a fullscreen Quickshell overlay showing a
preview tile per theme. It runs inside the already-running shell process (the
key is a Hyprland global shortcut, `quickshell:theme`; scripts can use
`quickshell ipc call theme toggle`), so there is nothing to start.

```
type            filter by name
← →             previous / next theme
↑ ↓             move a row
Home / End      first / last result
Enter / click   apply the focused theme
Escape          clear the search, or close if it is already empty
```

Two things worth knowing:

- **Moving the selection never applies anything.** Only Enter or a click runs the
  backend, so you can browse the whole gallery for free.
- **The picker wears the theme you are currently using**, not the one under the
  cursor. Each tile paints itself from its own palette; the chrome around them
  follows the active theme.

Each tile is drawn in QML from the theme's palette — a simulated bar, a simulated
terminal showing the semantic colours, and the theme's wallpaper behind it if one
exists. No thumbnails are generated or cached, and no processes are spawned per
tile. A theme with no wallpaper (12 of the 23) falls back to a palette gradient;
drop an image at `wallpaper/theme/<name>.jpg` and it starts being used with no
config change.

### What Changes Per Theme

Each theme consistently updates:

- **Hyprland** — active/inactive border colours, rounding, gaps, opacity, shadow, blur
- **Quickshell** — shell palette via generated `themes/.active/theme.json`
- **Kitty** — 16-colour ANSI palette, foreground/background, selection, cursor
  and background transparency. Hyprland blurs behind Kitty using the theme's
  blur strength, including on themes that disable blur for other applications.
  The Hermes desktop app gets the same blur; a window rule in
  `conf/window_rules.lua` makes it see-through.
- **T3 Code** — generated environment theme with matching surfaces, status and
  terminal colours; connected clients repaint through T3's watched theme file
- **System-aware apps** — light/dark preference for Electron, GTK, Chromium and
  websites using `prefers-color-scheme` (including Helium when set to follow the
  system)
- **Rofi** — launcher colours via generated `current.rasi`
- **Zsh / Powerlevel10k** — prompt colours via generated `current-theme.zsh`
- **Hyprlock** — lock screen colours
- **Quickshell notifications** — cards, gradients, borders, countdown and radius
- **Noctalia** — shell colour scheme
- **Fastfetch** — section key colours
- **Neovim** — generated colorscheme, with a stable `current` alias
- **btop** — generated theme, with a stable `current` alias
- **Obsidian** — generated CSS snippet source for manually linked vault snippets
- **Wallpaper** — set via `hyprpaper` over `hyprctl` for the 10 themes that have
  an asset; the other 13 leave your current wallpaper alone rather than clearing it.
  `theme index` prints which is which

### Dependencies

The theme system requires:

- `python3` (3.11+, for `tomllib`)
- `rofi` — theme selection menu

Optional (for live reload):

- `hyprctl` — reloads Hyprland decorations
- `kitty` — live-applies colours to running terminals
- `gsettings` and `xdg-desktop-portal-gtk` — the `xdg` package routes the
  Settings portal through GTK so light/dark changes reach Helium and other
  system-aware applications
- `t3` — selects the generated `dotfiles-desktop` environment theme in T3 Code;
  without the CLI, select that theme once under Settings > Appearance

### Switching Manually

```bash
# Apply a specific theme
theme set tokyo-night

# Check the current theme
theme current
```

### First Run / Bootstrap

Generated config files (decorations, colours, themes) are gitignored. After `stow`, generate them once:

```bash
theme set <slug>
~/.config/hypr/scripts/auto-monitor-profile.sh --force
```

Run T3 Code once so `~/.t3` exists, then switch a theme. The generator publishes
`~/.t3/userdata/themes/dotfiles-desktop.json` atomically and asks the `t3` CLI to
select it. If the CLI is unavailable, choose the `dotfiles-desktop` card once in
T3 Code's Appearance settings; later switches keep the stable theme id and
repaint it live. In Helium, choose the system/GTK appearance rather than a fixed
browser theme so its chrome and pages follow the desktop light/dark signal.

### Adding a New Theme

1. Create `hypr/.config/hypr/themes/<slug>/colors.toml` (copy `tokyo-night/colors.toml` for the format and required keys).
2. Run `theme set <slug>`.

Most applications consume generated output directly. Set btop's `color_theme`
to `"current"` once, and symlink then enable the generated Obsidian CSS snippet
in each vault as described in [Themes and appearance](docs/themes.md).

### Validation

```bash
theme validate --all      # every palette: required roles, 16 ANSI colours, contrast
theme validate <slug>     # just one
```

---

## Notifications

Notifications are served and rendered natively by the persistent Quickshell
process. Applications talk to `org.freedesktop.Notifications`; one service then
normalises the event, persists it, applies DND, and either places it in the
focused monitor's top-right stack or writes it silently to history.

```text
application -> Quickshell NotificationServer -> NotificationService
                                                |-> active/history state
                                                |-> per-output card stack
                                                `-> notifications IPC
```

The full-screen layer-shell surfaces use the overlay layer, request no keyboard
focus or exclusion zone, and have an input mask made only from the card stack.
Transparent space is therefore click-through. The active Quickshell bar is the
authoritative bar, so top notifications clear `Theme.barHeight` plus the normal
outer gap. Notifications without output metadata go to Hyprland's focused
monitor; a disconnected output is deterministically remapped to the current
focused monitor.

### Controls

| Binding | Action |
|---|---|
| `Super+,` | dismiss newest visible card |
| `Super+Shift+,` | dismiss all visible cards |
| `Super+D` | toggle persistent DND |
| `Super+Alt+,` | invoke/focus newest card |
| `Super+Shift+Alt+,` | replay the newest 10 history entries |

The bindings call `notificationctl`; they contain no notification logic.

```bash
notificationctl dismiss-one
notificationctl dismiss-all
notificationctl dnd-toggle
notificationctl dnd-on
notificationctl dnd-off
notificationctl invoke-latest
notificationctl history
notificationctl status
notificationctl status --json
```

Commands reach the shell over Quickshell IPC. When no shell runs from the
default `~/.config/quickshell`, as with a preview started by
`quickshell -p <worktree>/quickshell/.config/quickshell`, they fall back to the
newest running full shell by pid; smoke-test instances are never picked.
`NOTIFICATIONCTL_QUICKSHELL` overrides the `quickshell` binary for fixtures.

Left click invokes the live default action, then falls back to matching
`desktop-entry`, app name, and icon against Hyprland window classes. Right click
or the hover close button dismisses. Hover pauses the deadline. Critical cards
remain until acted on, unless the sender sets an expire time; then they count
down and expire at that time, and hover does not pause them. Low and normal cards last at least 5 and 8
seconds, with ordinary requests clamped to 30 seconds.

### State and configuration

User settings live in
`~/.config/quickshell/notifications/config.json`: position, history limit,
timeouts, 380 px card width, animation timing, padding, debug logging and
the audited DND bypass allow-list. A bypass requires both an allow-listed app
name and an explicit local bypass hint; urgency alone never bypasses DND.

Runtime state is private and atomic under:

```text
~/.local/state/hyprland-desktop/notifications/
├── state.json       # persistent DND
├── active/          # cards restored after a shell restart
├── history/         # newest 10 by default
└── images/          # bounded copies owned by retained records
```

The card component is shared by live and replayed history. Native actions exist
only while the originating notification object is live; restored/history cards
correctly use app-focus fallback instead of claiming an expired action works.
Malformed JSON is skipped, filenames are validated, notification text is never
sent through a shell, writes use fsync plus rename, and orphan images are swept.

Theme roles are generated for every palette as `notifications.background`,
`surface`, `shadow`, `text`, `bodyText`, `actionText`, `criticalActionText`,
`countdown`, and `close`. Cards show the app name, an icon badge, and any supplied
actions on a raised surface. Corner radius is the generated Hyprland rounding
plus four scaled pixels. The old `borderWidths`, `singleLinePadding`, and
`glyphGap` options are accepted but ignored; cards use `multiLinePadding` and
`iconGap`.

A notification with the boolean hint `desktop-verbatim` set to true shows its
body exactly as sent. Markup is not stripped and entities are not decoded. The
body uses a monospace font, has no line limit, and scrolls past 14 lines.
`agent-permission-hook` uses this hint so a card shows the whole command:

```bash
notify-send -h boolean:desktop-verbatim:true "Command" 'sort < in > out'
```

### Debugging and validation

```bash
# Reload the already-running shell after changing QML
quickshell ipc call notifications statusJson
quickshell kill && quickshell --daemonize

# Observe concise service logs
quickshell log

# Send manual cases
notify-send "Test notification" "This is the body."
notify-send -u low "Low urgency" "At least five seconds"
notify-send -u critical "Critical" "Dismiss explicitly"

# Headless QML and unit checks from the repository root
QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/NotificationSmoke.qml
python3 -m unittest discover -s quickshell/.config/quickshell/notifications/tests -p 'test_*.py'
node quickshell/.config/quickshell/notifications/tests/notification_logic.test.js
theme validate --all
```

---

## Web Apps

Turn a website into a first-class launcher. `SUPER + SHIFT + A` opens the manager.

```
Install > Name + URL > icon found automatically > Install
        > managed .desktop > Rofi / app menu > brave --app= > normal window
```

Each installed app owns exactly three files, and the manager will only ever
touch these:

| | |
|---|---|
| metadata | `~/.local/share/webapps/apps/<id>.toml` |
| icon | `~/.local/share/webapps/icons/<id>.png` |
| launcher | `~/.local/share/applications/webapp-<id>.desktop` |

The metadata file is the ownership marker: an app is removable by this tool only
if it is listed there, so an unrelated `.desktop` file can never be deleted.

Each row in the manager has an edit (pencil) button that reopens the form with
the app's name, URL and icon. Saving keeps the same id, so the launcher and any
window rule written against it keep working.

### CLI

```bash
webapp list                 # installed web apps
webapp install --name "YouTube" --url https://youtube.com/
webapp install --name "Local" --url localhost:8080/app --icon ~/pic.png
webapp edit youtube --name "YT" --url https://youtube.com/feed
webapp edit youtube --icon ~/pic.png   # or --reset-icon to find it again
webapp remove youtube
webapp doctor               # browser, tooling and orphan check
webapp launch youtube       # what the .desktop file runs
```

Notes worth knowing:

- **Browser**: the launch helper uses `$WEBAPP_BROWSER` if set, else the XDG
  default browser (the `x-scheme-handler/https` entry in `mimeapps.list`) when
  it is Chromium-family, else the first of `brave`, `chromium`,
  `chromium-browser`, `google-chrome`, `google-chrome-stable`, `helium-browser`
  on `PATH`. A Firefox default falls back to that list, because only Chromium
  browsers have an `--app=` window mode. `webapp doctor` says which rule won.
  Web apps share that browser's normal profile, so existing logins just work.
- **Window class**: Brave ignores `--class` for app-mode windows and derives its
  own, e.g. `brave-youtube.com__-Default`; Helium and other derivatives keep
  Chromium's prefix, e.g. `chrome-youtube.com__-Default`. That is recorded as
  `wm_class` in the metadata and is what a per-app Hyprland rule has to match.
  Usefully it is never plain `brave-browser`, so the `workspace 2 silent` rule
  in `window_rules.lua` does not capture web apps.
- **Icons** are normalised to PNG, because gdk-pixbuf here has no SVG or WebP
  loader and Rofi could not otherwise render them. Discovery prefers a declared
  `apple-touch-icon` or sized raster over an SVG favicon; if nothing is found, a
  letter tile is generated in the active theme's accent colour.
- Only `http` and `https` are accepted. `file:`, `data:` and `javascript:` are
  rejected. URLs are never passed through a shell and never appear in an `Exec`
  line -- the launcher receives only the app id.

## Chromium Desktop Tools

The `browser` package installs two unpacked Manifest V3 extensions and their
native messaging hosts for Chromium, Chrome, Brave (including Origin), and
Microsoft Edge profiles:

| Shortcut | Toolbar action | Result |
|---|---|---|
| `Alt + Shift + L` | Copy URL | Copies the active tab URL with `wl-copy`; the existing `cliphist` watcher records it |
| `Alt + Shift + D` | Download Video | Sends the active page URL to `yt-dlp`, saves one video in `~/Videos`, and shows progress in the Quickshell OSD |

The browser owns both shortcuts; they are not Hyprland bindings. Browser flag
files load the extensions from `~/.local/share/chromium-tools/extensions/`, and
each browser profile authorizes only the extensions' pinned IDs to launch the
matching executable in `~/.local/bin/`.

Download Video accepts only HTTP(S) pages, disables playlists, and leaves format
selection to yt-dlp. Set `CHROMIUM_YTDLP_DIR` in the browser's environment to
override `~/Videos`. After a successful download, click the ten-second
notification to open the validated file in mpv. An unsupported page or failed
download produces a critical desktop notification containing yt-dlp's error.
Concurrent duplicate requests are ignored. Native-host connection or
request errors produce a Brave notification and leave a red `!` badge on the
Download Video extension, so the shortcut no longer fails silently.

After first installation, completely close and reopen the browser. Inspect or
change the browser-owned shortcuts at `brave://extensions/shortcuts` (or the
equivalent `chrome://extensions/shortcuts`). A shortcut already assigned to
another extension must be cleared there before it can be assigned to these
tools.

If an older unpacked Download Video extension still owns `Alt + Shift + D`,
preview the narrowly scoped profile repair while Brave is open:

```bash
chromium-repair-download-video-shortcut ~/.config/BraveSoftware/Brave-Browser
```

Then completely quit Brave and rerun it with `--apply`. The repair refuses to
write while Brave's singleton socket is active, creates a timestamped
`Preferences` backup, and removes only obsolete Download Video registrations.
The current pinned extension claims the shortcut on the next browser launch.

Validation from the repository root:

```bash
tests/browser-native-tools.test.sh
stow --simulate browser quickshell
```

The fixture suite uses mocked clipboard, downloader, notification, player, and
OSD commands; it never downloads media or changes the live clipboard.

### Bar workspace badges

The left island shows a numbered badge for every workspace that has a window on
it, plus the focused workspace, across every monitor. The focused badge sits on
the accent pill; clicking a badge focuses that workspace. Empty unfocused
workspaces and special (scratchpad) workspaces are hidden. Selection rules are
in `workspaces/WorkspacesLogic.js`; validate with
`bash tests/workspaces-module.test.sh`.

### Bar centre

The centre island holds the clock, pinned to the screen centre, with the
indicator row to its left. It never pops out: track changes and videos stay
in the media panel and dashboard, and notifications keep their card in the
top-right stack. Validate with `bash tests/bar-center.test.sh`.

## What's Included

| Package | Tool | Description |
|---|---|---|
| `hypr` | [Hyprland](https://hyprland.org/) | Wayland compositor — keybinds, decorations, autostart, monitor profiles, theme system |
| `browser` | Chromium tools | Copy URL and yt-dlp extensions with native desktop integration |
| `hyprlock` | [Hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen with music widget, weather, and multiple layouts |
| `kitty` | [Kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator with generated theme palette |
| `rofi` | [Rofi](https://github.com/davatorium/rofi) | App launcher with generated colour theme on comet-glass layout |
| `fastfetch` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info with themed key colors |
| `zsh` | Zsh | Shell config — `.zshrc` and `.p10k.zsh`; Oh My Zsh itself is installed separately |
| `ssh` | autossh | Reconnecting SSH launcher and opt-in client keepalive fragment |

---

## Dependencies

**Core:**
- `hyprland`, `hyprlock`, `hypridle`
- `kitty`
- `rofi`
- `quickshell`
- `fastfetch`

**Scripts:** the packages in `setup/manifests/scripts.txt`, which `dots deploy`
and `dots update` keep installed (see **Script dependencies**).

**Shell:**
- `zsh`, `oh-my-zsh`
- `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fzf`, `fzf-tab`
- `eza` (ls replacement)
- `powerlevel10k`
- `autossh`, `tmux` (persistent SSH sessions)

Oh My Zsh and the two pieces `.zshrc` loads out of `$ZSH_CUSTOM` are **not
vendored in this repo** — Oh My Zsh's own `.gitignore` excludes `custom/`, so
nothing tracked here could ever carry them. Install them once:

```bash
(
# The subshell guards the exit below so a failed pin check can never close an
# interactive terminal.
# REQUIRED: fill this with a reviewed 40-character commit from
# https://github.com/ohmyzsh/ohmyzsh/commit/<sha>. When reviewing the commit,
# inspect tools/install.sh and record its SHA-256 digest through a trusted channel.
OMZ_PIN='<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'
[[ $OMZ_PIN =~ ^[0-9a-fA-F]{40}$ ]] || exit 1
omz_installer="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/$OMZ_PIN/tools/install.sh" \
  --output "$omz_installer"
sha256sum "$omz_installer"
printf '%s\n' 'Compare this SHA-256 with the digest recorded when OMZ_PIN was reviewed.'
less "$omz_installer"  # Inspect the complete script before continuing.
sh "$omz_installer" "" --unattended
rm -f "$omz_installer"

(
# REQUIRED: fill these with reviewed 40-character commits from the linked
# upstream repositories. The placeholder values fail closed. Review each at
# https://github.com/romkatv/powerlevel10k/commit/<sha> and
# https://github.com/Aloxaf/fzf-tab/commit/<sha> before using it.
POWERLEVEL10K_PIN='<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'
FZF_TAB_PIN='<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'
[[ $POWERLEVEL10K_PIN =~ ^[0-9a-fA-F]{40}$ ]] || exit 1
[[ $FZF_TAB_PIN =~ ^[0-9a-fA-F]{40}$ ]] || exit 1
git clone --no-checkout https://github.com/romkatv/powerlevel10k.git \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
git -C ~/.oh-my-zsh/custom/themes/powerlevel10k checkout --detach \
  "$POWERLEVEL10K_PIN"
git clone --no-checkout https://github.com/Aloxaf/fzf-tab.git \
  ~/.oh-my-zsh/custom/plugins/fzf-tab
git -C ~/.oh-my-zsh/custom/plugins/fzf-tab checkout --detach "$FZF_TAB_PIN"
)
```

**Theme system:**
- `python3` (3.11+, for `tomllib`)
- `rofi`

**Utilities used in scripts:**
- `playerctl` — media control
- `mpv` — video wallpapers
- `doas` — privilege escalation (used in place of sudo)
- `grim`, `slurp` — screenshots
- `cliphist` / `wl-clipboard` — clipboard
- `yt-dlp`, `jq`, `ffmpeg`, `mpv`, `libnotify` — Chromium video download integration

Install AUR packages with your preferred helper (e.g. `paru` or `yay`).

---

## Wallpaper Licensing

Wallpapers in `wallpaper/theme/` are sourced from [Unsplash](https://unsplash.com/license) — free for commercial and non-commercial use (Unsplash License). Each is a unique image selected to match its theme's color palette.
