#!/usr/bin/env bash
set -euo pipefail

PICTURES_DIR="${TRANSCODE_PICTURES_DIR:-$HOME/Pictures}"
VIDEOS_DIR="${TRANSCODE_VIDEOS_DIR:-$HOME/Videos}"
TRANSCODE_BIN="${TRANSCODE_BIN:-$HOME/.local/bin/transcode}"
ROFI_THEME="${TRANSCODE_ROFI_THEME:-$HOME/.config/rofi/current-theme.rasi}"
[[ -r "$ROFI_THEME" ]] || ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Transcode" -u critical "Transcode" "$1" 2>/dev/null || true
  else
    printf 'Transcode: %s\n' "$1" >&2
  fi
}

command -v rofi >/dev/null 2>&1 || { notify_error "rofi is not installed"; exit 1; }
[[ -x "$TRANSCODE_BIN" ]] || { notify_error "transcode command is not installed"; exit 1; }

runtime_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/transcode-menu.XXXXXX") || exit 1
index_file="$runtime_dir/index"
menu_file="$runtime_dir/menu"
trap 'rm -rf -- "$runtime_dir"' EXIT INT TERM

declare -a roots=()
[[ -d "$PICTURES_DIR" ]] && roots+=("$PICTURES_DIR")
[[ -d "$VIDEOS_DIR" ]] && roots+=("$VIDEOS_DIR")
if ((${#roots[@]} == 0)); then
  notify_error "Neither Pictures nor Videos exists"
  exit 1
fi

find "${roots[@]}" -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
     -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' -o -iname '*.tif' \
     -o -iname '*.tiff' -o -iname '*.bmp' -o -iname '*.mp4' -o -iname '*.mov' \
     -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.avi' -o -iname '*.m4v' \
     -o -iname '*.mpeg' -o -iname '*.mpg' \) -print0 |
  sort -z > "$index_file"

if [[ ! -s "$index_file" ]]; then
  notify_error "No supported images or videos found"
  exit 1
fi

number=0
while IFS= read -r -d '' path; do
  number=$((number + 1))
  display="$path"
  if [[ "$path" == "$PICTURES_DIR"/* ]]; then
    display="Pictures/${path#"$PICTURES_DIR"/}"
  elif [[ "$path" == "$VIDEOS_DIR"/* ]]; then
    display="Videos/${path#"$VIDEOS_DIR"/}"
  fi
  display=${display//$'\n'/\\n}
  display=${display//$'\r'/\\r}
  printf '%06d\t%s\n' "$number" "$display" >> "$menu_file"
done < "$index_file"

selection=$(rofi -dmenu -i -matching fuzzy -sorting-method fzf \
  -p "Transcode" -mesg "Choose an image or video" -theme "$ROFI_THEME" \
  < "$menu_file") || exit 0
[[ -n "$selection" ]] || exit 0

selected_number=${selection%%$'\t'*}
[[ "$selected_number" =~ ^[0-9]{6}$ ]] || exit 0
selected_index=$((10#$selected_number))
selected_path=""
number=0
while IFS= read -r -d '' path; do
  number=$((number + 1))
  if (( number == selected_index )); then
    selected_path="$path"
    break
  fi
done < "$index_file"
[[ -n "$selected_path" ]] || exit 0

mime=$(file -Lb --mime-type -- "$selected_path" 2>/dev/null || true)
extension="${selected_path##*.}"
extension="${extension,,}"
case "$mime:$extension" in
  image/*:*|*:jpg|*:jpeg|*:png|*:webp|*:heic|*:heif|*:avif|*:tif|*:tiff|*:bmp)
    format_items=$'jpg — transparency becomes white\npng — preserve transparency'
    preset_items=$'High — maximum width 3160 px\nMedium — maximum width 2160 px\nLow — maximum width 1080 px'
    ;;
  video/*:*|*:mp4|*:mov|*:mkv|*:webm|*:avi|*:m4v|*:mpeg|*:mpg)
    format_items=$'mp4 — compatible H.264\ngif — palette optimized'
    preset_items=$'4k — maximum 3840×2160\n1080p — maximum 1920×1080\n720p — maximum 1280×720'
    ;;
  *) notify_error "Unsupported media type"; exit 1 ;;
esac

format_choice=$(printf '%s\n' "$format_items" | rofi -dmenu -i -no-custom \
  -p "Format" -mesg "$(basename -- "$selected_path")" -theme "$ROFI_THEME") || exit 0
[[ -n "$format_choice" ]] || exit 0
output_format=${format_choice%% *}

preset_choice=$(printf '%s\n' "$preset_items" | rofi -dmenu -i -no-custom \
  -p "Size" -mesg "$output_format output" -theme "$ROFI_THEME") || exit 0
[[ -n "$preset_choice" ]] || exit 0
preset=${preset_choice%% *}
preset=${preset,,}

"$TRANSCODE_BIN" --copy --notify "$selected_path" "$output_format" "$preset" >/dev/null
