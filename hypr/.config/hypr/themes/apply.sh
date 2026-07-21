#!/usr/bin/env bash
# apply.sh — Apply a Hyprland theme across all components
#
# Usage: apply.sh <theme-name>
#   theme-name must match a key in themes.json (case-sensitive)
#
# Reads themes.json, generates per-component config files,
# applies wallpaper, and reloads affected services.
#
# Dependencies: jq, find, sed
# Optional: hyprctl, swaync, kitty, qs (for live reload)

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$SCRIPT_DIR"
THEMES_JSON="$THEMES_DIR/themes.json"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

HYPR_DIR="$CONFIG_HOME/hypr"
HYPR_CONF_DIR="$HYPR_DIR/conf"
HYPR_THEMES="$HYPR_DIR/themes"
THEME_STATE="$HYPR_THEMES/current-theme"

HYPRLOCK_DIR="$CONFIG_HOME/hyprlock"
HYPRLOCK_LAYOUTS="$HYPRLOCK_DIR/layouts"

ROFI_DIR="$CONFIG_HOME/rofi"
ROFI_THEMES="$ROFI_DIR/color-themes"

WOFI_DIR="$CONFIG_HOME/wofi"

KITTY_DIR="$CONFIG_HOME/kitty"
KITTY_THEMES="$KITTY_DIR/theme"

SWAYNC_DIR="$CONFIG_HOME/swaync"

NOCTALIA_DIR="$CONFIG_HOME/noctalia"

FASTFETCH_DIR="$CONFIG_HOME/fastfetch"

ZSH_FILE="$HOME/.p10k.zsh"

WALLPAPER_DIR="$HOME/Wallpapers"
THEME_WALLPAPERS="$WALLPAPER_DIR/theme"
HYPRLOCK_WALL_DIR="$CONFIG_HOME/hyprlock/wallpapers"

# ── Helpers ─────────────────────────────────────────────────────────────────
notify() {
  local title="$1" message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Convert a 6-character hex color to "r, g, b" decimal tuple
hex_to_rgb() {
  local hex="$1"
  local r g b
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))
  printf '%d,%d,%d' "$r" "$g" "$b"
}

require_cmd jq

# ── Parse arguments ─────────────────────────────────────────────────────────
THEME_NAME="${1:-}"
if [ -z "$THEME_NAME" ]; then
  die "Usage: apply.sh <theme-name>"
fi

# ── Load theme data ─────────────────────────────────────────────────────────
if [ ! -f "$THEMES_JSON" ]; then
  die "Themes database not found: $THEMES_JSON"
fi

# Validate theme exists
theme_exists() {
  jq -e ".themes[\"$THEME_NAME\"]" "$THEMES_JSON" >/dev/null 2>&1
}

if ! theme_exists; then
  available=$(jq -r '.themes | keys[]' "$THEMES_JSON" | tr '\n' ', ' | sed 's/, $//')
  die "Theme '$THEME_NAME' not found. Available: $available"
fi

# Helper to get a theme value — returns raw JSON value
tv() {
  jq -r ".themes[\"$THEME_NAME\"]$1" "$THEMES_JSON"
}

pal() {
  jq -r ".themes[\"$THEME_NAME\"].palette[\"$1\"]" "$THEMES_JSON"
}

