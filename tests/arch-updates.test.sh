#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# The result cache is exercised on its own below; the counting assertions want a
# fresh check every time.
export ARCH_UPDATES_TTL=0

printf '#!/bin/sh\nprintf "core 1 -> 2\\nextra 1 -> 2\\n"\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\n' > "$fixture/yay"
chmod +x "$fixture/checkupdates" "$fixture/yay"
# The stubs are only meaningful if the host's real checkupdates/yay/paru are out
# of reach, so the fixture is the entire PATH and supplies its own bash.
ln -s "$(command -v bash)" "$fixture/bash"

output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":2,"aur":1,"total":3,"repoPackages":["core","extra"],"aurPackages":["aur-one"]}' ]]

# Exit 2 is checkupdates reporting a clean system, not a failure.
printf '#!/bin/sh\nexit 2\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":0,"total":0,"repoPackages":[],"aurPackages":[]}' ]]

# An AUR helper that lists updates but exits non-zero still contributes a count.
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":1,"total":1,"repoPackages":[],"aurPackages":["aur-one"]}' ]]

# AUR throttling must keep the last known widget values rather than claim that
# there are no updates.
printf '#!/bin/sh\nprintf "status 429: Rate limit reached\\n" >&2\nexit 1\n' > "$fixture/yay"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: rate-limited AUR check reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

# A failed sync must not be reported as "zero updates"; the widget keeps its
# last known count when the script exits non-zero.
printf '#!/bin/sh\nexit 1\n' > "$fixture/checkupdates"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: failed sync reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

mv "$fixture/yay" "$fixture/paru"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/kitty"
chmod +x "$fixture/kitty"
ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture" \
  "$repo_root/hypr/.config/hypr/scripts/arch-updates" update
grep -F '"$1" -Syyu;' "$fixture/update.log" >/dev/null
grep -Fx "$fixture/paru" "$fixture/update.log" >/dev/null

# The cache is what stops several callers (the bar, lmenu, a prompt) from each
# querying the AUR. A repeat call inside the TTL must not reach the helper.
cache=$(mktemp -d)
trap 'rm -rf "$fixture" "$cache"' EXIT
calls="$cache/calls"
: > "$calls"
printf '#!/bin/sh\nprintf "checkupdates\\n" >> "%s"\nprintf "core 1 -> 2\\n"\n' "$calls" > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "yay\\n" >> "%s"\nprintf "aur-one 1 -> 2\\n"\n' "$calls" > "$fixture/yay"
rm -f "$fixture/paru"
chmod +x "$fixture/checkupdates" "$fixture/yay"

run_cached() {
  ARCH_UPDATES_TTL=600 ARCH_UPDATES_CACHE_DIR="$cache/store" PATH="$fixture:$PATH" \
    "$repo_root/hypr/.config/hypr/scripts/arch-updates"
}

first=$(run_cached)
[[ $first == '{"repo":1,"aur":1,"total":2,"repoPackages":["core"],"aurPackages":["aur-one"]}' ]]
[[ $(grep -c '^yay$' "$calls") == 1 ]]

second=$(run_cached)
[[ $second == "$first" ]]
if [[ $(grep -c '^yay$' "$calls") != 1 ]]; then
  printf 'FAIL: cached call still queried the AUR\n' >&2
  exit 1
fi

# An expired entry must fall through to a real check again.
printf '0' > "$cache/store/last-attempt"
third=$(run_cached)
[[ $third == "$first" ]]
[[ $(grep -c '^yay$' "$calls") == 2 ]]

# After a failure the cooldown reports an error rather than serving the last
# good payload, so the widget keeps showing its own stale count.
rm -rf "$cache/store"
: > "$calls"
printf '#!/bin/sh\nprintf "yay\\n" >> "%s"\nprintf "status 429: Rate limit reached\\n" >&2\nexit 1\n' "$calls" > "$fixture/yay"
chmod +x "$fixture/yay"
if run_cached >/dev/null 2>&1; then
  printf 'FAIL: rate-limited check reported success\n' >&2
  exit 1
fi
if run_cached >/dev/null 2>&1; then
  printf 'FAIL: throttled retry reported success\n' >&2
  exit 1
fi
if [[ $(grep -c '^yay$' "$calls") != 1 ]]; then
  printf 'FAIL: retry inside the cooldown queried the AUR again\n' >&2
  exit 1
fi
