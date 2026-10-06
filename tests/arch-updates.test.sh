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
ln -s "$(command -v mktemp)" "$fixture/mktemp"
ln -s "$(command -v rm)" "$fixture/rm"

output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":2,"aur":1,"total":3,"repoPackages":["core","extra"],"aurPackages":["aur-one"]}' ]]

# yay 13 appends the update's age. Rejecting that failed the whole check, so
# the bar showed "!" over hundreds of pending repo updates. The synthetic
# [ignored] line also checks compatibility with other trailing annotations;
# yay 13 itself omits ignored packages from its query output.
printf '#!/bin/sh\nprintf "terraform-bin 1.16.3-1.0 -> 1.16.5-1.0 [15h44m]\\nbrave-bin 1:1.95.104-1 -> 1:1.96.61-1 [1d1h]\\nheld 1-1 -> 2-1 [ignored]\\n"\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":2,"aur":3,"total":5,"repoPackages":["core","extra"],"aurPackages":["terraform-bin","brave-bin","held"]}' ]] ||
  { printf 'FAIL: annotated yay output was rejected: %s\n' "$output" >&2; exit 1; }

# Exit 2 is checkupdates reporting a clean system, not a failure.
printf '#!/bin/sh\nexit 2\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":0,"total":0,"repoPackages":[],"aurPackages":[]}' ]]

# An AUR helper that lists updates but exits non-zero still contributes a count.
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":1,"total":1,"repoPackages":[],"aurPackages":["aur-one"]}' ]]

# A crash with no stderr is still a failed check, unlike yay's empty exit 1.
printf '#!/bin/sh\nexit 139\n' > "$fixture/yay"
if PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" >/dev/null 2>&1; then
  printf 'FAIL: crashed AUR check reported success\n' >&2
  exit 1
fi

# AUR throttling must keep the last known widget values rather than claim that
# there are no updates.
printf '#!/bin/sh\nprintf "status 429: Rate limit reached\\n" >&2\nexit 1\n' > "$fixture/yay"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: rate-limited AUR check reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

# Network errors and stderr warnings must never become package names.
printf '#!/bin/sh\nprintf "connection refused\\n" >&2\nexit 1\n' > "$fixture/yay"
if PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" >/dev/null 2>&1; then
  printf 'FAIL: AUR network failure reported success\n' >&2
  exit 1
fi
printf '#!/bin/sh\nprintf "error: request failed\\n"\nexit 1\n' > "$fixture/yay"
if PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" >/dev/null 2>"$fixture/err"; then
  printf 'FAIL: AUR diagnostic counted as a package\n' >&2
  exit 1
fi
# The rejected line reaches the widget's log, so the next format change is
# diagnosable without rerunning the AUR query by hand.
grep -Fq 'unexpected yay output: error: request failed' "$fixture/err"
rm "$fixture/err"
# Brackets belong only to complete trailing annotations. Keep the same token
# count for malformed versions, so rejection cannot just depend on extra words.
printf '#!/bin/sh\nprintf "%%s\\n" "$ARCH_UPDATES_TEST_LINE"\n' > "$fixture/yay"
for line in 'aur-one [x] 1 -> 2' 'aur-one [x] -> 2' 'aur-one 1 -> [2]' \
            'aur-one 1 -> 2 [nested[x]' 'aur-one 1 -> 2 [15h44m' \
            'aur-one 1 -> 2 [15h44m]]' 'aur-one 1 -> 2 [15h44m] diagnostic'; do
  if output=$(ARCH_UPDATES_TEST_LINE="$line" PATH="$fixture" \
    "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>"$fixture/err"); then
    printf 'FAIL: malformed annotated line counted as a package: %s\n' "$line" >&2
    exit 1
  fi
  [[ -z $output ]]
  grep -Fq "unexpected yay output: $line" "$fixture/err"
done
rm "$fixture/err"
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\nprintf "warning: orphan package\\n" >&2\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":1,"total":1,"repoPackages":[],"aurPackages":["aur-one"]}' ]]

# A failed sync must not be reported as "zero updates"; the widget keeps its
# last known count when the script exits non-zero.
printf '#!/bin/sh\nexit 1\n' > "$fixture/checkupdates"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: failed sync reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

# pacman without pacman-contrib has no checkupdates. Counting that as zero repo
# updates hid hundreds of pending packages, so it has to be an error too.
mv "$fixture/checkupdates" "$fixture/checkupdates.off"
printf '#!/bin/sh\nexit 0\n' > "$fixture/pacman"
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\n' > "$fixture/yay"
chmod +x "$fixture/pacman"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>"$fixture/err"); then
  printf 'FAIL: missing checkupdates reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]
