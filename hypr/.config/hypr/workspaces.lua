-- KVM profile workspace pinning -- keyed by EDID description, see kvm.monitors.lua.
--
-- Bands preserve the historical arrangement by screen position:
--   1-5   middle   6-10  left (portrait)   11-15  right

local MIDDLE = "desc:Dell Inc. DELL P2722H CTCS1M3"
local LEFT = "desc:Dell Inc. DELL P2214H KW14V42L3ACB"
local RIGHT = "desc:Dell Inc. DELL P2725H 21MG834"

for workspace = 1, 15 do
    local monitor = workspace <= 5 and MIDDLE or (workspace <= 10 and LEFT or RIGHT)
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = monitor,
        default = workspace == 1 or workspace == 6 or workspace == 11,
    })
end
