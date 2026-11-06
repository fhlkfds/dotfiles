#!/usr/bin/env bash
# Centre island: glance queue rules under node, then IslandSmoke.qml, which
# measures the real BarCenter clock and capsule before, during and after a
# track glance, and checks notifications stay cards.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
logic="$shell_dir/island/IslandLogic.js"
smoke="$shell_dir/IslandSmoke.qml"
island_qml=("$shell_dir/IslandState.qml" "$shell_dir/IslandGlance.qml" "$shell_dir/IslandPanel.qml"
            "$shell_dir/IslandPanelContent.qml" "$shell_dir/BarCenter.qml" "$smoke")

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Colours come from Theme so a palette switch repaints the island.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "${island_qml[@]}"; then
  fail 'island QML contains a hardcoded colour'
fi

# Glances ride the bar's hot path: no process spawns, no polling.
if grep -nE 'Process|execDetached|repeat: *true' "${island_qml[@]}" "$logic"; then
  fail 'island QML spawns processes or polls'
fi

python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$shell_dir/island/config.json" \
  || fail 'island/config.json is not valid JSON'

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/island.logic.test.js" "$logic" || fail 'island logic test failed'
else
  printf 'skip: node is not installed, island logic not run\n'
fi

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'skip: quickshell is not installed, IslandSmoke.qml not run\n'
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
    fail 'IslandSmoke.qml reported a failing assertion'
  fi
  grep -Fq 'island smoke: ok' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'IslandSmoke.qml did not report success'; }
  printf 'ok: IslandSmoke.qml (%s assertions)\n' "$(grep -c '^.*ok   ' "$smoke_log" || true)"
fi

printf 'ok: island static checks\n'
