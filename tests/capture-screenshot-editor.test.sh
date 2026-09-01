#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t capture-screenshot-editor.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime" "$test_root/screenshots"

printf '%s\n' '#!/usr/bin/env bash' 'printf "0,0 100x100\n"' >"$test_root/bin/slurp"
printf '%s\n' '#!/usr/bin/env bash' 'printf png > "${!#}"' >"$test_root/bin/grim"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' >"$test_root/bin/wl-copy"
printf '%s\n' '#!/usr/bin/env bash' 'printf "edit\n"' >"$test_root/bin/notify-send"
printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == --fork ]] && shift; exec "$@"' >"$test_root/bin/setsid"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$SATTY_ARGS"' >"$test_root/bin/satty"
chmod +x "$test_root/bin/"*

PATH="$test_root/bin:$PATH" \
XDG_RUNTIME_DIR="$test_root/runtime" \
SCREENSHOT_DIR="$test_root/screenshots" \
SATTY_ARGS="$test_root/satty.args" \
  "$repo_root/hypr/.config/hypr/scripts/capture/screenshot.sh" region >/dev/null

mapfile -t args <"$test_root/satty.args"
[[ "${args[0]:-} ${args[1]:-} ${args[2]:-}" == '--copy-command wl-copy --filename' ]] || {
  printf 'FAIL: Satty editor arguments do not enable clipboard copy and filename input\n' >&2
  exit 1
}
[[ "${args[3]:-}" == "$test_root/screenshots/"*.png ]] || {
  printf 'FAIL: Satty did not receive the captured PNG\n' >&2
  exit 1
}

printf 'ok: screenshot Edit action launches Satty with --filename\n'