# Pre-compute values we need repeatedly
THEME_SLUG=$(echo "$THEME_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

PAL_BASE=$(pal 'base')
PAL_MANTLE=$(pal 'mantle')
PAL_TEXT=$(pal 'text')
PAL_SURFACE0=$(pal 'surface0')
PAL_SURFACE1=$(pal 'surface1')
PAL_OVERLAY0=$(pal 'overlay0')
PAL_SUBTEXT0=$(pal 'subtext0')
PAL_SUBTEXT1=$(pal 'subtext1')
PAL_BLUE=$(pal 'blue')
PAL_MAUVE=$(pal 'mauve')
PAL_TEAL=$(pal 'teal')
PAL_GREEN=$(pal 'green')
PAL_RED=$(pal 'red')
PAL_YELLOW=$(pal 'yellow')
PAL_PEACH=$(pal 'peach')
PAL_PINK=$(pal 'pink')
PAL_ROSEWATER=$(pal 'rosewater')
PAL_CRUST=$(pal 'crust')

PAL_BASE_RGB=$(hex_to_rgb "$PAL_BASE")
PAL_MANTLE_RGB=$(hex_to_rgb "$PAL_MANTLE")
PAL_TEXT_RGB=$(hex_to_rgb "$PAL_TEXT")
PAL_SURFACE0_RGB=$(hex_to_rgb "$PAL_SURFACE0")
PAL_BLUE_RGB=$(hex_to_rgb "$PAL_BLUE")
PAL_MAUVE_RGB=$(hex_to_rgb "$PAL_MAUVE")
PAL_RED_RGB=$(hex_to_rgb "$PAL_RED")
PAL_GREEN_RGB=$(hex_to_rgb "$PAL_GREEN")

HYPR_AB1=$(tv '.hyprland.active_border_1')
HYPR_AB2=$(tv '.hyprland.active_border_2')
HYPR_AB_ANGLE=$(tv '.hyprland.active_border_angle')
HYPR_IB=$(tv '.hyprland.inactive_border')
HYPR_BS=$(tv '.hyprland.border_size')
HYPR_ROUND=$(tv '.hyprland.rounding')
HYPR_ROUND_POW=$(tv '.hyprland.rounding_power')
HYPR_GIN=$(tv '.hyprland.gaps_in')
HYPR_GOUT=$(tv '.hyprland.gaps_out')
HYPR_AO=$(tv '.hyprland.active_opacity')
HYPR_IO=$(tv '.hyprland.inactive_opacity')
HYPR_SHADOW=$(tv '.hyprland.shadow_enabled')
HYPR_SHADOW_COL=$(tv '.hyprland.shadow_color')
HYPR_SHADOW_RANGE=$(tv '.hyprland.shadow_range')
HYPR_BLUR_EN=$(tv '.hyprland.blur_enabled')
HYPR_BLUR_SZ=$(tv '.hyprland.blur_size')
HYPR_BLUR_PASS=$(tv '.hyprland.blur_passes')
FF_COLOR=$(tv '.fastfetch_keycolor')
P10K_COLOR=$(tv '.p10k_color')
WALL_NAME="$(tv '.wallpaper')"

# ══════════════════════════════════════════════════════════════════════════════
# Create directories
# ══════════════════════════════════════════════════════════════════════════════
mkdir -p "$HYPR_CONF_DIR" "$ROFI_THEMES" "$KITTY_THEMES" \
         "$HYPRLOCK_LAYOUTS" "$HYPRLOCK_WALL_DIR" \
         "$SWAYNC_DIR" "$NOCTALIA_DIR" "$FASTFETCH_DIR" \
         "$THEME_WALLPAPERS"

# ══════════════════════════════════════════════════════════════════════════════
# 1. Hyprland decorations.conf
# ══════════════════════════════════════════════════════════════════════════════
cat > "$HYPR_CONF_DIR/decorations.conf" << DEOF
# ~/.config/hypr/decorations.conf
# GENERATED BY THEME SWITCHER — DO NOT EDIT DIRECTLY
# Theme: ${THEME_NAME}

general {
    border_size = ${HYPR_BS}
    gaps_in = ${HYPR_GIN}
    gaps_out = ${HYPR_GOUT}
    float_gaps = ${HYPR_GOUT}

    col.active_border = rgba(${HYPR_AB1}ff) rgba(${HYPR_AB2}ff) ${HYPR_AB_ANGLE}
    col.inactive_border = rgba(${HYPR_IB}ff)
}

decoration {
    rounding = ${HYPR_ROUND}
    rounding_power = ${HYPR_ROUND_POW}

    active_opacity = ${HYPR_AO}
    inactive_opacity = ${HYPR_IO}
    fullscreen_opacity = ${HYPR_AO}

    shadow {
        enabled = ${HYPR_SHADOW}
        range = ${HYPR_SHADOW_RANGE}
        render_power = 3
        color = rgba(${HYPR_SHADOW_COL})
    }

    blur {
        enabled = ${HYPR_BLUR_EN}
        size = ${HYPR_BLUR_SZ}
        passes = ${HYPR_BLUR_PASS}
        ignore_opacity = true
        new_optimizations = true
        xray = false
        noise = 0.01
        contrast = 0.95
        brightness = 0.82
        vibrancy = 0.18
    }
}
DEOF
printf '  ✓ decorations.conf\n'

# ══════════════════════════════════════════════════════════════════════════════
# 2. Hyprlock colors.conf
# ══════════════════════════════════════════════════════════════════════════════
cat > "$HYPRLOCK_DIR/colors.conf" << HLOCKEOF
# ~/.config/hyprlock/colors.conf
# GENERATED BY THEME SWITCHER — DO NOT EDIT DIRECTLY
# Theme: ${THEME_NAME}

# Primary
\$primary   = ${PAL_BASE}
\$text      = ${PAL_TEXT}
\$bg        = ${PAL_MANTLE}

# Accents
\$accent_1  = ${PAL_MAUVE}
\$accent_2  = ${PAL_BLUE}
\$accent_3  = ${PAL_TEAL}
\$accent_4  = ${PAL_PINK}

# Surfaces
\$surface_1 = ${PAL_SURFACE0}
\$surface_2 = ${PAL_SURFACE1}
\$overlay_1 = ${PAL_OVERLAY0}

# rgba variants
\$primary_rgba   = rgba(${PAL_BASE_RGB},0.9)
\$text_rgba      = rgba(${PAL_TEXT_RGB},0.9)
\$accent_1_rgba  = rgba(${PAL_MAUVE_RGB},0.9)
\$accent_2_rgba  = rgba(${PAL_BLUE_RGB},0.9)
\$accent_3_rgba  = rgba(${PAL_TEAL},0.9)
\$accent_4_rgba  = rgba(${PAL_PINK},0.9)
\$surface_1_rgba = rgba(${PAL_SURFACE0_RGB},0.9)
\$surface_2_rgba = rgba(${PAL_SURFACE1},0.9)

# Dimmed variants
\$primary_dim   = rgba(${PAL_BASE_RGB},0.5)
\$accent_1_dim  = rgba(${PAL_MAUVE_RGB},0.5)
\$accent_2_dim  = rgba(${PAL_BLUE_RGB},0.5)
HLOCKEOF
printf '  ✓ hyprlock colors.conf\n'

# ══════════════════════════════════════════════════════════════════════════════
# 3. Hyprlock layout (hyprlock.conf)
# ══════════════════════════════════════════════════════════════════════════════
cat > "$HYPRLOCK_LAYOUTS/hyprlock.conf" << HLAYOUT
# ~/.config/hyprlock/layouts/hyprlock.conf
# GENERATED BY THEME SWITCHER — DO NOT EDIT DIRECTLY
# Theme: ${THEME_NAME}

\$fn_greet=echo "<i> Hi \$USER :)</i>"
\$wall = \$HOME/.config/hyprlock/wallpapers/1.jpg

general {
  no_fade_in = true
  grace = 1
  disable_loading_bar = false
  hide_cursor = true
  ignore_empty_input = true
  text_trim = true
}

background {
    monitor =
    path = \$wall
    blur_passes = 2
    contrast = 0.8916
    brightness = 0.7172
    vibrancy = 0.1696
    vibrancy_darkness = 0
}

label {
    monitor =
    text = cmd[update:1000] echo -e "\$(date +"%H")"
    color = \$accent_1_rgba
    shadow_size = 3
    shadow_color = rgb(0,0,0)
    shadow_boost = 1.2
    font_size = 150
    font_family = AlfaSlabOne
    position = 0, -250
    halign = center
    valign = top
    zindex = 5
}

label {
    monitor =
    text = cmd[update:1000] echo -e "\$(date +"%M")"
    color = \$accent_2_rgba
    font_size = 150
    font_family = AlfaSlabOne
    position = 0, -420
    halign = center
    valign = top
    zindex = 5
}

label {
    monitor =
    text = cmd[update:1000] echo -e "\$(date +"%d %b %A")"
    color = \$accent_3_rgba
    font_size = 14
    font_family = JetBrains Mono Nerd Font Mono ExtraBold
    position = 0, -130
    halign = center
    valign = center
    zindex = 5
}

input-field {
    monitor =
    size = 250, 60
    outline_thickness = 0
    outer_color = rgba(0, 0, 0, 0)
    dots_size = 0.1
    dots_spacing = 1
    dots_center = true
    inner_color = \$accent_2_dim
    font_color = rgba(200, 200, 200, 0.5)
    fade_on_empty = true
    placeholder_text =<i>Use Me ;) </i>
    hide_input = false
    position = 0, -370
    halign = center
    valign = center
    zindex = 20
}

