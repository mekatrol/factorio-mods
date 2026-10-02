-- Data-stage builders for inert scripted robots with complete vanilla graphics.
-- Runtime code swaps visual-state prototypes; these clones must never perform
-- vanilla logistic-network work or carry payloads independently.
local M = {}

local function require_graphic(base, family, field)
    if not base[field] then
        error("mekatrol_assist_bot: vanilla " .. family .. "-robot has no " .. field .. " animation")
    end
end

local function build(role, family, state, name)
    local base_name = family .. "-robot"
    local base = data.raw[base_name] and data.raw[base_name][base_name]
    if not base then
        error("mekatrol_assist_bot: missing base " .. base_name)
    end
    for _, field in ipairs{"idle", "in_motion", "shadow_idle", "shadow_in_motion"} do
        require_graphic(base, family, field)
    end
    if family == "construction" then
        require_graphic(base, family, "working")
        require_graphic(base, family, "shadow_working")
    end

    local prototype = table.deepcopy(base)
    prototype.name = name
    prototype.localised_name = {"entity-name.mekatrol-assist-bot", role}
    prototype.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
                       "not-selectable-in-game"}
    -- Zero payload/radii retain animation and attackability while preventing
    -- autonomous logistic-network assignments.
    prototype.max_payload_size = 0
    prototype.construction_radius = 0
    prototype.logistic_radius = 0
    prototype.energy_per_move = "0J"
    prototype.energy_per_tick = "0J"

    if state == "idle" then
        prototype.in_motion = table.deepcopy(base.idle)
        prototype.shadow_in_motion = table.deepcopy(base.shadow_idle)
    elseif state == "working" then
        -- Vanilla logistic robots have no dedicated working graphic in 2.0.77;
        -- their complete in-motion animation is the closest family-native state.
        local working = base.working or base.in_motion
        local working_shadow = base.shadow_working or base.shadow_in_motion
        prototype.idle = table.deepcopy(working)
        prototype.in_motion = table.deepcopy(working)
        prototype.shadow_idle = table.deepcopy(working_shadow)
        prototype.shadow_in_motion = table.deepcopy(working_shadow)
    elseif state ~= "moving" then
        error("mekatrol_assist_bot: unknown robot visual state " .. tostring(state))
    end
    return prototype
end

---Build a construction-family role prototype with all vanilla directional graphics.
function M.construction(role, state, name)
    return build(role, "construction", state, name)
end

---Build a logistic-family role prototype with all vanilla directional graphics.
function M.logistic(role, state, name)
    return build(role, "logistic", state, name)
end

return M
