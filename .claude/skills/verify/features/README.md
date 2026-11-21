# Dotfiles verification map

This folder is the maintained list of journeys for proving the desktop's
user-facing features. Read this index before you drive anything, then follow
the matching feature file. Every command goes through the `verify` helper,
which [../SKILL.md](../SKILL.md) explains.

## Baseline preconditions

- Work from the repository root, with `V=.claude/skills/verify/bin/verify`.
- Run `$V launch` and keep the printed run id. When other agents may be
  verifying at the same time, pass `--run <id>` to every command.
- Run `$V doctor` and require `doctor: ok to drive`.
- Use the default palette `tokyo-night` unless the journey names another.
- Never drive the live session: the real `~/.config`, `/run/user/$UID`, or
  `hyprctl` without the stand-in. Never run Stow, `theme set`,
  `shell-reload.sh` or a Hyprland reload without the user's approval
  (AGENTS.md "Boundaries").

## Driving conventions

- Start every journey from a fresh `$V launch` unless it says otherwise.
- Treat every command as literal. Keep quoted expect lines unchanged: they are
  the strings the smokes print.
- Use the smoke's own success line as `--expect`. LOADED is not a pass.
- Every dry-run gets its side effects checked through `calls.log` and
  `fs-changes.txt`, never through its name.

## Proof and skip reporting

- Report the verdict line from `evidence/INDEX` and the evidence folder for
  each journey step.
- UI proof is a PNG from `$V shot` plus its `checks.txt`, which records the
  click, the text shown, and the close.
- CLI proof is `command.txt`, `stdout.txt`, `stderr.txt` and `exit-code`.
- A state change needs proof from a second view: a file in
  `fs-changes.txt`, a call in `calls.log`, or a `status` read afterwards.
- A `skip:` line, a LOADED verdict, or a `No PanelWindow backend loaded`
  failure is unverified. Name the precondition that's missing: a Wayland
  layer-shell backend, a live session, or the tool.
- Don't report a skipped entry point as verified through a different one.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing what
the user sees. Four H2 sections follow, in this order:

1. `Sub-features`: short IDs, one line each.
2. `How to get to it (user POV)`: every user entry point.
3. `Driving it with verify`: starts with `Preconditions:`, then labelled
   bullets that pair a user action with an exact command and the observable
   result.
4. `Gotchas`: traps that waste a run or make its result invalid.

## Features

- [Bar islands](./bar-islands.md): the four capsules on the bar and the
  modules inside them, through module smokes and the island render smoke.
- [Battery panel](./battery-panel.md): the battery icon, the panel it opens,
  the readouts, the power-profile switch, and low-battery alerts. Smokes,
  fixture mode and clicked PNG shots.
- [lmenu](./lmenu.md): the launcher tree, aliases, generated submenus and
  guards, through `lmenu --dry-run` and `--dry-run-display`.
- [Keybind palette](./keybind-palette.md): the SUPER+K palette's collector,
  ranking and search. Its panel is unverifiable headless.
- [Theme generator](./theme-generator.md): palette validation and rendering,
  and the read-only `theme` CLI.
