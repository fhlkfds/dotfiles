#!/usr/bin/env python3
"""Fixture tests for hypr/.local/bin/wallfx, the wallpaper transition maps.

Everything runs against a temporary cache, data dir and wallpaper folder; the
cut-out model is never loaded (a fake mask stands in for it).
"""
import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WALLFX = ROOT / "hypr/.local/bin/wallfx"

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:
    print(f"skip: {exc.name} not installed, wallfx maps not tested")
    sys.exit(0)

failures = 0


def check(ok, name):
    global failures
    print(("ok   " if ok else "FAIL ") + name)
    failures += 0 if ok else 1


tmp = Path(tempfile.mkdtemp(prefix="wallfx-test."))
env = dict(os.environ,
           WALLFX_CACHE_DIR=str(tmp / "cache"), WALLFX_DATA_DIR=str(tmp / "data"),
           WALLFX_WALLPAPER_DIR=str(tmp / "walls"), WALLFX_NO_OUTLINE=str(tmp / "no-outline"),
           WALLFX_NOTIFY="true", WALLFX_RENEW_DELAY="0")
os.environ.update(env)


def run(*args):
    return subprocess.run([sys.executable, str(WALLFX), *args], env=env,
                          capture_output=True, text=True, timeout=120)


def load():
    loader = importlib.machinery.SourceFileLoader("wallfx_fixture", str(WALLFX))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def image(path, size=(320, 180), color=(40, 80, 120)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path)
    return path


def arrival16(path):
    a = np.asarray(Image.open(path), np.uint32)
    return a[..., 0] * 256 + a[..., 1]


check(run("--help").returncode == 0, "--help exits 0")
check(run("bogus").returncode == 2, "an unknown command exits 2")
check(run("pick").returncode == 2, "pick without an image exits 2")
check(run("pick", "a", "--bogus").returncode == 2, "an unknown flag exits 2")
run("install", "--dry-run")
check(not (tmp / "data").exists(), "install --dry-run creates nothing")

spread = run("spread")
check(spread.returncode == 0, "spread exits 0")
field, smooth = (Path(p) for p in spread.stdout.split())
check(field.exists() and smooth.exists(), "spread prints a map and its smooth twin")
with Image.open(field) as f:
    check(f.mode == "RGB" and f.size == (480, 270),
          "the contagion map is 480x270 RGB with no alpha for Qt to premultiply")
ranks = arrival16(field)
check(ranks.min() == 0 and ranks.max() == 65535, "arrival ranks span the whole transition")
# Ranked by area: at 30 % of the transition, 30 % of the screen is new.
check(abs((ranks <= 0.3 * 65535).mean() - 0.3) < 0.01, "the covered area grows evenly with time")
check(int(np.asarray(Image.open(smooth))[..., 0].max()) == 0,
      "the smooth twin keeps its 16 bits in G and B, R free")

# The pool slot used by a change is redrawn behind it, so patterns never repeat.
before = field.read_bytes()
deadline = time.time() + 30
while time.time() < deadline and field.read_bytes() == before:
    time.sleep(0.1)
check(field.read_bytes() != before, "a used pool map is renewed in the background")

new = image(tmp / "walls" / "new.png")
pick = run("pick", str(new))
words = pick.stdout.split()
check(pick.returncode == 0 and words[0] == "contagion" and len(words) == 3
      and all(Path(p).exists() for p in words[1:]),
      "a wallpaper with no outline support gets contagion maps")

wallfx = load()
base = Path(wallfx.CACHE) / "outline" / wallfx._key(str(new))
base.parent.mkdir(parents=True, exist_ok=True)
for suffix in ("-field.png", "-line.png"):
    image(Path(str(base) + suffix))
Path(str(base) + ".json").write_text('{"ok": true}')
check(run("pick", str(new)).stdout.split() == ["outline", f"{base}-field.png", f"{base}-line.png"],
      "a wallpaper with a cached character gets its outline maps")

(tmp / "no-outline").write_text("# comment\nnew.png\n")
check(run("pick", str(new)).stdout.split()[0] == "contagion",
      "a wallpaper on the no-outline list gets contagion anyway")
(tmp / "no-outline").unlink()

Path(str(base) + ".json").write_text('{"ok": false}')
check(run("pick", str(new)).stdout.split()[0] == "contagion",
      "a wallpaper cached as having no character gets contagion")

try:
    import cv2  # noqa: F401
except ImportError:
    print("skip: opencv not installed, outline maps not drawn")
else:
    wallfx = load()
    yy, xx = np.mgrid[0:360, 0:640]
    disc = ((xx - 320) ** 2 + (yy - 180) ** 2 < 90 ** 2).astype(np.uint8) * 255
    wallfx._cutout = lambda im: Image.fromarray(disc, "L").resize(im.size)
    hero = image(tmp / "walls" / "hero.png", (640, 360))
    maps = wallfx.outline(str(hero))
    check(maps is not None and all(Path(p).exists() for p in maps),
          "a clear character gets outline maps")
    f = np.asarray(Image.open(maps[0]), np.int32)
    line = np.asarray(Image.open(maps[1]), np.int32)
    check(abs(f[180, 410, 2] - 128) <= 8, "the signed distance is zero on the silhouette")
    check(f[180, 320, 1] > 200 and f[180, 410, 1] < 30, "depth grows from the outline to the centre")
    check(line[89, 320, 0] > 0 and line[180, 320, 0] == 0,
          "the pen parameter lives only near the outline")
    check(line[89, 320, 0] < line[271, 320, 0], "the pens start at the top and meet at the bottom")

    wallfx._cutout = lambda im: Image.new("L", im.size, 255)
    poster = image(tmp / "walls" / "poster.png", (640, 360), (200, 10, 10))
    check(wallfx.outline(str(poster)) is None, "a cut-out covering the whole picture is not a character")

shutil.rmtree(tmp, ignore_errors=True)
print(f"{failures} failure(s)")
sys.exit(1 if failures else 0)
