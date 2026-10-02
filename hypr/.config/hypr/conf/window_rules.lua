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
    -- Overrides dim-floating above (later rules win): the pinned overlay stays
    -- up for a whole recording, and dimming around it darkened every frame.
    dim_around = false,
})

hl.window_rule({
    name = "fullscreen-border",
    match = { fullscreen = true },
    border_color = "rgb(89B4FA) rgb(CBA6F7)",
})

hl.window_rule({ match = { class = "^(obsidian|Obsidian)$" }, workspace = "3 silent" })
hl.window_rule({ match = { class = "^(virt-manager)$" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(org.kde.neochat)$" }, workspace = "7 silent" })
hl.window_rule({ match = { class = "^(Spotify|spotify)$" }, workspace = "9 silent" })
hl.window_rule({ match = { class = "^([Bb]rave-browser|helium|firefox)$" }, workspace = "2 silent" })
hl.window_rule({ match = { class = "^t3code$" }, workspace = "4 silent" })
-- The updater terminal from the bar's update count (scripts/arch-updates).
-- Silent like the rest: it runs in the background on workspace 1 while the bar
-- shows an ellipsis. Go there when the sudo prompt or the both/pacman/AUR
-- question needs an answer.
hl.window_rule({ match = { title = "^System Update$" }, workspace = "1 silent" })

hl.window_rule({
    name = "ascii-screensaver",
    match = { class = [[^io\.github\.fhlkfds\.screensaver$]] },
    -- No float rule: if fullscreen is ever dropped the window must fall back to
    -- tiled, not to a small floating window.
    fullscreen = true,
    animation = "slide",
})
