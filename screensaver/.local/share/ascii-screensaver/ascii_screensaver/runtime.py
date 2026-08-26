from __future__ import annotations

import fcntl
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from .config import Config, ConfigError, MONITOR_RE, SUPPORTED_TERMINALS, load_config


def state_dir() -> Path:
    root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "ascii-screensaver"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        root.chmod(0o700)
    except OSError:
        pass
    return root


def runtime_dir() -> Path:
    root = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/ascii-screensaver-{os.getuid()}")) / "ascii-screensaver"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    return root


def automatic_enabled(config: Config) -> bool:
    path = state_dir() / "automatic.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data["enabled"] if isinstance(data.get("enabled"), bool) else config.automatic_enabled
    except (OSError, ValueError, TypeError):
        return config.automatic_enabled


def set_automatic(enabled: bool) -> None:
    path = state_dir() / "automatic.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"enabled": enabled}) + "\n", encoding="utf-8")
    temporary.replace(path)
    signal_scheduler(signal.SIGHUP)


def signal_scheduler(sig: signal.Signals) -> bool:
    path = runtime_dir() / "scheduler.pid"
    try:
        pid = int(path.read_text(encoding="ascii").strip())
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
        if b"ascii_screensaver" not in cmdline and b"ascii-screensaver" not in cmdline:
            return False
        os.kill(pid, sig)
        return True
    except (OSError, ValueError):
        return False


def discover_monitors() -> list[str]:
    fixture = os.environ.get("ASCII_SCREENSAVER_MONITORS_JSON")
    try:
        if fixture is not None:
            data = json.loads(fixture)
        else:
            result = subprocess.run([os.environ.get("HYPRCTL", "hyprctl"), "-j", "monitors"],
                                    text=True, capture_output=True, timeout=3, check=False)
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or "hyprctl monitor query failed")
            data = json.loads(result.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"cannot discover Hyprland monitors: {error}") from error
    names = []
    for item in data:
        name = item.get("name") if isinstance(item, dict) else None
        if isinstance(name, str) and MONITOR_RE.fullmatch(name) and not item.get("disabled", False):
            names.append(name)
    if not names:
        raise RuntimeError("Hyprland reported no active monitors")
    return names


def selected_monitors(config: Config, requested: list[str]) -> list[str]:
    active = discover_monitors()
    wanted = requested or list(config.monitors) or active
    missing = [name for name in wanted if name not in active]
    if missing:
        raise RuntimeError(f"inactive or unknown monitor(s): {', '.join(missing)}")
    result = []
    for name in wanted:
        override = config.monitor_overrides.get(name)
        if name not in result and (override is None or override.enabled):
            result.append(name)
    if not result:
        raise RuntimeError("monitor selection disabled every active monitor")
    return result


def resolve_terminal(config: Config, monitor: str) -> str:
    override = config.monitor_overrides.get(monitor)
    requested = override.terminal if override and override.terminal else config.terminal
    if requested == "plain":
        return "plain"
    if requested != "auto":
        if shutil.which(requested):
            return requested
        raise RuntimeError(f"configured terminal is unavailable: {requested}")
    for name in SUPPORTED_TERMINALS:
        if shutil.which(name):
            return name
    return "plain"


def terminal_command(terminal: str, wrapper: str, monitor: str, config: Config) -> list[str]:
    title = f"ASCII Screensaver [{monitor}]"
    app_id = f"ascii-screensaver.{monitor}"
    custom = list(config.terminal_args.get(terminal, ()))
    renderer = [wrapper, "__render", "--monitor", monitor]
    if terminal == "kitty":
        return ["kitty", "--class", app_id, "--title", title, "--start-as", "fullscreen", *custom, *renderer]
    if terminal == "foot":
        return ["foot", f"--app-id={app_id}", f"--title={title}", "--fullscreen", *custom, *renderer]
    if terminal == "ghostty":
        return ["ghostty", f"--class={app_id}", f"--title={title}", "--fullscreen=true", *custom, "-e", *renderer]
    if terminal == "alacritty":
        return ["alacritty", "--class", f"{app_id},{app_id}", "--title", title,
                "--option", 'window.startup_mode="Fullscreen"', *custom, "-e", *renderer]
    if terminal == "plain":
        return renderer
    raise RuntimeError(f"unsupported terminal: {terminal}")


