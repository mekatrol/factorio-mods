-- Cleanup role policy: collect loose stacks into bounded, persistent bot cargo.
local config = require("config")
local supply = require("supply")
local M = {
    tasks = {"follow", "cleanup"}
}

---Follow formation while passively watching for new litter, but keep the bot
---in its cleanup run once it has selected a target or is carrying cargo.
function M.scan_phase(rs)
    return ((rs.target and rs.target.valid) or (rs.cargo_count or 0) > 0) and "moving" or "idle"
end

---Keep formation only while waiting for player inventory space.  A false
---destination means the bounded chest search is still active.
function M.cargo_phase(destination)
    return destination == nil and "idle" or "working"
end

function M.radius()
    return config.tasks.cleanup.radius
end

function M.filter()
    return {type = "item-entity"}
end

function M.valid()
    return true
end

---Return cargo only once the bot is full or its latest search found no item.
---Other roles flush immediately because their cargo represents unused supplies,
---whereas cleanup cargo is intentionally accumulated up to the configured cap.
function M.should_flush_cargo(rs)
    if rs.task ~= "cleanup" then
        return true
    end
    if (rs.cargo_count or 0) >= config.supply.cleanup_capacity then
        return true
    end
    return rs.scan ~= nil and rs.scan.done and not (rs.target and rs.target.valid)
end

---Move as much of one ground stack as fits into the role's shared cargo cap.
---Cargo is stored as serializable counts rather than inventory objects, allowing
---delivery to resume safely after save/load or after the player changes surface.
function M.act(rs, _, entity)
    local stack = entity.stack
    if stack and stack.valid_for_read then
        -- `remaining_cargo_capacity` is the number of individual item units the
        -- cleanup bot may still carry, shared across every item type already in
        -- its manifest. Old saves may have no cargo_count, which means zero used.
        local carried_item_count = rs.cargo_count or 0
        local remaining_cargo_capacity = math.max(0, config.supply.cleanup_capacity - carried_item_count)
        -- Never remove more units from the ground stack than the bot can retain.
        local pickup_count = math.min(stack.count, remaining_cargo_capacity)
        if pickup_count > 0 then
            local item_name, original_stack_count = stack.name, stack.count
            if pickup_count >= original_stack_count then
                entity.destroy()
            else
                stack.count = original_stack_count - pickup_count
            end
            supply.queue_cargo(rs, {name = item_name, count = pickup_count}, true)
        end
    end
    return true
end

return M
