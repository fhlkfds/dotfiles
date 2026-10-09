#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readme="$repo_root/README.md"
install_ttfx="$repo_root/screensaver/.local/bin/install-ttfx"
test_root=$(mktemp -d -t pinned-sources-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Join shell line continuations so direct execution cannot evade the scan by
# putting the pipe or process substitution on the following physical line.
scan_input="$test_root/docs.logical-lines"
sed ':join; /\\$/ { N; s/\\\n/ /; b join; }' "$readme" >"$scan_input"

# Reject downloader output piped to a shell, including path-qualified shells
# and sudo with flags. The wget alternatives cover its common stdout forms.
pipe_exec_pattern='(curl[^|]*|wget[^|]*(-qO-|-O[[:space:]]+-|--output-document(=|[[:space:]]+)-)[^|]*)\|[[:space:]]*(sudo[[:space:]]+[^|]*)?([^|[:space:]]*/)?(ba|z|da)?sh([[:space:]]|$)'
# Reject shells (or eval) executing downloader output via command substitution.
command_substitution_exec_pattern='(([^[:space:]]*/)?(ba|z|da)?sh[[:space:]]+-c|eval)[[:space:]]+"?\$\([[:space:]]*(curl|wget)[^)]*\)'
# Reject source/dot and shell-stdin execution via process substitution.
process_substitution_exec_pattern='((source|\.)[[:space:]]+|([^[:space:]]*/)?(ba|z|da)?sh[[:space:]]*(<[[:space:]]*)?)<\([[:space:]]*(curl|wget)[^)]*\)'
direct_exec_pattern="$pipe_exec_pattern|$command_substitution_exec_pattern|$process_substitution_exec_pattern"
printf '%s\n' 'bash <(curl -fsSL https://example.com/x)' |
  grep -Eq -- "$direct_exec_pattern" ||
  fail 'source scan missed bash process substitution without a stdin redirect'
if grep -Eq -- "$direct_exec_pattern" "$scan_input"; then
  fail 'documentation still executes curl output directly in a shell'
else
  grep_status=$?
  ((grep_status == 1)) || fail "documentation source scan failed with grep status $grep_status"
fi

grep -Eq -- '--git https://github\.com/omacom-io/ttfx --rev "\$TTFX_PIN"' \
  "$install_ttfx" || fail 'install-ttfx does not pass TTFX_PIN with --rev'
grep -Eq 'TTFX_PIN=.*REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA' \
  "$install_ttfx" || \
  fail 'install-ttfx is missing the TTFX_PIN variable'
grep -Fq '[[ $TTFX_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$install_ttfx" || \
  fail 'install-ttfx does not require a full commit SHA'

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/rust-target"
ln -s "$(command -v bash)" "$test_root/bin/bash"
for command_name in cargo musl-gcc; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/$command_name"
  chmod +x "$test_root/bin/$command_name"
done
for command_name in paru yay; do
  printf '#!/usr/bin/env bash\nexit 1\n' >"$test_root/bin/$command_name"
  chmod +x "$test_root/bin/$command_name"
done
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$RUST_TARGET_FIXTURE"\n' \
  >"$test_root/bin/rustc"
chmod +x "$test_root/bin/rustc"

fixture_env=(
  "HOME=$test_root/home"
  "PATH=$test_root/bin"
  "RUST_TARGET_FIXTURE=$test_root/rust-target"
)
if env -u TTFX_PIN "${fixture_env[@]}" "$install_ttfx" --dry-run \
    >"$test_root/missing-pin.out" 2>&1; then
  fail 'install-ttfx accepted its placeholder source pin'
fi

pin=0123456789abcdef0123456789abcdef01234567
env "${fixture_env[@]}" TTFX_PIN=$pin "$install_ttfx" --dry-run \
  >"$test_root/pinned.out"
grep -Fq -- "--git https://github.com/omacom-io/ttfx --rev $pin ttfx" \
  "$test_root/pinned.out" || fail 'install-ttfx dry-run omitted the pinned revision'

printf 'pinned source checks passed\n'
