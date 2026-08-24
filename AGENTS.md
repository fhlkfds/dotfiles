# Repository maintenance instructions

- Treat this Git repository as the only authoritative source. Edit Stow package
  paths such as `hypr/.config/hypr/`, never live paths under `~/.config` or
  `~/.local`, even when those paths are symlinks into the repository.
- Begin non-trivial changes with read-only discovery and present the intended
  files and validation before editing.
- Preserve all existing user changes and keep patches focused. Do not delete,
  rename, stage, commit, or push unrelated work.
- Do not run GNU Stow, reload or restart Hyprland, or restart desktop services
  without explicit approval for that specific action.
- Scripts that can mutate Hyprland or other system state must provide and use a
  safe dry-run or fixture path during validation. Do not assume a live Hyprland
  session is available.
- Edit theme palettes, templates, or generators rather than generated outputs
  identified in `.gitignore` and `README.md`.
- Run applicable syntax checks and fixture tests, then `git diff --check`.
  Review the complete diff and confirm every changed path before reporting
  completion.
