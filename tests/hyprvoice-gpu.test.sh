#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
wrapper_dir=$repo_root/systemd/.local/libexec/hyprvoice-gpu
wrapper=$wrapper_dir/whisper-cli
recorder=$wrapper_dir/pw-record
installer=$repo_root/systemd/.local/bin/hyprvoice-gpu-install
dropin=$repo_root/systemd/.config/systemd/user/hyprvoice.service.d/10-amd-gpu.conf
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for script in "$wrapper" "$recorder" "$installer" "$wrapper_dir/wl-copy" "$wrapper_dir/notify-send"; do
  [[ -x $script ]] || fail "$script is not executable"
  bash -n "$script"
done

gpu_stub=$test_root/gpu-whisper-cli
cat >"$gpu_stub" <<'SH'
#!/usr/bin/env bash
{
  printf 'VK_DRIVER_FILES=%s\nGGML_VK_VISIBLE_DEVICES=%s\nLD_LIBRARY_PATH=%s\n' \
    "${VK_DRIVER_FILES-unset}" "${GGML_VK_VISIBLE_DEVICES-unset}" "${LD_LIBRARY_PATH-unset}"
  printf 'arg=%s\n' "$@"
} >"$STUB_LOG"
if [[ ${GPU_STATUS:-0} != 0 ]]; then
  printf 'gpu partial\n'
  printf 'vulkan exploded\n' >&2
  exit "$GPU_STATUS"
fi
printf 'gpu transcript\n'
SH
cpu_stub=$test_root/cpu/whisper-cli
mkdir -p "$test_root/cpu"
cat >"$cpu_stub" <<'SH'
#!/usr/bin/env bash
printf 'cpu transcript\n'
printf 'arg=%s\n' "$@" >"$STUB_CPU_LOG"
SH
chmod +x "$gpu_stub" "$cpu_stub"

w_prefix=$test_root/w-prefix
w_icd=$test_root/w-icd.json
mkdir -p "$w_prefix/bin" "$w_prefix/lib"
cp "$gpu_stub" "$w_prefix/bin/whisper-cli"
: >"$w_icd"
printf '# note\nvendor=amd\nicd=%s\ndevice=0\n' "$w_icd" >"$w_prefix/device.env"
export STUB_LOG=$test_root/gpu.log STUB_CPU_LOG=$test_root/cpu.log
export HYPRVOICE_GPU_PREFIX=$w_prefix HYPRVOICE_CPU_WHISPER_CLI=$cpu_stub

args=(-m 'model with spaces.bin' -l en -nt -np -f sample.wav -t 4)
printf 'arg=%s\n' "${args[@]}" >"$test_root/expected-args"

reset_logs() { rm -f -- "$STUB_LOG" "$STUB_CPU_LOG"; }
expect_cpu() {
  local label=$1 out
  shift
  reset_logs
  out=$("$@" 2>"$test_root/err") || fail "$label: wrapper failed"
  [[ $out == 'cpu transcript' ]] || fail "$label: expected the CPU transcript, got: $out"
  [[ ! -e $STUB_LOG ]] || fail "$label: the GPU build ran"
  cmp -s "$test_root/expected-args" "$STUB_CPU_LOG" || fail "$label: CPU arguments were changed"
}

reset_logs
out=$(LD_LIBRARY_PATH=/existing/lib "$wrapper" "${args[@]}" 2>/dev/null)
[[ $out == 'gpu transcript' ]] || fail 'GPU transcript was lost'
[[ ! -e $STUB_CPU_LOG ]] || fail 'CPU build ran although the GPU run succeeded'
grep -Fxq "VK_DRIVER_FILES=$w_icd" "$STUB_LOG" || fail 'GPU run did not get the ICD from device.env'
grep -Fxq 'GGML_VK_VISIBLE_DEVICES=0' "$STUB_LOG" || fail 'GPU run did not get the device index'
grep -Fxq "LD_LIBRARY_PATH=$w_prefix/bin/../lib:/existing/lib" "$STUB_LOG" ||
  fail 'GPU libraries were not put first on LD_LIBRARY_PATH'
cmp -s "$test_root/expected-args" <(grep '^arg=' "$STUB_LOG") || fail 'GPU arguments were changed'

