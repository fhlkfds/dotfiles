#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Replay transcript key events with SUPER held against the real registrations.
# Hyprland's per-device keybinds=false gate runs before shortcut matching.
lua - "$repo_root/hypr/.config/hypr" <<'LUA'
local root = assert(arg[1])
local devices, binds = {}, {}
local function stub()
    return setmetatable({}, {
        __index = function() return stub() end,
        __call = function() return {} end,
    })
end
hl = stub()
hl.device = function(config) devices[config.name] = config end
hl.bind = function(keys, dispatcher, flags)
    binds[keys] = flags.description
    if flags.description == "voice dictation" then
        assert(flags.release == true, "dictation fires before key release")
    end
end
package.path = root .. "/?.lua;" .. package.path
dofile(root .. "/conf/keybindings.lua")

local function press(device, keys)
    if devices[device] and devices[device].keybinds == false then return nil end
    return binds[keys]
end
local keys = { "SUPER + E", "SUPER + W", "SUPER + Return", "SUPER + T", "SUPER + code:10", "SUPER + R" }
for _, device in ipairs({ "ydotoold-virtual-device", "hl-virtual-keyboard-wtype", "hl-virtual-keyboard" }) do
    for _, key in ipairs(keys) do
        assert(press("physical-keyboard", key), "missing physical shortcut: " .. key)
        assert(not press(device, key), device .. " transcript triggered " .. tostring(press(device, key)))
    end
end
LUA

# The retained legacy entry point needs the same device gate.
python3 - "$repo_root/hypr/.config/hypr/conf/keybinding.conf" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
assert 'bindrd = $mainMod, R, voice dictation, exec, $scriptsDir/voice-dictation toggle' in text
devices = {}
for body in re.findall(r"(?m)^device\s*\{([^}]+)\}", text):
    name = re.search(r"(?m)^\s*name\s*=\s*(\S+)", body)
    if name:
        devices[name[1]] = body
for name in ("ydotoold-virtual-device", "hl-virtual-keyboard-wtype", "hl-virtual-keyboard"):
    assert re.search(r"(?m)^\s*keybinds\s*=\s*false\s*$", devices.get(name, "")), name
PY

printf 'voice dictation keyboard isolation: ok\n'
