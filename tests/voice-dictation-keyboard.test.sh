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
        assert(not flags.release, "release binds leak the R press on Hyprland 0.57.0")
    end
end
package.path = root .. "/?.lua;" .. package.path
dofile(root .. "/conf/keybindings.lua")

local function press(device, keys)
    if devices[device] and devices[device].keybinds == false then return nil end
    return binds[keys]
end
local keys = { "SUPER + W", "SUPER + Return", "SUPER + T", "SUPER + code:10", "SUPER + R" }
for _, device in ipairs({ "ydotoold-virtual-device", "hl-virtual-keyboard-wtype", "hl-virtual-keyboard" }) do
    for _, key in ipairs(keys) do
        assert(press("physical-keyboard", key), "missing physical shortcut: " .. key)
        assert(not press(device, key), device .. " transcript triggered " .. tostring(press(device, key)))
    end
end
LUA

printf 'voice dictation keyboard isolation: ok\n'
