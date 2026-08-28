#!/usr/bin/env python3
"""hypr-monitor-watch.py -- apply the monitor profile when displays change.

Replaces the old 15-second polling loop. Hyprland publishes monitor events on
its socket2 IPC socket; this listens there and calls auto-monitor-profile.sh
once per settled burst.

A KVM switch produces several add/remove events in quick succession, so events
are debounced here, and the applier additionally waits for the display stack to
finish enumerating and takes a lock. The applier is idempotent: if the layout is
already correct it exits without touching the configuration.

Started from conf/autostart.lua. Exits when Hyprland goes away.

Logs to the journal:  journalctl -t hypr-monitor -f
"""

import os
import selectors
import socket
import subprocess
import sys
import time

DEBOUNCE = float(os.environ.get("HYPR_WATCH_DEBOUNCE", "0.6"))
CONNECT_TIMEOUT = float(os.environ.get("HYPR_WATCH_CONNECT_TIMEOUT", "30"))
# If the IPC socket drops we retry briefly rather than exiting: a watcher that
# dies on a transient hiccup would silently stop restoring the layout for the
# rest of the session. If nothing is listening after this, Hyprland is gone.
RECONNECT_TIMEOUT = float(os.environ.get("HYPR_WATCH_RECONNECT_TIMEOUT", "5"))

# v2 variants carry the monitor name/description; both forms are emitted.
WATCHED_EVENTS = {
    "monitoradded",
    "monitoraddedv2",
    "monitorremoved",
    "monitorremovedv2",
}

HYPR_DIR = os.environ.get("HYPR_DIR", os.path.expanduser("~/.config/hypr"))
APPLIER = os.environ.get(
    "HYPR_APPLIER", os.path.join(HYPR_DIR, "scripts", "auto-monitor-profile.sh")
)


def log(message):
    try:
        subprocess.run(
            ["logger", "-t", "hypr-monitor", "--", f"watch: {message}"],
            check=False,
        )
    except OSError:
        pass
    if sys.stderr.isatty():
        print(f"watch: {message}", file=sys.stderr)


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime or not signature:
        return None
    return os.path.join(runtime, "hypr", signature, ".socket2.sock")


def connect(path, timeout):
    """Hyprland may still be starting when autostart fires, so retry briefly."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(path)
            return sock
        except OSError:
            time.sleep(0.5)
    return None


def apply_profile(reason):
    """Run the applier. No --force: it decides for itself whether work is due."""
    log(f"triggering apply ({reason})")
    try:
        result = subprocess.run(
            ["bash", APPLIER], check=False, capture_output=True, text=True
        )
    except OSError as exc:
        log(f"could not run applier: {exc}")
        return
    if result.returncode != 0:
        log(f"applier exited {result.returncode}")


def read_events(sock):
    """Read until the socket closes. Returns True if an apply may have been missed."""
    sel = selectors.DefaultSelector()
    sock.setblocking(False)
    sel.register(sock, selectors.EVENT_READ)

    buffer = ""
    pending = False
    deadline = None

    try:
        while True:
            timeout = None
            if pending:
                timeout = max(0.0, deadline - time.monotonic())

            for _key, _mask in sel.select(timeout=timeout):
                try:
                    chunk = sock.recv(8192)
                except BlockingIOError:
                    continue
                except OSError as exc:
                    log(f"socket error: {exc}")
                    return pending
                if not chunk:
                    return pending

                buffer += chunk.decode("utf-8", "replace")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    name = line.split(">>", 1)[0].strip()
                    if name in WATCHED_EVENTS:
                        if not pending:
                            log(f"event {name}, debouncing {DEBOUNCE}s")
                        pending = True
                        # Each further event pushes the deadline out, so a
                        # burst collapses into a single apply.
                        deadline = time.monotonic() + DEBOUNCE

            if pending and time.monotonic() >= deadline:
                pending = False
                deadline = None
                apply_profile("monitor event")
    finally:
        sel.close()


def main():
    path = socket_path()
    if not path:
        log("XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE unset, exiting")
        return 1
    if not os.path.exists(APPLIER):
        log(f"applier missing at {APPLIER}, exiting")
        return 1

    timeout = CONNECT_TIMEOUT
    first = True

    while True:
        sock = connect(path, timeout)
        if sock is None:
            if first:
                log(f"could not connect to {path} within {timeout}s, exiting")
                return 1
            log("Hyprland is gone, exiting")
            return 0

        log(f"listening on {path}")
        # Reconcile on every (re)connect: the session may have started with the
        # KVM pointed elsewhere, and after a reconnect we may have missed events.
        apply_profile("startup" if first else "reconnect")
        first = False
        timeout = RECONNECT_TIMEOUT

        try:
            missed = read_events(sock)
        except KeyboardInterrupt:
            return 0
        finally:
            sock.close()

        if missed:
            apply_profile("socket closed mid-burst")
        log("socket closed, attempting to reconnect")


if __name__ == "__main__":
    sys.exit(main())
