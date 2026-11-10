#!/usr/bin/env bash
# Bar centre: the clock capsule is static. Nothing pops out of it for track
# changes or notifications. Static checks first: no theme-bypassing colours,
# nothing that spawns or polls, no leftover island references. Then
# BarCenterSmoke.qml measures the real BarCenter on a roomy bar and a crowded
# one, and before and after notifications arrive.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
smoke="$shell_dir/BarCenterSmoke.qml"
center_qml=("$shell_dir/BarCenter.qml" "$smoke")

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Colours come from Theme so a palette switch repaints the capsule.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "${center_qml[@]}"; then
  fail 'bar centre QML contains a hardcoded colour'
fi

# The centre is on the bar's hot path: no process spawns, no polling.
if grep -nE 'Process|execDetached|repeat: *true' "$shell_dir/BarCenter.qml"; then
  fail 'BarCenter.qml spawns processes or polls'
fi

# The pop-out island is gone. A leftover reference would stop the whole shell
# from loading, so catch it here rather than on the next reload.
if grep -rnE '\bIsland(State|Glance|Panel|PanelContent|Logic)\b|island/' \
    --include='*.qml' --include='*.js' "$shell_dir"; then
  fail 'quickshell still references the removed island glance'
fi

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'skip: quickshell is not installed, BarCenterSmoke.qml not run\n'
elif ! command -v dbus-run-session >/dev/null 2>&1; then
  printf 'skip: quickshell smoke needs dbus-run-session, which is not installed\n'
else
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  mkdir -p "$test_root/bin" "$test_root/state" "$test_root/runtime"
  chmod 700 "$test_root/runtime"
  # WeatherState fetches on load; keep the fixture off the network.
  printf '#!/usr/bin/env sh\nexit 1\n' > "$test_root/bin/curl"
  chmod +x "$test_root/bin/curl"
  smoke_log="$test_root/smoke.log"
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen \
    dbus-run-session -- timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'BarCenterSmoke.qml reported a failing assertion'
  fi
  grep -Fq 'bar centre smoke: ok' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'BarCenterSmoke.qml did not report success'; }
  printf 'ok: BarCenterSmoke.qml (%s assertions)\n' "$(grep -c '^.*ok   ' "$smoke_log" || true)"
fi

printf 'ok: bar centre static checks\n'
