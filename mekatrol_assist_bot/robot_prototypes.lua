-- Data-stage builders for inert scripted robots with complete vanilla graphics.
-- Runtime code swaps visual-state prototypes; these clones must never perform
-- vanilla logistic-network work or carry payloads independently.
local M = {}

---Fail early when a vanilla prototype cannot provide a required animation.
local function require_graphic(base, family, field)
    if not base[field] then
        error("mekatrol_assist_bot: vanilla " .. family .. "-robot has no " .. field .. " animation")
    end
end

---Clone and neutralize a vanilla robot for one role/visual state.
---The clone retains complete directional graphics and attackability while its
---zero payload, radii, and energy use prevent logistic-network autonomy.
local function build(role, family, state, name)
    local base_name = family .. "-robot"
    -- `data.raw` is grouped first by prototype type and then by name. Guard the
    -- outer lookup because a heavily modified data stage may remove a family.
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

    -- Factorio prototypes contain nested animation tables. A deep copy is
    -- essential; mutating a shallow copy would also alter the vanilla robot.
    local prototype = table.deepcopy(base)
    prototype.name = name
    prototype.localised_name = {"entity-name.mekatrol-assist-bot", role}
    prototype.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
                       "not-selectable-in-game"}
    -- Assist bots are script-driven visual actors.  Do not inherit a collision
    -- layer from the vanilla robot: several followers crossing or crowding the
    -- character must never impede the character's running speed.
    prototype.collision_mask = {
        layers = {}
    }
    prototype.collision_box = {{0, 0}, {0, 0}}
    -- The vanilla robot clones inherit a mining result.  Clear it explicitly:
    -- holding the mine control over a ground entity must not collect an assist
    -- bot that happens to fly beneath the cursor.
    prototype.minable = nil
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
        -- Construction robots supply dedicated working graphics. Logistic
        -- robots do not in vanilla 2.0, so their complete movement animation is
        -- the family-consistent fallback.
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
