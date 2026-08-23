#!/usr/bin/env bash
# hyprland-monitor-hotplug.sh — udev → user-session bridge for monitor hotplug.
#
# Invoked as ROOT from 99-hyprland-monitor-hotplug.rules on every
# ACTION=change/SUBSYSTEM=drm event. It deliberately does *no* user work of its
# own: it detaches from udev, works out which uid owns the graphical session,
# discovers that session's live Hyprland instance signature, and then drops
# privileges with runuser to run the user's own
# ~/.config/hypr/scripts/auto-monitor-profile.sh --force.
#
# Design rules (root context — keep them):
#   * never run hyprctl or any user-writable code as root;
#   * never write into a user-controlled path as root, and never follow a
#     user-created symlink — the debounce lock lives in root-owned /run;
#   * everything is best-effort: if no session is up we exit 0 silently and the
#     --watch poll picks the change up within 15s.
#
# Install: see the header of 99-hyprland-monitor-hotplug.rules (user step).

# Intentionally no `set -e`: this must never leave a udev worker in a bad state.
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

LOCK_DIR=/run/hyprland-monitor-hotplug
LOCK_FILE="$LOCK_DIR/lock"
SETTLE_SECONDS=1
USER_SCRIPT_REL=".config/hypr/scripts/auto-monitor-profile.sh"

log() { logger -t hyprland-monitor-hotplug -- "$*" 2>/dev/null || true; }

# ── Detach ──────────────────────────────────────────────────────────────────
# udev kills (and serialises on) long-running RUN+= children, so return to udev
# immediately and finish the work in a new session.
if [ "${HYPR_HOTPLUG_DETACHED:-0}" != "1" ]; then
  export HYPR_HOTPLUG_DETACHED=1
  if command -v setsid >/dev/null 2>&1; then
    setsid --fork "$0" "$@" </dev/null >/dev/null 2>&1 || true
  else
    "$0" "$@" </dev/null >/dev/null 2>&1 &
  fi
  exit 0
fi

# ── Debounce (root-owned /run only) ─────────────────────────────────────────
# A single dock event produces a burst of drm changes. The first handler takes
# the lock, sleeps briefly so the burst and the DRM state settle, then applies
# once; the rest of the burst exits immediately.
mkdir -p "$LOCK_DIR" 2>/dev/null || true
[ -d "$LOCK_DIR" ] || exit 0
[ -L "$LOCK_DIR" ] && exit 0
lock_owner="$(stat -c %u "$LOCK_DIR" 2>/dev/null || echo -1)"
[ "$lock_owner" = "0" ] || { log "refusing: $LOCK_DIR not root-owned"; exit 0; }
chmod 700 "$LOCK_DIR" 2>/dev/null || true

if command -v flock >/dev/null 2>&1; then
  if { exec 9>"$LOCK_FILE"; } 2>/dev/null; then
    flock -n 9 || exit 0
  fi
fi

sleep "$SETTLE_SECONDS"

# ── Resolve the graphical session ───────────────────────────────────────────
# Prefer an active wayland/x11 loginctl session; fall back to whoever owns a
# live /run/user/<uid>/hypr directory.
session_uid=""

if command -v loginctl >/dev/null 2>&1; then
  while read -r sid _rest; do
    [ -n "$sid" ] || continue
    s_active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
    s_type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    s_uid="$(loginctl show-session "$sid" -p User --value 2>/dev/null || true)"
    [ "$s_active" = "yes" ] || continue
    case "$s_type" in wayland | x11 | tty) ;; *) continue ;; esac
    case "$s_uid" in '' | *[!0-9]*) continue ;; esac
    if [ -d "/run/user/$s_uid/hypr" ]; then
      session_uid="$s_uid"
      break
    fi
    [ -n "$session_uid" ] || session_uid="$s_uid"
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi

if [ -z "$session_uid" ]; then
  for d in /run/user/*/hypr; do
    [ -d "$d" ] || continue
    candidate="${d#/run/user/}"
    candidate="${candidate%/hypr}"
    case "$candidate" in '' | *[!0-9]*) continue ;; esac
    session_uid="$candidate"
    break
  done
fi

[ -n "$session_uid" ] || exit 0

RUNTIME_DIR="/run/user/$session_uid"
# Root must not follow a user-planted symlink, and the runtime dir must really
# belong to that uid.
[ -L "$RUNTIME_DIR" ] && exit 0
[ -d "$RUNTIME_DIR" ] || exit 0
[ "$(stat -c %u "$RUNTIME_DIR" 2>/dev/null || echo -1)" = "$session_uid" ] || exit 0

session_user="$(getent passwd "$session_uid" | cut -d: -f1)"
session_home="$(getent passwd "$session_uid" | cut -d: -f6)"
[ -n "$session_user" ] || exit 0
[ -n "$session_home" ] || exit 0

# ── Discover the live Hyprland instance signature ───────────────────────────
HYPR_SOCK_DIR="$RUNTIME_DIR/hypr"
[ -L "$HYPR_SOCK_DIR" ] && exit 0
[ -d "$HYPR_SOCK_DIR" ] || exit 0
[ "$(stat -c %u "$HYPR_SOCK_DIR" 2>/dev/null || echo -1)" = "$session_uid" ] || exit 0

# Newest <signature>.sock wins; ignore anything nested or symlinked.
signature="$(
  find "$HYPR_SOCK_DIR" -maxdepth 1 -type f -name '*.sock' -printf '%T@ %f\n' 2>/dev/null |
    sort -rn | head -n1 | cut -d' ' -f2-
)"
if [ -z "$signature" ]; then
  # Older/newer layouts keep the socket inside a per-instance directory.
  signature="$(
    find "$HYPR_SOCK_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null |
      sort -rn | head -n1 | cut -d' ' -f2-
  )"
else
  signature="${signature%.sock}"
fi

[ -n "$signature" ] || exit 0
# Only pass a signature that is safe as an env value / path component.
case "$signature" in
  *[!A-Za-z0-9_.:-]* | '' | .* | */*) exit 0 ;;
esac

# ── Hand off to the user ────────────────────────────────────────────────────
USER_SCRIPT="$session_home/$USER_SCRIPT_REL"
[ -f "$USER_SCRIPT" ] || exit 0

command -v runuser >/dev/null 2>&1 || exit 0

export HOME="$session_home"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export HYPRLAND_INSTANCE_SIGNATURE="$signature"

runuser -u "$session_user" -- env \
  HOME="$session_home" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  HYPRLAND_INSTANCE_SIGNATURE="$signature" \
  bash "$USER_SCRIPT" --force >/dev/null 2>&1 || true

exit 0
