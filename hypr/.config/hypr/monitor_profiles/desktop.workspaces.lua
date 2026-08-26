for workspace = 1, 15 do
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = workspace <= 5 and "HDMI-A-3" or "DP-4",
        default = workspace == 1 or workspace == 6,
    })
end
