#!/usr/bin/env bash
# Persist a monitor scale into the Hyprland monitor config.
#
# monitors.lua is a GENERATED file: auto-monitor-profile.sh copies
# monitor_profiles/<profile>.monitors.lua over it whenever the connected-output
# set changes. So a scale change has to be written to BOTH the live file (so it
# survives a `hyprctl reload`) and the profile file (so it survives a profile
# switch or reboot).
#
# Only the `scale` field in the matching `hl.monitor` table is rewritten.
# Disabled outputs and other fields are left untouched.
#
# Applying the scale to the running compositor is the caller's job
# (`hyprctl eval 'hl.monitor(...)'`); this script only edits files.

set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <MONITOR> <SCALE>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
MON=$1
SCALE=$2

[[ $MON =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid monitor name: $MON" >&2; exit 2; }
[[ $SCALE =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "invalid scale: $SCALE" >&2; exit 2; }

HYPR_DIR=${HYPR_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}
TARGETS=(
  "$HYPR_DIR/monitors.lua"
  "$HYPR_DIR/monitor_profiles/desktop.monitors.lua"
)

total_hits=0
for f in "${TARGETS[@]}"; do
  if [[ ! -f $f ]]; then
    echo "warning: not found, skipping: $f" >&2
    continue
  fi

  tmp=$(mktemp "${f}.XXXXXX")
  trap 'rm -f "$tmp"' EXIT

  hits=$(awk -v mon="$MON" -v scale="$SCALE" '
    BEGIN { in_monitor = 0; target = 0; hits = 0 }
    /^[[:space:]]*hl\.monitor\([[:space:]]*\{/ { in_monitor = 1; target = 0 }
    in_monitor && $0 ~ "output[[:space:]]*=[[:space:]]*\"" mon "\"" { target = 1 }
    in_monitor && target && /^[[:space:]]*scale[[:space:]]*=/ {
      indent = $0
      sub(/[^[:space:]].*$/, "", indent)
      comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
      $0 = indent "scale = " scale comma
      hits++
    }
    { print }
    in_monitor && /^[[:space:]]*\}\)[,;]?[[:space:]]*$/ { in_monitor = 0; target = 0 }
    END { print hits > "/dev/stderr" }
  ' "$f" 2>"$tmp.hits" >"$tmp")

  hits=$(cat "$tmp.hits")
  rm -f "$tmp.hits"

  if [[ ${hits:-0} -eq 0 ]]; then
    rm -f "$tmp"
    echo "warning: no scaled monitor table for '$MON' in $f" >&2
    continue
  fi

  # Preserve the original mode, then swap atomically.
  chmod --reference="$f" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$f"
  trap - EXIT
  total_hits=$((total_hits + hits))
  echo "updated $f ($hits line(s))"
done

if [[ $total_hits -eq 0 ]]; then
  echo "error: scale for '$MON' was not persisted anywhere" >&2
  exit 1
fi
