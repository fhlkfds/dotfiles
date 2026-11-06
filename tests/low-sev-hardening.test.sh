#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
location_script="$repo_root/hyprlock/.config/hyprlock/scripts/location.sh"
weather_script="$repo_root/hyprlock/.config/hyprlock/scripts/weather.sh"
picker="$repo_root/hypr/.local/bin/hypr-wallpaper-picker"
test_root="$(mktemp -d -t low-sev-hardening-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

# Kept: security guard. Lock-screen helpers must never fetch over plaintext HTTP.
if grep -Fq -- 'http://' "$location_script" "$weather_script"; then
  fail "plaintext HTTP URL remains in a Hyprlock helper"
fi
# Kept: security guard. eval would let a crafted wallpaper path run as code.
if grep -Eq '(^|[[:space:]|;])eval([[:space:]]|$)' "$picker"; then
  fail "hypr-wallpaper-picker invokes eval"
fi

stub_bin="$test_root/bin"
mkdir -p "$stub_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"${CURL_LOG:?}"' \
  'case ${CURL_MODE:-valid} in' \
  '  empty) exit 0 ;;' \
  '  long) printf "%200s" "" | tr " " x; exit 0 ;;' \
  'esac' \
  'case $* in' \
  '  *ipinfo.io*) printf "{\"country\":\"US\",\"city\":\"Fixture City\"}\n" ;;' \
  '  *) printf "Clear +21C\n" ;;' \
  'esac' >"$stub_bin/curl"
chmod +x "$stub_bin/curl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'IFS= read -r input || true' \
  '[[ $input == *'"'"'"country":"US","city":"Fixture City"'"'"'* ]] || exit 1' \
  'printf "US, Fixture City\n"' >"$stub_bin/jq"
chmod +x "$stub_bin/jq"

disabled_home="$test_root/disabled-home"
disabled_log="$test_root/disabled-curl.log"
mkdir -p "$disabled_home"
output=$(env -u HYPRLOCK_ENABLE_LOCATION HOME="$disabled_home" \
  PATH="$stub_bin:$PATH" CURL_LOG="$disabled_log" "$location_script")
[[ "$output" == "Location unavailable" ]] || fail "disabled location was not neutral"
[[ ! -e "$disabled_log" ]] || fail "disabled location invoked curl"

location_home="$test_root/location-home"
location_log="$test_root/location-curl.log"
mkdir -p "$location_home"
output=$(HOME="$location_home" PATH="$stub_bin:$PATH" CURL_LOG="$location_log" \
  HYPRLOCK_ENABLE_LOCATION=1 "$location_script")
[[ "$output" == "US, Fixture City" ]] || fail "enabled location fixture failed"
assert_contains "$location_log" "--fail --silent --show-error --location --proto =https --proto-redir =https --connect-timeout 5 --max-time 15 https://ipinfo.io"

weather_home="$test_root/weather-home"
weather_log="$test_root/weather-curl.log"
mkdir -p "$weather_home"
output=$(env -u HYPRLOCK_ENABLE_WEATHER HOME="$weather_home" \
  PATH="$stub_bin:$PATH" CURL_LOG="$weather_log" "$weather_script")
[[ "$output" == "Weather unavailable" ]] || fail "disabled weather was not neutral"
[[ ! -e "$weather_log" ]] || fail "disabled weather invoked curl"

output=$(HOME="$weather_home" PATH="$stub_bin:$PATH" CURL_LOG="$weather_log" \
  HYPRLOCK_ENABLE_WEATHER=1 "$weather_script")
[[ "$output" == "Clear +21C" ]] || fail "weather fixture failed"
assert_contains "$weather_log" "--fail --silent --show-error --location --proto =https --proto-redir =https --connect-timeout 5 --max-time 15 https://wttr.in?format=%c+%C+%t"

invalid_home="$test_root/invalid-home"
mkdir -p "$invalid_home"
output=$(HOME="$invalid_home" PATH="$stub_bin:$PATH" \
  CURL_LOG="$test_root/invalid-curl.log" CURL_MODE=long \
  HYPRLOCK_ENABLE_WEATHER=1 "$weather_script")
[[ "$output" == "Weather unavailable" ]] || fail "oversized weather output was accepted"
[[ ! -e "$invalid_home/.cache/wttr_cache.txt" ]] || fail "invalid weather response was cached"

if ! command -v jq >/dev/null 2>&1; then
  printf 'skip: jq not installed (wallpaper picker path quoting)\n'
else
  wallpaper_bin="$test_root/wallpaper-bin"
  wallpaper_home="$test_root/home with spaces"
  wallpaper="$wallpaper_home/Pictures/Wallpapers/my wallpaper.png"
  hyprctl_log="$test_root/hyprctl.log"
  mkdir -p "$wallpaper_bin" "${wallpaper%/*}"
  printf fixture >"$wallpaper"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "<%s>\n" "$@" >>"${HYPRCTL_LOG:?}"' \
    >"$wallpaper_bin/hyprctl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$wallpaper_bin/pgrep"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$wallpaper_bin/notify-send"
  chmod +x "$wallpaper_bin/hyprctl" "$wallpaper_bin/pgrep" "$wallpaper_bin/notify-send"

  env -u HYPR_WALLPAPER_DIR -u HYPR_WALLPAPER_STATE_FILE -u XDG_STATE_HOME \
    HOME="$wallpaper_home" PATH="$wallpaper_bin:$PATH" "$picker" index |
    jq -e --arg path "$wallpaper" '.items[] | select(.path == $path)' >/dev/null ||
    fail "picker index split a path containing spaces"

  env -u HYPR_WALLPAPER_STATE_FILE -u XDG_STATE_HOME HOME="$wallpaper_home" \
    PATH="$wallpaper_bin:$PATH" HYPRCTL_LOG="$hyprctl_log" "$picker" apply "$wallpaper"
  assert_contains "$hyprctl_log" "<,$wallpaper,cover>"
  state="$wallpaper_home/.local/state/hyprland-desktop/wallpaper/current"
  [[ "$(jq -r .path "$state")" == "$wallpaper" ]] ||
    fail "picker did not persist a path containing spaces"
fi

printf 'ok: low-severity script hardening\n'
