#!/usr/bin/env bash
# Clipboard store filter, invoked by the wl-paste watchers in autostart.lua:
#
#   wl-paste --type text  --watch .../clipboard-store.sh
#   wl-paste --type image --watch .../clipboard-store.sh
#
# The clipboard content arrives on stdin and is passed straight through to
# `cliphist store` unless it should be skipped. This replaces `cliphist store`
# as the handler -- the watcher count is unchanged, and only this short-lived
# filter runs per clipboard change.

set -uo pipefail

# ---------------------------------------------------------------------------
# Window classes whose clipboard content should never be stored.
# The ONLY place these live. Matched against class and initialClass.
# ---------------------------------------------------------------------------
EXCLUDED_CLASSES=(
)

# Password managers (KeePassXC and friends) advertise this MIME type to mark a
# selection as secret. No password manager is installed right now, so this is
# future-proofing -- browser built-in managers do not set it.
if wl-paste --list-types 2>/dev/null | grep -qiF 'x-kde-passwordManagerHint'; then
  exit 0
fi

if ((${#EXCLUDED_CLASSES[@]})); then
  win=$(hyprctl -j activewindow 2>/dev/null)
  if [[ -n $win && $win != "{}" ]]; then
    class=$(jq -r '.class // ""' <<<"$win")
    initial=$(jq -r '.initialClass // ""' <<<"$win")
    for c in "${EXCLUDED_CLASSES[@]}"; do
      [[ $class == "$c" || $initial == "$c" ]] && exit 0
    done
  fi
fi

exec cliphist store
