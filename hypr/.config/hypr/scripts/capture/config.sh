#!/usr/bin/env bash
# =============================================================================
# capture/config.sh — every user-adjustable value for the capture system
#
# This is THE place to change capture behaviour. Nothing below is duplicated in
# the other capture scripts; they all source this file.
#
# Every value honours a pre-existing environment variable, so you can also
# override any of them per-invocation without editing this file:
#     SCREENRECORD_FPS=30 capture.sh record start
#
# The capture KEY is not here: it is Hyprland syntax, not shell, and lives in
# conf/variables.lua as $captureKey.
# =============================================================================

# --- screenshots -------------------------------------------------------------
# Matches the folder the previous Screenshot.sh already used, so old and new
# captures stay together. Note ~/.config/user-dirs.dirs does not exist on this
# machine, which makes `xdg-user-dir PICTURES` return $HOME -- hence an explicit
# default rather than an XDG lookup that would litter the home directory.
: "${SCREENSHOT_DIR:=$HOME/Pictures/screenshot}"

# Opened by the "Edit" notification action. Empty disables the action.
: "${SCREENSHOT_EDITOR:=satty --copy-command wl-copy --filename}"

# grim omits the pointer unless asked; set to 1 to bake the cursor in.
: "${SCREENSHOT_CURSOR:=0}"

# --- screen recording --------------------------------------------------------
: "${SCREENRECORD_DIR:=$HOME/Videos/screenrecording}"
: "${SCREENRECORD_FPS:=60}"

# Recordings larger than this are scaled down to it. Both monitors here are
# under 4K, so this is inert today; it exists for a future high-DPI display.
: "${SCREENRECORD_MAX_RESOLUTION:=3840x2160}"

# Seconds trimmed from the head of a recording to drop encoder startup frames.
# 0 keeps the fast stream-copy path; any non-zero value forces a re-encode.
: "${SCREENRECORD_TRIM:=0}"

# Loudness-normalise the audio track (needs a re-encode). Off by default.
: "${SCREENRECORD_NORMALIZE:=0}"
: "${SCREENRECORD_LOUDNESS:=-14}"    # LUFS integrated
: "${SCREENRECORD_TRUE_PEAK:=-1.5}"  # dBTP
: "${SCREENRECORD_LRA:=11}"          # LU

# Used only when a re-encode is unavoidable.
: "${SCREENRECORD_X264_PRESET:=veryfast}"
: "${SCREENRECORD_X264_CRF:=20}"

# Player for the "Open" notification action.
: "${SCREENRECORD_PLAYER:=mpv}"

# --- OCR ---------------------------------------------------------------------
# Tesseract language spec: "eng", "eng+spa", "eng+deu". Unavailable languages
# are dropped automatically rather than failing the run.
: "${OCR_LANGS:=eng}"
: "${OCR_PSM:=6}"
: "${OCR_OEM:=1}"
: "${OCR_DPI:=300}"

# --- webcam ------------------------------------------------------------------
# "auto" picks the first device that actually reports capture formats, rather
# than assuming /dev/video0 (this machine exposes video0 AND video1 for one cam).
: "${WEBCAM_DEVICE:=auto}"
: "${WEBCAM_RESOLUTION:=1280x720}"
: "${WEBCAM_DEFAULT_SIZE:=medium}"   # small | medium | large

# --- selection ---------------------------------------------------------------
# A drag whose area is below this many square logical pixels is treated as a
# click, and snaps to the window (or failing that, the monitor) underneath.
: "${CAPTURE_CLICK_THRESHOLD:=20}"

# Seconds to let hyprpicker paint the frozen frame before slurp is drawn on top.
: "${CAPTURE_FREEZE_WARMUP:=0.1}"
