from __future__ import annotations

import os
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

SUPPORTED_TERMINALS = ("kitty", "foot", "ghostty", "alacritty")
MONITOR_RE = re.compile(r"^[A-Za-z0-9_.:-]+$")
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class MonitorOverride:
    enabled: bool = True
    terminal: str | None = None


@dataclass(frozen=True)
class Config:
    automatic_enabled: bool = True
    idle_seconds: int = 300
    lock_handoff_seconds: int = 660
    terminal: str = "auto"
    terminal_args: dict[str, tuple[str, ...]] = field(default_factory=dict)
    frame_delay: float = 0.12
    effect_frames: int = 80
    seed: int | None = None
    ascii_width: int = 72
    ascii_height: int = 24
    glyphs: str = ".:+*#%@"
    colors: tuple[str, ...] = ("#89b4fa", "#a6e3a1", "#cba6f7")
    ansi: bool = True
    logo_path: Path = Path("~/.config/ascii-screensaver/logo.txt")
    monitors: tuple[str, ...] = ()
    monitor_overrides: dict[str, MonitorOverride] = field(default_factory=dict)


def default_config_path() -> Path:
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return root / "ascii-screensaver" / "config.toml"


def _integer(data: dict[str, Any], key: str, default: int, minimum: int, maximum: int) -> int:
    value = data.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ConfigError(f"{key} must be an integer from {minimum} to {maximum}")
    return value


def _number(data: dict[str, Any], key: str, default: float, minimum: float, maximum: float) -> float:
    value = data.get(key, default)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not minimum <= float(value) <= maximum:
        raise ConfigError(f"{key} must be a number from {minimum} to {maximum}")
    return float(value)


def _boolean(data: dict[str, Any], key: str, default: bool) -> bool:
    value = data.get(key, default)
    if not isinstance(value, bool):
        raise ConfigError(f"{key} must be true or false")
    return value


def _string_list(value: Any, label: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ConfigError(f"{label} must be an array of strings")
    return tuple(value)


def load_config(path: Path | None = None) -> Config:
    path = path or Path(os.environ.get("ASCII_SCREENSAVER_CONFIG", default_config_path()))
    try:
        with path.open("rb") as stream:
            raw = tomllib.load(stream)
    except FileNotFoundError as error:
        raise ConfigError(f"configuration not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ConfigError(f"invalid TOML in {path}: {error}") from error

    known = {"automatic_enabled", "idle_seconds", "lock_handoff_seconds", "terminal", "terminal_args",
             "frame_delay", "effect_frames", "seed", "ascii_width", "ascii_height", "glyphs", "colors",
             "ansi", "logo_path", "monitor_selection", "monitor"}
    unknown = sorted(set(raw) - known)
    if unknown:
        raise ConfigError(f"unknown configuration key(s): {', '.join(unknown)}")

    terminal = raw.get("terminal", "auto")
    if terminal not in ("auto", "plain", *SUPPORTED_TERMINALS):
        raise ConfigError(f"terminal must be auto, plain, or one of {', '.join(SUPPORTED_TERMINALS)}")
    seed = raw.get("seed")
    if seed is not None and (isinstance(seed, bool) or not isinstance(seed, int)):
        raise ConfigError("seed must be an integer when set")
    glyphs = raw.get("glyphs", ".:+*#%@")
    if not isinstance(glyphs, str) or not glyphs or any(ord(char) < 32 for char in glyphs):
        raise ConfigError("glyphs must be a non-empty printable string")
    colors = _string_list(raw.get("colors", ["#89b4fa", "#a6e3a1", "#cba6f7"]), "colors")
    if not colors or any(not HEX_RE.fullmatch(color) for color in colors):
        raise ConfigError("colors must contain one or more #RRGGBB values")
    monitor_selection = _string_list(raw.get("monitor_selection", []), "monitor_selection")
    if any(not MONITOR_RE.fullmatch(name) for name in monitor_selection):
        raise ConfigError("monitor_selection contains an invalid monitor identifier")

    args_raw = raw.get("terminal_args", {})
    if not isinstance(args_raw, dict):
        raise ConfigError("terminal_args must be a table")
    terminal_args: dict[str, tuple[str, ...]] = {}
    for name, args in args_raw.items():
        if name not in SUPPORTED_TERMINALS:
            raise ConfigError(f"terminal_args has unsupported terminal: {name}")
        terminal_args[name] = _string_list(args, f"terminal_args.{name}")

    monitor_raw = raw.get("monitor", {})
    if not isinstance(monitor_raw, dict):
        raise ConfigError("monitor must be a table")
    overrides: dict[str, MonitorOverride] = {}
    for name, values in monitor_raw.items():
        if not MONITOR_RE.fullmatch(name) or not isinstance(values, dict):
            raise ConfigError(f"invalid monitor override: {name}")
        extra = set(values) - {"enabled", "terminal"}
        if extra:
            raise ConfigError(f"unknown monitor.{name} key(s): {', '.join(sorted(extra))}")
        override_terminal = values.get("terminal")
        if override_terminal is not None and override_terminal not in ("plain", *SUPPORTED_TERMINALS):
            raise ConfigError(f"monitor.{name}.terminal is unsupported")
        overrides[name] = MonitorOverride(
            enabled=_boolean(values, "enabled", True), terminal=override_terminal
        )

    idle = _integer(raw, "idle_seconds", 300, 10, 86400)
    lock = _integer(raw, "lock_handoff_seconds", 660, 0, 86400)
    if lock and lock <= idle:
        raise ConfigError("lock_handoff_seconds must be 0 or greater than idle_seconds")
    logo = raw.get("logo_path", "~/.config/ascii-screensaver/logo.txt")
    if not isinstance(logo, str) or not logo.strip() or "\x00" in logo:
        raise ConfigError("logo_path must be a non-empty path")

    return Config(
        automatic_enabled=_boolean(raw, "automatic_enabled", True), idle_seconds=idle,
        lock_handoff_seconds=lock, terminal=terminal, terminal_args=terminal_args,
        frame_delay=_number(raw, "frame_delay", 0.12, 0.02, 10.0),
        effect_frames=_integer(raw, "effect_frames", 80, 1, 100000), seed=seed,
        ascii_width=_integer(raw, "ascii_width", 72, 8, 500),
        ascii_height=_integer(raw, "ascii_height", 24, 4, 200), glyphs=glyphs, colors=colors,
        ansi=_boolean(raw, "ansi", True), logo_path=Path(os.path.expandvars(logo)).expanduser(),
        monitors=monitor_selection, monitor_overrides=overrides,
    )


def active_window_seconds(config: Config) -> int | None:
    if config.lock_handoff_seconds == 0:
        return None
    return config.lock_handoff_seconds - config.idle_seconds