reset_logs
out=$(env -u LD_LIBRARY_PATH "$wrapper" "${args[@]}" 2>/dev/null)
grep -Fxq "LD_LIBRARY_PATH=$w_prefix/bin/../lib" "$STUB_LOG" || fail 'LD_LIBRARY_PATH gained an empty entry'

mv "$w_prefix/device.env" "$test_root/device.env.saved"
expect_cpu 'no device.env' "$wrapper" "${args[@]}"
[[ ! -s $test_root/err ]] || fail 'a machine without a GPU setup printed a warning'
cp "$test_root/device.env.saved" "$w_prefix/device.env"

mv "$w_prefix/bin/whisper-cli" "$w_prefix/bin/whisper-cli.saved"
expect_cpu 'missing GPU build' "$wrapper" "${args[@]}"
grep -Fq 'missing' "$test_root/err" || fail 'a missing GPU build was not explained'
mv "$w_prefix/bin/whisper-cli.saved" "$w_prefix/bin/whisper-cli"

mv "$w_icd" "$w_icd.saved"
expect_cpu 'missing ICD' "$wrapper" "${args[@]}"
grep -Fq 'missing' "$test_root/err" || fail 'a missing ICD was not explained'
mv "$w_icd.saved" "$w_icd"

for bad in 'not a pair' 'vendor=amd' "vendor=amd
icd=relative.json
device=0" "vendor=amd
icd=$w_icd
device=zero"; do
  printf '%s\n' "$bad" >"$w_prefix/device.env"
  expect_cpu "malformed device.env ($bad)" "$wrapper" "${args[@]}"
  [[ -s $test_root/err ]] || fail 'a malformed device.env was not explained'
done

# device.env is read as data, never executed.
printf 'vendor=amd\nicd=%s/$(touch %s/pwned)\ndevice=0\nextra=1\n' "$w_icd" "$test_root" >"$w_prefix/device.env"
expect_cpu 'device.env with a command substitution' "$wrapper" "${args[@]}"
[[ ! -e $test_root/pwned ]] || fail 'device.env was executed'
printf '# note\nvendor=amd\nicd=%s\ndevice=0\nunknown=ignored\n' "$w_icd" >"$w_prefix/device.env"
out=$("$wrapper" "${args[@]}" 2>/dev/null)
[[ $out == 'gpu transcript' ]] || fail 'an unknown device.env key broke GPU use'

# A GPU failure falls back to the CPU and only the CPU text is printed.
reset_logs
out=$(GPU_STATUS=3 "$wrapper" "${args[@]}" 2>"$test_root/err") || fail 'GPU failure was not retried on the CPU'
[[ $out == 'cpu transcript' ]] || fail "partial GPU output leaked or CPU text was lost: $out"
cmp -s "$test_root/expected-args" "$STUB_CPU_LOG" || fail 'CPU retry arguments were changed'
grep -Fq 'retrying on the CPU' "$test_root/err" || fail 'GPU failure was not reported'

# Without HYPRVOICE_CPU_WHISPER_CLI the wrapper finds the next whisper-cli on
# PATH and skips itself, even through a symlinked directory like Stow's.
unset HYPRVOICE_CPU_WHISPER_CLI
mkdir -p "$test_root/link" "$test_root/tools"
ln -s "$wrapper" "$test_root/link/whisper-cli"
ln -s "$(command -v readlink)" "$test_root/tools/readlink"
rm -f "$w_prefix/device.env"
reset_logs
out=$(PATH="$test_root/link:$test_root/cpu:/usr/bin" timeout 10 "$test_root/link/whisper-cli" "${args[@]}" 2>/dev/null)
[[ $out == 'cpu transcript' ]] || fail 'the wrapper did not find the CPU build past itself'
cmp -s "$test_root/expected-args" "$STUB_CPU_LOG" || fail 'PATH-found CPU build got other arguments'
status=0
PATH="$test_root/link:$test_root/tools" "$(command -v timeout)" 10 "$BASH" "$test_root/link/whisper-cli" "${args[@]}" \
  >"$test_root/out" 2>"$test_root/err" || status=$?
[[ $status != 0 && ! -s $test_root/out ]] || fail 'a missing CPU build was accepted'
[[ $status == 127 ]] || fail "a missing CPU build exited $status instead of 127"
grep -Fq 'no CPU whisper-cli' "$test_root/err" || fail 'a missing CPU build was not explained'
unset HYPRVOICE_GPU_PREFIX STUB_LOG STUB_CPU_LOG

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

