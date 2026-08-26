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

hl.config({
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