def diagnostic(config: Config, wrapper: str, requested: list[str], automatic: bool) -> list[dict[str, object]]:
    monitors = selected_monitors(config, requested)
    report = []
    for monitor in monitors:
        terminal = resolve_terminal(config, monitor)
        report.append({"monitor": monitor, "terminal": terminal,
                       "command": terminal_command(terminal, wrapper, monitor, config),
                       "automatic": automatic, "idle_seconds": config.idle_seconds,
                       "lock_handoff_seconds": config.lock_handoff_seconds})
    return report


def _assign_hyprland_window(pid: int, monitor: str, app_id: str) -> None:
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    hyprctl = os.environ.get("HYPRCTL", "hyprctl")
    deadline = time.monotonic() + 5
    address = None
    match = None
    last_error = "window did not appear"
    while time.monotonic() < deadline:
        result = subprocess.run([hyprctl, "-j", "clients"], text=True, capture_output=True, check=False)
        if result.returncode == 0:
            try:
                clients = json.loads(result.stdout)
                match = next((item for item in clients if item.get("pid") == pid or
                              item.get("class") == app_id or item.get("initialClass") == app_id), None)
                if match and isinstance(match.get("address"), str):
                    address = match["address"]
                    break
            except (ValueError, TypeError) as error:
                last_error = str(error)
        else:
            last_error = result.stderr.strip() or "hyprctl clients failed"
        time.sleep(0.05)
    if not address:
        raise RuntimeError(f"cannot assign {app_id} to {monitor}: {last_error}")
    if len(address) <= 2 or not address.startswith("0x") or not all(
            char in "0123456789abcdefABCDEF" for char in address[2:]):
        raise RuntimeError(f"cannot assign {app_id}: Hyprland returned an invalid window address")
    result = subprocess.run([hyprctl, "dispatch", "focuswindow", f"address:{address}"],
                            text=True, capture_output=True, check=False)
    if result.returncode or "ok" not in result.stdout.lower():
        raise RuntimeError(f"cannot focus {app_id}: {result.stderr.strip() or result.stdout.strip()}")
    result = subprocess.run([hyprctl, "dispatch", "movewindow", f"mon:{monitor}"],
                            text=True, capture_output=True, check=False)
    if result.returncode or "ok" not in result.stdout.lower():
        raise RuntimeError(f"cannot move {app_id} to {monitor}: {result.stderr.strip() or result.stdout.strip()}")
    # Kitty may already have honored its native fullscreen startup request.
    # Hyprland's stable `fullscreen 0` dispatcher toggles, so call it only when
    # the exact client is not already in true fullscreen mode (enum value 2).
    assert match is not None
    if match.get("fullscreen") != 2 and match.get("fullscreenClient") != 2:
        result = subprocess.run([hyprctl, "dispatch", "fullscreen", "0"],
                                text=True, capture_output=True, check=False)
        if result.returncode or "ok" not in result.stdout.lower():
            raise RuntimeError(f"cannot fullscreen {app_id}: {result.stderr.strip() or result.stdout.strip()}")


def _terminate(children: list[subprocess.Popen[bytes]]) -> None:
    groups = [child.pid for child in children]
    for child in children:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    alive = set(groups)
    while alive and time.monotonic() < deadline:
        for child in children:
            child.poll()
        for group in tuple(alive):
            try:
                os.killpg(group, 0)
            except ProcessLookupError:
                alive.remove(group)
        if alive:
            time.sleep(0.02)
    for group in alive:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
    for child in children:
        if child.poll() is None:
            child.wait()