grep -Fxq 'Environment=PATH=%h/.local/libexec/hyprvoice-gpu:%h/.local/bin:/usr/local/bin:/usr/bin' "$dropin" ||
  fail 'Hyprvoice will not find the wrappers'
grep -Fxq '[Service]' "$dropin" || fail 'drop-in has no [Service] section'
! grep -Eq 'VK_DRIVER_FILES|GGML_' "$dropin" || fail 'the shared drop-in pins a GPU'

base_path=$PATH
installer_stub=$test_root/installed-whisper-cli
cat >"$installer_stub" <<'SH'
#!/usr/bin/env bash
printf 'VK_DRIVER_FILES=%s GGML_VK_VISIBLE_DEVICES=%s LD_LIBRARY_PATH=%s\n' \
  "${VK_DRIVER_FILES-unset}" "${GGML_VK_VISIBLE_DEVICES-unset}" "${LD_LIBRARY_PATH-unset}" >>"${STUB_LOG:-/dev/null}"
printf '%s\n' "${STUB_DEVICE_LINE-ggml_vulkan: 0 = AMD Radeon RX 6400 (RADV NAVI24) (radv) | uma: 0 | fp16: 1}" >&2
printf '%s\n' "${STUB_BACKEND_LINE-whisper_backend_init_gpu: using Vulkan0 backend}" >&2
printf '%s\n' "${STUB_TEXT-And so my fellow Americans, ask not what your country can do for you.}"
exit "${STUB_STATUS:-0}"
SH
chmod +x "$installer_stub"

amd_line='ggml_vulkan: 0 = AMD Radeon RX 6400 (RADV NAVI24) (radv) | uma: 0 | fp16: 1'
intel_line='ggml_vulkan: 0 = Intel(R) UHD Graphics 620 (KBL GT2) (Intel open-source Mesa driver) | uma: 1'

# new_machine NAME PCI_ID...: a fake machine with the listed GPUs, every ICD
# file, an installed build, a model, a sample, and a stub toolchain.
new_machine() {
  local name=$1 index=0 id icd
  shift
  m=$test_root/$name
  mkdir -p "$m/icd" "$m/prefix/bin" "$m/prefix/lib" "$m/dropins" "$m/src/samples" "$m/bin"
  for id in "$@"; do
    mkdir -p "$m/sys/class/drm/card$index/device"
    printf '%s\n' "$id" >"$m/sys/class/drm/card$index/device/vendor"
    index=$((index + 1))
  done
  mkdir -p "$m/sys/class/drm/card9-DP-1/device"
  for icd in radeon_icd.json intel_icd.json intel_hasvk_icd.json nvidia_icd.json lvp_icd.json; do
    : >"$m/icd/$icd"
  done
  cp "$installer_stub" "$m/prefix/bin/whisper-cli"
  : >"$m/model.bin"
  : >"$m/src/samples/jfk.wav"
  : >"$m/src/CMakeLists.txt"
  : >"$m/prefix/lib/libold.so"
  export STUB_LOG=$m/stub.log HYPRVOICE_GPU_SYSFS=$m/sys HYPRVOICE_GPU_ICD_DIR=$m/icd \
    HYPRVOICE_GPU_PREFIX=$m/prefix HYPRVOICE_GPU_DROPIN_DIR=$m/dropins \
    HYPRVOICE_GPU_TEST_MODEL=$m/model.bin HYPRVOICE_GPU_TEST_AUDIO=$m/src/samples/jfk.wav \
    WHISPER_SOURCE=$m/src PATH=$m/bin:$base_path
}

inst() { "$installer" "$@"; }

stale_dropin() { printf 'Environment=VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json\n' >"$m/dropins/$1"; }

status=0
"$installer" >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail 'no arguments did not exit 2'
for bad_args in '--bogus' '--install --enable' '--vendor' '--vendor nvidia --enable' '--vendor amd'; do
  status=0
  # shellcheck disable=SC2086
  "$installer" $bad_args >/dev/null 2>&1 || status=$?
  [[ $status == 2 ]] || fail "installer arguments '$bad_args' did not exit 2"
