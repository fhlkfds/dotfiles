#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
capture_dir="$repo_root/hypr/.config/hypr/scripts/capture"
frame="$capture_dir/frame.sh"
test_root=$(mktemp -d -t capture-frame.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || { printf 'skip: jq not installed\n'; exit 0; }

mkdir -p "$test_root/bin" "$test_root/shots" "$test_root/runtime"
cat >"$test_root/theme.json" <<'JSON'
{"colors": {"accent": "#112233", "accentAlt": "#445566", "background": "#778899"},
 "style": {"rounding": 7}}
JSON
cat >"$test_root/bin/magick" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$MAGICK_ARGS"
printf framed >"${!#}"
SH
cat >"$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$COPY_ARGS"
cat >"$COPY_DATA"
SH
chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
export FRAME_THEME_FILE="$test_root/theme.json"
export MAGICK_ARGS="$test_root/magick.args" COPY_ARGS="$test_root/copy.args" COPY_DATA="$test_root/copy.data"
printf png >"$test_root/shots/shot.png"

# Frame a capture with the stand-in ImageMagick.
output=$("$frame" "$test_root/shots/shot.png")
[[ $output == "$test_root/shots/shot-framed.png" ]] || fail "framed copy is not beside the original: $output"
mapfile -t args <"$MAGICK_ARGS"
[[ ${args[0]} == "$test_root/shots/shot.png" ]] || fail 'magick did not read the capture'
[[ ${args[-1]} == "$output" ]] || fail 'magick did not write the framed copy'
grep -Fxq 'roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 7,7' "$MAGICK_ARGS" || fail 'corner radius is not the theme rounding'
grep -Fxq '0,0 #112233 %[fx:w-1],%[fx:h-1] #445566' "$MAGICK_ARGS" || fail 'gradient is not accent to accentAlt'
grep -Fxq -- '-shadow' "$MAGICK_ARGS" || fail 'no drop shadow'
[[ $(<"$COPY_ARGS") == $'-t\nimage/png' ]] || fail 'wl-copy was not given a PNG'
[[ $(<"$COPY_DATA") == framed ]] || fail 'the clipboard did not receive the framed copy'

# A palette without accentAlt falls back to its background.
jq 'del(.colors.accentAlt)' "$test_root/theme.json" >"$test_root/no-alt.json"
FRAME_THEME_FILE="$test_root/no-alt.json" "$frame" "$test_root/shots/shot.png" >/dev/null
grep -Fxq '0,0 #112233 %[fx:w-1],%[fx:h-1] #778899' "$MAGICK_ARGS" || fail 'no background fallback for accentAlt'

# Rounding 0 draws square corners with a plain rectangle.
jq '.style.rounding = 0' "$test_root/theme.json" >"$test_root/square.json"
FRAME_THEME_FILE="$test_root/square.json" "$frame" "$test_root/shots/shot.png" >/dev/null
grep -Fxq 'rectangle 0,0 %[fx:w-1],%[fx:h-1]' "$MAGICK_ARGS" || fail 'rounding 0 does not draw a plain rectangle'

# An input without an extension frames beside itself, even in a dotted directory.
mkdir -p "$test_root/b.dir"
printf png >"$test_root/b.dir/shot"
output=$("$frame" "$test_root/b.dir/shot")
[[ $output == "$test_root/b.dir/shot-framed.png" ]] || fail "extensionless input framed to $output"

# --dry-run prints the plan and runs nothing.
rm -f "$MAGICK_ARGS" "$COPY_ARGS"
plan=$("$frame" --dry-run "$test_root/shots/shot.png")
[[ $plan == "+ magick "*"#112233"*"#445566"*"shot-framed.png"* ]] || fail "dry-run did not print the magick command: $plan"
[[ $plan == *"+ wl-copy -t image/png < $test_root/shots/shot-framed.png" ]] || fail 'dry-run did not print the copy'
[[ ! -e $MAGICK_ARGS && ! -e $COPY_ARGS ]] || fail 'dry-run ran magick or wl-copy'

# A missing theme is a clear error, not a crash.
if err=$(FRAME_THEME_FILE="$test_root/missing.json" "$frame" "$test_root/shots/shot.png" 2>&1); then
  fail 'missing theme file did not fail'
fi
[[ $err == "frame: theme file not found: $test_root/missing.json"* ]] || fail "unclear missing-theme error: $err"
[[ ! -e $MAGICK_ARGS ]] || fail 'magick ran without a theme'

status=0; "$frame" >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail 'no image argument did not exit 2'
status=0; "$frame" --bogus x.png >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail 'unknown option did not exit 2'
"$frame" --help | grep -q '^usage:' || fail '--help printed no usage'

# capture.sh --frame --dry-run selects, then prints both commands without
# running grim or magick.
printf '%s\n' '#!/usr/bin/env bash' 'printf "0,0 100x100\n"' >"$test_root/bin/slurp"
cat >"$test_root/bin/grim" <<'SH'
#!/usr/bin/env bash
touch "$GRIM_RAN"
printf png >"${!#}"
SH
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$test_root/bin/hyprpicker"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$test_root/bin/hyprctl"
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$NOTIFY_ARGS"
SH
chmod +x "$test_root/bin/"*
export XDG_RUNTIME_DIR="$test_root/runtime" SCREENSHOT_DIR="$test_root/screenshots"
export GRIM_RAN="$test_root/grim.ran" NOTIFY_ARGS="$test_root/notify.args"

plan=$("$capture_dir/capture.sh" screenshot region --frame --dry-run)
[[ $plan == "+ grim -g 0\\,0\\ 100x100 $SCREENSHOT_DIR/screenshot-"*".png"$'\n'"+ magick "*"#112233"* ]] ||
  fail "capture dry-run did not print the grim and magick commands: $plan"
[[ ! -e $GRIM_RAN && ! -e $MAGICK_ARGS && ! -e $COPY_ARGS ]] || fail 'capture dry-run captured or framed'
[[ -z $(find "$SCREENSHOT_DIR" -type f 2>/dev/null) ]] || fail 'capture dry-run wrote a file'

# capture.sh --frame saves the original, frames it beside it, and copies it.
framed=$("$capture_dir/capture.sh" screenshot region --frame)
[[ $framed == "$SCREENSHOT_DIR/screenshot-"*"-framed.png" && -f $framed ]] || fail "no framed copy saved: $framed"
[[ -f ${framed%-framed.png}.png ]] || fail 'the original was not kept beside the framed copy'
[[ $(<"$COPY_DATA") == framed ]] || fail 'capture --frame did not copy the framed image'
grep -Fxq 'Screenshot framed' "$NOTIFY_ARGS" || fail 'no framed notification'

# FRAME_JQ replaces jq when reading the theme.
cat >"$test_root/jq-stand-in" <<'SH'
#!/usr/bin/env bash
touch "$JQ_RAN"
exec jq "$@"
SH
chmod +x "$test_root/jq-stand-in"
JQ_RAN="$test_root/jq.ran" FRAME_JQ="$test_root/jq-stand-in" "$frame" "$test_root/shots/shot.png" >/dev/null
[[ -e $test_root/jq.ran ]] || fail 'FRAME_JQ was not used to read the theme'

# The clipboard checks honour FRAME_WL_COPY, and a dry run needs neither grim
# nor wl-copy. The system PATH here has both removed.
mkdir -p "$test_root/sysbin" "$test_root/stubs"
for tool in /usr/bin/* /bin/*; do
  case ${tool##*/} in grim|wl-copy) ;; *) ln -sf "$tool" "$test_root/sysbin/" ;; esac
