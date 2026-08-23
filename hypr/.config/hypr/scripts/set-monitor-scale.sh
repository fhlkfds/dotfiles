#!/usr/bin/env bash
# Persist a monitor scale into the Hyprland monitor config.
#
# monitors.conf is a GENERATED file: auto-monitor-profile.sh copies
# monitor_profiles/<profile>.monitors.conf over it whenever the connected-output
# set changes. So a scale change has to be written to BOTH the live file (so it
# survives a `hyprctl reload`) and the profile file (so it survives a profile
# switch or reboot).
#
# Only the 4th positional field of a `monitor=NAME,MODE,POSITION,SCALE` line is
# rewritten. The separate `monitor=NAME,transform,N` and `monitor=NAME,disable`
# forms are left untouched -- DP-4 relies on its transform line for rotation.
#
# Applying the scale to the running compositor is the caller's job
# (hyprctl keyword monitor ...); this script only edits files.

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
  "$HYPR_DIR/monitors.conf"
  "$HYPR_DIR/monitor_profiles/desktop.monitors.conf"
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
    BEGIN { FS = ","; OFS = ","; hits = 0 }
    {
      key = $1
      gsub(/[ \t]/, "", key)
      # Only the positional mode form has 4+ fields with a resolution in $2.
      if (key == "monitor=" mon && NF >= 4 && $2 ~ /^[ \t]*([0-9]+x[0-9]+(@[0-9.]+)?|preferred|highres|highrr)[ \t]*$/) {
        $4 = scale
        hits++
      }
      print
    }
    END { print hits > "/dev/stderr" }
  ' "$f" 2>"$tmp.hits" >"$tmp")

  hits=$(cat "$tmp.hits")
  rm -f "$tmp.hits"

  if [[ ${hits:-0} -eq 0 ]]; then
    rm -f "$tmp"
    echo "warning: no positional monitor line for '$MON' in $f" >&2
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
