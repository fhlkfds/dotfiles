-- Profile: work. Replace with capture-monitor-profile.sh --with-workspaces when ready.
for workspace = 1, 15 do
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = "eDP-1",
        default = workspace == 1,
    })
end
