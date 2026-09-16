#!/usr/bin/env bash
# Exercises auto-monitor-profile.sh around the undock failure it used to have:
# with the lid closed the internal panel is disabled, and a disabled output is
# absent from `hyprctl -j monitors`. Resolving profile outputs against that list
# conflated "not connected" with "not enabled", so unplugging the dock while the
# lid was shut made the laptop profile look like it had no outputs at all. The
# applier refused, and the session was left with nothing enabled.
#
#   journalctl -t hypr-monitor:
#     watch: event monitorremoved, debouncing 0.6s
#     profile=laptop has no connected enabled output; refusing to apply
set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { printf 'skip: jq is not installed\n'; exit 0; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hypr_root="$repo_root/hypr/.config/hypr"
applier="$hypr_root/scripts/auto-monitor-profile.sh"
[[ -r "$applier" ]] || fail "missing: $applier"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

# A hermetic config dir: real profiles, but active files we control per case so
# the tests never depend on whichever profile this machine happens to be in.
conf="$test_root/hypr"
mkdir -p "$conf"
cp -r "$hypr_root/monitor_profiles" "$conf/monitor_profiles"
: >"$conf/hyprland.lua"

lid_open="$test_root/no-such-lid-state"
lid_closed="$test_root/lid-closed"
printf 'state:      closed\n' >"$lid_closed"

mon() { # name desc disabled x
  printf '{"name":"%s","description":"%s","disabled":%s,"width":%s,"height":%s,"refreshRate":60.0,"x":%s,"y":0,"scale":1.0,"transform":%s}' \
    "$1" "$2" "$3" "$5" "$6" "$4" "${7:-0}"
}

internal_on="$(mon eDP-1 'BOE 0x0BCA' false 0 2256 1504)"
internal_off="$(mon eDP-1 'BOE 0x0BCA' true 0 2256 1504)"
kvm_set="$(mon DP-7 'Dell Inc. DELL P2214H KW14V42L3ACB' false 2256 1920 1080 1),
$(mon DP-5 'Dell Inc. DELL P2722H CTCS1M3' false 3336 1920 1080),
$(mon DP-9 'Dell Inc. DELL P2725H 21MG834' false 5256 1920 1080)"

use_active() { # profile -- pretend this profile's files are the live ones
  cp "$conf/monitor_profiles/$1.monitors.lua" "$conf/monitors.lua"
  cp "$conf/monitor_profiles/$1.workspaces.lua" "$conf/workspaces.lua"
}

dry() { # lid_state json [extra args...]
  local lid="$1" json="$2"; shift 2
  SIMULATED_MONITORS="$json" HYPR_DIR="$conf" HYPR_LID_STATE="$lid" \
    bash "$applier" --dry-run "$@" 2>/dev/null
}

# ── The regression: undocked, lid still closed ──────────────────────────────
# eDP-1 is present in hardware but disabled by lid-switch.sh. The laptop
# profile is the right answer and must be applied, not refused.
use_active kvm
out="$(dry "$lid_closed" "[$internal_off]")" || fail "dry-run (undocked, lid closed) exited $?"
grep -q 'profile=laptop' <<<"$out" || fail "undocked lid closed: expected laptop, got: $out"
grep -q 'refused-no-connected-output' <<<"$out" &&
  fail "undocked lid closed: still refuses to apply -- the regression is present: $out"
grep -q 'result=would-apply' <<<"$out" ||
  fail "undocked lid closed: expected would-apply, got: $out"

# ...and because the lid override wants every row off, the applier must say it
# will light the panel anyway rather than leave the session with no output.
grep -q 'fallback=' <<<"$out" ||
  fail "undocked lid closed: no zero-output fallback announced: $out"

# ── The guard still has to work ─────────────────────────────────────────────
# A profile whose outputs are genuinely not plugged in must still be refused.
use_active laptop
out="$(dry "$lid_open" "[$internal_on]" --profile desktop || true)"
grep -q 'refused-no-connected-output' <<<"$out" ||
  fail "absent outputs must still be refused, got: $out"

# ── Ordinary cases must not regress ────────────────────────────────────────
# Docked, lid closed, kvm files already active: correct and idempotent.
use_active kvm
out="$(dry "$lid_closed" "[$internal_off,$kvm_set]")" || fail "dry-run (docked) exited $?"
grep -q 'profile=kvm' <<<"$out" || fail "docked: expected kvm, got: $out"
grep -q 'result=already-correct' <<<"$out" || fail "docked lid closed: expected already-correct, got: $out"

# A disabled panel must not read as "enabled" and force a pointless re-apply.
grep -q 'want=disabled  got=enabled' <<<"$out" &&
  fail "docked: disabled panel misreported as enabled: $out"

# Undocked with the lid open: laptop profile, panel enabled, nothing to do.
use_active laptop
out="$(dry "$lid_open" "[$internal_on]")" || fail "dry-run (lid open) exited $?"
grep -q 'profile=laptop' <<<"$out" || fail "lid open: expected laptop, got: $out"
grep -q 'result=already-correct' <<<"$out" || fail "lid open: expected already-correct, got: $out"
grep -q 'fallback=' <<<"$out" && fail "lid open: fallback must not trigger: $out"

# Partial KVM set is still "leave it alone", not a collapse onto the panel.
use_active kvm
out="$(dry "$lid_closed" "[$internal_off,$(mon DP-5 'Dell Inc. DELL P2722H CTCS1M3' false 3336 1920 1080)]")" ||
  fail "dry-run (partial) exited $?"
grep -q 'profile=none' <<<"$out" || fail "partial KVM set: expected profile=none, got: $out"
grep -q 'result=no-action' <<<"$out" || fail "partial KVM set: expected no-action, got: $out"

# ── Live apply: the session must never end with zero enabled outputs ────────
calls="$test_root/hyprctl.calls"
live="$test_root/live.json"
cat >"$test_root/hyprctl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$calls"
case "\$*" in
  "-j monitors all"|"-j monitors") cat "$live" ;;
  "-j workspaces"|"-j workspacerules") printf '[]\n' ;;
esac
exit 0
SH
chmod +x "$test_root/hyprctl"

use_active kvm
printf '[%s]\n' "$internal_off" >"$live"
: >"$calls"
HYPRCTL="$test_root/hyprctl" HYPR_DIR="$conf" HYPR_LID_STATE="$lid_closed" \
  HYPR_SKIP_SETTLE=1 bash "$applier" --verbose 2>/dev/null || true

cmp -s "$conf/monitors.lua" "$conf/monitor_profiles/laptop.monitors.lua" ||
  fail 'live apply did not install the laptop monitor profile'
cmp -s "$conf/workspaces.lua" "$conf/monitor_profiles/laptop.workspaces.lua" ||
  fail 'live apply left stale workspaces.lua -- workspaces stay pinned to gone monitors'
grep -q 'mode = "preferred"' "$calls" ||
  fail "zero-output fallback never re-enabled the panel; calls were: $(cat "$calls")"

printf 'ok: auto-monitor-profile.sh\n'
