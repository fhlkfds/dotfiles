#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
widget="$repo_root/quickshell/.config/quickshell/UpdatesIcon.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

! grep -Fq 'opacity: (UpdatesState.updating || UpdatesState.checking) ? 0.55 : 1' "$widget" ||
  fail 'update checks still dim the Pacman indicator'

grep -Fq 'onClicked: UpdatesState.update()' "$widget" ||
  fail 'updater click does not start the updater state'

! grep -Fq 'enabled: !UpdatesState.checking && !UpdatesState.updating' "$widget" ||
  fail 'update checks disable the updater click target'

state="$repo_root/quickshell/.config/quickshell/UpdatesState.qml"

# pollTimer.restart() is called from both onExited handlers. With
# triggeredOnStart the restart fired the timer immediately, so every finished
# check started the next one and the AUR was queried until it returned 429.
! grep -Eq '^\s*triggeredOnStart:\s*true' "$state" ||
  fail 'poll timer fires on start, so restarting it re-runs the check immediately'

grep -Fq 'Component.onCompleted: root.refresh()' "$state" ||
  fail 'nothing checks for updates at shell startup'

grep -Fq 'minRefreshGap' "$state" ||
  fail 'refresh() has no minimum gap between AUR checks'

# One number on the bar; the pacman/AUR split lives in the hover.
grep -Fq '"󰚰  " + UpdatesState.totalCount' "$widget" ||
  fail 'bar label is not the single combined count'
grep -Fq '"Pacman (" + UpdatesState.repoCount' "$widget" &&
  grep -Fq '"\nAUR (" + UpdatesState.aurCount' "$widget" ||
  fail 'hover does not break the count down into pacman and AUR'

# Hidden on a clean zero, but a failed check must stay visible or a missing
# checkupdates looks like an up-to-date system.
grep -Fq 'UpdatesState.totalCount > 0 || UpdatesState.updating || UpdatesState.stale' "$widget" ||
  fail 'a failed check with no count hides the widget'
grep -Fq '"󰚰  !"' "$widget" ||
  fail 'a failed check with no count has no visible marker'

# A partial update clears only the side the script reports it upgraded.
grep -Fq 'if (scope !== "aur")' "$state" && grep -Fq 'if (scope !== "repo")' "$state" ||
  fail 'a partial update still clears both counts'

printf 'updates widget: ok\n'
