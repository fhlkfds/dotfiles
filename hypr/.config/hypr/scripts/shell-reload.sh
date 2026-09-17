#!/usr/bin/env bash
#
# Reload the desktop in place after a config change: Hyprland re-reads its
# config, then every Quickshell instance is stopped and relaunched detached.
#
# Quickshell picks up most QML edits on its own, but a panel that changed
# shape — new files, new singleton properties — needs a fresh process. Both
# autostarted instances are restarted, not just the bar: they share one
# binary, so stopping the bar takes the cava visualiser with it.

set -euo pipefail

program=${0##*/}

note() { printf '%s: %s\n' "$program" "$*"; }
fail() {
  printf '%s: error: %s\n' "$program" "$*" >&2
  exit 1
}

command -v quickshell >/dev/null 2>&1 || fail "quickshell is not installed"

# Matches the exec-once lines in conf/autostart.conf: the default config is
# the bar, and the visualiser is a sibling directory. It has to be launched by
# path rather than by `-c cava-visualizer`, because quickshell stops looking at
# subdirectories once `quickshell/shell.qml` exists, which it does here.
shell_root=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell
declare -a shell_configs=("$shell_root/cava-visualizer")

if pgrep -x Hyprland >/dev/null 2>&1; then
  command -v hyprctl >/dev/null 2>&1 || fail "Hyprland is live but hyprctl is unavailable"
  note 'reloading Hyprland'
  hyprctl reload >/dev/null || fail "hyprctl reload failed"
else
  note 'no live Hyprland session; skipping the compositor reload'
fi

if pgrep -x quickshell >/dev/null 2>&1; then
  note 'stopping Quickshell'
  pkill -x quickshell || true

  # Give the instances a moment to unmap their layer surfaces. A survivor
  # would hold the bar's namespace and the relaunched process would sit
  # behind it, so escalate rather than racing.
  for _ in {1..30}; do
    pgrep -x quickshell >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -x quickshell >/dev/null 2>&1; then
    note 'Quickshell did not exit; sending SIGKILL'
    pkill -KILL -x quickshell || true
    sleep 0.2
  fi
fi

note 'starting Quickshell'
quickshell --daemonize || fail "quickshell failed to start"

for config in "${shell_configs[@]}"; do
  if [[ ! -f $config/shell.qml ]]; then
    note "skipping $config: no shell.qml there"
    continue
  fi
  note "starting Quickshell (${config##*/})"
  quickshell -p "$config" --daemonize ||
    fail "quickshell -p $config failed to start"
done

note 'desktop reloaded'