done
"$installer" --help | grep -Fq -- '--enable' || fail 'installer --help does not describe --enable'

# dry-run changes nothing and reports the plan
new_machine dry 0x1002
stale_dropin 10-amd-gpu.conf
printf 'old\n' >"$m/prefix/device.env"
before=$(find "$m" -type f -printf '%p %s %T@\n' | sort)
out=$(inst --dry-run)
after=$(find "$m" -type f -printf '%p %s %T@\n' | sort)
[[ $before == "$after" ]] || fail 'dry-run changed files'
[[ $out == *'Chosen vendor: amd'* && $out == *"Vulkan driver: $m/icd/radeon_icd.json"* ]] ||
  fail "dry-run did not report the GPU: $out"
[[ $out == *"$m/dropins/10-amd-gpu.conf"* ]] || fail 'dry-run did not list the drop-in it would disable'
[[ $out == *"$m/prefix/device.env"* ]] || fail 'dry-run did not name the device file'

# Without small.en, another downloaded Hyprvoice model verifies the build.
mkdir -p "$m/data/hyprvoice/models/whisper"
: >"$m/data/hyprvoice/models/whisper/ggml-base.en.bin"
out=$(env -u HYPRVOICE_GPU_TEST_MODEL XDG_DATA_HOME="$m/data" "$installer" --dry-run)
[[ $out == *"Test model: $m/data/hyprvoice/models/whisper/ggml-base.en.bin"* ]] ||
  fail "a machine without small.en did not fall back to its own model: $out"

# enable: AMD
new_machine amd 0x1002
out=$(inst --enable)
[[ $(<"$m/prefix/device.env") == "$(printf '# Written by hyprvoice-gpu-install after a verified transcription.\nvendor=amd\nicd=%s\ndevice=0' "$m/icd/radeon_icd.json")" ]] ||
  fail "AMD device.env is wrong: $(<"$m/prefix/device.env")"
[[ $out == *"Verified: $amd_line"* ]] || fail 'the verified device line was not printed'
grep -Fxq "VK_DRIVER_FILES=$m/icd/radeon_icd.json GGML_VK_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=$m/prefix/lib" "$STUB_LOG" ||
  fail 'verification did not use the AMD driver and the installed libraries'
ls "$m/prefix"/device.env.* >/dev/null 2>&1 && fail 'a temporary device.env was left behind'

# vendor selection
new_machine intel 0x10de 0x8086
STUB_DEVICE_LINE=$intel_line inst --enable >/dev/null
grep -Fxq 'vendor=intel' "$m/prefix/device.env" && grep -Fxq "icd=$m/icd/intel_icd.json" "$m/prefix/device.env" ||
  fail 'Intel with NVIDIA did not choose Intel and intel_icd.json'
rm "$m/icd/intel_icd.json"
STUB_DEVICE_LINE=$intel_line inst --enable >/dev/null
grep -Fxq "icd=$m/icd/intel_hasvk_icd.json" "$m/prefix/device.env" || fail 'Intel did not fall back to the hasvk driver'

new_machine both 0x8086 0x1002
inst --enable >/dev/null
grep -Fxq 'vendor=amd' "$m/prefix/device.env" || fail 'AMD is not preferred over Intel'
STUB_DEVICE_LINE=$intel_line inst --vendor intel --enable >/dev/null
grep -Fxq 'vendor=intel' "$m/prefix/device.env" && grep -Fxq "icd=$m/icd/intel_icd.json" "$m/prefix/device.env" ||
  fail '--vendor intel was not honoured'

new_machine intel-only 0x8086
printf 'old\n' >"$m/prefix/device.env"
if inst --vendor amd --enable >/dev/null 2>"$test_root/err"; then fail '--vendor amd worked on an Intel-only machine'; fi
[[ ! -e $m/prefix/device.env ]] || fail 'a missing vendor left a stale device.env'
grep -Fq 'CPU' "$test_root/err" || fail 'a missing vendor did not say it uses the CPU'