label {
    monitor =
    text = cmd[update:60000] \$fn_greet
    color = \$accent_1_rgba
    font_size = 17
    font_family = JetBrains Mono Nerd Font Mono
    position = 0, -250
    halign = center
    valign = center
}
HLAYOUT
printf '  ✓ hyprlock layout\n'

# ══════════════════════════════════════════════════════════════════════════════
# 4. Rofi color theme
# ══════════════════════════════════════════════════════════════════════════════
cat > "$ROFI_THEMES/${THEME_SLUG}.rasi" << ROFIT
/**
 * ${THEME_SLUG}.rasi
 * ${THEME_NAME} palette
 * GENERATED BY THEME SWITCHER
 */

@theme "~/.config/rofi/comet-glass.rasi"

* {
    bg0: rgba(${PAL_BASE_RGB}, 92%);
    bg1: rgba(${PAL_MANTLE_RGB}, 95%);
    bg2: #${PAL_SURFACE0};

    fg0: #${PAL_TEXT};
    fg1: #${PAL_SUBTEXT1};
    fg2: #${PAL_SUBTEXT0};

    accent: #${PAL_BLUE};
    accent-alt: #${PAL_MAUVE};
    border-col: #${PAL_OVERLAY0};
    urgent: #${PAL_RED};
    good: #${PAL_GREEN};

    window-border: rgba(${PAL_BLUE_RGB}, 45%);
    alt-bg: rgba(255, 255, 255, 3%);
    urgent-bg: rgba(${PAL_RED_RGB}, 10%);
    urgent-border: rgba(${PAL_RED_RGB}, 18%);
    active-bg: rgba(${PAL_GREEN_RGB}, 8%);
    active-border: rgba(${PAL_GREEN_RGB}, 16%);
    selected-bg: rgba(${PAL_BLUE_RGB}, 14%);
    selected-border: rgba(${PAL_BLUE_RGB}, 34%);
    selected-active-bg: rgba(${PAL_GREEN_RGB}, 14%);
    selected-active-border: rgba(${PAL_GREEN_RGB}, 32%);
    selected-urgent-bg: rgba(${PAL_RED_RGB}, 15%);
    selected-urgent-border: rgba(${PAL_RED_RGB}, 34%);
    button-selected-bg: rgba(${PAL_MAUVE_RGB}, 16%);
}
ROFIT
printf '  ✓ rofi theme\n'

