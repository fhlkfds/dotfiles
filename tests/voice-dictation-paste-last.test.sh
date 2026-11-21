#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=${VOICE_DICTATION_SCRIPT:-"$repo_root/hypr/.config/hypr/scripts/voice-dictation"}
test_root=$(mktemp -d -t voice-dictation-paste-last-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$test_root/bin" "$test_root/tmp"
cat >"$test_root/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
printf 'wl-paste %s\n' "$*" >>"$CALLS"
[[ ${CLIP_HANG:-} != "$1" ]] || exec sleep 5
if [[ $1 == --list-types ]]; then
  [[ -n ${CLIP_TYPES:-} ]] || { printf 'Nothing is copied\n' >&2; exit 1; }
  printf '%s\n' "$CLIP_TYPES"
else
  stat -L -c %a "/proc/$$/fd/1" >"$SNAPSHOT_MODE"
  cat "$CLIP_BYTES"
fi
SH
cat >"$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
[[ -z ${WL_COPY_SERVES:-} ]] || { sleep 3 & }
if [[ $1 == --clear ]]; then
  printf 'wl-copy --clear\n' >>"$CALLS"
else
  copy="$COPIES/copy.$(grep -c '^wl-copy --type' "$CALLS")"
  cat >"$copy"
  printf 'wl-copy %s < %s\n' "$*" "${copy##*/}" >>"$CALLS"
fi
SH
cat >"$test_root/bin/paste" <<'SH'
#!/usr/bin/env bash
printf 'paste %s\n' "$*" >>"$CALLS"
SH
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >>"$CALLS"
SH
chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp"
export CALLS="$test_root/calls" COPIES="$test_root" SNAPSHOT_MODE="$test_root/snapshot-mode"
export CLIP_BYTES="$test_root/clipboard" VOICE_DICTATION_LAST="$test_root/state/last.txt"
export VOICE_DICTATION_PASTE=paste VOICE_DICTATION_RESTORE_DELAY=0
export VOICE_DICTATION_TARGET="$test_root/target"
mkdir -p "$test_root/state"
printf 'the last dictation, with "quotes" and no newline' >"$VOICE_DICTATION_LAST"

paste_last() {
  : >"$CALLS"
  rm -f -- "$test_root"/copy.*
  "$script" paste-last "$@"
}
expect_calls() {
  [[ $(<"$CALLS") == "$1" ]] || { cat "$CALLS" >&2; fail "$2"; }
}

printf 'old clipboard text' >"$CLIP_BYTES"
CLIP_TYPES=$'text/html\ntext/plain\ntext/plain;charset=utf-8' paste_last
expect_calls 'wl-paste --list-types
wl-paste --no-newline --type text/plain;charset=utf-8
wl-copy --type text/plain;charset=utf-8 < copy.0
paste paste
wl-copy --type text/plain;charset=utf-8 < copy.1' 'text clipboard was not lent and restored in order'
cmp -s "$test_root/copy.0" "$VOICE_DICTATION_LAST" || fail 'pasted text is not the saved dictation'
cmp -s "$test_root/copy.1" "$CLIP_BYTES" || fail 'restored text differs from the saved clipboard'
[[ $(<"$SNAPSHOT_MODE") == 600 ]] || fail 'clipboard snapshot is not private'
[[ -z $(ls -A "$TMPDIR") ]] || fail 'clipboard snapshot outlived paste-last'

printf '\x89PNG\r\n\x1a\n\x00\xff binary' >"$CLIP_BYTES"
CLIP_TYPES=$'image/jpeg\nimage/png' paste_last
expect_calls 'wl-paste --list-types
wl-paste --no-newline --type image/png
wl-copy --type text/plain;charset=utf-8 < copy.0
paste paste
wl-copy --type image/png < copy.1' 'image clipboard was not restored as PNG'
cmp -s "$test_root/copy.1" "$CLIP_BYTES" || fail 'restored image bytes differ'

CLIP_TYPES=$'application/x-custom\ntext/html' paste_last
[[ $(tail -n1 "$CALLS") == 'wl-copy --type application/x-custom < copy.1' ]] || fail 'first listed type was not restored'
CLIP_TYPES=$'TEXT\nUTF8_STRING' paste_last
[[ $(tail -n1 "$CALLS") == 'wl-copy --type UTF8_STRING < copy.1' ]] || fail 'UTF8_STRING was not preferred'

paste_last
expect_calls 'wl-paste --list-types
wl-copy --type text/plain;charset=utf-8 < copy.0
paste paste
wl-copy --clear' 'empty clipboard was not cleared after pasting'

for marker in x-kde-passwordmanagerhint application/x-KeePassXC; do
  CLIP_TYPES=$'text/plain\n'"$marker" paste_last
  expect_calls 'wl-paste --list-types
wl-copy --type text/plain;charset=utf-8 < copy.0
paste paste' "password clipboard ($marker) was restored"
done

printf 'old clipboard text' >"$CLIP_BYTES"
VOICE_DICTATION_PASTE=false CLIP_TYPES=text/plain paste_last && fail 'failed paste reported success'
[[ $(tail -n1 "$CALLS") == 'wl-copy --type text/plain < copy.1' ]] || fail 'failed paste left the dictation on the clipboard'

for hang in --list-types --no-newline; do
  CLIP_HANG=$hang CLIP_TYPES=text/plain paste_last && fail "unanswered clipboard ($hang) reported success"
  ! grep -Eq '^(wl-copy|paste)' "$CALLS" || { cat "$CALLS" >&2; fail "unanswered clipboard ($hang) was replaced"; }
  grep -Fq 'nothing was pasted' "$CALLS" || fail "unanswered clipboard ($hang) gave no notification"
done

: >"$CALLS"
exec 7>"$VOICE_DICTATION_TARGET.paste.lock"
flock 7
CLIP_TYPES=text/plain "$script" paste-last
[[ ! -s $CALLS ]] || { cat "$CALLS" >&2; fail 'a second paste-last ran while the first held the clipboard'; }
exec 7>&-

WL_COPY_SERVES=1 CLIP_TYPES=text/plain paste_last
: >"$CALLS"
WL_COPY_SERVES=1 CLIP_TYPES=text/plain "$script" paste-last
grep -q '^paste paste$' "$CALLS" || fail 'a finished paste-last kept the lock through the clipboard server'

CLIP_TYPES=text/plain paste_last --dry-run >"$test_root/dry-run"
[[ $(<"$test_root/dry-run") == "copy=$VOICE_DICTATION_LAST
paste=paste paste
wait=0
restore=copy text/plain" ]] || { cat "$test_root/dry-run" >&2; fail 'dry-run does not describe each action'; }
! grep -Eq '^(wl-copy|paste)|--no-newline' "$CALLS" || fail 'dry-run read, changed, or pasted the clipboard'

rm -- "$VOICE_DICTATION_LAST"
paste_last
expect_calls 'notify-send -a Voice dictation -r 9931 -t 2500 Voice dictation No dictation saved yet' \
  'missing dictation did not notify, or touched the clipboard'
[[ $(paste_last --dry-run) == 'notification=No dictation saved yet' ]] || fail 'dry-run hides the missing dictation'

bad_args() {
  local status=0
  "$script" paste-last "$@" 2>/dev/null || status=$?
  [[ $status == 2 ]] || fail "paste-last $* exited $status, not 2"
}
bad_args --bogus
bad_args --dry-run extra

grep -Fq 'paste-last [--dry-run]' <("$script" 2>&1 || true) || fail 'usage omits paste-last'

printf 'voice dictation paste-last: ok\n'
