#!/usr/bin/env bash
# WallpaperFx.qml, the shell's wallpaper transitions: static wiring, the pure
# helpers under node, the shader against its compiled copy, and the headless
# smoke driving the state machine and one screen's content with stand-in
# hyprctl scripts.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
fx="$shell_dir/WallpaperFx.qml"
fx_files=("$fx" "$shell_dir/WallpaperFxState.qml" "$shell_dir/WallpaperFxContent.qml")
smoke="$shell_dir/WallpaperFxSmoke.qml"
shader="$shell_dir/shaders/wallfx.frag"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

# Kept: colours come from Theme so the burning edge follows the palette.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "${fx_files[@]}"; then
  fail 'WallpaperFx QML contains a hardcoded color'
fi

# Kept as text checks: the offscreen smoke cannot see layer-shell stacking.
# hyprpaper rebuilds its Background surface on every change, so the effect
# lives on Bottom, created before the desktop widgets, which sit on Bottom too.
grep -Fq 'WlrLayershell.layer: WlrLayer.Bottom' "$fx" || fail 'WallpaperFx is not on the Bottom layer'
for widget in DesktopClock DesktopNowPlaying CavaEdgeVisualizer; do
  grep -Fq 'WlrLayershell.layer: WlrLayer.Bottom' "$shell_dir/$widget.qml" \
    || fail "$widget is not on the Bottom layer, so the transition would cover it"
done
fx_line=$(grep -n 'WallpaperFx {}' "$shell_dir/shell.qml" | cut -d: -f1)
bar_line=$(grep -n 'Bar {}' "$shell_dir/shell.qml" | cut -d: -f1)
[[ -n "$fx_line" && -n "$bar_line" && "$fx_line" -lt "$bar_line" ]] \
  || fail 'shell.qml must create WallpaperFx before the bar and desktop widgets'

qsb_file=$(sed -n 's|.*Qt.resolvedUrl("\(shaders/[^"]*\.qsb\)").*|\1|p' "$shell_dir/WallpaperFxContent.qml")
[[ -n "$qsb_file" && -f "$shell_dir/$qsb_file" ]] || fail "WallpaperFxContent.qml points at a missing shader: $qsb_file"

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/wallpaper-fx.logic.test.js" "$shell_dir/wallfx/WallpaperFxLogic.js"
else
  printf 'skip: node not installed, WallpaperFxLogic.js not run\n'
fi

qsb_bin=""
for candidate in qsb /usr/lib/qt6/bin/qsb pyside6-qsb; do
  if command -v "$candidate" >/dev/null 2>&1; then
    qsb_bin=$candidate
    break
  fi
done
if [[ -n "$qsb_bin" ]]; then
  "$qsb_bin" --glsl "100es,120,150,300es" --hlsl 50 --msl 12 -o "$test_root/wallfx.qsb" "$shader" \
    || fail 'shaders/wallfx.frag does not compile'
  reflection() { "$qsb_bin" -d "$1" | sed -n '/^Reflection info/,/^Shader 0:/p'; }
  # Bytes differ between Qt versions; the uniform layout must not. A stale
  # compiled copy feeds the shader the wrong uniforms.
  diff <(reflection "$test_root/wallfx.qsb") <(reflection "$shell_dir/$qsb_file") >&2 \
    || fail "$qsb_file is stale: rebuild it from shaders/wallfx.frag"
  printf 'ok: shaders/wallfx.frag compiles and matches %s\n' "$qsb_file"
else
  printf 'skip: qsb not installed, shaders/wallfx.frag not compiled\n'
fi

if command -v quickshell >/dev/null 2>&1; then
  smoke_dir="$test_root/smoke"
  mkdir -p "$smoke_dir"
  python3 - "$smoke_dir" <<'PY'
import struct
import sys
import zlib
from pathlib import Path

def png(path, w, h, rgb):
    raw = b"".join(b"\0" + bytes(rgb) * w for _ in range(h))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

out = Path(sys.argv[1])
for name, rgb in (("old", (20, 30, 60)), ("new", (200, 120, 40)), ("fail", (10, 200, 10)),
                  ("replaced", (90, 90, 90)), ("field", (128, 0, 0)), ("line", (0, 128, 0))):
    png(out / f"{name}.png", 64, 36, rgb)
PY
  for outcome in ok fail; do
    cat > "$smoke_dir/hyprctl-$outcome" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$smoke_dir/hyprctl-$outcome.log"
[[ $outcome == ok ]]
STUB
    chmod +x "$smoke_dir/hyprctl-$outcome"
  done

  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_RUNTIME_DIR="$test_root" WALLFX_SMOKE_DIR="$smoke_dir" \
  WALLFX_HYPRCTL="$smoke_dir/hyprctl-fail" QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: WallpaperFx smoke' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'WallpaperFxSmoke.qml did not report success'; }
  if grep -F 'FAIL' "$smoke_log" >&2; then
    fail 'WallpaperFxSmoke.qml reported a failing assertion'
  fi

  ok_log="$smoke_dir/hyprctl-ok.log"
  fail_log="$smoke_dir/hyprctl-fail.log"
  [[ "$(grep -cFx "hyprpaper wallpaper ,$smoke_dir/new.png,cover" "$ok_log")" == 3 ]] \
    || { cat "$ok_log" >&2; fail 'each finished change should switch hyprpaper exactly once'; }
  # A failed switch is retried once, detached, after the effect steps aside.
  [[ "$(grep -cFx "hyprpaper wallpaper ,$smoke_dir/fail.png,cover" "$fail_log")" == 2 ]] \
    || { cat "$fail_log" >&2; fail 'a failed switch was not retried exactly once'; }
  grep -Fqx "hyprpaper wallpaper ,$smoke_dir/missing.png,cover" "$ok_log" \
    || fail 'a wallpaper that never loaded was not switched by hyprpaper alone'
  if grep -Fq 'replaced.png' "$ok_log"; then
    fail 'a change replaced mid-load still switched hyprpaper'
  fi
  printf 'ok: WallpaperFxSmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell not installed, WallpaperFxSmoke.qml not run\n'
fi

printf 'ok: wallpaper-fx checks\n'
