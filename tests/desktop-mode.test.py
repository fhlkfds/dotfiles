#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import Callable
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "modes/.local/share/desktop-mode"
WRAPPER = ROOT / "modes/.local/bin/desktop-mode"
sys.path.insert(0, str(LIB))

from desktop_mode import (Config, Controller, ModeError, StateStore, default_state,  # noqa: E402
                          load_config, parse_duration, timing_report)


class DesktopModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="desktop-mode-test."))
        self.addCleanup(shutil.rmtree, self.temp, True)
        environment = mock.patch.dict(os.environ, NIGHT_LIGHT_STATE_FILE=str(self.temp / "shader"))
        environment.start()
        self.addCleanup(environment.stop)
        self.config_path = self.temp / "config.toml"
        self.config_path.write_text(
            'warm_temperature = 1000\nnormal_temperature = 6500\n'
            'maximum_duration_seconds = 3600\nduration_presets = ["15m", "30m", "1h"]\n'
            'reconcile_seconds = 0.2\nnotification_command = ["notify-fixture"]\n'
            'screensaver_command = ["screen-fixture"]\n', encoding="utf-8")
        self.config = load_config(self.config_path)
        self.store = StateStore(self.temp / "runtime")

    def test_config_and_duration_validation(self) -> None:
        self.assertEqual(self.config.warm_temperature, 1000)
        self.assertEqual(parse_duration("15m", 3600), 900)
        with self.assertRaisesRegex(ModeError, "look like"):
            parse_duration("forever")
        with self.assertRaisesRegex(ModeError, "exceeds"):
            parse_duration("2h", 3600)
        invalid = self.temp / "bad.toml"
        invalid.write_text("unknown = true\n", encoding="utf-8")
        with self.assertRaisesRegex(ModeError, "unknown configuration"):
            load_config(invalid)

    def test_custom_durations(self) -> None:
        day = 86400
        for text, seconds in (("30m", 1800), ("1h", 3600), ("3h", 10800), ("8h", 28800),
                              ("1h30m", 5400), ("90", 5400), (" 2H ", 7200),
                              ("1h 15m", 4500), ("45s", 45)):
            self.assertEqual(parse_duration(text, day), seconds, text)
        for text in ("", "0m", "0", "h", "1d", "-5m", "1.5h", "m30"):
            with self.assertRaises(ModeError, msg=text):
                parse_duration(text, day)

    def test_default_presets_are_30m_1h_3h_8h(self) -> None:
        expected = ("30m", "1h", "3h", "8h")
        self.assertEqual(Config().duration_presets, expected)
        bare = self.temp / "bare.toml"
        bare.write_text("", encoding="utf-8")
        self.assertEqual(load_config(bare).duration_presets, expected)
        shipped = load_config(ROOT / "modes/.config/desktop-mode/config.toml")
        self.assertEqual(shipped.duration_presets, expected)

    def test_atomic_state_permissions_and_validation(self) -> None:
        state = self.store.update(lambda value: value["modes"]["stay-awake"].update(desired=True))
        self.assertTrue(state["modes"]["stay-awake"]["desired"])
        self.assertEqual(self.store.path.stat().st_mode & 0o777, 0o600)
        self.store.path.write_text("not json", encoding="utf-8")
        self.assertEqual(self.store.read(), default_state())

    def test_concurrent_state_updates_are_serialized(self) -> None:
        threads = [threading.Thread(target=lambda: self.store.update(lambda _value: None))
                   for _ in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(self.store.read()["generation"], 20)

    def test_stay_awake_is_idempotent_and_timed(self) -> None:
        controller = Controller(self.config, self.store)
        first = controller.set("stay-awake", True, "15m")
        second = controller.set("stay-awake", True, "15m")
        self.assertTrue(first["observed"])
        self.assertTrue(second["observed"])
        self.assertGreater(second["expires_at"], time.time())
        controller.set("stay-awake", False)
        self.assertFalse(controller.status_one("stay-awake")["observed"])

    def test_expiry_disables_transient_mode(self) -> None:
        controller = Controller(self.config, self.store)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() - 1))
        controller.expire()
        self.assertFalse(controller.status_one("stay-awake")["observed"])

    def test_expiry_never_overwrites_a_renewal_made_meanwhile(self) -> None:
        # The user renews while expire() waits on a slow backend call.
        def runner(argv, **_kwargs):
            if argv[-1] == "dnd-off":
                for name in ("do-not-disturb", "stay-awake"):
                    self.store.update(lambda value, n=name: value["modes"][n].update(
                        desired=True, expires_at=time.time() + 3600))
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": True}), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        for name in ("do-not-disturb", "stay-awake"):
            self.store.update(lambda value, n=name: value["modes"][n].update(
                desired=True, expires_at=time.time() - 1))
        controller.expire()
        for name in ("do-not-disturb", "stay-awake"):
            item = self.store.read()["modes"][name]
            self.assertTrue(item["desired"], name)
            self.assertGreater(item["expires_at"], time.time(), name)

    def test_expired_stay_awake_reads_off_without_a_daemon(self) -> None:
        controller = Controller(self.config, self.store)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() - 1))
        self.assertFalse(controller.status_one("stay-awake")["observed"])
        self.assertTrue(controller.toggle("stay-awake")["observed"], "toggle of an expired timer turns it on")

    def test_backend_commands_are_argv_and_observed(self) -> None:
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv)
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": True}), "")
            if argv[-2:] == ["auto", "status"]:
                return subprocess.CompletedProcess(argv, 0, "automatic=enabled\n", "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.assertTrue(controller.status_one("do-not-disturb")["observed"])
        self.assertTrue(controller.status_one("screensaver-auto")["observed"])
        controller.set("do-not-disturb", False)
        self.assertIn(["notify-fixture", "dnd-off"], calls)

    def test_failed_backend_records_desired_and_error(self) -> None:
        def runner(argv, **_kwargs):
            return subprocess.CompletedProcess(argv, 2, "", "fixture failure")
        controller = Controller(self.config, self.store, runner)
        with self.assertRaisesRegex(ModeError, "fixture failure"):
            controller.set("do-not-disturb", True)
        item = self.store.read()["modes"]["do-not-disturb"]
        self.assertTrue(item["desired"])
        self.assertEqual(item["error"], "fixture failure")

    def test_shader_status_and_external_changes(self) -> None:
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, "night-light: off\n", "")
        controller = Controller(self.config, self.store, runner)
        item = controller.status_one("night-light")
        self.assertTrue(item["available"])
        self.assertFalse(item["observed"])
        self.assertIsNone(item["error"])
        controller.set("night-light", True, "15m")
        self.assertIn([*self.config.night_light_command, "on"], calls)
        calls.clear()
        controller.reconcile()
        self.assertNotIn([*self.config.night_light_command, "on"], calls)
        self.assertFalse(controller.status_one("night-light")["desired"])
        self.store.update(lambda value: value["modes"]["night-light"].update(
            expires_at=time.time() - 1))
        controller.expire()
        self.assertNotIn([*self.config.night_light_command, "off"], calls)

    def test_shader_expiry_preserves_later_requests(self) -> None:
        shader = self.temp / "shader"
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv[-1])
            if argv[-1] == "on":
                replacement = shader.with_suffix(".tmp")
                replacement.write_text("enabled\n")
                replacement.replace(shader)
            elif argv[-1] == "off":
                shader.unlink(missing_ok=True)
            status = "on" if shader.exists() else "off"
            return subprocess.CompletedProcess(argv, 0, f"night-light: {status}\n", "")
        with mock.patch.dict(os.environ, NIGHT_LIGHT_STATE_FILE=str(shader)):
            controller = Controller(self.config, self.store, runner)
            for external in (None, "on", "off"):
                controller.set("night-light", True, "15m")
                if external:
                    runner([external])
                calls.clear()
                self.store.update(lambda value: value["modes"]["night-light"].update(
                    expires_at=time.time() - 1))
                # Ownership survives a controller restart through stored state.
                Controller(self.config, self.store, runner).expire()
                self.assertEqual(calls.count("off"), 0 if external else 1)
                self.assertEqual(shader.exists(), external == "on")
                self.assertIsNone(self.store.read()["modes"]["night-light"]["expires_at"])

    def test_night_light_renewed_during_expiry_stays_on(self) -> None:
        # night-light.sh serializes calls, so the renewal's "on" can finish
        # before the expiry's "off" runs.
        shader = self.temp / "shader"
        renewed = []
        def runner(argv, **_kwargs):
            if argv[-1] == "off" and not renewed:
                renewed.append(True)
                Controller(self.config, self.store, runner).set("night-light", True, "1h")
            if argv[-1] == "on":
                shader.write_text("enabled\n")
            elif argv[-1] == "off":
                shader.unlink(missing_ok=True)
            status = "on" if shader.exists() else "off"
            return subprocess.CompletedProcess(argv, 0, f"night-light: {status}\n", "")
        controller = Controller(self.config, self.store, runner)
        controller.set("night-light", True, "1h")
        self.store.update(lambda value: value["modes"]["night-light"].update(
            expires_at=time.time() - 1))
        controller.expire()
        self.assertTrue(renewed)
        self.assertTrue(shader.exists(), "renewed night light was turned off")
        controller.expire()
        item = self.store.read()["modes"]["night-light"]
        self.assertGreater(item["expires_at"] or 0, time.time(), "renewed timer was dropped")

    def test_probed_mode_error_clears_when_backend_recovers(self) -> None:
        def runner(argv, **_kwargs):
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": False}), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.store.update(lambda value: value["modes"]["do-not-disturb"].update(
            error="notification service unavailable"))
        self.assertIsNone(controller.status_one("do-not-disturb")["error"])
        controller.reconcile()
        self.assertIsNone(self.store.read()["modes"]["do-not-disturb"]["error"])

    def test_reconcile_restores_desired_backend_state(self) -> None:
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv)
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": False}), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.store.update(lambda value: value["modes"]["do-not-disturb"].update(desired=True))
        with mock.patch("desktop_mode.shutil.which", return_value=None):
            controller.reconcile()
        self.assertIn(["notify-fixture", "dnd-on"], calls)

    def test_lock_condition_honors_active_and_expired_timer(self) -> None:
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.store.root)})
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() + 60))
        active = subprocess.run([str(WRAPPER), "condition", "lock"], env=env)
        self.assertEqual(active.returncode, 1)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() - 1))
        expired = subprocess.run([str(WRAPPER), "condition", "lock"], env=env)
        self.assertEqual(expired.returncode, 0)

    def _inhibit_fixture(self) -> tuple[Path, Path]:
        """An inhibitor stand-in that, like systemd-inhibit + cat, runs until stdin closes."""
        log = self.temp / "inhibit-log"
        fixture = self.temp / "inhibit-fixture"
        fixture.write_text("#!/bin/sh\necho start >> \"$INHIBIT_LOG\"\ncat >/dev/null\n"
                           "echo stop >> \"$INHIBIT_LOG\"\n", encoding="utf-8")
        fixture.chmod(0o755)
        self.config_path.write_text(self.config_path.read_text(encoding="utf-8")
                                    + f'inhibit_command = ["{fixture}"]\n', encoding="utf-8")
        return fixture, log

    def _log(self, log: Path) -> list[str]:
        return log.read_text(encoding="utf-8").split() if log.exists() else []

    def _wait_for(self, predicate: Callable[[], bool], timeout: float = 4) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(0.05)
        return predicate()

    def test_stay_awake_holds_idle_inhibitor_until_off_or_expired(self) -> None:
        _fixture, log = self._inhibit_fixture()
        with mock.patch.dict(os.environ, INHIBIT_LOG=str(log)):
            controller = Controller(load_config(self.config_path), self.store)
            controller.hold_awake()
            self.assertIsNone(controller.inhibitor, "no inhibitor while stay-awake is off")
            controller.set("stay-awake", True, "1h")
            controller.hold_awake()
            first = controller.inhibitor
            self.assertIsNotNone(first)
            controller.hold_awake()
            self.assertIs(controller.inhibitor, first, "a held inhibitor is not respawned")
            controller.set("stay-awake", False)
            controller.hold_awake()
            self.assertIsNone(controller.inhibitor)
            self.assertIsNotNone(first.returncode, "inhibitor still running after stay-awake off")
            controller.set("stay-awake", True, "1h")
            controller.hold_awake()
            self.assertIsNotNone(controller.inhibitor)
            self.store.update(lambda value: value["modes"]["stay-awake"].update(
                expires_at=time.time() - 1))
            controller.expire()
            controller.hold_awake()
            self.assertIsNone(controller.inhibitor, "expired timer kept the inhibitor")
        self.assertTrue(self._wait_for(lambda: self._log(log) == ["start", "stop"] * 2), self._log(log))

    def test_dead_or_missing_inhibitor_is_reported_and_replaced(self) -> None:
        missing = self.temp / "does-not-exist"
        self.config_path.write_text(self.config_path.read_text(encoding="utf-8")
                                    + f'inhibit_command = ["{missing}"]\n', encoding="utf-8")
        controller = Controller(load_config(self.config_path), self.store)
        controller.set("stay-awake", True)
        controller.hold_awake()
        self.assertIn("idle inhibitor unavailable", controller.status_one("stay-awake")["error"])
        dying = Config(**{**load_config(self.config_path).__dict__, "inhibit_command": ("true",)})
        controller = Controller(dying, self.store)
        controller.hold_awake()
        self.assertTrue(self._wait_for(lambda: controller.inhibitor.poll() is not None))
        first = controller.inhibitor
        controller.hold_awake()
        self.assertIsNot(controller.inhibitor, first, "dead inhibitor was not replaced")
        self.assertIn("exited with status 0", controller.status_one("stay-awake")["error"])
        controller.release_awake()

    def test_inhibitor_error_clears_once_stay_awake_is_off(self) -> None:
        dying = Config(**{**self.config.__dict__, "inhibit_command": ("true",)})
        controller = Controller(dying, self.store)
        controller.set("stay-awake", True)
        controller.hold_awake()
        self.assertTrue(self._wait_for(lambda: controller.inhibitor.poll() is not None))
        controller.hold_awake()
        self.assertIsNotNone(controller.status_one("stay-awake")["error"])
        # Turning stay-awake off clears a recorded inhibitor failure.
        self.store.update(lambda value: value["modes"]["stay-awake"].update(desired=False))
        controller.hold_awake()
        self.assertIsNone(controller.status_one("stay-awake")["error"])
        self.assertIsNone(controller.inhibitor)

    def test_daemon_inhibitor_follows_cli_and_dies_with_daemon(self) -> None:
        _fixture, log = self._inhibit_fixture()
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "awake-runtime"),
                    "INHIBIT_LOG": str(log)})
        daemon = subprocess.Popen([str(WRAPPER), "daemon"], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: daemon.poll() is None and daemon.kill())
        self.assertTrue(self._wait_for(lambda: (self.temp / "awake-runtime/daemon.pid").exists()))
        cli = lambda *args: subprocess.run([str(WRAPPER), *args], env=env, check=True,
                                           capture_output=True, text=True)
        cli("enable", "stay-awake", "--for", "1h")
        self.assertTrue(self._wait_for(lambda: self._log(log) == ["start"]), self._log(log))
        cli("disable", "stay-awake")
        self.assertTrue(self._wait_for(lambda: self._log(log) == ["start", "stop"]), self._log(log))
        cli("enable", "stay-awake")
        self.assertTrue(self._wait_for(lambda: self._log(log) == ["start", "stop", "start"]))
        # A hard kill runs no cleanup; the closed stdin pipe must still end the block.
        daemon.send_signal(signal.SIGKILL)
        daemon.wait(timeout=4)
        self.assertTrue(self._wait_for(lambda: self._log(log) == ["start", "stop"] * 2), self._log(log))

    def test_idle_condition_blocks_only_while_stay_awake_is_active(self) -> None:
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.store.root)})
        idle = lambda: subprocess.run([str(WRAPPER), "condition", "idle"], env=env).returncode
        self.assertEqual(idle(), 0)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(desired=True, expires_at=None))
        self.assertEqual(idle(), 1)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(expires_at=time.time() - 1))
        self.assertEqual(idle(), 0)
        env["DESKTOP_MODE_CONFIG"] = str(self.temp / "missing.toml")
        broken = subprocess.run([str(WRAPPER), "condition", "idle"], env=env, text=True, capture_output=True)
        self.assertEqual(broken.returncode, 0, "a broken config must not block suspend")
        self.assertIn("idle allowed", broken.stderr)

    def test_every_hypridle_listener_is_gated_by_stay_awake(self) -> None:
        text = (ROOT / "hypr/.config/hypr/hypridle.conf").read_text(encoding="utf-8")
        listeners = re.findall(r"^listener\s*\{\n(.*?)^\}", text, re.DOTALL | re.MULTILINE)
        self.assertEqual(len(listeners), 4)
        for block in listeners:
            action = re.search(r"on-timeout\s*=\s*(.*)", block).group(1)
            self.assertRegex(block, r"condition_cmd\s*=.*desktop-mode\" condition (idle|lock)",
                             f"listener '{action}' ignores stay-awake")
        self.assertNotRegex(text, r"ignore_systemd_inhibit\s*=\s*(true|1)")

    def test_daemon_signal_cleanup(self) -> None:
        env = os.environ.copy()
        runtime = self.temp / "daemon-runtime"
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(runtime)})
        process = subprocess.Popen([str(WRAPPER), "daemon"], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pidfile = runtime / "daemon.pid"
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and not pidfile.exists():
            time.sleep(0.02)
        self.assertTrue(pidfile.exists())
        process.terminate()
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertFalse(pidfile.exists())

    def test_daemon_reconciles_dnd_less_often_than_expiry(self) -> None:
        # Each DND reconcile starts notificationctl plus a Quickshell IPC
        # client; at reconcile_seconds = 0.2 the daemon makes ~6 passes in 1.2 s.
        log = self.temp / "notify-calls"
        fixture = self.temp / "notify-log-fixture"
        fixture.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MODE_LOG\"\n"
                           "printf '{\"available\":true,\"dnd\":false}\\n'\n", encoding="utf-8")
        fixture.chmod(0o755)
        config = self.config_path.read_text(encoding="utf-8").replace(
            '["notify-fixture"]', f'["{fixture}"]')
        self.config_path.write_text(config, encoding="utf-8")
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "reconcile-runtime"),
                    "MODE_LOG": str(log)})
        process = subprocess.Popen([str(WRAPPER), "daemon"], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(1.2)
        process.terminate()
        process.communicate(timeout=4)
        calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        status_calls = [c for c in calls if c.startswith("status")]
        self.assertGreaterEqual(len(status_calls), 1)
        self.assertLessEqual(len(status_calls), 2)

    def test_watch_exits_when_its_parent_dies(self) -> None:
        # The bar keeps one `watch` running; a crashed shell must not leave it
        # polling status forever.
        pid_file = self.temp / "watch.pid"
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "watch-runtime")})
        subprocess.run(["sh", "-c", f'"{WRAPPER}" watch >/dev/null 2>&1 & echo $! > "{pid_file}"; sleep 0.5'],
                       env=env, check=True)
        pid = int(pid_file.read_text(encoding="ascii"))
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            os.kill(pid, 15)
            self.fail("desktop-mode watch outlived its parent")

    def test_lock_condition_fails_closed_when_config_is_missing(self) -> None:
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.temp / "missing.toml"),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "condition")})
        result = subprocess.run([str(WRAPPER), "condition", "lock"], env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lock allowed", result.stderr)

    def test_cli_manual_and_automatic_are_separate(self) -> None:
        fixture = self.temp / "screen-fixture"
        log = self.temp / "calls"
        fixture.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MODE_LOG\"\n"
                           "[ \"$*\" = 'auto status' ] && printf 'automatic=enabled\\n'\n"
                           "exit 0\n", encoding="utf-8")
        fixture.chmod(0o755)
        config = self.config_path.read_text(encoding="utf-8").replace(
            '["screen-fixture"]', f'["{fixture}"]')
        self.config_path.write_text(config, encoding="utf-8")
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "cli-runtime"),
                    "MODE_LOG": str(log)})
        manual = subprocess.run([str(WRAPPER), "action", "screensaver"], env=env)
        automatic = subprocess.run([str(WRAPPER), "disable", "screensaver-auto"], env=env,
                                   text=True, capture_output=True)
        self.assertEqual(manual.returncode, 0)
        self.assertEqual(automatic.returncode, 0, automatic.stderr)
        self.assertEqual(log.read_text(encoding="utf-8").splitlines(),
                         ["start", "auto disable", "auto status"])

    def test_hypridle_screensaver_and_lock_timing_report(self) -> None:
        idle = self.temp / "hypridle.conf"
        idle.write_text(
            "listener {\n timeout = 180\n on-timeout = ascii-screensaver\n}\n"
            "listener {\n timeout = 300\n on-timeout = loginctl lock-session\n}\n",
            encoding="utf-8")
        with mock.patch.dict(os.environ, {"DESKTOP_MODE_HYPRIDLE_CONFIG": str(idle)}):
            report = timing_report()
        self.assertEqual(report["screensaver_idle_seconds"], 180)
        self.assertEqual(report["lock_seconds"], 300)
        self.assertEqual(report["warnings"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
