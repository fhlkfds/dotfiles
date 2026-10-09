#!/usr/bin/env bash
# The clock dashboard (overview, media, system, weather) must open and switch
# tabs without building anything, and must cost nothing while it is closed.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qs="$repo_root/quickshell/.config/quickshell"
panel="$qs/DashboardPanel.qml"
view="$qs/DashboardView.qml"
state="$qs/DashboardState.qml"
pages=("$qs/DashOverview.qml" "$qs/DashMedia.qml" "$qs/DashSystem.qml" "$qs/DashWeather.qml")

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$panel" "$view" "$state" "${pages[@]}" "$qs/DashCard.qml" \
                "$qs/WaveProgress.qml" "$qs/Sparkline.qml" "$qs/Holidays.js"; do
  test -f "$required" || fail "missing dashboard file: ${required#"$repo_root"/}"
done

# --- GPU power ----------------------------------------------------------------

# A sleeping hybrid-laptop dGPU must not be woken just to draw a graph.
# Kept as text checks: no fixture covers the sysfs power-state gate.
grep -Fq 'power/runtime_status' "$qs/SysState.qml" && grep -Fq '"suspended"' "$qs/SysState.qml" \
  || fail 'nvidia-smi can wake a suspended GPU'
grep -Fq '"--id=" + root.gpuPciId' "$qs/SysState.qml" \
  || fail 'nvidia-smi queries GPUs other than the one whose power state was checked'
grep -Fq 'state === "active" && !nvidiaProc.running' "$qs/SysState.qml" \
  || fail 'NVIDIA query runs without a completed active power-state reading'

# --- theming -------------------------------------------------------------------

# Kept: colours must come from Theme so a palette switch repaints the dashboard.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$panel" "$view" "${pages[@]}" "$qs/DashCard.qml" \
     "$qs/WaveProgress.qml" "$qs/Sparkline.qml"; then
  fail 'dashboard QML hardcodes a colour instead of reading Theme roles'
fi

# --- holiday logic ---------------------------------------------------------------

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/dashboard-holidays.logic.test.js" "$qs/Holidays.js"
  node "$repo_root/tests/dashboard-state.logic.test.js"
else
  printf 'skip: node is not installed, holiday logic not run\n'
fi

printf 'ok: clock dashboard\n'
