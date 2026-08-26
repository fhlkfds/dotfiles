#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pty
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "screensaver/.local/share/ascii-screensaver"
WRAPPER = ROOT / "screensaver/.local/bin/ascii-screensaver"
sys.path.insert(0, str(LIB))

from ascii_screensaver.config import ConfigError, active_window_seconds, load_config  # noqa: E402
from ascii_screensaver.convert import convert_image, write_asset  # noqa: E402
from ascii_screensaver.render import render_frame, safe_text  # noqa: E402
from ascii_screensaver.runtime import (diagnostic, scheduler_config, selected_monitors,  # noqa: E402
                                       terminal_command)
from ascii_screensaver.runtime import _assign_hyprland_window  # noqa: E402


BASE_CONFIG = """
automatic_enabled = true
idle_seconds = 30
lock_handoff_seconds = 60
terminal = "kitty"
frame_delay = 0.02
effect_frames = 2
seed = 17
ascii_width = 40
ascii_height = 12
glyphs = ".+#"
colors = ["#112233", "#aabbcc"]
ansi = true
logo_path = "{logo}"
monitor_selection = []
[terminal_args]
kitty = ["--override", "background_opacity=1.0"]
foot = []
ghostty = []
alacritty = []
"""


class ScreensaverTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="screensaver-test."))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.logo = self.temp / "logo.txt"
        self.logo.write_text("TEST\nARRAY\n", encoding="utf-8")
        self.config_path = self.temp / "config.toml"
        self.config_path.write_text(BASE_CONFIG.format(logo=self.logo), encoding="utf-8")
        self.config = load_config(self.config_path)

    def env(self) -> dict[str, str]:
        env = os.environ.copy()
        env.update({
            "ASCII_SCREENSAVER_CONFIG": str(self.config_path),
            "ASCII_SCREENSAVER_EXECUTABLE": str(WRAPPER),
            "ASCII_SCREENSAVER_MONITORS_JSON": '[{"name":"DP-1"},{"name":"HDMI-A-1"}]',
            "XDG_STATE_HOME": str(self.temp / "state"),
            "XDG_RUNTIME_DIR": str(self.temp / "runtime"),
        })
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        return env

    def wait_for(self, path: Path, timeout: float = 4) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.02)
        self.fail(f"timed out waiting for {path}")

    def test_configuration_and_timing_validation(self) -> None:
        self.assertTrue(self.config.automatic_enabled)
        self.assertEqual(active_window_seconds(self.config), 30)
        invalid = self.temp / "invalid.toml"
        invalid.write_text(BASE_CONFIG.format(logo=self.logo).replace("lock_handoff_seconds = 60", "lock_handoff_seconds = 20"), encoding="utf-8")
        with self.assertRaisesRegex(ConfigError, "greater than idle_seconds"):
            load_config(invalid)
        invalid.write_text(BASE_CONFIG.format(logo=self.logo).replace("[terminal_args]", "unknown = true\n[terminal_args]"), encoding="utf-8")
        with self.assertRaisesRegex(ConfigError, "unknown configuration"):
            load_config(invalid)

    def test_terminal_commands_are_argument_arrays(self) -> None:
        expected = {
            "kitty": "--start-as", "foot": "--fullscreen", "ghostty": "--fullscreen=true",
            "alacritty": 'window.startup_mode="Fullscreen"',
        }
        for terminal, token in expected.items():
            command = terminal_command(terminal, str(WRAPPER), "DP-1", self.config)
            self.assertIsInstance(command, list)
            self.assertIn(token, command)
            self.assertEqual(command[-3:], ["__render", "--monitor", "DP-1"])
            self.assertNotIn(";", "".join(command))

    def test_monitor_selection_and_dry_run(self) -> None:
        with mock.patch.dict(os.environ, {"ASCII_SCREENSAVER_MONITORS_JSON": '[{"name":"DP-1"},{"name":"HDMI-A-1"}]'}):
            self.assertEqual(selected_monitors(self.config, ["DP-1"]), ["DP-1"])
            with self.assertRaisesRegex(RuntimeError, "inactive or unknown"):
                selected_monitors(self.config, ["BAD-1"])
            report = diagnostic(self.config, str(WRAPPER), [], False)
        self.assertEqual([item["monitor"] for item in report], ["DP-1", "HDMI-A-1"])

    def test_hyprland_window_assignment_targets_address_and_monitor(self) -> None:
        clients = subprocess.CompletedProcess([], 0, '[{"pid":42,"class":"ascii-screensaver.DP-1","address":"0xabc"}]', "")
        focused = subprocess.CompletedProcess([], 0, "ok\n", "")
        moved = subprocess.CompletedProcess([], 0, "ok\n", "")
        fullscreened = subprocess.CompletedProcess([], 0, "ok\n", "")
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "fixture"}), \
             mock.patch("ascii_screensaver.runtime.subprocess.run",
                        side_effect=[clients, focused, moved, fullscreened]) as run:
            _assign_hyprland_window(42, "DP-1", "ascii-screensaver.DP-1")
        self.assertEqual(run.call_args_list[1].args[0],
                         ["hyprctl", "dispatch", "focuswindow", "address:0xabc"])
        self.assertEqual(run.call_args_list[2].args[0],
                         ["hyprctl", "dispatch", "movewindow", "mon:DP-1"])
        self.assertEqual(run.call_args_list[3].args[0],
                         ["hyprctl", "dispatch", "fullscreen", "0"])

    def test_hyprland_does_not_toggle_off_native_fullscreen(self) -> None:
        clients = subprocess.CompletedProcess(
            [], 0, '[{"pid":42,"class":"ascii-screensaver.DP-1","address":"0xabc","fullscreen":2}]', "")
        ok = subprocess.CompletedProcess([], 0, "ok\n", "")
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "fixture"}), \
             mock.patch("ascii_screensaver.runtime.subprocess.run",
                        side_effect=[clients, ok, ok]) as run:
            _assign_hyprland_window(42, "DP-1", "ascii-screensaver.DP-1")
        self.assertEqual(len(run.call_args_list), 3)

    def test_renderer_is_deterministic_changes_and_escapes_assets(self) -> None:
        logo = [safe_text("OK\x1b[31m")]
        first = render_frame(self.config, logo, random.Random(7), 0, 40, 12, effect="noise", ansi=False)
        again = render_frame(self.config, logo, random.Random(7), 0, 40, 12, effect="noise", ansi=False)
        later = render_frame(self.config, logo, random.Random(7), 1, 40, 12, effect="noise", ansi=False)
        self.assertEqual(first, again)
        self.assertNotEqual(first, later)
        self.assertNotIn("\x1b", first)
        ansi = render_frame(self.config, ["OK"], random.Random(7), 0, 40, 12, ansi=True)
        self.assertIn("\x1b[H", ansi)
        self.assertTrue(ansi.endswith("\x1b[0m"))

    @unittest.skipUnless(shutil.which("magick"), "ImageMagick not installed")
    def test_asset_conversion_is_deterministic_and_backed_up(self) -> None:
        image = self.temp / "source.pgm"
        image.write_bytes(b"P5\n4 4\n255\n" + bytes([0, 255, 0, 255] * 4))
        blocks_a = convert_image(image, 4, 4, "blocks", 100, False)
        blocks_b = convert_image(image, 4, 4, "blocks", 100, False)
        braille = convert_image(image, 2, 1, "braille", 100, False)
        inverted = convert_image(image, 4, 4, "blocks", 100, True)
        self.assertEqual(blocks_a, blocks_b)
        self.assertNotEqual(blocks_a, inverted)
        self.assertTrue(braille.strip())
        output = self.temp / "asset.txt"
        write_asset(output, blocks_a, False)
        with self.assertRaises(FileExistsError):
            write_asset(output, blocks_a, False)
        backup = write_asset(output, inverted, True)
        self.assertIsNotNone(backup)
        self.assertEqual(backup.read_text(encoding="utf-8"), blocks_a)

    def test_renderer_exits_on_keyboard_or_mouse_and_restores_terminal(self) -> None:
        for event in (b"x", b"\x1b[<35;2;2M"):
            with self.subTest(event=event):
                master, slave = pty.openpty()
                process = subprocess.Popen([str(WRAPPER), "render"], stdin=slave, stdout=slave, stderr=slave,
                                           env=self.env(), close_fds=True)
                os.close(slave)
                try:
                    seen = b""
                    deadline = time.monotonic() + 2
                    while b"\x1b[?1003h" not in seen and time.monotonic() < deadline:
                        seen += os.read(master, 8192)
                    self.assertIn(b"\x1b[?1003h", seen)
                    os.write(master, event)
                    self.assertEqual(process.wait(timeout=3), 0)
                    tail = b""
                    try:
                        tail = os.read(master, 8192)
                    except OSError:
                        pass
                    self.assertIn(b"\x1b[?1049l", tail)
                finally:
                    if process.poll() is None:
                        process.kill()
                    os.close(master)

    def test_renderer_keyboard_exit_is_armed_before_mouse_tracking(self) -> None:
        master, slave = pty.openpty()
        process = subprocess.Popen([str(WRAPPER), "render"], stdin=slave, stdout=slave, stderr=slave,
                                   env=self.env(), close_fds=True)
        os.close(slave)
        try:
            initial = os.read(master, 8192)
            self.assertIn(b"\x1b[?1049h", initial)
            self.assertNotIn(b"\x1b[?1003h", initial)
            os.write(master, b"q")
            self.assertEqual(process.wait(timeout=1), 0)
        finally:
            if process.poll() is None:
                process.kill()
            os.close(master)

    def test_auto_enable_disable_and_scheduler_dry_run(self) -> None:
        env = self.env()
        status = subprocess.run([str(WRAPPER), "auto", "status"], env=env, text=True, capture_output=True, check=True)
        self.assertIn("automatic=enabled", status.stdout)
        subprocess.run([str(WRAPPER), "auto", "disable"], env=env, check=True, capture_output=True)
        status = subprocess.run([str(WRAPPER), "auto", "status"], env=env, text=True, capture_output=True, check=True)
        self.assertIn("automatic=disabled", status.stdout)
        subprocess.run([str(WRAPPER), "auto", "enable"], env=env, check=True, capture_output=True)
        dry = subprocess.run([str(WRAPPER), "schedule", "--dry-run"], env=env, text=True, capture_output=True, check=True)
        self.assertIn("timeout = 30", dry.stdout)
        self.assertIn("start --automatic", dry.stdout)
        self.assertIn("on-resume", dry.stdout)
        self.assertNotIn("hyprlock", dry.stdout)

    def test_stop_and_disable_remain_available_with_broken_config(self) -> None:
        self.config_path.write_text("this is not toml = [", encoding="utf-8")
        env = self.env()
        disabled = subprocess.run([str(WRAPPER), "auto", "disable"], env=env,
                                  text=True, capture_output=True)
        stopped = subprocess.run([str(WRAPPER), "stop"], env=env, text=True, capture_output=True)
        self.assertEqual(disabled.returncode, 0, disabled.stderr)
        self.assertEqual(stopped.returncode, 0, stopped.stderr)

    def test_scheduler_reloads_state_and_cleans_hypridle_child(self) -> None:
        bindir = self.temp / "scheduler-bin"
        bindir.mkdir()
        child_pid = self.temp / "hypridle.pid"
        fake = bindir / "hypridle"
        fake.write_text(textwrap.dedent(f"""\
            #!/bin/sh
            echo $$ > {child_pid}
            trap 'exit 0' TERM INT HUP
            while :; do sleep 0.1; done
            """), encoding="utf-8")
        fake.chmod(0o755)
        env = self.env()
        env["PATH"] = f"{bindir}:{env['PATH']}"
        scheduler = subprocess.Popen([str(WRAPPER), "schedule"], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(child_pid)
            first_pid = int(child_pid.read_text())
            subprocess.run([str(WRAPPER), "auto", "disable"], env=env, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            deadline = time.monotonic() + 3
            while Path(f"/proc/{first_pid}").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(Path(f"/proc/{first_pid}").exists())
            child_pid.unlink(missing_ok=True)
            subprocess.run([str(WRAPPER), "auto", "enable"], env=env, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.wait_for(child_pid)
            second_pid = int(child_pid.read_text())
            self.assertNotEqual(first_pid, second_pid)
            scheduler.send_signal(signal.SIGTERM)
            self.assertEqual(scheduler.wait(timeout=4), 0)
            deadline = time.monotonic() + 3
            while Path(f"/proc/{second_pid}").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(Path(f"/proc/{second_pid}").exists())
            scheduler_runtime = Path(env["XDG_RUNTIME_DIR"]) / "ascii-screensaver"
            self.assertFalse((scheduler_runtime / "scheduler.pid").exists())
            self.assertFalse((scheduler_runtime / "scheduler.lock").exists())
            self.assertFalse((scheduler_runtime / "hypridle.conf").exists())
        finally:
            if scheduler.poll() is None:
                scheduler.kill()
                scheduler.wait(timeout=3)
            if scheduler.stdout:
                scheduler.stdout.close()
            if scheduler.stderr:
                scheduler.stderr.close()

    def test_duplicate_prevention_stop_and_child_cleanup(self) -> None:
        bindir = self.temp / "bin"
        bindir.mkdir()
        child_pid = self.temp / "terminal.pid"
        fake = bindir / "kitty"
        fake.write_text(f"#!/bin/sh\necho $$ > {child_pid}\nexec sleep 30\n", encoding="utf-8")
        fake.chmod(0o755)
        env = self.env()
        env["PATH"] = f"{bindir}:{env['PATH']}"
        first = subprocess.Popen([str(WRAPPER), "start", "--monitor", "DP-1"], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(child_pid)
            second = subprocess.run([str(WRAPPER), "start", "--monitor", "DP-1"], env=env,
                                    text=True, capture_output=True, timeout=3, check=True)
            self.assertIn("already running", second.stderr)
            stopped = subprocess.run([str(WRAPPER), "stop"], env=env, text=True, capture_output=True, check=True)
            self.assertIn("stopped", stopped.stdout)
            self.assertEqual(first.wait(timeout=4), 0)
            pid = int(child_pid.read_text())
            deadline = time.monotonic() + 3
            while Path(f"/proc/{pid}").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(Path(f"/proc/{pid}").exists(), "terminal child survived coordinator exit")
            session_runtime = Path(env["XDG_RUNTIME_DIR"]) / "ascii-screensaver"
            self.assertFalse((session_runtime / "session.pid").exists())
            self.assertFalse((session_runtime / "session.lock").exists())
        finally:
            if first.poll() is None:
                first.send_signal(signal.SIGTERM)
                first.wait(timeout=3)
            if first.stdout:
                first.stdout.close()
            if first.stderr:
                first.stderr.close()

    def test_missing_monitor_and_unavailable_terminal_fail_safely(self) -> None:
        env = self.env()
        env["ASCII_SCREENSAVER_MONITORS_JSON"] = "[]"
        result = subprocess.run([str(WRAPPER), "start", "--dry-run"], env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("no active monitors", result.stderr)
        with mock.patch("ascii_screensaver.runtime.shutil.which", return_value=None):
            from ascii_screensaver.runtime import resolve_terminal
            with self.assertRaisesRegex(RuntimeError, "unavailable"):
                resolve_terminal(self.config, "DP-1")

    def test_scheduler_command_quotes_executable(self) -> None:
        content = scheduler_config(self.config, "/tmp/path with spaces/ascii-screensaver")
        self.assertIn("'/tmp/path with spaces/ascii-screensaver' start --automatic", content)
        self.assertIn("condition screensaver", content)
        self.assertIn("condition_retry = 5", content)
        self.assertEqual(content.count("listener {"), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