def start(config: Config, wrapper: str, requested: list[str], automatic: bool) -> int:
    if automatic and not automatic_enabled(config):
        return 0
    lock_path = runtime_dir() / "session.lock"
    lock_stream = lock_path.open("w")
    try:
        fcntl.flock(lock_stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("ascii-screensaver: already running", file=sys.stderr)
        lock_stream.close()
        return 0
    pid_path = runtime_dir() / "session.pid"
    pid_path.write_text(f"{os.getpid()}\n", encoding="ascii")
    children: list[subprocess.Popen[bytes]] = []
    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    old = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    try:
        report = diagnostic(config, wrapper, requested, automatic)
        if any(item["terminal"] == "plain" for item in report) and len(report) != 1:
            raise RuntimeError("plain fallback supports one monitor only; install or select a supported terminal")
        for item in report:
            command = item["command"]
            assert isinstance(command, list)
            child = subprocess.Popen(command, start_new_session=True)
            children.append(child)
            terminal = str(item["terminal"])
            if terminal != "plain":
                _assign_hyprland_window(child.pid, str(item["monitor"]),
                                        f"ascii-screensaver.{item['monitor']}")
        while children and not stopping:
            if any(child.poll() is not None for child in children):
                break
            time.sleep(0.05)
        return 0
    finally:
        _terminate(children)
        pid_path.unlink(missing_ok=True)
        lock_stream.close()
        lock_path.unlink(missing_ok=True)
        for sig, handler in old.items():
            signal.signal(sig, handler)


def stop_running() -> bool:
    path = runtime_dir() / "session.pid"
    try:
        pid = int(path.read_text(encoding="ascii").strip())
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
        if b"ascii_screensaver" not in cmdline and b"ascii-screensaver" not in cmdline:
            return False
        os.kill(pid, signal.SIGTERM)
        return True
    except (OSError, ValueError):
        path.unlink(missing_ok=True)
        return False


def scheduler_config(config: Config, wrapper: str) -> str:
    command = shlex.quote(str(Path(wrapper).resolve()))
    mode_path = os.environ.get(
        "DESKTOP_MODE_EXECUTABLE", str(Path.home() / ".local/bin/desktop-mode"))
    mode_command = shlex.quote(mode_path)
    return ("general {\n    ignore_dbus_inhibit = false\n}\n\nlistener {\n"
            f"    timeout = {config.idle_seconds}\n"
            f"    condition_cmd = test ! -x {mode_command} || {mode_command} condition screensaver\n"
            "    condition_retry = 5\n"
            f"    on-timeout = {command} start --automatic\n"
            f"    on-resume = {command} stop\n"
            "}\n")


def schedule(config: Config, wrapper: str, dry_run: bool, config_path: Path | None = None) -> int:
    content = scheduler_config(config, wrapper)
    target = runtime_dir() / "hypridle.conf"
    if dry_run:
        print(f"automatic_enabled={str(automatic_enabled(config)).lower()}")
        print(f"scheduler_config={target}")
        print(f"command=hypridle --quiet --config {shlex.quote(str(target))}")
        print(content, end="")
        return 0
    scheduler_lock = runtime_dir() / "scheduler.lock"
    lock_stream = scheduler_lock.open("w")
    try:
        fcntl.flock(lock_stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("ascii-screensaver: scheduler already running", file=sys.stderr)
        lock_stream.close()
        return 0
    (runtime_dir() / "scheduler.pid").write_text(f"{os.getpid()}\n", encoding="ascii")
    reload_requested = False
    stopped = False

    def reload_handler(_signum: int, _frame: object) -> None:
        nonlocal reload_requested
        reload_requested = True

    def stop_handler(_signum: int, _frame: object) -> None:
        nonlocal stopped
        stopped = True

    old_hup = signal.signal(signal.SIGHUP, reload_handler)
    old_int = signal.signal(signal.SIGINT, stop_handler)
    old_term = signal.signal(signal.SIGTERM, stop_handler)
    child: subprocess.Popen[bytes] | None = None
    try:
        while not stopped:
            if reload_requested:
                reload_requested = False
                try:
                    candidate = load_config(config_path)
                    candidate_content = scheduler_config(candidate, wrapper)
                except (ConfigError, OSError, ValueError) as error:
                    print(f"ascii-screensaver: scheduler reload rejected: {error}", file=sys.stderr)
                    continue
                if child and child.poll() is None:
                    child.terminate()
                    child.wait(timeout=3)
                child = None
                config = candidate
                content = candidate_content
                if automatic_enabled(config):
                    temporary = target.with_suffix(".tmp")
                    temporary.write_text(content, encoding="utf-8")
                    temporary.replace(target)
                    child = subprocess.Popen(["hypridle", "--quiet", "--config", str(target)])
            elif child is None and automatic_enabled(config):
                temporary = target.with_suffix(".tmp")
                temporary.write_text(content, encoding="utf-8")
                temporary.replace(target)
                child = subprocess.Popen(["hypridle", "--quiet", "--config", str(target)])
            if child and child.poll() is not None:
                raise RuntimeError(f"screensaver hypridle exited with status {child.returncode}")
            time.sleep(0.2)
        return 0
    finally:
        if child and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        stop_running()
        (runtime_dir() / "scheduler.pid").unlink(missing_ok=True)
        target.unlink(missing_ok=True)
        lock_stream.close()
        scheduler_lock.unlink(missing_ok=True)
        signal.signal(signal.SIGHUP, old_hup)
        signal.signal(signal.SIGINT, old_int)
        signal.signal(signal.SIGTERM, old_term)
