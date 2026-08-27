for workspace = 1, 15 do
    local monitor = workspace <= 5 and "DP-5" or (workspace <= 10 and "DP-7" or "DP-9")
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = monitor,
        default = workspace == 1 or workspace == 6 or workspace == 11,
    })
end