# Symlink to current-theme.rasi so WIN+A (SUPER + A) uses the active theme
ln -sfn "$ROFI_THEMES/${THEME_SLUG}.rasi" "$ROFI_DIR/current-theme.rasi"
printf '  ✓ rofi current-theme.rasi link\n'

# ══════════════════════════════════════════════════════════════════════════════
# 5. Wofi style.css
# ══════════════════════════════════════════════════════════════════════════════
cat > "$WOFI_DIR/style.css" << WOFIS
/* ~/.config/wofi/style.css */
/* GENERATED BY THEME SWITCHER — DO NOT EDIT DIRECTLY */
/* Theme: ${THEME_NAME} */

window {
  margin: 0px;
  border: 2px solid rgba(${PAL_BLUE_RGB}, 0.35);
  border-radius: 18px;
  background-color: rgba(${PAL_BASE_RGB}, 0.88);
  font-family: "JetBrainsMono Nerd Font";
  font-size: 14px;
  color: #${PAL_TEXT};
}

#outer-box {
  margin: 0px;
  padding: 14px;
  border-radius: 18px;
  background-color: rgba(${PAL_BASE_RGB}, 0.82);
}

#input {
  margin: 0px 0px 12px 0px;
  padding: 12px 14px;
  border: none;
  border-radius: 14px;
  background-color: rgba(${PAL_SURFACE0_RGB}, 0.55);
  color: #${PAL_TEXT};
}

#input:focus {
  outline: none;
  box-shadow: none;
  border: 1px solid rgba(${PAL_BLUE_RGB}, 0.45);
}

#entry {
  padding: 10px 12px;
  border-radius: 12px;
  background-color: transparent;
}

