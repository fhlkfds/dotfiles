#!/usr/bin/env bash
# Exercises the socket2 listener against a fake Hyprland event socket: event
# filtering, burst debouncing, and clean exit when the compositor goes away.
set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
watcher="$repo_root/hypr/.config/hypr/scripts/hypr-monitor-watch.py"
[[ -x "$watcher" ]] || fail "watcher not executable: $watcher"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

signature=test-instance
mkdir -p "$test_root/hypr/$signature"
sock="$test_root/hypr/$signature/.socket2.sock"
calls="$test_root/applier.calls"

cat >"$test_root/applier.sh" <<SH
#!/usr/bin/env bash
printf 'run\n' >>"$calls"
SH
chmod +x "$test_root/applier.sh"

# Fake Hyprland: accept one client, emit a burst of events, then a tail of
# unrelated ones, then close.
python3 - "$sock" <<'PY' &
import socket, sys, time
path = sys.argv[1]
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path); srv.listen(1)
conn, _ = srv.accept()
time.sleep(0.6)
# a KVM switch produces several events in quick succession
for _ in range(5):
    conn.sendall(b"monitorremoved>>DP-6\n")
    time.sleep(0.05)
for _ in range(5):
    conn.sendall(b"monitoraddedv2>>3,DP-6,Dell Inc. DELL P2722H CTCS1M3\n")
    time.sleep(0.05)
time.sleep(1.5)
# events the watcher must ignore
for _ in range(20):
    conn.sendall(b"workspace>>2\n")
    conn.sendall(b"activewindow>>kitty,shell\n")
time.sleep(1.0)
conn.close(); srv.close()
PY
server_pid=$!
sleep 0.5

set +e
XDG_RUNTIME_DIR="$test_root" \
HYPRLAND_INSTANCE_SIGNATURE="$signature" \
HYPR_APPLIER="$test_root/applier.sh" \
HYPR_WATCH_DEBOUNCE=0.4 \
  timeout 20 "$watcher" >"$test_root/watch.out" 2>&1
watch_rc=$?
set -e
wait "$server_pid" 2>/dev/null || true

[[ "$watch_rc" == 0 ]] ||
  fail "watcher exited $watch_rc, expected clean exit when the socket closed"

runs="$(wc -l <"$calls" 2>/dev/null || echo 0)"
# one reconcile at startup, plus exactly one for the whole debounced burst
(( runs == 2 )) ||
  fail "expected 2 applier runs (startup + one debounced burst), got $runs"

# ── Reconnect ───────────────────────────────────────────────────────────────
# A watcher that dies on a transient socket drop would silently stop restoring
# the layout for the rest of the session.
sock2="$test_root/hypr/$signature/.socket2.sock"
calls2="$test_root/applier2.calls"
cat >"$test_root/applier2.sh" <<SH
#!/usr/bin/env bash
printf 'run\n' >>"$calls2"
SH
chmod +x "$test_root/applier2.sh"

python3 - "$sock2" <<'PYSRV' &
import os, socket, sys, time
path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(1)
# Never block indefinitely: if the watcher fails to reconnect the test must
# fail, not hang.
srv.settimeout(15)
try:
    conn, _ = srv.accept()
except (socket.timeout, OSError):
    srv.close()
    sys.exit(0)
time.sleep(0.5)
conn.close()
# second connection: the watcher must come back on its own
try:
    conn, _ = srv.accept()
except (socket.timeout, OSError):
    srv.close()
    sys.exit(0)
time.sleep(0.5)
conn.sendall(b"monitoradded>>DP-9\n")
time.sleep(1.5)
conn.close()
srv.close()
PYSRV
server2_pid=$!
sleep 0.5

set +e
XDG_RUNTIME_DIR="$test_root" \
HYPRLAND_INSTANCE_SIGNATURE="$signature" \
HYPR_APPLIER="$test_root/applier2.sh" \
HYPR_WATCH_DEBOUNCE=0.4 \
HYPR_WATCH_RECONNECT_TIMEOUT=6 \
  timeout 40 "$watcher" >"$test_root/watch2.out" 2>&1
watch2_rc=$?
set -e
wait "$server2_pid" 2>/dev/null || true

[[ "$watch2_rc" == 0 ]] || fail "watcher exited $watch2_rc after reconnect sequence"

runs2="$(wc -l <"$calls2" 2>/dev/null || echo 0)"
# startup + reconnect reconcile + the event received after reconnecting
((runs2 >= 3)) ||
  fail "watcher did not reconnect and keep working (applier runs: $runs2)"

printf 'ok: hypr-monitor-watch event handling\n'