done
for tool in slurp hyprpicker hyprctl notify-send magick; do ln -s "$test_root/bin/$tool" "$test_root/stubs/"; done
bare_path="$test_root/stubs:$test_root/sysbin"
PATH=$bare_path "$capture_dir/capture.sh" screenshot region --frame --dry-run >/dev/null ||
  fail 'frame dry-run needed grim or wl-copy'
ln -s "$test_root/bin/grim" "$test_root/stubs/"
framed=$(PATH=$bare_path FRAME_WL_COPY="$test_root/bin/wl-copy" "$capture_dir/capture.sh" screenshot region --frame) ||
  fail 'capture --frame ignored FRAME_WL_COPY in its preflight'
[[ -f $framed ]] || fail "no framed copy with FRAME_WL_COPY: $framed"

# A clipboard failure after framing names the saved framed copy.
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$test_root/broken-copy"
chmod +x "$test_root/broken-copy"
: >"$NOTIFY_ARGS"
if FRAME_WL_COPY="$test_root/broken-copy" "$capture_dir/capture.sh" screenshot region --frame >/dev/null 2>&1; then
  fail 'a clipboard failure did not fail the capture'
fi
saved=$(sed -n 's/^Could not copy framed screenshot; saved at //p' "$NOTIFY_ARGS")
[[ $saved == "$SCREENSHOT_DIR/screenshot-"*"-framed.png" && -f $saved ]] ||
  fail "clipboard failure did not report the framed copy: $(<"$NOTIFY_ARGS")"

# Real ImageMagick on a tiny image, when it is installed (CI installs it).
real_magick=$(PATH=${PATH#"$test_root/bin:"} command -v magick || true)
if [[ -z $real_magick ]]; then
  printf 'skip: magick not installed\n'
else
  "$real_magick" -size 40x30 xc:'#202020' "$test_root/tiny.png"
  real=$(FRAME_MAGICK="$real_magick" "$frame" "$test_root/tiny.png")
  read -r w h <<<"$("$real_magick" identify -format '%w %h' "$real")"
  ((w > 40 && h > 30)) || fail "framed image ${w}x${h} is not larger than 40x30"
  corner=$("$real_magick" "$real" -format '%[hex:p{0,0}]' info:)
  [[ ${corner:0:6} == 112233 ]] || fail "backdrop corner is #$corner, not the accent"
  # Rounding 0 keeps every capture pixel visible, square corners included.
  square=$(FRAME_THEME_FILE="$test_root/square.json" FRAME_MAGICK="$real_magick" "$frame" "$test_root/tiny.png")
  shown=$("$real_magick" "$square" -alpha off -fill black +opaque '#202020' -fill white -opaque '#202020' \
    -format '%[fx:round(mean*w*h)]' info:)
  [[ $shown == 1200 ]] || fail "rounding 0 shows $shown of 1200 capture pixels"
fi

printf 'ok: frame.sh themed backdrop, clipboard copy, dry-run, missing theme, capture --frame\n'