#entry:selected {
  background: linear-gradient(
    90deg,
    rgba(${PAL_BLUE_RGB}, 0.24),
    rgba(${PAL_MAUVE_RGB}, 0.20)
  );
  border: 1px solid rgba(${PAL_BLUE_RGB}, 0.32);
}

#text {
  color: #${PAL_TEXT};
}

#entry:selected #text {
  color: #ffffff;
  font-weight: 600;
}
WOFIS
printf '  ✓ wofi style\n'

# ══════════════════════════════════════════════════════════════════════════════
# 6. Kitty theme
# ══════════════════════════════════════════════════════════════════════════════
cat > "$KITTY_THEMES/${THEME_SLUG}.conf" << KITTYT
# ${THEME_NAME} — Kitty theme
# GENERATED BY THEME SWITCHER
background #${PAL_BASE}
foreground #${PAL_TEXT}
cursor #${PAL_ROSEWATER}
cursor_text_color #${PAL_BASE}
selection_background #${PAL_SURFACE1}
selection_foreground #${PAL_TEXT}
url_color #${PAL_BLUE}
active_border_color #${PAL_MAUVE}
inactive_border_color #${PAL_OVERLAY0}
bell_border_color #${PAL_RED}
color0 #${PAL_SURFACE1}
color1 #${PAL_RED}
color2 #${PAL_GREEN}
color3 #${PAL_YELLOW}
color4 #${PAL_BLUE}
color5 #${PAL_MAUVE}
color6 #${PAL_TEAL}
color7 #${PAL_SUBTEXT1}
color8 #${PAL_OVERLAY0}
color9 #${PAL_RED}
color10 #${PAL_GREEN}
color11 #${PAL_YELLOW}
color12 #${PAL_BLUE}
color13 #${PAL_MAUVE}
color14 #${PAL_TEAL}
color15 #${PAL_TEXT}
KITTYT

# Update kitty current-theme symlink
ln -sfn "$KITTY_THEMES/${THEME_SLUG}.conf" "$KITTY_THEMES/current-theme.conf"

# Ensure kitty.conf includes the current theme
KITTY_CONF="$KITTY_DIR/kitty.conf"
INCLUDE_LINE="include $KITTY_THEMES/current-theme.conf"
if [ -f "$KITTY_CONF" ]; then
  TMP="$(mktemp)"
  grep -vxF "$INCLUDE_LINE" "$KITTY_CONF" >"$TMP" || true
  printf '%s\n' "$INCLUDE_LINE" >>"$TMP"
  mv "$TMP" "$KITTY_CONF"
fi
printf '  ✓ kitty theme\n'

# ══════════════════════════════════════════════════════════════════════════════
# 7. SwayNC style.css
# ══════════════════════════════════════════════════════════════════════════════
cat > "$SWAYNC_DIR/style.css" << SWAYNCS
/* ~/.config/swaync/style.css */
/* GENERATED BY THEME SWITCHER — DO NOT EDIT DIRECTLY */
/* Theme: ${THEME_NAME} */

@define-color base #${PAL_BASE};
@define-color surface #${PAL_SURFACE0};
@define-color card #${PAL_SURFACE1};
@define-color border #${PAL_OVERLAY0};
@define-color text #${PAL_TEXT};
@define-color muted #${PAL_SUBTEXT0};
@define-color accent #${PAL_BLUE};
@define-color accent_soft #${PAL_MAUVE};
@define-color low #${PAL_SUBTEXT0};
@define-color urgent #${PAL_RED};
SWAYNCS

# Append the structural CSS (shared across all themes)
# We store the structural layout separately so it doesn't need to be repeated
cat >> "$SWAYNC_DIR/style.css" << 'SWAYNCBODY'

* {
  font-family: "JetBrainsMono Nerd Font", "Inter", sans-serif;
  font-size: 14px;
  --notification-icon-size: 54px;
  --notification-group-icon-size: 42px;
  --mpris-album-art-icon-size: 72px;
  --widget-volume-row-icon-size: 20px;
}

.blank-window { background: alpha(@base, 0.20); }
.floating-notifications, .control-center, .control-center-list { background: transparent; }

.control-center {
  background: alpha(@base, 0.80);
  border: 1px solid alpha(@border, 0.78);
  border-radius: 24px;
  box-shadow: 0 18px 40px 0 rgba(0, 0, 0, 0.35);
  color: @text;
  padding: 18px;
}

