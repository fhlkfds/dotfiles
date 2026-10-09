#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
state="$shell_dir/BatteryState.qml"
icon="$shell_dir/BatteryIcon.qml"
smoke="$shell_dir/BatterySmoke.qml"
panel="$shell_dir/BatteryPanel.qml"
panel_content="$shell_dir/BatteryPanelContent.qml"
metric="$shell_dir/BatteryMetric.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$panel" "$panel_content" "$metric"; do
  test -f "$required" || fail "missing battery panel file: $required"
done

# Kept: colours must come from Theme so a palette switch repaints the widget.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$state" "$icon" "$smoke" "$panel" \
     "$panel_content" "$metric"; then
  fail 'battery QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  mkdir -p "$test_root/bin" "$test_root/state"
  cat > "$test_root/bin/gsettings" <<'SH'
#!/usr/bin/env sh
exit 0
SH
  chmod +x "$test_root/bin/gsettings"
  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" \
    PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Battery widget projections' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'BatterySmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'BatterySmoke.qml reported a failing assertion'
  fi
  printf 'ok: BatterySmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, BatterySmoke.qml not run\n'
fi

printf 'ok: battery widget static checks\n'
