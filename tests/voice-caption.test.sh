#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if grep -nE '#[0-9a-fA-F]{3,8}\b' "$shell_dir"/VoiceCaption*.qml; then
  fail 'caption QML contains a hardcoded color'
fi

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/voice-caption.logic.test.js" "$shell_dir/voicecaption/VoiceCaptionLogic.js"
else
  printf 'skip: node not installed, VoiceCaptionLogic.js not run\n'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  mkdir -p "$test_root/state"
  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root" \
    QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$shell_dir/VoiceCaptionSmoke.qml" >"$smoke_log" 2>&1 || true
  grep -Fq 'voice caption smoke done: 0 failures' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'VoiceCaptionSmoke.qml did not finish cleanly'; }
  if grep -q 'FAIL ' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'VoiceCaptionSmoke.qml reported a failing assertion'
  fi
  printf 'ok: VoiceCaptionSmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell not installed, VoiceCaptionSmoke.qml not run\n'
fi

printf 'voice-caption: ok\n'
