#!/usr/bin/env bash
# Omarchy-style "Files Here" for Hyprland: open Nautilus at the current working
# directory of the focused terminal.
#
# Bound to Super+Shift+Alt+F. Super+Shift+E opens Nautilus plainly; this script
# is the context-aware variant.
#
# Behaviour, in order:
#   focused window is not a terminal  -> open Nautilus normally
#   focused window is a terminal      -> resolve its CWD and open Nautilus there
#   terminal is inside ssh/mosh       -> notify, then open $HOME
#   CWD cannot be resolved            -> notify, then open $HOME
#
# Two CWD strategies, because neither alone is sufficient:
#
#   1. kitty remote control (primary, exact). KITTY_LISTEN_ON is read out of
#      /proc/<pid>/environ, so we talk to *that* kitty instance and nobody
#      else's. `kitten @ ls` reports the focused tab's window, its cwd, and its
#      foreground processes -- which is the only way to know which tab or split
#      is actually active, and gives us ssh detection for free.
#      Requires `allow_remote_control socket-only` + `listen_on` in kitty.conf.
#
#   2. /proc descendant walk (fallback). Used for kitty windows started before
#      that config existed, and for any future terminal without a control API.
#      It cannot distinguish tabs -- with several shells under one terminal PID
#      it takes the deepest, then most recently started, which is a heuristic.
#
# Paths are passed to Nautilus as an argument array. There is no eval and no
# shell-string interpolation anywhere, so spaces and quotes in paths are safe.

set -uo pipefail

scripts_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/terminals.sh
source "$scripts_dir/lib/terminals.sh"

FILE_MANAGER=nautilus
MAX_WALK_DEPTH=32

# Commands that mean "this shell is not on this machine". A CWD read from under
# one of these is a remote path that has no local meaning.
REMOTE_COMMANDS=(ssh mosh mosh-client sshpass et telnet)

# Helper processes a terminal spawns alongside the shell. They are real
# descendants but their CWD is not the user's, so the /proc walk must skip them.
IGNORED_COMMANDS=(kitten kitty-tool)

is_ignored_command() {
  local name=${1##*/} c
  for c in "${IGNORED_COMMANDS[@]}"; do
    [[ $name == "$c" ]] && return 0
  done
  return 1
}

is_remote_command() {
  local name=${1##*/} c
  for c in "${REMOTE_COMMANDS[@]}"; do
    [[ $name == "$c" ]] && return 0
  done
  return 1
}

notify() {
  local title="$1"
  local message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Files Here" "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  notify "Files Here unavailable" "$1 is not installed."
  exit 1
}

require_cmd hyprctl
require_cmd jq
require_cmd "$FILE_MANAGER"

action=${1:-open}
case "$action" in
  open|info) ;;
  *)
    echo "usage: $(basename "$0") [open|info]" >&2
    exit 2
    ;;
esac

open_files() {
  # Argument array, never a shell string. `--` guards against a path that
  # somehow begins with a dash.
  exec "$FILE_MANAGER" -- "$1"
}

# --- focused window -------------------------------------------------------

win=$(hyprctl -j activewindow 2>/dev/null)

if [[ -z $win || $win == "{}" ]]; then
  # Nothing focused at all. Plain Files is the least surprising result.
  [[ $action == info ]] && { echo "no focused window -> plain $FILE_MANAGER"; exit 0; }
  exec "$FILE_MANAGER"
fi

class=$(jq -r '.class // ""'        <<<"$win")
initial=$(jq -r '.initialClass // ""' <<<"$win")
pid=$(jq -r '.pid // 0'             <<<"$win")

if ! is_terminal_class "$class" "$initial"; then
  [[ $action == info ]] && {
    printf 'class=%s initialClass=%s pid=%s -> gui (plain %s)\n' \
      "${class:-<none>}" "${initial:-<none>}" "$pid" "$FILE_MANAGER"
    exit 0
  }
  exec "$FILE_MANAGER"
fi

if [[ ! $pid =~ ^[0-9]+$ ]] || (( pid <= 0 )); then
  notify "Could not open here" "Focused terminal reported no usable PID."
  open_files "$HOME"
fi

strategy=""
cwd=""
fg_comm=""
remote_comm=""

# --- process tree ---------------------------------------------------------

# Descendants of the terminal window's PID as "<depth> <pid>" lines, deepest
# first; on a tie the most recently started (highest PID) wins. Populated once
# and reused by both strategies.
DESCENDANTS=()

