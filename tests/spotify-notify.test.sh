#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/spotify-notify.sh"
test_root=$(mktemp -d -t spotify-notify-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

bin="$test_root/bin"
mkdir -p "$bin"

# Two tracks with different art, then the first track again.
cat >"$bin/playerctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' \
  'Daughtry|Over You|Daughtry|https://art.example/a' \
  'Bad Omens|Limits|Limits|https://art.example/b' \
  'Daughtry|Over You|Daughtry|https://art.example/a'
STUB
# Writes the URL as the "image" and counts downloads.
cat >"$bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$TEST_ROOT/curl.log"
printf '%s' "$url" >"$out"
STUB
cat >"$bin/notify-send" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  [ "$1" = -i ] && printf '%s\n' "$2" >>"$TEST_ROOT/icons.log"
  shift
done
STUB
chmod +x "$bin"/*

TEST_ROOT="$test_root" XDG_CACHE_HOME="$test_root/cache" PATH="$bin:$PATH" \
  bash "$script"

mapfile -t icons <"$test_root/icons.log"
[ "${#icons[@]}" -eq 3 ] || fail "expected 3 notifications with art, got ${#icons[@]}"
[ "${icons[0]}" != "${icons[1]}" ] || fail 'different tracks share one art file'
[ "${icons[0]}" = "${icons[2]}" ] || fail 'same art URL did not reuse its cached file'
[ "$(cat "${icons[0]}")" = https://art.example/a ] || fail 'first card has the wrong art'
[ "$(cat "${icons[1]}")" = https://art.example/b ] || fail 'second card has the wrong art'
[ "$(wc -l <"$test_root/curl.log")" -eq 2 ] || fail 'cached art was downloaded again'

printf 'ok: spotify-notify\n'
