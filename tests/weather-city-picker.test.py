#!/usr/bin/env python3
"""Exercise production WeatherState with real Quickshell IO in temporary state.

Curl is a fixture executable; no desktop, services, or real network are used.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
qs = shutil.which("quickshell")
if not qs:
    print("skip: quickshell is not installed")
    sys.exit(0)

shell = r'''
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
  id: test
  property int phase: 0
  property int ticks: 0
  property string mode: Quickshell.env("WEATHER_TEST_MODE")
  function require(ok, message) { if (!ok) throw new Error(message) }
  function done() { console.log("WEATHER_FIXTURE_PASS", mode); Qt.quit() }
  FileView { id: nightWriter; path: WeatherState.stateHome + "/night-light/schedule.json" }
  Component.onCompleted: {
    if (mode === "late")
      WeatherState.selectCity({latitude: 48.85, longitude: 2.35, timezone: "Europe/Paris", place: "Paris"})
  }
  Timer {
    interval: 80; repeat: true; running: true
    onTriggered: {
      try {
        test.ticks++
        test.require(test.ticks < 100, "timed out in phase " + test.phase)
        if (test.phase === 0) {
          if (!WeatherState.hasData || !WeatherState.defaultLoaded) return
          if (test.mode === "late") {
            test.require(WeatherState.place === "Paris", "late default replaced user choice")
            test.require(WeatherState.defaultKey === "41,-87,America/Chicago", "saved metadata missing")
            test.done(); return
          }
          if (test.mode === "reload") {
            test.require(WeatherState.latitude === 41 && WeatherState.isDefault, "default did not win at boot")
          } else {
            test.require(WeatherState.latitude === 51.5, "detected city fallback did not load")
            test.require(!WeatherState.userChoice, "fallback unexpectedly pinned")
            WeatherState.saveDefault()
            test.require(!WeatherState.isDefault, "write confirmed before saved signal")
            test.require(WeatherState.savingDefault, "save not pending")
          }
          test.phase++; return
        }
        if (test.phase === 1) {
          if (WeatherState.savingDefault) return
          if (test.mode === "failure") {
            test.require(WeatherState.defaultError !== "" && !WeatherState.isDefault, "failure falsely confirmed")
            test.require(!WeatherState.userChoice, "failed save pinned city")
            WeatherState.saveDefault(); test.phase = 9; return
          }
          test.require(WeatherState.isDefault && WeatherState.userChoice, "successful save not pinned")
          nightWriter.setText(JSON.stringify({location: {latitude: 59.3, longitude: 18.1,
            timezone: "Europe/Stockholm", place: "Stockholm"}}))
          test.ticks = 0; test.phase++; return
        }
        if (test.phase === 2) {
          if (test.ticks < 4) return
          test.require(WeatherState.latitude === (test.mode === "reload" ? 41 : 51.5), "night-light replaced default")
          if (test.mode === "reload") { test.done(); return }
          WeatherState.searchCities("new"); test.phase++; return
        }
        if (test.phase === 3) {
          if (!WeatherState.canPickCity("new")) return
          WeatherState.searchCities("chi")
          test.require(!WeatherState.canPickCity("chi") && WeatherState.cityResults.length === 0, "stale suggestions remained")
          // Change again while curl is running; only the final query can win.
          WeatherState.updateCityQuery("par")
          test.phase++; return
        }
        if (test.phase === 4) {
          if (!WeatherState.canPickCity("par")) return
          test.require(WeatherState.cityResults[0].name === "Paris", "inflight query race")
          WeatherState.searchCities("chi"); test.phase++; return
        }
        if (test.phase === 5) {
          if (!WeatherState.canPickCity("chi")) return
          WeatherState.selectCity(WeatherState.cityResults[0])
          WeatherState.saveDefault()
          WeatherState.selectCity({latitude: 48.85, longitude: 2.35, timezone: "Europe/Paris", place: "Paris"})
          test.phase++; return
        }
        if (test.phase === 6) {
          if (WeatherState.savingDefault || !WeatherState.hasData) return
          test.require(WeatherState.defaultKey === "41,-87,America/Chicago", "wrong save snapshot")
          test.require(!WeatherState.isDefault && WeatherState.place === "Paris", "save replaced newer choice")
          test.require(WeatherState.current.temp === 48.85, "stale forecast accepted")
          test.done(); return
        }
        if (test.phase === 9) {
          if (WeatherState.savingDefault) return
          test.require(WeatherState.defaultError !== "" && !WeatherState.isDefault, "retry failure falsely confirmed")
          test.done()
        }
      } catch (e) { console.error("WEATHER_FIXTURE_FAIL", e); Qt.quit() }
    }
  }
}
'''

curl = r'''
import json, sys, time
args = sys.argv[1:]
params = dict(a.split("=", 1) for a in args if "=" in a)
time.sleep(0.15)
if "geocoding-api" in args[-1]:
    cities = {"new": ("New York", 40.7, -74, "America/New_York"),
              "chi": ("Chicago", 41, -87, "America/Chicago"),
              "par": ("Paris", 48.85, 2.35, "Europe/Paris")}
    name, lat, lon, tz = cities[params["name"]]
    print(json.dumps({"results": [{"name": name, "latitude": lat, "longitude": lon,
          "timezone": tz, "feature_code": "PPL", "population": 100000}]}))
else:
    print(json.dumps({"current": {"temperature_2m": float(params["latitude"]),
          "apparent_temperature": 65, "relative_humidity_2m": 50,
          "weather_code": 0, "wind_speed_10m": 1, "is_day": 1}}))
'''

with tempfile.TemporaryDirectory(prefix="weather-city-fixture-") as tmp:
    root = Path(tmp)
    for name in ("app", "bin", "home", "config", "cache", "runtime", "state/night-light"):
        (root / name).mkdir(parents=True)
    (root / "runtime").chmod(0o700)
    shutil.copyfile(repo / "quickshell/.config/quickshell/WeatherState.qml", root / "app/WeatherState.qml")
    (root / "app/shell.qml").write_text(shell)
    (root / "app/weather.json").write_text(json.dumps({"latitude": 34, "longitude": -118, "timezone": "America/Los_Angeles"}))
    stub = root / "bin/curl"
    stub.write_text("#!" + sys.executable + "\n" + curl)
    stub.chmod(0o755)
    env = {**os.environ, "HOME": str(root / "home"), "XDG_CONFIG_HOME": str(root / "config"),
           "XDG_CACHE_HOME": str(root / "cache"), "XDG_RUNTIME_DIR": str(root / "runtime"),
           "XDG_STATE_HOME": str(root / "state"), "QT_QPA_PLATFORM": "offscreen",
           "PATH": str(root / "bin"), "QT_QUICK_BACKEND": "software"}
    location = root / "state/hyprland-desktop/weather/location.json"

    def run(mode):
        (root / "state/night-light/schedule.json").write_text(json.dumps({"location": {
            "latitude": 51.5, "longitude": -0.1, "timezone": "Europe/London", "place": "London"}}))
        result = subprocess.run([qs, "--no-color", "-p", str(root / "app")],
                                env={**env, "WEATHER_TEST_MODE": mode}, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if result.returncode or "WEATHER_FIXTURE_PASS" not in output or any(
                marker in output for marker in ("WEATHER_FIXTURE_FAIL", "ReferenceError", "TypeError", "Failed to load configuration", "Binding loop")):
            raise AssertionError(output)
        print("ok:", mode)

    # Missing parent directories must be created by FileView's real writer.
    run("success")
    saved = json.loads(location.read_text())
    assert saved["latitude"] == 41 and saved["timezone"] == "America/Chicago", saved
    run("reload")
    run("late")
    location.write_text("not json")
    run("malformed")
    # Block the state directory to force an actual FileView.saveFailed signal.
    shutil.rmtree(root / "state/hyprland-desktop")
    (root / "state/hyprland-desktop").write_text("fixture blocker")
    run("failure")
