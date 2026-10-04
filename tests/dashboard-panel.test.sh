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

# --- speed: everything built once, nothing loaded or resized on demand ------

for page in DashOverview DashMedia DashSystem DashWeather; do
  grep -Fq "$page {" "$view" || fail "dashboard does not instantiate $page up front"
done
! grep -Eq 'Loader|StackView|SwipeView' "$view" "$panel" \
  || fail 'dashboard builds pages on demand instead of keeping them alive'
grep -Fq 'implicitWidth: pageW + pad * 2' "$view" || fail 'dashboard size is not fixed across tabs'
! grep -Eq 'Behavior on (implicitWidth|implicitHeight|width|height|opacity)' "$view" "$panel" \
  || fail 'dashboard animates its size or fades, which delays every open and tab switch'
! grep -Fq 'Behavior on' "$panel" || fail 'dashboard window animates on open'

# --- one popup per bar, tied to the screen whose clock was clicked ----------

grep -Fq 'visible: DashboardState.panelVisible && DashboardState.panelScreen === panel.ownerScreen' "$panel" \
  || fail 'dashboard is not gated on the screen that opened it'
grep -Fq 'grabFocus: true' "$panel" || fail 'dashboard does not close on an outside click'
grep -Fq 'DashboardState.panelVisible = false' "$panel" \
  || fail 'an outside click leaves DashboardState thinking the dashboard is open'
grep -Fq 'Qt.Key_Escape' "$view" || fail 'Escape does not close the dashboard'
grep -Fq 'activeTab = "overview"' "$state" || fail 'opening the dashboard does not land on the overview'
grep -Fq 'target: "dashboard"' "$qs/Bar.qml" || fail 'dashboard has no IPC target'

# --- closed costs nothing ------------------------------------------------------

grep -Fq 'readonly property bool active: DashboardState.panelVisible' "$qs/SysState.qml" \
  || fail 'system metrics poll while the dashboard is closed'
grep -Fq 'root.panelVisible || (DashboardState.panelVisible' "$qs/MediaState.qml" \
  || fail 'media position does not tick for the dashboard timeline'
grep -Fq 'DashboardState.activeTab === "overview" || DashboardState.activeTab === "media"' "$qs/MediaState.qml" \
  || fail 'media position ticks on tabs without a timeline'
grep -Fq 'live: root.shown && visible' "$view" || fail 'pages are not told when they are on screen'
for page in "${pages[@]}"; do
  grep -Fq 'property bool live' "$page" || fail "${page##*/} has no on-screen gate"
done
grep -Fq 'animating: root.live && MediaState.isPlaying' "$qs/DashMedia.qml" \
  || fail 'media timeline animates while off screen'
grep -Fq 'readonly property var levels: live &&' "$qs/DashMedia.qml" \
  || fail 'media spectrum re-evaluates at cava frame rate while off screen'
grep -Fq 'readonly property var levels: live &&' "$qs/DashOverview.qml" \
  || fail 'overview spectrum re-evaluates at cava frame rate while off screen'
! grep -Fq 'CavaBars' "$qs/DashOverview.qml" \
  || fail 'overview uses CavaBars, which binds straight to the 30 fps spectrum'
grep -Fq 'NumberAnimation on x' "$qs/WaveProgress.qml" && grep -Fq 'running: root.animating' "$qs/WaveProgress.qml" \
  || fail 'wave timeline repaints instead of sliding a pre-drawn canvas'

# A sleeping hybrid-laptop dGPU must not be woken just to draw a graph.
grep -Fq 'power/runtime_status' "$qs/SysState.qml" && grep -Fq '"suspended"' "$qs/SysState.qml" \
  || fail 'nvidia-smi can wake a suspended GPU'
grep -Fq '"--id=" + root.gpuPciId' "$qs/SysState.qml" \
  || fail 'nvidia-smi queries GPUs other than the one whose power state was checked'
grep -Fq 'state === "active" && !nvidiaProc.running' "$qs/SysState.qml" \
  || fail 'NVIDIA query runs without a completed active power-state reading'
grep -Fq 'Component.onDestruction' "$panel" \
  || fail 'removing the owning screen can leave dashboard polling active'
grep -Fq 'panel.screen.width' "$panel" && grep -Fq 'contentWidth > width' "$view" \
  || fail 'dashboard body is unreachable on narrow screens'

# --- theming -------------------------------------------------------------------

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
