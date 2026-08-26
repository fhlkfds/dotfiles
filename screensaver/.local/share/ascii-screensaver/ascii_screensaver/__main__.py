from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import sys
from pathlib import Path

from . import __version__
from .config import ConfigError, active_window_seconds, load_config
from .convert import convert_image, write_asset
from .render import run_renderer
from .runtime import (automatic_enabled, diagnostic, runtime_dir, schedule, set_automatic,
                      signal_scheduler, start, stop_running)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="ascii-screensaver", description="Fullscreen terminal ASCII screensaver")
    root.add_argument("--config", type=Path, help="configuration file override")
    root.add_argument("--version", action="version", version=__version__)
    commands = root.add_subparsers(dest="command", required=True)
    launch = commands.add_parser("start", help="launch one fullscreen terminal per active monitor")
    launch.add_argument("--automatic", action="store_true", help=argparse.SUPPRESS)
    launch.add_argument("--monitor", action="append", default=[])
    launch.add_argument("--dry-run", action="store_true")
    commands.add_parser("stop", help="stop the active screensaver session")
    render = commands.add_parser("render", help="run the renderer in the current terminal")
    render.add_argument("--frames", type=int)
    render.add_argument("--plain", action="store_true")
    render.add_argument("--monitor", default="foreground")
    hidden = commands.add_parser("__render", help=argparse.SUPPRESS)
    hidden.add_argument("--monitor", required=True)
    auto = commands.add_parser("auto", help="control automatic idle activation")
    auto.add_argument("action", choices=("enable", "disable", "status", "reload"))
    scheduler = commands.add_parser("schedule", help="run the dedicated idle scheduler")
    scheduler.add_argument("--dry-run", action="store_true")
    convert = commands.add_parser("convert", help="convert a PNG/SVG/image to editable ASCII")
    convert.add_argument("input", type=Path)
    convert.add_argument("output", type=Path)
    convert.add_argument("--mode", choices=("blocks", "braille"), default="blocks")
    convert.add_argument("--width", type=int, default=72)
    convert.add_argument("--height", type=int, default=24)
    convert.add_argument("--threshold", type=int, default=96)
    convert.add_argument("--invert", action="store_true")
    convert.add_argument("--force", action="store_true")
    commands.add_parser("doctor", help="validate configuration and report dependencies")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        wrapper = os.environ.get("ASCII_SCREENSAVER_EXECUTABLE", sys.argv[0])
        if args.command == "stop":
            print("stopped" if stop_running() else "not running")
            return 0
        if args.command == "auto" and args.action in ("enable", "disable"):
            enabled = args.action == "enable"
            set_automatic(enabled)
            if not enabled:
                stop_running()
            print(f"automatic={'enabled' if enabled else 'disabled'}")
            return 0
        if args.command == "convert":
            output = convert_image(args.input, args.width, args.height, args.mode, args.threshold, args.invert)
            backup = write_asset(args.output, output, args.force)
            print(f"wrote {args.output}")
            if backup:
                print(f"backup {backup}")
            return 0

        config = load_config(args.config)
        if args.command == "start":
            if args.dry_run:
                print(json.dumps({"config": str(args.config or os.environ.get("ASCII_SCREENSAVER_CONFIG", "default")),
                                  "assignments": diagnostic(config, wrapper, args.monitor, args.automatic)}, indent=2))
                return 0
            return start(config, wrapper, args.monitor, args.automatic)
        if args.command in ("render", "__render"):
            frames = getattr(args, "frames", None)
            if frames is not None and frames < 1:
                raise ValueError("--frames must be at least 1")
            return run_renderer(config, args.monitor, frames=frames, plain=getattr(args, "plain", False))
        if args.command == "auto":
            if args.action == "reload":
                if not signal_scheduler(__import__("signal").SIGHUP):
                    raise RuntimeError("scheduler is not running")
            print(f"automatic={'enabled' if automatic_enabled(config) else 'disabled'}")
            return 0
        if args.command == "schedule":
            return schedule(config, wrapper, args.dry_run, args.config)
        if args.command == "doctor":
            window = active_window_seconds(config)
            print(f"config=ok\nautomatic={'enabled' if automatic_enabled(config) else 'disabled'}")
            print(f"idle_seconds={config.idle_seconds}\nlock_handoff_seconds={config.lock_handoff_seconds}")
            print(f"visible_before_lock={'unlimited' if window is None else window}")
            print(f"runtime_dir={runtime_dir()}")
            for name in ("hypridle", "hyprctl", "kitty", "foot", "ghostty", "alacritty", "magick"):
                print(f"{name}={shutil.which(name) or 'missing'}")
            return 0
        return 2
    except (ConfigError, FileExistsError, OSError, RuntimeError, ValueError) as error:
        print(f"ascii-screensaver: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
