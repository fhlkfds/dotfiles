# Dotfiles agent guide

Arch + Hyprland desktop. Config lives in GNU Stow packages (top-level
directories); the desktop shell is Quickshell. Terms like Island, Module,
Panel, Package path and Fixture test are defined in `CONTEXT.md`; use them.

## Working with me

- Explain in short, plain language. Give a one-line meaning for any jargon.
- For non-trivial work, state the plan (files, validation) in a few lines, then
  build. Ask first only when a step touches the live system (see Boundaries) or
  when something visual is ready for a look (see Design check-ins).
- Finish with what changed and which tests ran and passed.
- Stop at a clean, tested diff on a feature branch. Commit and open the PR when
  I ask.

## Priorities: works, then fast

Both are required. Speed is the feature: nothing you build may slow me down.

- **Works:** name the test that proves it. A change without a passing test is
  unfinished.
- **Fast to use:** the path from keypress to something on screen is the hot
  path (keybind, bar, panel, menu). Keep process spawns off it. A keybind that
  opens a panel goes through `GlobalShortcut` to the resident shell (the
  `shell()` helper), which skips a ~30 ms client start. Open the menu or panel
  first and fill it after, the way `lmenu` streams rows. Push slow work
  (network, disk scans, slow probes) off the hot path, cache it, react to
  events instead of polling, bound anything that can grow, and coalesce
  repeats.
- **Measure:** when you touch a hot path, time it (`time <cmd>`) and report the
  number.
- **Fast to build:** run only the tests for what you touched, in parallel when
  independent, and trust a passing test instead of re-checking it.

## Boundaries

- The Git repository is the only source of truth. Edit Stow package paths such
  as `hypr/.config/hypr/`; live paths under `~/.config` and `~/.local` are
  symlinks into it.
- Ask before running GNU Stow, `theme set`, reloading or restarting Hyprland,
  or restarting desktop services (including `shell-reload.sh`). Approval covers
  that one action.
- A script that changes Hyprland or system state ships a dry-run or fixture
  path, and you validate with it. No live Hyprland session is available.
- Edit palettes, templates and generators; generated outputs (listed in
  `.gitignore` and `README.md`) are rebuilt by `theme set`.
- Keep patches focused. Leave unrelated user changes untouched, unstaged and
  uncommitted.

## Design check-ins

For anything visual (bar module, panel, overlay, menu, theme colours), show me
the first working version and ask for my input before you polish. This is the
one place to pause without a live-system reason. Scripts, logic and keybind
plumbing need no check-in.

- **If this environment can display images**, show screenshots so I can see what
  you were thinking. **If it cannot** (a plain CLI), skip them and describe the
  layout in three or four lines.
- Show real captures only. `hypr/.config/hypr/scripts/capture/capture.sh
  screenshot <smart|region|window|monitor> --save` takes one from the running
  session, which needs the shell reloaded with your change, so ask first.
- With no live session, say so and describe the design in words.

## Build a script

Fits: a CLI in `<package>/.local/bin/<name>`, or a Hyprland helper in
`hypr/.config/hypr/scripts/<name>`. Copy the shape of `night-light.sh`.

1. `#!/usr/bin/env bash`, `set -euo pipefail`, a header comment saying *why* it
   exists, a `usage()` and `-h|--help`, exit 2 on bad arguments. Mark it
   executable.
2. Anything that mutates takes `--dry-run`.
3. Read every external command and state file from an env override with a real
   default (`NIGHT_LIGHT_HYPRCTL`, `NIGHT_LIGHT_STATE_FILE`), so a fixture can
   inject stand-ins. State lives under `${XDG_STATE_HOME:-$HOME/.local/state}`.
4. Add `tests/<name>.test.sh` (`set -euo pipefail`, `fail()` helper, stub
   binaries on a temp `PATH`). Print `skip: <tool> not installed` when an
   optional tool is missing; never silently pass. Use `tests/<name>.test.py`
   when the logic is Python.
5. Wire it: a keybind, a menu entry, or both (below), and the doc that lists its
   sibling scripts.

## Build a Quickshell module

Fits: a bar module, panel or overlay in `quickshell/.config/quickshell/`. Copy
the Battery set, one file per role:

