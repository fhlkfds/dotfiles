#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_root/hypr/.config/hypr/scripts/default-browser-private"
test_root="$(mktemp -d -t default-browser-private-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

mkdir -p "$test_root/data/applications" "$test_root/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/fake-browser"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/firefox"
chmod +x "$test_root/bin/fake-browser" "$test_root/bin/firefox"

cat > "$test_root/data/applications/action.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Fixture Browser
Exec=fake-browser %U
Actions=new-window;new-private-window;

[Desktop Action new-private-window]
Name=New private window
Exec=fake-browser --incognito
DESKTOP

common_env=(
    "PATH=$test_root/bin:$PATH"
    "DEFAULT_BROWSER_PRIVATE_DATA_DIRS=$test_root/data"
    "DEFAULT_BROWSER_PRIVATE_DRY_RUN=1"
    "DEFAULT_BROWSER_PRIVATE_NO_NOTIFY=1"
)

output="$(env "${common_env[@]}" DEFAULT_BROWSER_PRIVATE_DESKTOP=action.desktop "$helper")"
[[ "$output" == "fake-browser --incognito" ]] || fail "desktop private action was not used: $output"

cat > "$test_root/data/applications/firefox.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Fixture Firefox
Exec=firefox %U
DESKTOP

output="$(env "${common_env[@]}" DEFAULT_BROWSER_PRIVATE_DESKTOP=firefox.desktop "$helper")"
[[ "$output" == "firefox --private-window" ]] || fail "Firefox fallback was wrong: $output"

cat > "$test_root/data/applications/unknown.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Unknown Browser
Exec=fake-browser %U
DESKTOP

if env "${common_env[@]}" DEFAULT_BROWSER_PRIVATE_DESKTOP=unknown.desktop \
    "$helper" > /dev/null 2> "$test_root/unknown.err"; then
    fail "unknown browser incorrectly reported success"
fi
grep -Fq "private mode is unknown" "$test_root/unknown.err" || \
    fail "unknown browser error was not useful"

printf 'ok: default-browser-private fixtures\n'
