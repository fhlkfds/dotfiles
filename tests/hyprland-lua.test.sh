#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_root="$repo_root/hypr/.config/hypr"
test_root=$(mktemp -d -t hyprland-lua-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v luac >/dev/null 2>&1 || fail 'luac is required'
command -v Hyprland >/dev/null 2>&1 || fail 'Hyprland is required'

while IFS= read -r -d '' file; do
  luac -p "$file"
done < <(find "$hypr_root" -type f -name '*.lua' -not -path '*/themes/.active/*' -print0)

mkdir -p "$test_root/config" "$test_root/home" "$test_root/runtime"
cp -a "$hypr_root/." "$test_root/config/hypr/"
rm -f "$test_root/config/hypr/hyprland.conf" \
  "$test_root/config/hypr/workspaces.conf"
XDG_RUNTIME_DIR="$test_root/runtime" \
  python3 "$hypr_root/theme/generate.py" set everforest \
    --prefix "$test_root/config" --no-reload >/dev/null
luac -p "$test_root/config/hypr/conf/decorations.lua"
HOME="$test_root/home" \
XDG_CONFIG_HOME="$test_root/config" \
XDG_RUNTIME_DIR="$test_root/runtime" \
  Hyprland --verify-config --config "$test_root/config/hypr/hyprland.lua" \
  >"$test_root/verify.log" 2>&1 || {
    sed -n '1,240p' "$test_root/verify.log" >&2
    fail 'Hyprland rejected the Lua config'
  }
grep -Fq 'config ok' "$test_root/verify.log" || fail 'config verification did not report success'
[[ ! -e "$test_root/config/hypr/hyprland.conf" ]] ||
  fail 'config verification regenerated hyprland.conf'

fixture_hypr="$test_root/profile-hypr"
mkdir -p "$fixture_hypr/monitor_profiles" "$test_root/bin" "$test_root/profile-runtime"
cp "$hypr_root/monitor_profiles/"*.lua "$fixture_hypr/monitor_profiles/"

cat >"$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HYPRCTL_CALLS"
case "$*" in
  '-j monitors')
    printf '%s\n' '[{"name":"DP-4"},{"name":"HDMI-A-3"},{"name":"DP-1"}]'
    ;;
  '-j workspaces')
    printf '%s\n' '[{"id":1,"monitor":"DP-4"},{"id":6,"monitor":"HDMI-A-3"}]'
    ;;
esac
SH
chmod +x "$test_root/bin/hyprctl-fixture"

export HYPRCTL_CALLS="$test_root/hyprctl.calls"
HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-fixture" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --force

cmp "$fixture_hypr/monitors.lua" "$fixture_hypr/monitor_profiles/desktop.monitors.lua" ||
  fail 'desktop monitor profile was not copied to the Lua active file'
cmp "$fixture_hypr/workspaces.lua" "$fixture_hypr/monitor_profiles/desktop.workspaces.lua" ||
  fail 'desktop workspace profile was not copied to the Lua active file'
grep -Fq 'dispatch hl.dsp.workspace.move({ workspace = 1, monitor = "HDMI-A-3" })' "$HYPRCTL_CALLS" ||
  fail 'workspace migration did not use the Lua dispatcher'
grep -Fq 'dispatch hl.dsp.focus({ monitor = "HDMI-A-3" })' "$HYPRCTL_CALLS" ||
  fail 'desktop focus did not use the Lua dispatcher'

HYPR_DIR="$fixture_hypr" "$hypr_root/scripts/set-monitor-scale.sh" HDMI-A-3 1.25 >/dev/null
for file in "$fixture_hypr/monitors.lua" "$fixture_hypr/monitor_profiles/desktop.monitors.lua"; do
  awk '
    /output = "HDMI-A-3"/ { target = 1 }
    target && /scale = 1.25/ { found = 1 }
    target && /^})/ { exit found ? 0 : 1 }
    END { if (!target || !found) exit 1 }
  ' "$file" || fail "scale was not persisted in $file"
  luac -p "$file"
done

: >"$HYPRCTL_CALLS"
HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-fixture" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --force --dry-run >"$test_root/dry-run.out"
grep -Fq 'profile=desktop' "$test_root/dry-run.out" || fail 'dry-run did not report the selected profile'
! grep -Fq 'reload' "$HYPRCTL_CALLS" || fail 'dry-run contacted a mutating Hyprland command'

printf 'ok: Hyprland Lua config and monitor fixtures\n'