.widget-title, .widget-dnd, .widget-volume, .widget-backlight,
.widget-mpris, .widget-buttons-grid, .widget-inhibitors, .widget-label {
  background: alpha(@surface, 0.88);
  border: 1px solid alpha(@border, 0.70);
  border-radius: 18px;
  box-shadow: none;
  padding: 14px 16px;
  margin-bottom: 12px;
}

.widget-title { background: transparent; border: none; padding: 4px 4px 12px 4px; }
.widget-title label { color: @text; font-size: 18px; font-weight: 700; }
.widget-title > button {
  background: alpha(@surface, 0.88); color: @text;
  border: 1px solid alpha(@border, 0.72); border-radius: 14px; padding: 7px 14px;
}
.widget-title > button:hover { background: alpha(@accent_soft, 0.22); border-color: alpha(@accent, 0.60); }

.widget-dnd label, .widget-volume label, .widget-backlight label {
  color: @text; font-weight: 600;
}

.widget-dnd switch { background: alpha(@card, 0.95); border: 1px solid alpha(@border, 0.72); border-radius: 999px; }
.widget-dnd switch slider { background: @text; border-radius: 999px; min-width: 18px; min-height: 18px; }
.widget-dnd switch:checked { background: alpha(@accent, 0.92); border-color: alpha(@accent, 0.92); }

.widget-volume trough, .widget-backlight trough, scale trough {
  background: alpha(@muted, 0.16); border: none; border-radius: 999px; min-height: 10px;
}
.widget-volume highlight, .widget-backlight highlight, scale highlight {
  background: @accent; border-radius: 999px; min-height: 10px;
}
.widget-volume slider, .widget-backlight slider, scale slider {
  background: @text; border-radius: 999px; min-width: 16px; min-height: 16px;
  box-shadow: 0 0 0 4px alpha(@accent, 0.18);
}

.control-center-list-placeholder > label { color: @muted; font-style: italic; }
.notification-row { outline: none; margin: 0 0 12px 0; padding: 0; }
.notification-row:hover, .notification-row:focus { background: transparent; }

.control-center .notification-background, .floating-notifications .notification-background {
  background: alpha(@surface, 0.90); border: 1px solid alpha(@border, 0.72);
  border-radius: 20px; box-shadow: 0 12px 28px 0 rgba(0, 0, 0, 0.28);
}
.control-center .notification-background { padding: 16px; }
.floating-notifications .notification-background { padding: 16px; margin: 8px 12px 0 12px; }

.notification { background: transparent; color: @text; }
.notification-content { background: transparent; padding: 0; margin: 0; }
.notification-default-action { background: transparent; border: none; box-shadow: none; padding: 0; margin: 0; }
.notification-default-action:hover { background: transparent; }

.notification.low { border-left: 3px solid alpha(@low, 0.88); padding-left: 10px; }
.notification.normal { border-left: 3px solid alpha(@accent, 0.88); padding-left: 10px; }
.notification.critical { border-left: 3px solid alpha(@urgent, 0.92); padding-left: 10px; }

.summary { color: @text; font-size: 15px; font-weight: 700; margin-bottom: 4px; }
.time { color: @muted; font-size: 12px; font-weight: 600; margin-right: 38px; }
.body { color: @muted; font-size: 13px; }
.notification image { margin-right: 14px; }

.close-button {
  background: alpha(@card, 0.96); color: @muted;
  border: 1px solid alpha(@border, 0.72); border-radius: 999px;
  min-width: 32px; min-height: 32px; box-shadow: none;
}
.close-button:hover { background: alpha(@urgent, 0.18); color: @text; border-color: alpha(@urgent, 0.56); }

.notification-action, .notification-alt-actions button {
  background: alpha(@card, 0.92); color: @text;
  border: 1px solid alpha(@border, 0.68); border-radius: 12px;
  box-shadow: none; padding: 8px 12px; margin: 10px 8px 0 0;
}
.notification-action:hover, .notification-alt-actions button:hover {
  background: alpha(@accent_soft, 0.22); border-color: alpha(@accent, 0.56);
}
.notification-group { margin-top: 6px; }
SWAYNCBODY
printf '  ✓ swaync style\n'

