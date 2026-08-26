from __future__ import annotations

import os
import random
import math
import selectors
import shutil
import signal
import sys
import termios
import time
import tty
from pathlib import Path

from .config import Config

CSI = "\x1b["
MESSAGES = ("SIGNAL DRIFT", "VECTOR LOCK", "ECHO FIELD", "PHASE TRACE", "QUIET CURRENT")
EFFECTS = ("rain", "orbit", "noise")
MOUSE_ARM_DELAY = 0.35


def safe_text(text: str) -> str:
    return "".join(char if char == "\t" or ord(char) >= 32 and ord(char) != 127 else " " for char in text)


def load_logo(path: Path) -> list[str]:
    try:
        return [safe_text(line.expandtabs(4)).rstrip() for line in path.read_text(encoding="utf-8").splitlines()]
    except (OSError, UnicodeError) as error:
        raise ValueError(f"cannot read logo {path}: {error}") from error


def _color(hex_value: str) -> str:
    return f"{CSI}38;2;{int(hex_value[1:3], 16)};{int(hex_value[3:5], 16)};{int(hex_value[5:7], 16)}m"


def render_frame(config: Config, logo: list[str], rng: random.Random, frame: int,
                 width: int, height: int, effect: str | None = None, ansi: bool | None = None) -> str:
    width = max(8, min(width, config.ascii_width))
    height = max(4, min(height, config.ascii_height))
    effect = effect or EFFECTS[(frame // config.effect_frames) % len(EFFECTS)]
    canvas = [[" " for _ in range(width)] for _ in range(height)]
    glyphs = config.glyphs

    if effect == "rain":
        for x in range(0, width, 2):
            head = (x * 7 + frame) % (height + 8) - 4
            for tail in range(5):
                y = head - tail
                if 0 <= y < height:
                    canvas[y][x] = glyphs[(x + frame + tail) % len(glyphs)]
    elif effect == "orbit":
        cx, cy = width // 2, height // 2
        for step in range(max(width, height) * 2):
            angle = (step * 0.31) + frame * 0.07
            x = int(cx + (width * 0.42) * math.cos(angle))
            y = int(cy + (height * 0.36) * math.sin(angle * 1.7))
            if 0 <= x < width and 0 <= y < height:
                canvas[y][x] = glyphs[(step + frame) % len(glyphs)]
    else:
        for _ in range(max(1, width * height // 18)):
            x, y = rng.randrange(width), rng.randrange(height)
            canvas[y][x] = rng.choice(glyphs)

    clipped_logo = [line[:width] for line in logo[: max(0, height - 4)]]
    start_y = max(1, (height - len(clipped_logo)) // 2)
    for offset, line in enumerate(clipped_logo):
        start_x = max(0, (width - len(line)) // 2)
        for index, char in enumerate(line):
            if start_x + index < width and char != " ":
                canvas[start_y + offset][start_x + index] = char

    status = f" {MESSAGES[(frame // max(1, config.effect_frames // 2)) % len(MESSAGES)]}  {frame:06d} "
    for index, char in enumerate(status[:width]):
        canvas[height - 2][index] = char
    lines = ["".join(row).rstrip() for row in canvas]
    use_ansi = config.ansi if ansi is None else ansi
    if use_ansi:
        body = "\n".join(_color(config.colors[(frame + idx) % len(config.colors)]) + line for idx, line in enumerate(lines))
        return f"{CSI}H{body}{CSI}0m"
    return "\n".join(lines)


def run_renderer(config: Config, monitor: str, frames: int | None = None, plain: bool = False) -> int:
    logo = load_logo(config.logo_path)
    seed = config.seed if config.seed is not None else int.from_bytes(os.urandom(8), "little")
    rng = random.Random(seed)
    interactive = sys.stdin.isatty() and sys.stdout.isatty() and not plain
    original = None
    stopped = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopped
        stopped = True

    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    selector = selectors.DefaultSelector()
    mouse_enabled = False
    mouse_arm_at = 0.0
    try:
        if interactive:
            original = termios.tcgetattr(sys.stdin.fileno())
            tty.setcbreak(sys.stdin.fileno())
            selector.register(sys.stdin, selectors.EVENT_READ)
            # Window creation/focus can synthesize a pointer-motion report.
            # Arm mouse tracking after placement, while keyboard input remains
            # active immediately, so a screensaver cannot dismiss itself.
            mouse_arm_at = time.monotonic() + MOUSE_ARM_DELAY
            sys.stdout.write(f"{CSI}?1049h{CSI}?25l{CSI}2J")
            sys.stdout.flush()
        for frame in range(frames if frames is not None else 2**63):
            if stopped:
                break
            size = shutil.get_terminal_size((config.ascii_width, config.ascii_height))
            output = render_frame(config, logo, rng, frame, size.columns, max(4, size.lines - 1), ansi=interactive and config.ansi)
            sys.stdout.write(output + ("\n\f\n" if plain else ""))
            sys.stdout.flush()
            if interactive and not mouse_enabled and time.monotonic() >= mouse_arm_at:
                sys.stdout.write(f"{CSI}?1003h{CSI}?1006h")
                sys.stdout.flush()
                mouse_enabled = True
            if interactive and selector.select(config.frame_delay):
                os.read(sys.stdin.fileno(), 4096)
                break
            if not interactive:
                time.sleep(config.frame_delay)
        return 0
    finally:
        if interactive:
            sys.stdout.write(f"{CSI}?1003l{CSI}?1006l{CSI}?25h{CSI}?1049l{CSI}0m")
            sys.stdout.flush()
            if original is not None:
                termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, original)
        selector.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)