# NVIDIA only (and an AMD connector entry) is unsupported
new_machine nvidia 0x10de
mkdir -p "$m/sys/class/drm/card0-DP-1/device"
printf '0x1002\n' >"$m/sys/class/drm/card0-DP-1/device/vendor"
printf 'old\n' >"$m/prefix/device.env"
stale_dropin 10-amd-gpu.conf
for mode in --enable --install; do
  printf 'old\n' >"$m/prefix/device.env"
  if inst "$mode" >/dev/null 2>"$test_root/err"; then fail "$mode succeeded on an NVIDIA-only machine"; fi
  [[ ! -e $m/prefix/device.env ]] || fail "$mode left a stale device.env on an NVIDIA-only machine"
done
[[ -e $m/dropins/10-amd-gpu.conf ]] || fail 'an unsupported machine migrated drop-ins'
status=0
inst --dry-run >/dev/null || status=$?
[[ $status == 1 ]] || fail 'dry-run on an NVIDIA-only machine did not exit 1'

# a vendor with no driver file
new_machine no-icd 0x1002
rm "$m/icd/radeon_icd.json"
printf 'old\n' >"$m/prefix/device.env"
if inst --enable >/dev/null 2>&1; then fail 'a missing ICD was accepted'; fi
[[ ! -e $m/prefix/device.env ]] || fail 'a missing ICD left a stale device.env'

# verification failures never write, and --enable disables
verification_failure() {
  local label=$1 assignment=$2
  new_machine "bad-$label" 0x1002
  stale_dropin 10-amd-gpu.conf
  if (export "${assignment?}"; inst --enable >/dev/null 2>&1); then fail "$label: verification passed"; fi
  [[ ! -e $m/prefix/device.env ]] || fail "$label: device.env was written"
  printf 'old\n' >"$m/prefix/device.env"
  (export "${assignment?}"; inst --enable >/dev/null 2>&1) || true
  [[ ! -e $m/prefix/device.env ]] || fail "$label: --enable kept an old device.env"
  [[ -f $m/dropins/10-amd-gpu.conf ]] || fail "$label: a failed verification migrated drop-ins"
}
verification_failure no-vulkan 'STUB_BACKEND_LINE=whisper_backend_init_gpu: no GPU found'
verification_failure llvmpipe 'STUB_DEVICE_LINE=ggml_vulkan: 0 = llvmpipe (LLVM 19.1.7, 256 bits) (llvmpipe) | uma: 0'
verification_failure wrong-vendor "STUB_DEVICE_LINE=$intel_line"
verification_failure no-phrase 'STUB_TEXT=(buzzing)'
verification_failure exit-code 'STUB_STATUS=1'
verification_failure no-device-line 'STUB_DEVICE_LINE='

# a missing build disables
new_machine no-build 0x1002
rm "$m/prefix/bin/whisper-cli"
printf 'old\n' >"$m/prefix/device.env"
if inst --enable >/dev/null 2>&1; then fail 'a missing build was enabled'; fi
[[ ! -e $m/prefix/device.env ]] || fail 'a missing build left a stale device.env'

# migration
new_machine migrate 0x1002
stale_dropin 10-amd-gpu.conf
printf 'Environment=GGML_VK_VISIBLE_DEVICES=0\n' >"$m/dropins/30-device.conf"
printf 'Environment=PATH=%%h/.local/libexec/hyprvoice-gpu:/usr/bin\n' >"$m/dropins/50-path.conf"
printf '[Service]\nEnvironment=FOO=bar\n' >"$m/dropins/20-unrelated.conf"
printf 'Environment=VK_DRIVER_FILES=/x\n' >"$m/linked-target"
ln -s "$m/linked-target" "$m/dropins/40-linked.conf"
stale_dropin 60-taken.conf
printf 'earlier\n' >"$m/dropins/60-taken.conf.disabled"
out=$(inst --enable)
for moved in 10-amd-gpu 30-device 50-path; do
  [[ ! -e $m/dropins/$moved.conf && -f $m/dropins/$moved.conf.disabled ]] || fail "$moved.conf was not disabled"
done
[[ -f $m/dropins/20-unrelated.conf && $(<"$m/dropins/20-unrelated.conf") == *FOO=bar* ]] || fail 'an unrelated drop-in was touched'
[[ -L $m/dropins/40-linked.conf ]] || fail 'a symlinked drop-in was touched'
[[ -f $m/dropins/60-taken.conf && $(<"$m/dropins/60-taken.conf.disabled") == earlier ]] || fail 'an existing .disabled file was overwritten'
[[ $out == *'60-taken.conf'*'already exists'* ]] || fail 'a blocked move was not reported'
[[ $out == *'dots deploy'* ]] || fail 'the 10-amd-gpu.conf relink was not mentioned'
[[ $out == *'systemctl --user daemon-reload'* ]] || fail 'the daemon-reload hint is missing'
listing=$(find "$m/dropins" | sort)
out=$(inst --enable)
[[ $(find "$m/dropins" | sort) == "$listing" ]] || fail 'migration is not idempotent'
[[ $out != *'dots deploy'* && $out != *daemon-reload* ]] || fail 'a rerun repeated the migration hints'