# ══════════════════════════════════════════════════════════════════════════════
# 8. Noctalia colors.json
# ══════════════════════════════════════════════════════════════════════════════
cat > "$NOCTALIA_DIR/colors.json" << NOCTJSON
{
  "mError": "#${PAL_RED}",
  "mHover": "#${PAL_TEAL}",
  "mOnError": "#${PAL_CRUST}",
  "mOnHover": "#${PAL_CRUST}",
  "mOnPrimary": "#${PAL_CRUST}",
  "mOnSecondary": "#${PAL_CRUST}",
  "mOnSurface": "#${PAL_TEXT}",
  "mOnSurfaceVariant": "#${PAL_SUBTEXT1}",
  "mOnTertiary": "#${PAL_CRUST}",
  "mOutline": "#${PAL_OVERLAY0}",
  "mPrimary": "#${PAL_MAUVE}",
  "mSecondary": "#${PAL_PEACH}",
  "mShadow": "#${PAL_CRUST}",
  "mSurface": "#${PAL_BASE}",
  "mSurfaceVariant": "#${PAL_SURFACE0}",
  "mTertiary": "#${PAL_TEAL}"
}
NOCTJSON
printf '  ✓ noctalia colors\n'

# ══════════════════════════════════════════════════════════════════════════════
# 9. Fastfetch config — update key colors
# ══════════════════════════════════════════════════════════════════════════════
FF_CONFIG="$FASTFETCH_DIR/config.jsonc"
if [ -f "$FF_CONFIG" ]; then
  sed -i "s/\"keyColor\": \"[a-z]*\"/\"keyColor\": \"${FF_COLOR}\"/g" "$FF_CONFIG"
  printf '  ✓ fastfetch colors\n'
else
  printf '  - fastfetch config not found, skipping\n'
fi

# ══════════════════════════════════════════════════════════════════════════════
# 10. Wallpaper
# ══════════════════════════════════════════════════════════════════════════════
WALL_DEST="${HYPRLOCK_WALL_DIR}/1.jpg"
WALL_FOUND=false

for ext in jpg png webp; do
  if [ -f "${THEME_WALLPAPERS}/${WALL_NAME}.${ext}" ]; then
    cp "${THEME_WALLPAPERS}/${WALL_NAME}.${ext}" "$WALL_DEST" 2>/dev/null || true
    WALL_FOUND=true
    printf '  ✓ wallpaper: %s.%s\n' "$WALL_NAME" "$ext"
    break
  fi
done

if [ "$WALL_FOUND" = false ]; then
  printf '  - wallpaper not found at %s/*.{jpg,png,webp}, skipping\n' "${THEME_WALLPAPERS}/${WALL_NAME}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 11. P10k — update OS icon color to match theme
# ══════════════════════════════════════════════════════════════════════════════
if [ -f "$ZSH_FILE" ]; then
  sed -i "s/^  typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION=.*/  typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='%F{${P10K_COLOR}}%f'/" "$ZSH_FILE" 2>/dev/null || true
  printf '  ✓ p10k OS icon color\n'
else
  printf '  - .p10k.zsh not found, skipping\n'
fi

# ══════════════════════════════════════════════════════════════════════════════
# 12. Save theme state
# ══════════════════════════════════════════════════════════════════════════════
printf '%s' "$THEME_NAME" > "$THEME_STATE"

# ══════════════════════════════════════════════════════════════════════════════
# 13. Reload services
# ══════════════════════════════════════════════════════════════════════════════
RELOADS=""

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 && RELOADS="${RELOADS} hyprland" || true
fi

if command -v swaync >/dev/null 2>&1; then
  swaync-client --reload-config 2>/dev/null && RELOADS="${RELOADS} swaync" || true
fi

if command -v kitty >/dev/null 2>&1; then
  kitty @ set-colors --all "$KITTY_THEMES/${THEME_SLUG}.conf" >/dev/null 2>&1 && RELOADS="${RELOADS} kitty" || true
fi

if command -v qs >/dev/null 2>&1; then
  qs -c noctalia-shell ipc call colorScheme set "$THEME_NAME" >/dev/null 2>&1 && RELOADS="${RELOADS} noctalia" || true
fi

notify "Theme Switcher" "Applied: ${THEME_NAME}"
printf '\n✓ Theme "%s" applied successfully\n' "$THEME_NAME"
if [ -n "$RELOADS" ]; then
  printf '  Reloaded:%s\n' "$RELOADS"
fi