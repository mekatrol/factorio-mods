-- Logistics role policy: collect ground items, inventories, and neutral resources.
local config = require("config")
local logistics = require("logistics")
local supply = require("supply")
local M = {
    tasks = {"follow", "collect", "pickup"},
    handoff = true,
    handoff_types = {"item-entity", "simple-entity", "simple-entity-with-owner", "container", "resource"},
    scan_phase = "moving"
}

function M.radius()
    return config.tasks.logistics.radius
end

---Use a broad engine filter; richer force, minability, and requested-name rules
---are applied by `valid` after candidates are returned.
function M.filter()
    return {
        type = {"item-entity", "simple-entity", "simple-entity-with-owner", "container", "resource"}
    }
end

---Collect loose items or minable neutral entities without stealing from forces.
function M.valid(entity, rs)
    local neutral = not entity.force or entity.force.name == "neutral"
    return (entity.type == "item-entity" or (entity.minable and neutral)) and
               logistics.matches_pickup(entity, rs and rs.pickup_name)
end

---Validate the named finite-pickup arguments or clear them for normal collection.
function M.configure_task(rs, task, values)
    if task == "pickup" then
        -- Requested quantities count individual items and must therefore be
        -- positive integers; Factorio item stacks cannot contain fractions.
        local requested_item_count = tonumber(values.count)
        if not values.name or not requested_item_count or requested_item_count < 1 or
            requested_item_count % 1 ~= 0 then
            return false, "pickup requires name=<item-or-entity> count=<positive integer>"
        end
        rs.pickup_name, rs.pickup_remaining = values.name, requested_item_count
    else
        rs.pickup_name, rs.pickup_remaining = nil, nil
    end
    return true
end

---Return a completed finite request to opportunistic collection mode.
function M.normalize(rs)
    if rs.pickup_remaining and rs.pickup_remaining <= 0 then
        rs.pickup_name, rs.pickup_remaining = nil, nil
        rs.task, rs.scan, rs.target = "collect", nil, nil
    end
end

---Transfer one loose item stack directly to the player.
local function collect_ground_stack(rs, anchor, entity)
    local stack = entity.stack
    if stack and stack.valid_for_read then
        local original_stack_count = stack.count
        -- `items_inserted` is the number of units accepted by the player's
        -- inventory, which may be smaller than the ground stack when nearly full.
        local items_inserted = supply.player_give(anchor.player, {
            name = stack.name,
            count = original_stack_count,
            quality = stack.quality
        })
        if items_inserted > 0 then
            if rs.pickup_remaining then
                rs.pickup_remaining = math.max(0, rs.pickup_remaining - items_inserted)
            end
            if items_inserted >= original_stack_count then
                entity.destroy()
            else
                stack.count = original_stack_count - items_inserted
            end
        end
    end
    return not rs.pickup_remaining or rs.pickup_remaining <= 0 or not entity.valid
end

---Mine a bounded quantity from a resource entity.
---The action cap prevents large resource amounts from monopolizing one tick.
local function collect_resource(rs, anchor, entity, player_inventory)
    if not player_inventory or not entity.amount or entity.amount <= 0 then
        return true
    end
    local mineable_properties = entity.prototype and entity.prototype.mineable_properties
    local mining_products = mineable_properties and mineable_properties.products
    -- This role deliberately uses the first declared product, matching the
    -- existing single-product resource policy used for vanilla ore entities.
    local mined_item_name = mining_products and mining_products[1] and mining_products[1].name
    if not mined_item_name then
        return true
    end
    -- The requested amount is bounded by per-tick policy, resource units left in
    -- the world entity, and units remaining in a finite pickup command.
    local resource_units_requested = math.min(config.tasks.logistics.resource_units_per_action, entity.amount,
        rs.pickup_remaining or math.huge)
    local resource_units_inserted = player_inventory.insert {
        name = mined_item_name,
        count = resource_units_requested
    }
    if resource_units_inserted <= 0 then
        return true
    end
    entity.amount = entity.amount - resource_units_inserted
    if rs.pickup_remaining then
        rs.pickup_remaining = math.max(0, rs.pickup_remaining - resource_units_inserted)
    end
    if entity.amount <= 0 and entity.valid then
        entity.deplete()
    end
    return not entity.valid or (rs.pickup_remaining and rs.pickup_remaining <= 0)
end

---Drain at most the configured number of inventory slots per work unit.
---The persistent cursor makes large inventories resumable across ticks and saves.
local function collect_inventory(rs, player_inventory, entity)
    local source_inventory = supply.entity_inventory(entity)
    if not source_inventory then
        return true
    end
    local job = rs.collect_job
    if not job or job.entity ~= entity then
        job = {entity = entity, cursor = 1}
        rs.collect_job = job
    end
    -- `last_slot_this_action` is an inclusive inventory index. Subtracting one
    -- ensures a limit of N processes exactly N slots starting at the cursor.
    local last_slot_this_action = math.min(#source_inventory,
        job.cursor + config.tasks.logistics.inventory_slots_per_action - 1)
    while job.cursor <= last_slot_this_action do
        local stack = source_inventory[job.cursor]
        if stack.valid_for_read then
            local items_inserted = player_inventory and player_inventory.insert {
                name = stack.name,
                count = stack.count,
                quality = stack.quality
            } or 0
            if items_inserted > 0 then
                stack.count = stack.count - items_inserted
            end
            if stack.valid_for_read then
                return false
            end
        end
        job.cursor = job.cursor + 1
    end
    if job.cursor <= #source_inventory then
        return false
    end
    rs.collect_job = nil
    return true
end

---Perform one bounded collection action for the selected entity family.
function M.act(rs, anchor, entity)
    if entity.type == "item-entity" then
        return collect_ground_stack(rs, anchor, entity)
    end
    local player_inventory = anchor.player.get_main_inventory()
    if entity.type == "resource" then
        return collect_resource(rs, anchor, entity, player_inventory)
    end
    if not collect_inventory(rs, player_inventory, entity) then
        return false
    end
    if player_inventory and entity.minable then
        entity.mine {inventory = player_inventory, force = true, raise_destroyed = true}
    end
    return true
end

return M
