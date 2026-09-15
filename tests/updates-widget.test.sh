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

printf 'updates widget: ok\n'
