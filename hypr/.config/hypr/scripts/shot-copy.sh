#!/usr/bin/env bash

if grim -g "$(slurp -d)" - | wl-copy; then
  hyprctl notify 5 2000 "rgb(a6e3a1)" "Screenshot copied to clipboard"
else
  hyprctl notify 3 4000 "rgb(f38ba8)" "Screenshot copy failed"
fi
