-- Hyprland 0.55+ Lua configuration entry point.
-- Keep component behavior in the modules below so generated state can be
-- replaced atomically without rewriting this file.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- ponytail: legacy DRM avoids Aquamarine's hotplug crash; remove after the page-flip bug is fixed.
hl.env("AQ_NO_ATOMIC", "1")

local home = assert(os.getenv("HOME"), "HOME is required")
local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local night_light_state = io.open(state_home .. "/hyprland-desktop/night-light-shader", "r")
local night_light_enabled = night_light_state ~= nil
if night_light_state then
    night_light_state:close()
end

hl.config({
    decoration = {
        screen_shader = night_light_enabled
            and (home .. "/.config/hypr/shaders/night-light.frag")
            or "",
    },
    cursor = {
        -- ponytail: software cursor avoids rotated-output glitches; retry hardware cursors after an upstream fix.
        no_hardware_cursors = 1,
    },
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

require("conf/keybindings")
require("conf/window_rules")
require("conf/autostart")
require("conf/decorations")
require("monitors")
require("workspaces")
