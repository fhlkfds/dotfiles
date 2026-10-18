#!/usr/bin/env bash
# capture.sh doctor warns when the running Hyprland bakes the night-light screen
# shader into screenshots (0.56 and older), and stays quiet without a session.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
capture="$repo_root/hypr/.config/hypr/scripts/capture/capture.sh"
test_root=$(mktemp -d -t capture-doctor-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || { printf 'skip: jq not installed\n'; exit 0; }

mkdir -p "$test_root/bin" "$test_root/runtime"
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ -n ${FIXTURE_HYPR_VERSION:-} ]] || exit 1
[[ "$*" == 'version -j' ]] || exit 2
printf '{"branch":"","commit":"abc","version":"%s","tag":"v%s"}\n' \
  "$FIXTURE_HYPR_VERSION" "$FIXTURE_HYPR_VERSION"
SH
chmod +x "$test_root/bin/hyprctl"
export PATH="$test_root/bin:$PATH" XDG_RUNTIME_DIR="$test_root/runtime"

doctor() { FIXTURE_HYPR_VERSION=$1 "$capture" doctor; }

output=$(doctor 0.56.2) || fail 'doctor failed on Hyprland 0.56.2'
[[ $output == *'night light -> screenshots include the tint on Hyprland 0.56.2'* ]] ||
  fail "doctor did not warn on 0.56.2: $output"

output=$(doctor 0.57.0) || fail 'doctor failed on Hyprland 0.57.0'
[[ $output == *'night light -> screenshots skip the tint (Hyprland 0.57.0)'* ]] ||
  fail "doctor did not report the fixed version: $output"

output=$(doctor '') || fail 'doctor failed without a Hyprland session'
[[ $output != *'night light ->'* ]] || fail 'doctor guessed a version without a session'

printf 'ok capture-doctor\n'
