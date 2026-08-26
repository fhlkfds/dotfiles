#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
record="$repo_root/hypr/.config/hypr/scripts/capture/record.sh"
test_root=$(mktemp -d -t webcam-resize-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/runtime/hypr-capture"
cat > "$test_root/bin/webcam-ipc-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$2" >> "$WEBCAM_IPC_CALLS"
[[ "${WEBCAM_IPC_FAIL:-0}" != 1 ]]
SH
cat > "$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WEBCAM_HYPRCTL_CALLS"
SH
chmod +x "$test_root/bin/webcam-ipc-fixture" "$test_root/bin/hyprctl-fixture"

capture_runtime="$test_root/runtime/hypr-capture"
printf '%s\n' "$$" > "$capture_runtime/record.pid"
printf '%s\n' "$$" > "$capture_runtime/webcam.pid"
printf '%s\n' medium > "$capture_runtime/webcam.size"

export XDG_RUNTIME_DIR="$test_root/runtime"
export WEBCAM_IPC_HELPER="$test_root/bin/webcam-ipc-fixture"
export WEBCAM_IPC_CALLS="$test_root/ipc-calls"
export WEBCAM_HYPRCTL="$test_root/bin/hyprctl-fixture"
export WEBCAM_HYPRCTL_CALLS="$test_root/hyprctl-calls"

"$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == small ]] ||
  fail 'smaller did not select the small preset'
grep -Fq -- $'webcam.sock\t320x180-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'smaller did not send the small geometry'

before=$(wc -l < "$WEBCAM_IPC_CALLS")
"$record" webcam-size smaller
after=$(wc -l < "$WEBCAM_IPC_CALLS")
[[ "$before" -eq "$after" ]] || fail 'small preset stepped below its minimum'

"$record" webcam-size larger
[[ "$(<"$capture_runtime/webcam.size")" == medium ]] ||
  fail 'first larger step did not select medium'
"$record" webcam-size larger
[[ "$(<"$capture_runtime/webcam.size")" == large ]] ||
  fail 'second larger step did not select large'
grep -Fq -- $'webcam.sock\t480x270-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'larger did not send the medium geometry'
grep -Fq -- $'webcam.sock\t640x360-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'larger did not send the large geometry'

"$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == medium ]] ||
  fail 'smaller did not step from large back to medium'

WEBCAM_IPC_FAIL=1 "$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == small ]] ||
  fail 'Hyprland fallback did not update the size preset'
grep -Fq -- "dispatch hl.dsp.window.resize({ x = 320, y = 180, window = \"pid:$$\" })" \
  "$WEBCAM_HYPRCTL_CALLS" || fail 'failed IPC did not use the PID-scoped Hyprland fallback'

rm -f "$capture_runtime/record.pid"
before=$(wc -l < "$WEBCAM_IPC_CALLS")
"$record" webcam-size smaller
after=$(wc -l < "$WEBCAM_IPC_CALLS")
[[ "$before" -eq "$after" ]] || fail 'idle resize reached the IPC helper'

printf 'ok: webcam resize fixtures\n'
