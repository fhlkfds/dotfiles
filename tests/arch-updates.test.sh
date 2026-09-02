#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

printf '#!/bin/sh\nprintf "core 1 -> 2\\nextra 1 -> 2\\n"\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\n' > "$fixture/yay"
chmod +x "$fixture/checkupdates" "$fixture/yay"

output=$(PATH="$fixture:/usr/bin" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":2,"aur":1,"total":3}' ]]

printf '#!/bin/sh\nexit 1\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nexit 0\n' > "$fixture/yay"
output=$(PATH="$fixture:/usr/bin" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":0,"total":0}' ]]

mv "$fixture/yay" "$fixture/paru"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/kitty"
chmod +x "$fixture/kitty"
ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture:/usr/bin" \
  "$repo_root/hypr/.config/hypr/scripts/arch-updates" update
grep -Fx 'exec "$1" -Syyu' "$fixture/update.log" >/dev/null
grep -Fx "$fixture/paru" "$fixture/update.log" >/dev/null
