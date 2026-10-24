#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
wrapper=$repo_root/systemd/.local/libexec/hyprvoice-gpu/whisper-cli
recorder=$repo_root/systemd/.local/libexec/hyprvoice-gpu/pw-record
installer=$repo_root/systemd/.local/bin/hyprvoice-gpu-install
dropin=$repo_root/systemd/.config/systemd/user/hyprvoice.service.d/10-amd-gpu.conf
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf '%s\n' "$*" >&2; exit 1; }

cat >"$test_root/whisper-cli" <<'SH'
#!/usr/bin/env bash
printf 'sample transcription\n'
[[ -z ${CLI_ARGS_LOG:-} ]] || printf '%s\n' "$@" >"$CLI_ARGS_LOG"
quiet=0
for arg in "$@"; do
  case $arg in -np|--no-prints) quiet=1 ;; esac
done
if [[ $quiet == 0 ]]; then
  printf '%s\n' "${BACKEND_LOG:-whisper_backend_init_gpu: using Vulkan0 backend}" >&2
fi
exit "${CLI_STATUS:-0}"
SH
chmod +x "$test_root/whisper-cli"

result=$(HYPRVOICE_GPU_WHISPER_CLI="$test_root/whisper-cli" "$wrapper" -f sample.wav)
[[ $result == 'sample transcription' ]] || fail 'Vulkan transcription was lost'

for quiet_flag in -np --no-prints; do
  result=$(CLI_ARGS_LOG="$test_root/args" HYPRVOICE_GPU_WHISPER_CLI="$test_root/whisper-cli" \
    "$wrapper" -m 'model with spaces.bin' "$quiet_flag" -f sample.wav -nt) \
    || fail "Hyprvoice quiet mode was rejected: $quiet_flag"
  [[ $result == 'sample transcription' ]] || fail 'Quiet mode lost the transcript'
  printf '%s\n' -m 'model with spaces.bin' -f sample.wav -nt >"$test_root/expected-args"
  cmp -s "$test_root/expected-args" "$test_root/args" || fail 'Whisper arguments were changed'
  if BACKEND_LOG='whisper_backend_init_gpu: no GPU found' \
    HYPRVOICE_GPU_WHISPER_CLI="$test_root/whisper-cli" "$wrapper" "$quiet_flag" \
    >"$test_root/out" 2>"$test_root/err"; then
    fail 'Quiet mode accepted CPU fallback'
  fi
  [[ ! -s $test_root/out ]] || fail 'Quiet mode leaked a CPU transcript'
done

if BACKEND_LOG='whisper_backend_init_gpu: no GPU found' \
  HYPRVOICE_GPU_WHISPER_CLI="$test_root/whisper-cli" "$wrapper" -f sample.wav \
  >"$test_root/out" 2>"$test_root/err"; then
  fail 'CPU fallback was accepted'
fi
[[ ! -s $test_root/out ]] || fail 'CPU fallback leaked a transcript'
grep -Fq 'did not use Vulkan' "$test_root/err" || fail 'CPU fallback was not reported'

if CLI_STATUS=1 HYPRVOICE_GPU_WHISPER_CLI="$test_root/whisper-cli" \
  "$wrapper" -f sample.wav >"$test_root/out" 2>"$test_root/err"; then
  fail 'Whisper command failure was accepted'
fi
[[ ! -s $test_root/out ]] || fail 'Failed Whisper command leaked a transcript'

if HYPRVOICE_GPU_WHISPER_CLI="$test_root/missing" "$wrapper" -f sample.wav \
  >"$test_root/out" 2>"$test_root/err"; then
  fail 'Missing Vulkan build was accepted'
fi

cat >"$test_root/pw-record" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CLI_ARGS_LOG"
SH
chmod +x "$test_root/pw-record"

CLI_ARGS_LOG="$test_root/args" HYPRVOICE_PW_RECORD="$test_root/pw-record" \
  "$recorder" --format s16 --rate 16000 --channels 1 - --target 'mic with spaces'
printf '%s\n' --raw --format s16 --rate 16000 --channels 1 - --target 'mic with spaces' >"$test_root/expected-args"
cmp -s "$test_root/expected-args" "$test_root/args" || fail 'Stdout recording is not raw PCM'

CLI_ARGS_LOG="$test_root/args" HYPRVOICE_PW_RECORD="$test_root/pw-record" \
  "$recorder" --target mic out.wav
printf '%s\n' --target mic out.wav >"$test_root/expected-args"
cmp -s "$test_root/expected-args" "$test_root/args" || fail 'File recording arguments were changed'

grep -Fq 'Environment=VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json' "$dropin" || fail 'AMD driver is not pinned'
grep -Fq 'Environment=GGML_VK_VISIBLE_DEVICES=0' "$dropin" || fail 'AMD device is not selected'
grep -Fq '.local/libexec/hyprvoice-gpu:' "$dropin" || fail 'Hyprvoice will not find the GPU wrapper'

dry_run=$(WHISPER_SOURCE="$test_root/nonexistent" "$installer" --dry-run)
[[ $dry_run == *'Whisper source: '* ]] || fail 'Installer dry-run is unavailable'
[[ ! -e $test_root/nonexistent ]] || fail 'Installer dry-run changed the source'

printf 'Hyprvoice GPU fixtures passed\n'