grep -Fq 'pacman-contrib' "$fixture/err"
rm "$fixture/pacman" "$fixture/err"
mv "$fixture/checkupdates.off" "$fixture/checkupdates"

# --- update path -------------------------------------------------------------
# The terminal stub records its argv instead of launching anything, so the
# composed upgrade command can be asserted on a host that has neither an AUR
# helper nor apt.
script="$repo_root/hypr/.config/hypr/scripts/arch-updates"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/kitty"
chmod +x "$fixture/kitty"

run_update_stub() {
  local status=0 output
  rm -f "$fixture/update.log"
  output=$(ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture" TERMINAL="${1:-}" "$script" update) || status=$?
  # A zero-exit terminal that never launches the child is not a successful update.
  [[ $status == 1 && -z $output ]]
}

# Arch: the AUR helper is the upgrade command, and it wins over apt.
printf '#!/bin/sh\nexit 0\n' > "$fixture/apt"
chmod +x "$fixture/apt"
run_update_stub
grep -Fx 'aur' "$fixture/update.log" >/dev/null
grep -Fx "$fixture/yay" "$fixture/update.log" >/dev/null
grep -Fq 'aur) "$helper" "$@"' "$fixture/update.log"
# Unattended: defaults everywhere, and removals (the [y/N] prompts) stay no.
grep -Fx -- '--noconfirm' "$fixture/update.log" >/dev/null
grep -Fx -- '--noremovemake' "$fixture/update.log" >/dev/null
grep -Fx -- '--answerdiff' "$fixture/update.log" >/dev/null
# The title is what the Hyprland rule uses to put this on workspace 1.
grep -Fx 'System Update' "$fixture/update.log" >/dev/null
# The window must stay open on a read rather than exiting the moment yay does.
grep -Fq 'read -rp "Done. Press Enter to close. "' "$fixture/update.log"
# The upgrade's exit status has to survive, or the widget cannot tell a failed
# update from a clean one and wrongly zeroes its count.
grep -Fq 'exit $status' "$fixture/update.log"
# --sudoloop runs "$sudobin -v", which doas rejects on every iteration. It is
# passed only when yay's configured sudobin is sudo, and never when the config
# cannot be read.
! grep -Fx -- '--sudoloop' "$fixture/update.log" >/dev/null ||
  { printf 'FAIL: --sudoloop passed without a readable yay config\n' >&2; exit 1; }
cp "$fixture/yay" "$fixture/yay.orig"
for case in 'doas|no' '/usr/bin/doas|no' 'sudo|yes' '/usr/bin/sudo|yes'; do
  IFS='|' read -r sudobin want_loop <<< "$case"
  printf '#!/bin/sh\n[ "$1" = -Pg ] && printf "{\\n\\t\\"sudobin\\": \\"%s\\",\\n\\t\\"sudoflags\\": \\"\\"\\n}\\n"\nexit 0\n' "$sudobin" > "$fixture/yay"
  run_update_stub
  if grep -Fx -- '--sudoloop' "$fixture/update.log" >/dev/null; then got_loop=yes; else got_loop=no; fi
  [[ $got_loop == "$want_loop" ]] ||
    { printf 'FAIL: sudobin %s gave --sudoloop=%s\n' "$sudobin" "$got_loop" >&2; exit 1; }
done
mv -f "$fixture/yay.orig" "$fixture/yay"

# Cache invalidation must not turn a failed terminal run into widget success.
printf '#!/bin/sh\nexit 23\n' > "$fixture/failterm"
chmod +x "$fixture/failterm"
status=0
ARCH_UPDATES_TTL=600 ARCH_UPDATES_CACHE_DIR="$fixture/update-cache" \
  TERMINAL="$fixture/failterm" PATH="$fixture:$PATH" "$script" update || status=$?
[[ $status == 23 ]] || { printf 'FAIL: update exit status was lost\n' >&2; exit 1; }

# The inner shell must execute a helper whose path contains spaces literally.
mkdir "$fixture/with space"
printf '#!/bin/sh\nprintf "updated\\n" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/with space/yay"
printf '#!/bin/sh\nshift 2\nprintf "\\n\\n" | "$@"\n' > "$fixture/exec-term"
chmod +x "$fixture/with space/yay" "$fixture/exec-term"
ARCH_UPDATES_TEST_LOG="$fixture/executed.log" TERMINAL="$fixture/exec-term" \
  PATH="$fixture/with space:$fixture:$PATH" "$script" update >/dev/null
grep -Fxq updated "$fixture/executed.log"

# The prompt: Enter means both, "p" is pacman alone, "a" is the AUR alone, all
# through yay. The side that ran is printed so the widget only clears that
# count; a partial update must not zero the other one.
# The config query (-Pg) is read-only and runs before the terminal opens.
printf '#!/bin/sh\n[ "$1" = -Pg ] && exit 0\necho "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/with space/yay"
printf '#!/bin/sh\nshift 2\nprintf "%%s\\n\\n" "$ARCH_UPDATES_ANSWER" | "$@" >/dev/null\n' > "$fixture/answer-term"
chmod +x "$fixture/with space/yay" "$fixture/answer-term"
for case in '|all|-Syu --noconfirm' 'B|all|-Syu --noconfirm' 'p|repo|-Syu --repo --noconfirm' 'a|aur|-Sua --noconfirm'; do
  IFS='|' read -r answer want_scope want_args <<< "$case"
  scope=$(ARCH_UPDATES_ANSWER=$answer ARCH_UPDATES_TEST_LOG="$fixture/executed.log" \
    TERMINAL="$fixture/answer-term" PATH="$fixture/with space:$fixture:$PATH" \
    "$script" update)
  [[ $scope == "$want_scope" && $(<"$fixture/executed.log") == "$want_args"* ]] ||
    { printf 'FAIL: answer "%s" printed "%s" and ran: %s\n' "$answer" "$scope" "$(<"$fixture/executed.log")" >&2; exit 1; }
done

# Closing stdin or entering an invalid answer must not start an upgrade.
printf '#!/bin/sh\nshift 2\n"$@" </dev/null\nexit 0\n' > "$fixture/cancel-term"
chmod +x "$fixture/cancel-term"
rm "$fixture/executed.log"
for answer in eof x potato; do
  term="$fixture/answer-term"
  [[ $answer != eof ]] || term="$fixture/cancel-term"
  if ARCH_UPDATES_ANSWER=$answer ARCH_UPDATES_TEST_LOG="$fixture/executed.log" \
    TERMINAL="$term" PATH="$fixture/with space:$fixture:$PATH" "$script" update >/dev/null 2>&1; then
    printf 'FAIL: cancelled or invalid choice reported success\n' >&2
    exit 1
  fi
  [[ ! -e $fixture/executed.log ]]
done

# Kitty can return zero after a failed child. Use the manager result, and keep
# terminal stdout out of the scope protocol.
printf '#!/bin/sh\nexit 42\n' > "$fixture/with space/yay"
printf '#!/bin/sh\nshift 2\nprintf "\\n\\n" | "$@"\nprintf "terminal diagnostic\\n"\nexit 0\n' > "$fixture/masking-term"
chmod +x "$fixture/masking-term"
status=0
scope=$(TERMINAL="$fixture/masking-term" PATH="$fixture/with space:$fixture:$PATH" "$script" update 2>/dev/null) || status=$?
[[ $status == 42 && -z $scope ]] || { printf 'FAIL: terminal masked manager failure\n' >&2; exit 1; }
printf '#!/bin/sh\nexit 0\n' > "$fixture/with space/yay"
scope=$(TERMINAL="$fixture/masking-term" PATH="$fixture/with space:$fixture:$PATH" "$script" update 2>/dev/null)
[[ $scope == all ]]

# Different terminal CLIs need their own command separator/title syntax.
for terminal_name in alacritty ghostty; do
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/$terminal_name"
  chmod +x "$fixture/$terminal_name"
  run_update_stub "$terminal_name"
  grep -Fxq -- '-e' "$fixture/update.log"
done
grep -Fxq -- '--title=System Update' "$fixture/update.log"
grep -Fxq -- '--gtk-single-instance=false' "$fixture/update.log"
rm "$fixture/alacritty" "$fixture/ghostty"

# A failed run reports no side, so nothing is cleared.
[[ -z $(ARCH_UPDATES_TEST_LOG=/dev/null TERMINAL="$fixture/failterm" PATH="$fixture:$PATH" "$script" update 2>/dev/null) ]] ||
  { printf 'FAIL: failed update still reported an updated side\n' >&2; exit 1; }

# yay only: paru on its own is not used as the AUR helper.
mv "$fixture/yay" "$fixture/paru"
run_update_stub
! grep -Fx aur "$fixture/update.log" >/dev/null ||
  { printf 'FAIL: paru was used as the AUR helper\n' >&2; exit 1; }
mv "$fixture/paru" "$fixture/yay"

# Debian: with no AUR helper, apt takes over. This branch never runs on the
# Arch machines, so the stub is the only thing that will catch a typo in it.
rm "$fixture/yay"
run_update_stub
grep -Fx apt "$fixture/update.log" >/dev/null
grep -Fq 'apt) sudo apt update && sudo apt full-upgrade' "$fixture/update.log"

# Fallback managers upgrade repository packages only; never clear AUR counts.
# sudo is a fixture and the whole PATH is isolated from host managers.
printf '#!/bin/sh\n"$@"\n' > "$fixture/sudo"
printf '#!/bin/sh\nexit 0\n' > "$fixture/pacman"
chmod +x "$fixture/sudo" "$fixture/pacman"
scope=$(TERMINAL="$fixture/masking-term" PATH="$fixture" "$script" update 2>/dev/null)
[[ $scope == repo ]]
rm "$fixture/pacman"
scope=$(TERMINAL="$fixture/masking-term" PATH="$fixture" "$script" update 2>/dev/null)
[[ $scope == repo ]]
rm "$fixture/sudo"

# Debian count uses apt's local upgrade listing, not Arch's checkupdates.
rm "$fixture/checkupdates"
ln -s "$(command -v awk)" "$fixture/awk"
printf '#!/bin/sh\nprintf "Listing...\\nalpha/stable 2.0 amd64 [upgradable]\\nbeta/stable 3.0 amd64 [upgradable]\\n"\n' > "$fixture/apt"
output=$(PATH="$fixture" "$script" count)
[[ $output == '{"repo":2,"aur":0,"total":2,"repoPackages":["alpha","beta"],"aurPackages":[]}' ]]

# $TERMINAL is preferred over the built-in candidate list.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/myterm"
chmod +x "$fixture/myterm"
rm -f "$fixture/update.log"
run_update_stub myterm
[[ -s $fixture/update.log ]]
rm "$fixture/myterm"

# No terminal emulator and no package manager are both reported as failures, so
# the widget can surface them instead of looking like a dead button.
mv "$fixture/kitty" "$fixture/kitty.off"
if PATH="$fixture" TERMINAL="" "$script" update 2>/dev/null; then
  printf 'FAIL: missing terminal reported success\n' >&2
  exit 1
fi
mv "$fixture/kitty.off" "$fixture/kitty"

rm "$fixture/apt"
if PATH="$fixture" TERMINAL="" "$script" update 2>/dev/null; then
  printf 'FAIL: missing package manager reported success\n' >&2
  exit 1
fi


# The cache is what stops several callers (the bar, lmenu, a prompt) from each
# querying the AUR. A repeat call inside the TTL must not reach the helper.
cache=$(mktemp -d)
trap 'rm -rf "$fixture" "$cache"' EXIT
calls="$cache/calls"
: > "$calls"
printf '#!/bin/sh\nprintf "checkupdates\\n" >> "%s"\nprintf "core 1 -> 2\\n"\n' "$calls" > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "yay\\n" >> "%s"\nprintf "aur-one 1 -> 2\\n"\n' "$calls" > "$fixture/yay"
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

printf 'arch-updates: ok\n'
