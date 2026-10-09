#!/usr/bin/env bash
# Exercise the LibrePods fallback without a real D-Bus or Bluetooth connection.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backend="$repo_root/hypr/.config/hypr/scripts/bluetooth-control"
test_root=$(mktemp -d -t librepods-battery-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
command -v jq >/dev/null || { printf 'skip: jq not installed\n'; exit 0; }
mkdir -p "$test_root/bin"
export XDG_CACHE_HOME="$test_root/cache" LIBREPODS_CALLS="$test_root/calls"
cat > "$test_root/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  show) printf 'Controller AA:BB:CC:DD:EE:FF\n Powered: yes\n Discovering: no\n' ;;
  devices|'devices Paired'|'devices Trusted'|'devices Connected')
    if [[ "$*" != 'devices Connected' || "$MODE" != disconnected ]]; then
      printf 'Device 11:22:33:44:55:66 Renamed earbuds\n'
    fi
    printf 'Device AA:00:BB:11:CC:22 Another headset\n'
    ;;
  'info 11:22:33:44:55:66'|'info AA:00:BB:11:CC:22')
    printf ' Icon: audio-headphones\n Trusted: yes\n'
    if [[ "$*" == *11:22:33:44:55:66 || "$MODE" == ambiguous ]]; then
      printf ' Modalias: bluetooth:v004Cp2027d215C\n UUID: Vendor specific (74ec2172-0bad-4d01-8f77-997b2be0722a)\n'
    fi
    [[ "$MODE" != native ]] || printf ' Battery Percentage: 0x57 (87)\n'
    ;;
esac
exit 0
SH
cat > "$test_root/bin/upower" <<'SH'
#!/usr/bin/env bash
[[ "$MODE" == upower ]] || exit 0
case "$1" in
  -e) printf '/org/freedesktop/UPower/devices/airpods\n' ;;
  -i) printf ' serial: 11:22:33:44:55:66\n percentage: 64%%\n' ;;
esac
SH
cat > "$test_root/bin/busctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LIBREPODS_CALLS"
[[ "$MODE" != unavailable ]] || exit 1
if [[ "$*" == *' list' ]]; then
  [[ "$MODE" != closed ]] || { printf '[]\n'; exit 0; }
  printf '[{"name":":1.50","process":"librepods","pid":123},{"name":":1.51","process":"librepods","pid":%s}]\n' \
    "$([[ "$MODE" == multiple-apps ]] && printf 456 || printf 123)"
else
  [[ "$*" != *':1.50 '* ]] || exit 1
  [[ "$MODE" != vanished ]] || exit 1
  case "$MODE" in
    malformed) printf '{broken\n' ;;
    invalid) printf '{"type":"(sa(iiay)ss)","data":["",[],"Battery Status: Left: 101%%, Right: 42%%, Case: 0%%",""]}\n' ;;
    zero) printf '{"type":"(sa(iiay)ss)","data":["",[],"Battery Status: Left: 0%%, Right: 0%%, Case: 0%%",""]}\n' ;;
    *) printf '{"type":"(sa(iiay)ss)","data":["",[],"Battery Status: Left: 0%%, Right: 42%%, Case: 0%%",""]}\n' ;;
  esac
fi
SH
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
export MODE=working
: > "$LIBREPODS_CALLS"
result=$("$backend" status)
jq -e '.devices[0].battery == 42 and .devices[0].batteryLabel == "L 0% · R 42% · Case 0%"
  and .devices[1].battery == null and .devices[1].batteryLabel == ""' <<< "$result" >/dev/null \
  || fail 'renamed AirPods did not receive the three readings exclusively'
[[ $(wc -l < "$LIBREPODS_CALLS") == 3 ]] || fail 'D-Bus discovery was repeated'
for MODE in closed unavailable vanished malformed invalid multiple-apps ambiguous; do
  export MODE
  result=$("$backend" status)
  jq -e 'all(.devices[]; .battery == null and .batteryLabel == "")' <<< "$result" >/dev/null \
    || fail "$MODE retained or misassigned a LibrePods reading"
done
export MODE=disconnected
: > "$LIBREPODS_CALLS"
"$backend" status >/dev/null
[[ ! -s "$LIBREPODS_CALLS" ]] || fail 'disconnected AirPods queried LibrePods'
for MODE in native upower; do
  export MODE
  : > "$LIBREPODS_CALLS"
  result=$("$backend" status)
  expected=87; [[ "$MODE" != upower ]] || expected=64
  jq -e --argjson expected "$expected" '.devices[0].battery == $expected and .devices[0].batteryLabel == ""' \
    <<< "$result" >/dev/null || fail "$MODE battery was overridden"
  [[ ! -s "$LIBREPODS_CALLS" ]] || fail "$MODE unnecessarily queried LibrePods"
done
export MODE=zero
result=$("$backend" status)
jq -e '.devices[0].battery == 0 and .devices[0].batteryLabel == "L 0% · R 0% · Case 0%"' \
  <<< "$result" >/dev/null || fail 'zero readings were discarded'
export MODE=working
result=$(BLUETOOTH_CONTROL_BUSCTL="$test_root/missing-busctl" "$backend" status)
jq -e '.devices[0].battery == null and .devices[0].batteryLabel == ""' <<< "$result" >/dev/null \
  || fail 'missing optional busctl was not handled'
printf 'ok: LibrePods battery fixtures\n'
