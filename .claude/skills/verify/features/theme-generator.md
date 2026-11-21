# Theme generator

A theme is a palette, `hypr/.config/hypr/themes/<slug>/colors.toml`, that the
generator renders into every themed app's config: Quickshell's `theme.json`,
kitty, rofi, hyprlock, the greeter and more. Applying a theme (`theme set`,
the theme picker on SUPER+T, or `style.theme` in lmenu) repaints the desktop.
Validation checks every required role, the 16 ANSI colours and contrast, and
validates each rendered file without installing anything.

## Sub-features

- `theme-validate`: every palette loads, renders and passes each artifact's validator.
- `theme-render`: a palette renders to Quickshell's `theme.json` and the panels paint with it.
- `theme-cli-read`: `theme list`, `index`, `current` and `mode`.
- `theme-apply`: `theme set` / `next` / `previous`, which install outputs and reload apps.

## How to get to it (user POV)

- Press SUPER+T for the theme picker, or open `style.theme` (alias `themes`) in lmenu.
- Run `theme list`, `theme validate --all`, or `theme set <slug>` in a terminal.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `rofi` and `luac` are installed. Validation runs `rofi -dump-theme` and
  `luac` on the generated files.

- **Validate every palette.** Run
  `$V run --label theme-validate-all -- python3 hypr/.config/hypr/theme/generate.py validate --all`.
  Expect PASS, with stdout ending in `23 theme(s): 23 valid, 0 failed, 0
  contrast warning(s)`. `calls.log` is empty. `processes.txt` shows `rofi`
  and `luac`, usually with `gvfsd`, which rofi starts on the sandbox's
  private session bus. The sampler misses some short `rofi` runs, so don't
  count them. `fs-changes.txt` lists only `tmp`, and sometimes
  `runtime/gvfs*`. Nothing under `home/` changes.
- **Validate one palette.** Run
  `$V run --label theme-validate -- python3 hypr/.config/hypr/theme/generate.py validate <slug>`.
  Expect PASS and ` ok   <slug>`, or a ` WARN` line naming each contrast pair.
- **Paint a panel with a palette.** Run
  `$V launch --palette catppuccin-latte`, then `$V shot battery-panel`.
  Expect PASS. The PNGs use the light palette, which shows that `Theme.qml`
  reads the rendered `theme.json`.
- **Read through the CLI.** Run
  `$V run --label theme-cli -- bash -c 'theme current; theme mode; theme list'`.
  Expect PASS, with stdout starting `tokyo-night` and `dark` (the run's
  palette), then the palette table.
- **Run the generator tests.** Run
  `$V run --label theme-generator-test -- python3 tests/test_theme_generator.py`.
  Expect PASS.
- **Apply a theme.** Don't. `theme set` changes the live desktop, so it needs
  the user's approval (AGENTS.md "Boundaries"). In the sandbox, the `theme`
  stand-in refuses `set`, `next`, `previous` and `cycle` with exit 1. Report
  `theme-apply` as unverified unless the user approves a live run.

## Gotchas

- `validate` renders into a temporary folder and installs nothing, as its
  name claims. `fs-changes.txt` above is the proof. `theme set --prefix DIR`
  is documented as "no state write, no reload", but no journey here has run
  it: it is still `theme set`, so it needs the user's approval first.
- Outside the sandbox, `theme` reads `~/.config/hypr/theme/generate.py`,
  which is the main checkout, not this worktree. In the sandbox, `theme`
  always runs this worktree's CLI.
- The generator stores the active theme in `themes/current-theme`, next to
  itself. It is gitignored, so a fresh worktree has none. The sandbox reports
  the run's palette instead.
- `tests/test_theme_generator.py` checks properties of the rendered output.
  It has no stored snapshot files to refresh.