new_machine migrate-other 0x1002
printf 'Environment=GGML_VK_VISIBLE_DEVICES=0\n' >"$m/dropins/30-device.conf"
out=$(inst --enable)
[[ $out == *daemon-reload* && $out != *'dots deploy'* ]] || fail 'the relink hint appeared without 10-amd-gpu.conf'

# install, with stub build tools
install_machine() {
  new_machine "$1" "${@:2}"
  cat >"$m/bin/git" <<'SH'
#!/usr/bin/env bash
[[ $1 == clone ]] && mkdir -p -- "${@: -1}"
exit 0
SH
  cat >"$m/bin/cmake" <<'SH'
#!/usr/bin/env bash
[[ ${STUB_CMAKE_FAIL:-0} == 0 || $1 != --build ]] || exit 1
if [[ $1 == --build ]]; then
  mkdir -p -- "$2/bin"
  cp -- "$STUB_BUILT_CLI" "$2/bin/whisper-cli"
  printf 'built\n' >"$2/bin/libggml-built.so"
fi
SH
  printf '#!/usr/bin/env bash\nexit 0\n' >"$m/bin/c++"
  cp "$m/bin/c++" "$m/bin/glslc"
  chmod +x "$m/bin"/*
  cp "$installer_stub" "$m/built-cli"
  export STUB_BUILT_CLI=$m/built-cli
}

install_machine install 0x1002
stale_dropin 10-amd-gpu.conf
rm "$m/prefix/bin/whisper-cli" "$m/prefix/lib/libold.so"
out=$(inst --install)
cmp -s "$m/built-cli" "$m/prefix/bin/whisper-cli" || fail 'the verified build was not installed'
[[ -f $m/prefix/lib/libggml-built.so ]] || fail 'the build libraries were not installed'
grep -Fxq 'vendor=amd' "$m/prefix/device.env" || fail '--install did not write device.env'
[[ -f $m/dropins/10-amd-gpu.conf.disabled ]] || fail '--install did not migrate drop-ins'
staged_lib=$(sed -n 's/.* LD_LIBRARY_PATH=//p' "$STUB_LOG" | head -n1)
[[ $staged_lib == */stage/lib && $staged_lib != "$m/prefix/lib" ]] || fail 'the staged build was not verified before it was installed'
grep -Fq "VK_DRIVER_FILES=$m/icd/radeon_icd.json GGML_VK_VISIBLE_DEVICES=0 " "$STUB_LOG" ||
  fail 'staged verification did not use the AMD driver'

for failure in STUB_STATUS=1 STUB_CMAKE_FAIL=1 'STUB_BACKEND_LINE=whisper_backend_init_gpu: no GPU found'; do
  install_machine "install-fail-${failure%%=*}-$RANDOM" 0x1002
  stale_dropin 10-amd-gpu.conf
  printf 'previous build\n' >"$m/prefix/bin/whisper-cli"
  chmod +x "$m/prefix/bin/whisper-cli"
  printf 'previous device\n' >"$m/prefix/device.env"
  if (export "${failure?}"; inst --install >/dev/null 2>&1); then
    fail "--install succeeded with $failure"
  fi
  [[ $(<"$m/prefix/bin/whisper-cli") == 'previous build' ]] || fail "--install replaced the build despite $failure"
  [[ $(<"$m/prefix/device.env") == 'previous device' ]] || fail "--install changed device.env despite $failure"
  [[ -f $m/prefix/lib/libold.so && ! -e $m/prefix/lib/libggml-built.so ]] || fail "--install changed libraries despite $failure"
  [[ -f $m/dropins/10-amd-gpu.conf ]] || fail "--install migrated drop-ins despite $failure"
done

printf 'Hyprvoice GPU fixtures passed\n'
