-- Builder role policy: locate same-force ghosts and revive them with supplied items.
local config = require("config")
local logistics = require("logistics")
local supply = require("supply")
local M = {
    tasks = {"follow", "move_to", "construct"},
    handoff = true,
    scan_phase = "moving"
}

---Return the configured radius for local ghost searches.
function M.radius()
    return config.tasks.builder.radius
end

---Restrict the engine query to ghosts owned by the player's force.
function M.filter(_, anchor)
    return {type = "entity-ghost", force = anchor.force}
end

---Protect discovery handoffs from passing non-ghost entities to the builder.
function M.valid(entity)
    return entity.type == "entity-ghost"
end

---Supply the prototype-defined placement item and revive one ghost.
---A failed revive returns the unused item to its original source so a race with
---another builder or player can never silently destroy inventory.
function M.act(rs, anchor, entity)
    -- Ghost prototypes may be placed by an item whose name differs from the
    -- resulting entity, so resolve the actual item before requesting supply.
    local placement_item_name = logistics.placement_item(entity)
    if not placement_item_name then
        return true
    end
    -- nil means the incremental supply search is still running; zero means it
    -- completed without finding an item; one means construction may proceed.
    local items_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity, placement_item_name, 1)
    if items_supplied == nil then
        return false
    end
    if items_supplied > 0 then
        local supply_source = rs.last_source
        rs.last_source = nil
        if not entity.revive {raise_revive = true} then
            supply.give_or_carry(rs, anchor.player, {name = placement_item_name, count = 1}, supply_source)
        end
    end
    return true
end

return M