| Role | File |
| --- | --- |
| data and logic | `XState.qml` (pure logic in `x/XLogic.js`, settings in `x/config.json`) |
| bar module | `XIcon.qml`, placed inside an island in `Bar.qml` |
| panel | `XPanel.qml` wrapping `XPanelContent.qml` (content takes fakes, so a test can load it alone) |
| headless test | `XSmoke.qml` |
| fixture test | `tests/x.test.sh` |

- Read colours through `Theme` roles; scale sizes with `Theme.fs()`. A module
  paints no background of its own.
- Register the state in `shell.qml`. A panel opened by key also needs a
  `GlobalShortcut` in `Bar.qml`.
- The smoke builds the pieces from fake `QtObject` devices, prints
  `ok   <name>` or `FAIL <name>`, and counts failures. The `.sh` test runs it
  with `QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p <Smoke.qml>` and
  fails on any `FAIL`.
- Run pure `.js` logic under `node` in the same test.
- Seeing it live needs a shell reload, so ask first.

## Build a keybinding

Bindings live in `hypr/.config/hypr/conf/keybindings.lua`. Pick the helper that
matches the target:

| Target | Helper |
| --- | --- |
| a command | `exec(keys, description, command)` |
| a Quickshell panel | `shell(keys, description, name)` |
| a command from another Stow package | `package_exec(...)`, which reports an undeployed package |
| a program that may be missing | `app_exec(...)`, which offers to install it |

- Search the file for the key combination first, so it does not clash with an
  existing binding.
- Write a `description`: it is the label in the `SUPER+K` palette. Its wording
  must match a rule in the ranking list in `keybinds-collector`, which
  `KeybindsState.qml` repeats identically, or it sorts last.
- Mirror it in `conf/keybinding.conf`, the compatibility copy.
- Run `python3 tests/keybinds-collector.test.py`, then add the row to the doc
  that lists the other keybindings.

## Build a menu

Fits: an entry in the `lmenu` tree, `menu/.config/lmenu/menu.jsonc` (the
default). A standalone Rofi script like `toggles-menu.sh` or `power-menu.sh`
fits when the menu has its own keybind.

- The dotted id is the tree position (`style.bar.position` sits under
  `style.bar`). Give each entry `id`, `icon`, `label`, `description`, and
  `aliases` for routes you will type. `action` makes a leaf, `target` a link,
  `provider` a generated submenu.
- `when`, `disabled` and `checked` are bash guards that run on every render
  of the menu. Keep them instant: local file or process checks only.
- Style comes from the `.rasi` files in `rofi/.config/rofi/`, whose colours are
  generated from the active theme. Use the theme variables, not hex values.
- Preview without opening Rofi: `lmenu --dry-run <route>` lists the rows and
  `lmenu --dry-run-display <route>` shows the exact lines Rofi would get.
- Test in `tests/lmenu.test.sh`, or a new `tests/<name>.test.sh` for a
  standalone script. Show a menu's look at a design check-in.

## Build a theme

- **New palette:** copy `hypr/.config/hypr/themes/tokyo-night/colors.toml` to
  `themes/<slug>/colors.toml` and fill every role. Check with
  `theme validate <slug>` (required roles, 16 ANSI colours, contrast); it is
  read-only and safe. Applying it with `theme set <slug>` changes the live
  desktop, so ask first.
- **New themed app:** add a template in `hypr/.config/hypr/theme/templates/`,
  register it as a `tl.Artifact(template, destination)` in `theme/generate.py`
  (see the kitty entry), add its output path to `.gitignore` and the
  README list.
- Run `python3 tests/test_theme_generator.py` and `theme validate --all`. If a
  snapshot fails, fix the cause; refresh a snapshot only for an intended change.
- Show a new palette's look at a design check-in.

## Packages and deploys

- New Stow package: `README.md` "Deploy with Stow". Preview deploys with
  `dots deploy --dry-run`.

## Before you finish

1. Run the tests for what you touched: `bash tests/<name>.test.sh`, plus
   `bash -n` on shell scripts and a parse check on JSON and Lua.
2. `git diff --check`, then read the whole diff and confirm every changed path
   is meant.
3. Branch `feat/<scope>-<thing>` or `fix/<scope>-<thing>`; commit subject
   `type(scope): imperative summary`, one feature per PR.
