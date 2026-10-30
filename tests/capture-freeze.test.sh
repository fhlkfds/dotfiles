#!/usr/bin/env bash
# A rotated monitor must skip the hyprpicker freeze: hyprpicker paints its
# still frame unrotated, so the screenshot came out landscape.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t capture-freeze.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
command -v jq >/dev/null || { printf 'skip: jq not installed\n'; exit 0; }

# shellcheck disable=SC2016 # Expansion happens when each mock runs.
printf '%s\n' '#!/usr/bin/env bash' 'cat "$MONITORS_JSON"' >"$test_root/bin/hyprctl"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'touch "$FREEZE_MARK"; exec sleep 5' >"$test_root/bin/hyprpicker"
chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH" XDG_RUNTIME_DIR="$test_root/runtime"
export MONITORS_JSON="$test_root/monitors.json" CAPTURE_FREEZE_WARMUP=0.2
select_sh="$repo_root/hypr/.config/hypr/scripts/capture/select.sh"

# freezes <transform...>: exit 0 when hyprpicker was started.
freezes() {
  local t json='['
  for t in "$@"; do json+="{\"name\":\"M$t\",\"transform\":$t},"; done
  printf '%s]\n' "${json%,}" >"$MONITORS_JSON"
  export FREEZE_MARK="$test_root/froze"
  rm -f -- "$FREEZE_MARK"
  bash -c 'source "$1"; capture_freeze_start; capture_freeze_stop' _ "$select_sh"
  [[ -e $FREEZE_MARK ]]
}

freezes 0 0 || fail 'unrotated monitors should still freeze'
! freezes 0 1 || fail 'a portrait monitor (transform 1) must skip the freeze'
! freezes 3 || fail 'a portrait monitor (transform 3) must skip the freeze'
printf 'ok   capture-freeze\n'
