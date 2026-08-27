#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
night_light="$repo_root/hypr/.config/hypr/scripts/night-light.sh"
test_root=$(mktemp -d -t night-light-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'cfg.scripts_dir .. "/night-light.sh toggle"' \
  "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'Lua keybinding does not use the Hypr-owned wrapper'
grep -Fq '$scriptsDir/night-light.sh toggle' \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" ||
  fail 'legacy keybinding does not use the Hypr-owned wrapper'

mkdir -p "$test_root/bin" "$test_root/home"
cat > "$test_root/bin/pgrep-fixture" <<'SH'
#!/usr/bin/env bash
[[ -e "$NIGHT_LIGHT_FIXTURE_RUNNING" ]]
SH
cat > "$test_root/bin/setsid-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NIGHT_LIGHT_FIXTURE_CALLS"
: > "$NIGHT_LIGHT_FIXTURE_RUNNING"
SH
cat > "$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NIGHT_LIGHT_FIXTURE_CALLS"
if [[ "$*" == 'hyprsunset temperature' ]]; then
  [[ -e "$NIGHT_LIGHT_FIXTURE_RUNNING" ]] || exit 1
  printf 'Current temperature: %s K\n' "$(<"$NIGHT_LIGHT_FIXTURE_TEMPERATURE")"
else
  printf '%s\n' "$3" > "$NIGHT_LIGHT_FIXTURE_TEMPERATURE"
fi
SH
cat > "$test_root/bin/hyprsunset-fixture" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$test_root/bin/desktop-mode-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NIGHT_LIGHT_FIXTURE_DESKTOP_MODE_CALLS"
SH
chmod +x "$test_root/bin/"*

export HOME="$test_root/home"
export NIGHT_LIGHT_PGREP="$test_root/bin/pgrep-fixture"
export NIGHT_LIGHT_SETSID="$test_root/bin/setsid-fixture"
export NIGHT_LIGHT_HYPRCTL="$test_root/bin/hyprctl-fixture"
export NIGHT_LIGHT_HYPRSUNSET="$test_root/bin/hyprsunset-fixture"
export NIGHT_LIGHT_STARTUP_DELAY=0
export NIGHT_LIGHT_FIXTURE_RUNNING="$test_root/running"
export NIGHT_LIGHT_FIXTURE_TEMPERATURE="$test_root/temperature"
export NIGHT_LIGHT_FIXTURE_CALLS="$test_root/calls"
export NIGHT_LIGHT_FIXTURE_DESKTOP_MODE_CALLS="$test_root/desktop-mode-calls"
printf '6500\n' > "$NIGHT_LIGHT_FIXTURE_TEMPERATURE"

"$night_light" toggle
[[ "$(<"$NIGHT_LIGHT_FIXTURE_TEMPERATURE")" == 1000 ]] ||
  fail 'first toggle did not enable maximum warmth'
grep -Fq -- '-f' "$NIGHT_LIGHT_FIXTURE_CALLS" || fail 'missing backend was not started'

"$night_light" toggle
[[ "$(<"$NIGHT_LIGHT_FIXTURE_TEMPERATURE")" == 6500 ]] ||
  fail 'second toggle did not restore the normal temperature'

"$night_light" on
[[ "$(<"$NIGHT_LIGHT_FIXTURE_TEMPERATURE")" == 1000 ]] || fail 'on did not select 1000 K'
"$night_light" off
[[ "$(<"$NIGHT_LIGHT_FIXTURE_TEMPERATURE")" == 6500 ]] || fail 'off did not select 6500 K'

before=$(wc -l < "$NIGHT_LIGHT_FIXTURE_CALLS")
dry_run_output=$("$night_light" --dry-run on)
after=$(wc -l < "$NIGHT_LIGHT_FIXTURE_CALLS")
[[ "$before" -eq "$after" ]] || fail 'dry-run changed fixture state'
[[ "$dry_run_output" == *'hyprsunset temperature 1000'* ]] || fail 'dry-run omitted temperature command'

export NIGHT_LIGHT_DESKTOP_MODE="$test_root/bin/desktop-mode-fixture"
"$night_light" toggle
grep -Fxq -- 'toggle night-light' "$NIGHT_LIGHT_FIXTURE_DESKTOP_MODE_CALLS" ||
  fail 'installed desktop-mode was not preferred'

printf 'ok: night-light fixtures\n'
