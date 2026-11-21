# Keybind palette

SUPER+K opens a full-screen palette listing every keybinding: its keys, its
description and what it runs. You can search it. Rows are ranked so the
essentials come first: keybindings, the launcher, the terminal, the browser
and so on. `keybinds-collector` builds the rows by merging `hyprctl binds`
with a replay of `conf/keybindings.lua`. `KeybindsState.qml` ranks and
searches them, using a ranking list that must match the collector's exactly.

## Sub-features

- `palette-collect`: the collector merges live binds with the Lua replay, recovers keycode-only binds, and caches by content hash.
- `palette-rank`: identical ranking lists in `keybinds-collector` and `KeybindsState.qml`; every description matches a rule.
- `palette-search`: searching rows in `KeybindsState`.
- `palette-panel`: the full-screen panel that SUPER+K opens.

## How to get to it (user POV)

- Press SUPER+K.
- Pick `learn.keybindings` in lmenu (the "Keybindings" row under Learn).
- Type to search the palette, and press Escape to close it.

## Driving it with verify

Preconditions:

- `$V launch` printed `ready: run <id>`, and `$V doctor` printed `doctor: ok to drive`.
- `lua` and `python3` are installed. The test treats a missing Lua as a
  failure, not a skip.

- **Run the collector, ranking and cache checks.** Run
  `$V run --label keybinds-collector-test --timeout 120 -- python3 tests/keybinds-collector.test.py`.
  Its stdout must hold, in order:
  - `ok: identical priority ladders rank all 168 repository descriptions`;
  - `ok: all 178 bind keywords use documented flags and retain descriptions`;
  - the cache-miss, cache-hit, hash-move and corrupt-cache `ok:` lines;
  - `--- first 40 prioritized repository-fixture rows ---`, starting with
    `keybindings`, `application launcher`, `terminal`, `browser`.

  The verdict is FAIL (exit 1) in the sandbox. The last step runs
  `KeybindsSmoke.qml`, which stops with `No PanelWindow backend loaded`. The
  steps before it are proven; report `palette-search` and `palette-panel` as
  unverified.
- **Show that the collector's dry-run still asks Hyprland.** Run
  `$V run --label collector-dry-run -- hypr/.config/hypr/scripts/keybinds-collector --dry-run --limit 5`.
  Expect FAIL (exit 1). `calls.log` holds `hyprctl binds -j`, and stderr says
  `Command '['hyprctl', 'binds', '-j']' returned non-zero exit status 1.`
  A fixture-safe run needs `--binds-json <file>` and `--keymap-summary <file>`,
  which the test above builds.
- **Check the palette's search state.** Run
  `$V smoke Keybinds --expect 'ok: KeybindsState fixture build and search'`.
  Expect FAIL: `Type KeybindsPanel unavailable … No PanelWindow backend
  loaded`. It is unverified headless. The smoke builds the panel component
  first, and that needs Wayland layer shell.

## Gotchas

- `--dry-run` on the collector means "don't write the cache". It doesn't
  mean "don't call Hyprland". Without `--binds-json` it runs `hyprctl binds -j`
  and, for the keymap, `hyprctl devices -j`.
- CI waives the `No PanelWindow backend loaded` failure for this test only
  (`.github/workflows/ci.yml:133`). Locally, `tests/run-all` doesn't.
- `qmllint` isn't installed on this machine, so the test prints
  `skip: qmllint is not installed`. The palette QML isn't linted.
- A new keybinding description must match a rule in the ranking list, or it
  sorts last. The ranking check above proves that for every description in
  `conf/keybinding.conf`.
