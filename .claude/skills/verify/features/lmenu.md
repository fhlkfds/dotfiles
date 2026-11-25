# lmenu

lmenu is the desktop's launcher tree: Apps, Development, Learn, Trigger,
Style, System and so on. Each dotted id is a position in the tree:
`style.bar.position` sits under `style.bar`. Rows can be:
- leaves (`action`);
- links (`target`);
- generated submenus (`provider`), such as the theme list.

Aliases let you type a route, so `themes` goes to `style.theme`. Guards
(`when`, `disabled`, `checked`) decide each time the menu renders whether a
row shows, dims or has a tick.

## Sub-features

- `lmenu-tree`: the shipped `menu.jsonc` parses, and every id resolves under its parent.
- `lmenu-routes`: dotted ids and aliases route, case-insensitively, with `_` folded to `-`.
- `lmenu-providers`: generated submenus such as `themes`, with the active theme ticked.
- `lmenu-guards`: `when` hides a row, `disabled` dims it, `checked` ticks it.
- `lmenu-display`: the exact lines Rofi shows.
- `lmenu-resident`: the Quickshell-resident menu that SUPER+SHIFT+A opens.

## How to get to it (user POV)

- Press SUPER+SHIFT+A. The resident Quickshell menu opens at the root.
- Run `lmenu`, `lmenu <route>` or `lmenu <alias>` in a terminal: the Rofi front end.
- Type in the search box to filter the current view and the rows nested below it.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `jq` and `python3` are installed. `tests/lmenu.test.sh` prints `skip:` without `jq`.

- **List the root.** Run `$V lmenu`. Expect `PASS lmenu --dry-run <root>:`
  with about 230 rows. `calls.log` shows the guards that reached for the
  desktop: `hyprctl` ×2, `nmcli`, `systemctl` ×3 and `theme` ×2.
  `processes.txt` shows read-only guards that ran for real, such as
  `pacman -Q`, `docker compose version` and `gpg`. The sampler misses some
  short ones, like `resolvectl`. `calls.log` is the complete record for the
  commands that have stand-ins.
- **Show what Rofi would display.** Run `$V lmenu style.bar --display`.
  Expect PASS, with 3 rows in `stdout.txt` exactly as Rofi lists them.
- **Follow an alias into a provider.** Run `$V lmenu themes --display`.
  Expect PASS with 23 rows, one per palette. `calls.log` must show exactly
  `theme list` and `theme current`. Both are reads; nothing sets a theme.
- **Run the repo's checks.** Run
  `$V run --label lmenu-test -- bash tests/lmenu.test.sh`. Expect PASS. It
  covers the tree, routes, guard batching, providers and the active-theme tick.
- **Check the resident menu's data and search.** Run
  `$V run --label lmenu-quickshell-test -- bash tests/lmenu-quickshell.test.sh`.
  Expect PASS, with stdout ending in `lmenu quickshell: ok`. The same stdout
  also says `skip: no Wayland display; LmenuPanel.qml was not compiled`.
  Report the panel itself as unverified.

## Gotchas

- `--dry-run` doesn't run row actions, but it does run every guard. Guards
  that call `hyprctl` or `nmcli` get the stand-in's exit 1, so rows they
  guard can show differently than on the live desktop. Compare against
  `calls.log` before you call a missing row a bug.
- Row and call counts depend on the host's installed tools, because guards
  check `command -v` first. On a Debian server without `qrencode` or
  Quickshell, the root listed 203 rows and called no `nmcli`, and
  `lmenu-quickshell.test.sh` printed `skip: quickshell is not installed`.
  Compare against the desktop's counts only on the desktop.
- Outside the sandbox, `lmenu` reads `~/.config/lmenu/` (the deployed main
  checkout), not this worktree. `$V lmenu` sets `LMENU_MENU` and
  `LMENU_PARSER` to the repo copies.
- In the sandbox, the active theme is the run's palette. `theme current`
  answers `tokyo-night` unless you passed `launch --palette`.
- `$V smoke Lmenu` on its own fails: `LmenuSmoke.qml` needs the dump fixture
  that `tests/lmenu-quickshell.test.sh` builds. Use the test.
- `LmenuPanelSmoke` stops with `No PanelWindow backend loaded`. The panel
  that SUPER+SHIFT+A opens is unverifiable headless.
