#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backend="$repo_root/hypr/.config/hypr/scripts/bluetooth-control"
test_root=$(mktemp -d -t bluetooth-control-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

mkdir -p "$test_root/bin"
cat > "$test_root/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BLUETOOTH_CALLS"
case "$*" in
  show)
    if [[ "${BLUETOOTH_FIXTURE_MODE:-}" == no-controller ]]; then
      printf '%s\n' 'No default controller available'
      exit 0
    fi
    printf '%s\n' \
      'Controller AA:BB:CC:DD:EE:FF workstation [default]' \
      '        Powered: yes' \
      '        Discovering: no'
    ;;
  devices)
    printf '%s\n' \
      'Device 11:22:33:44:55:66 Quiet Headphones' \
      'Device AA:00:BB:11:CC:22 Pocket Keyboard'
    ;;
  'devices Paired')
    printf '%s\n' 'Device 11:22:33:44:55:66 Quiet Headphones'
    ;;
  'devices Connected')
    printf '%s\n' 'Device 11:22:33:44:55:66 Quiet Headphones'
    ;;
  paired-devices)
    printf '%s\n' 'Device 11:22:33:44:55:66 Quiet Headphones'
    ;;
  *) printf 'ok\n' ;;
esac
SH
chmod +x "$test_root/bin/bluetoothctl"
export BLUETOOTH_CALLS="$test_root/calls"

status=$(PATH="$test_root/bin:$PATH" "$backend" status)
jq -e '
  .available and .powered and (.scanning | not) and
  (.devices | length == 2) and
  (.devices[0].name == "Quiet Headphones") and
  .devices[0].paired and .devices[0].connected and
  (.devices[1].paired | not) and (.devices[1].connected | not)
' <<< "$status" >/dev/null || fail 'status JSON did not describe fixture devices'

unavailable=$(BLUETOOTH_FIXTURE_MODE=no-controller PATH="$test_root/bin:$PATH" "$backend" status)
jq -e '
  (.available | not) and (.powered | not) and
  (.devices | length == 0) and (.error == "No Bluetooth controller available")
' <<< "$unavailable" >/dev/null || fail 'missing controller was not reported safely'

PATH="$test_root/bin:$PATH" "$backend" power off >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'power off'

PATH="$test_root/bin:$PATH" "$backend" connect aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'connect AA:00:BB:11:CC:22'

PATH="$test_root/bin:$PATH" "$backend" pair aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" '--agent NoInputNoOutput --timeout 45 pair AA:00:BB:11:CC:22'
assert_contains "$BLUETOOTH_CALLS" 'trust AA:00:BB:11:CC:22'

PATH="$test_root/bin:$PATH" "$backend" scan 8 >/dev/null
assert_contains "$BLUETOOTH_CALLS" '--timeout 8 scan on'

before=$(wc -l < "$BLUETOOTH_CALLS")
set +e
PATH="$test_root/bin:$PATH" "$backend" disconnect 'not-an-address' >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" -eq 2 ]] || fail 'invalid address did not return status 2'
after=$(wc -l < "$BLUETOOTH_CALLS")
[[ "$before" -eq "$after" ]] || fail 'invalid address reached bluetoothctl'

printf 'ok: bluetooth-control fixtures\n'
