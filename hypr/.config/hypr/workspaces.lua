for workspace = 1, 15 do
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = "eDP-1",
        default = workspace == 1,
    })
end
