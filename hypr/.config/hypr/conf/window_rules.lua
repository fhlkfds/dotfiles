-- Hyprland window behavior and application workspace assignment.

hl.window_rule({
    name = "float-modal",
    match = { modal = true },
    float = true,
    center = true,
})

hl.window_rule({
    name = "round-floating",
    match = { float = true },
    rounding = 10,
    border_size = 2,
})

hl.window_rule({
    name = "dim-floating",
    match = { float = true },
    dim_around = true,
})

hl.window_rule({
    name = "localsend",
    match = { class = [[^org\.localsend\.localsend_app$]] },
    float = true,
    center = true,
})

hl.window_rule({
    name = "capture-webcam-overlay",
    match = { title = "^capture-webcam$" },
    float = true,
    pin = true,
})

hl.window_rule({
    name = "fullscreen-border",
    match = { fullscreen = true },
    border_color = "rgb(89B4FA) rgb(CBA6F7)",
})

hl.window_rule({
    -- Wayland app_id is lowercase; "Brave-browser" is the XWayland WM_CLASS, so
    -- the unanchored capitalised form matched nothing and this rule was dead.
    match = { class = "^[Bb]rave-browser$" },
    opacity = "1.0 override 0.95 override 1.0 override",
})

hl.window_rule({ match = { class = "^(obsidian|Obsidian)$" }, workspace = "3 silent" })
hl.window_rule({ match = { class = "^(virt-manager)$" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(org.kde.neochat)$" }, workspace = "7 silent" })
hl.window_rule({ match = { class = "^(Spotify|spotify)$" }, workspace = "9 silent" })
hl.window_rule({ match = { class = "^(brave-browser)$" }, workspace = "2 silent" })
