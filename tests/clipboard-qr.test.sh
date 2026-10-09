#!/usr/bin/env bash
# Fixture test for the clipboard -> QR overlay.
#
# The generation step is a small `sh` script that lives inside
# ClipboardQrState.qml, so the test lifts it back out and runs it against fake
# wl-paste/qrencode binaries rather than re-implementing it here.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state="$repo_root/quickshell/.config/quickshell/ClipboardQrState.qml"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
test_root=$(mktemp -d -t clipboard-qr-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$test_root/bin" "$test_root/runtime"

# The generator script, extracted from the QML array it is declared as.
python3 - "$state" >"$test_root/generate.sh" <<'PY' || fail 'could not extract the generator script from ClipboardQrState.qml'
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text()
block = re.search(r'property string script: \[(.*?)\]\.join\("; "\)', src, re.S)
if not block:
    sys.exit('ClipboardQrState.qml no longer declares its script as a joined array')
lines = re.findall(r"'((?:[^'\\]|\\.)*)'", block.group(1))
if len(lines) < 4:
    sys.exit('the generator script lost its steps')
print("; ".join(lines))
PY

# Fakes: wl-paste publishes $CLIPBOARD (empty means nothing suitable to paste,
# which is what wl-paste does for an image-only or empty clipboard), and
# qrencode copies its input file to its output so the payload stays checkable.
cat >"$test_root/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WL_PASTE_CALLS"
if [[ -z ${CLIPBOARD:-} ]]; then
  printf 'No suitable type of content copied\n' >&2
  exit 1
fi
printf '%s' "$CLIPBOARD"
SH
cat >"$test_root/bin/qrencode" <<'SH'
#!/usr/bin/env bash
if [[ ${QRENCODE_FAIL:-} == 1 ]]; then
  printf 'Failed to encode the input data: Input data too large\n' >&2
  exit 1
fi
while (($#)); do
  case $1 in
    -o) output=$2; shift 2 ;;
    -r) input=$2; shift 2 ;;
    *) shift ;;
  esac
done
cat "$input" >"$output"
SH
chmod +x "$test_root/bin/wl-paste" "$test_root/bin/qrencode"

out="$test_root/runtime/clipboard-qr.svg"
export WL_PASTE_CALLS="$test_root/wl-paste.calls"

# generate <clipboard-contents> [qrencode-fails]
# `sh script arg` puts arg in $1 (there is no -c style $0 slot here), so the
# output path is the one and only parameter the generator sees.
generate() {
  CLIPBOARD=$1 QRENCODE_FAIL=${2:-0} PATH="$test_root/bin:$PATH" \
    sh "$test_root/generate.sh" "$out"
}

# Text on the clipboard is encoded to the runtime path, owner-readable only,
# and the scratch file it went through is cleaned up.
: >"$WL_PASTE_CALLS"
generate 'https://example.com/a?b=c&d=e' >"$test_root/ok.out" 2>"$test_root/ok.err" \
  || fail 'a text clipboard did not produce a QR code'
[[ -s $out ]] || fail 'no QR code was written to the runtime path'
[[ $(cat "$out") == 'https://example.com/a?b=c&d=e' ]] || fail 'the QR payload is not the clipboard content'
[[ $(stat -c '%a' "$out") == 600 ]] || fail 'the QR SVG is not owner-readable only'
[[ -e $out.txt ]] && fail 'the clipboard scratch file was left behind'
grep -Fq -- '--type text' "$WL_PASTE_CALLS" || fail 'the clipboard is not read as text'
grep -Fq -- '--no-newline' "$WL_PASTE_CALLS" || fail 'a trailing newline is encoded into the QR payload'

# Multi-line content survives the round trip rather than being truncated at the
# first line.
generate $'line one\nline two' >/dev/null 2>&1 \
  || fail 'a multi-line clipboard did not produce a QR code'
[[ $(cat "$out") == $'line one\nline two' ]] || fail 'multi-line clipboard content was truncated'

# An empty (or image-only) clipboard fails with an actionable sentence, and the
# previous run's code is gone rather than being shown again as if it were new.
if generate '' >"$test_root/empty.out" 2>"$test_root/empty.err"; then
  fail 'an empty clipboard was encoded anyway'
fi
grep -Fq 'There is no text on the clipboard' "$test_root/empty.err" \
  || fail 'an empty clipboard gave no actionable error'
[[ -e $out ]] && fail 'a failed run left the previous QR code on disk'
[[ -e $out.txt ]] && fail 'a failed run left the clipboard scratch file behind'

# qrencode refusing the content (too large, most likely) surfaces its own
# diagnostic and leaves nothing behind either.
if generate 'too much' 1 >"$test_root/big.out" 2>"$test_root/big.err"; then
  fail 'a qrencode failure was reported as success'
fi
grep -Fq 'Input data too large' "$test_root/big.err" || fail 'the qrencode diagnostic was swallowed'
[[ -e $out ]] && fail 'a failed encode left a partial QR code on disk'
[[ -e $out.txt ]] && fail 'a failed encode left the clipboard scratch file behind'

# Kept as a text check to stop clipboard data loss: the QR must go on screen,
# never back onto the clipboard. That was the bug in the row this replaces,
# which overwrote the content it had just encoded.
! grep -Fq 'wl-copy' "$state" || fail 'the clipboard QR writes back to the clipboard'
! grep -Fq 'qrencode -o - -t PNG' "$menu" \
  || fail 'the lmenu QR row still copies the code to the clipboard'

# Kept as a text check for privacy: the clipboard may hold a secret, so its QR
# must live on the per-user runtime tmpfs, never on persistent disk.
grep -Fq 'Quickshell.env("XDG_RUNTIME_DIR")' "$state" || fail 'the QR is not written to the runtime directory'

printf 'ok: clipboard-qr fixtures\n'
