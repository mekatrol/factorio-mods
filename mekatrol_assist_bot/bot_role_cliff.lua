-- Cliff role policy: demolish only cliffs explicitly selected by the player.
local config = require("config")
local discovery = require("discovery")
local state = require("state")
local supply = require("supply")
local visuals = require("visuals")
local M = {
    tasks = {"follow", "demolish"},
    scan_phase = "moving",
    help_suffix = "/mark/clear"
}

---Handle the cliff-specific planner and clear commands.
function M.command(action, context)
    if action == "clear" then
        local root = state.root()
        root.cliffs = {}
        visuals.begin_clear(root, "cliff:")
        context.say("cliff marks cleared")
        return true
    end
    if action == "mark" then
        context.player.cursor_stack.set_stack {name = "mekatrol-assist-cliff-planner", count = 1}
        return true
    end
    return false
end

function M.radius()
    return config.tasks.cliff.radius
end

function M.filter()
    return {type = "cliff"}
end

---Selection state is keyed by stable discovery identity, not LuaEntity handle.
function M.valid(entity)
    return state.root().cliffs[discovery.identity(entity)] == true
end

---Launch one explosive projectile and clear the mark after successful creation.
---If projectile creation fails, return the consumed explosive to its source.
function M.act(rs, anchor, entity)
    -- Supply searches may span ticks. nil means the search is incomplete, while
    -- zero means it finished without finding explosives and the target is done.
    local explosives_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity, "cliff-explosives", 1)
    if explosives_supplied == nil then
        return false
    end
    if explosives_supplied > 0 then
        -- Remember the exact player/container source so a failed projectile
        -- creation can return the explosive rather than losing inventory.
        local supply_source = rs.last_source
        local cliff_identity = discovery.identity(entity)
        rs.last_source = nil
        local projectile = entity.surface.create_entity {
            name = "cliff-explosives",
            position = rs.entity.position,
            target = entity.position,
            speed = config.tasks.cliff.projectile_speed,
            force = anchor.force
        }
        if projectile then
            state.root().cliffs[cliff_identity] = nil
            visuals.clear_role("cliff:" .. cliff_identity)
        else
            supply.give_or_carry(rs, anchor.player, {name = "cliff-explosives", count = 1}, supply_source)
        end
    end
    return true
end

return M