collect_descendants() {
  local -a acc=()
  _walk() {
    local parent=$1 depth=$2 child
    (( depth > MAX_WALK_DEPTH )) && return
    for child in $(ps -o pid= --ppid "$parent" 2>/dev/null); do
      acc+=("$depth $child")
      _walk "$child" $((depth + 1))
    done
  }
  _walk "$pid" 1
  if (( ${#acc[@]} )); then
    mapfile -t DESCENDANTS < <(printf '%s\n' "${acc[@]}" | sort -k1,1nr -k2,2nr)
  fi
}
collect_descendants

# --- strategy 1: kitty remote control -------------------------------------

kitty_cwd() {
  local sock="" ls_json node entry cpid
  command -v kitten >/dev/null 2>&1 || return 1

  # kitty exports KITTY_LISTEN_ON to the processes it spawns, not to its own
  # environment -- so the socket is found on a descendant (the shell), never on
  # the window PID itself. Check both anyway, cheapest first.
  for cpid in "$pid" $(printf '%s\n' "${DESCENDANTS[@]}" | awk '{print $2}'); do
    [[ -r /proc/$cpid/environ ]] || continue
    sock=$(tr '\0' '\n' < "/proc/$cpid/environ" 2>/dev/null \
           | grep -m1 '^KITTY_LISTEN_ON=' | cut -d= -f2-)
    [[ -n $sock ]] && break
  done
  [[ -n $sock ]] || return 1

  ls_json=$(kitten @ --to "$sock" ls 2>/dev/null) || return 1
  [[ -n $ls_json ]] || return 1

  # The focused window of the focused OS window and tab. Fall back to any
  # focused window in the instance if the OS window flag is unset.
  node=$(jq -c '
    [ .[] | select(.is_focused) | .tabs[] | select(.is_focused) | .windows[] | select(.is_focused) ]
    + [ .[] | .tabs[] | .windows[] | select(.is_focused) ]
    | .[0] // empty
  ' <<<"$ls_json" 2>/dev/null) || return 1
  [[ -n $node ]] || return 1

  cwd=$(jq -r '.cwd // ""' <<<"$node")
  # Deepest foreground process wins for the CWD -- its directory is what the
  # user perceives as "here".
  fg_comm=$(jq -r '(.foreground_processes // []) | last | (.cmdline // []) | .[0] // ""' <<<"$node")
  fg_comm=${fg_comm##*/}
  local fg_cwd cmd
  fg_cwd=$(jq -r '(.foreground_processes // []) | last | .cwd // ""' <<<"$node")
  [[ -n $fg_cwd ]] && cwd=$fg_cwd

  # But scan the *whole* chain for a remote session: `ssh` may not be the
  # deepest entry (a ProxyCommand child sits below it), and checking only the
  # last one would miss it.
  while read -r cmd; do
    [[ -n $cmd ]] || continue
    if is_remote_command "$cmd"; then remote_comm=${cmd##*/}; break; fi
  done < <(jq -r '(.foreground_processes // [])[] | (.cmdline // []) | .[0] // empty' <<<"$node")

  [[ -n $cwd ]] || return 1
  strategy="kitty-remote-control"
  return 0
}

# --- strategy 2: /proc descendant walk ------------------------------------

proc_cwd() {
  local resolved="" node depth cpid entry comm

  # DESCENDANTS is already deepest-first, most-recent-first.
  for entry in "${DESCENDANTS[@]}"; do
    read -r depth cpid <<<"$entry"
    [[ -n $cpid ]] || continue
    comm=$(cat "/proc/$cpid/comm" 2>/dev/null)
    is_ignored_command "$comm" && continue
    node=$(readlink -e "/proc/$cpid/cwd" 2>/dev/null) || continue
    [[ -n $node ]] || continue
    resolved=$node
    fg_comm=$comm
    break
  done

  # Same whole-tree scan for a remote session as the kitty path does.
  for entry in "${DESCENDANTS[@]}"; do
    read -r depth cpid <<<"$entry"
    [[ -n $cpid ]] || continue
    node=$(cat "/proc/$cpid/comm" 2>/dev/null) || continue
    if is_remote_command "$node"; then remote_comm=$node; break; fi
  done

  # No usable descendant: the terminal process itself is better than nothing.
  if [[ -z $resolved ]]; then
    resolved=$(readlink -e "/proc/$pid/cwd" 2>/dev/null) || return 1
    fg_comm=$(cat "/proc/$pid/comm" 2>/dev/null)
  fi

  [[ -n $resolved ]] || return 1
  cwd=$resolved
  strategy="proc-walk"
  return 0
}

kitty_cwd || proc_cwd || {
  [[ $action == info ]] && { echo "class=$class pid=$pid -> terminal, cwd unresolved"; exit 0; }
  notify "Could not open here" "Failed to determine the terminal's directory."
  open_files "$HOME"
}

# --- ssh / remote sessions ------------------------------------------------

if [[ -n $remote_comm ]]; then
  if [[ $action == info ]]; then
    printf 'class=%s pid=%s strategy=%s foreground=%s remote=%s -> remote session\n' \
      "$class" "$pid" "$strategy" "${fg_comm:-<none>}" "$remote_comm"
    exit 0
  fi
  notify "Remote session" "A remote CWD cannot be mapped to a local path. Opening Home."
  open_files "$HOME"
fi

# --- validate -------------------------------------------------------------

if [[ $action == info ]]; then
  printf 'class=%s initialClass=%s pid=%s strategy=%s foreground=%s cwd=%s\n' \
    "${class:-<none>}" "${initial:-<none>}" "$pid" "$strategy" \
    "${fg_comm:-<none>}" "${cwd:-<none>}"
  exit 0
fi

if [[ $cwd != /* ]] || [[ ! -d $cwd ]] || [[ ! -x $cwd ]]; then
  notify "Could not open here" "Not a usable directory: ${cwd:-<empty>}"
  open_files "$HOME"
fi

open_files "$cwd"
