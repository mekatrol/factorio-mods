-- Upgrade role policy: replace configured entities while preserving topology.
local config = require("config")
local supply = require("supply")
local movement = require("movement")
local upgrades = config.tasks.upgrade.mappings
local M = {
    tasks = {"follow", "yellow-to-red-belts", "red-to-blue-belts", "blue-to-green-inserters", "containers",
             "combined"},
    -- A bounded scan does not own a movement destination. Keep formation while
    -- it searches; active movement begins only after the nearest target has
    -- been selected from the completed scan.
    scan_phase = "idle"
}

-- Supplying prototype names to the engine avoids scanning unrelated entities.
local names = {}
for name in pairs(upgrades) do
    -- Burner inserters are often the power-independent fallback that keeps
    -- boiler fuel moving during a brownout, so never replace them.
    if name ~= "burner-inserter" then
        names[#names + 1] = name
    end
end
table.sort(names)

function M.radius(rs)
    return config.tasks.upgrade.mode_radii[rs.task] or config.tasks.upgrade.radius
end

function M.filter()
    return {name = names}
end

---Validate prototype availability, recipe access, and the selected task subset.
function M.valid(entity, rs, anchor)
    if entity.name == "burner-inserter" then
        return false
    end
    local target_prototype_name = upgrades[entity.name]
    local target_recipe = target_prototype_name and anchor and anchor.force.recipes[target_prototype_name]
    -- Entity and item prototypes are both required: one is created in the world
    -- and the other is consumed from supply. Disabled known recipes are rejected.
    if not target_prototype_name or not prototypes.entity[target_prototype_name] or
        not prototypes.item[target_prototype_name] or (target_recipe and not target_recipe.enabled) then
        return false
    end
    local task = rs and rs.task or "combined"
    if task == "yellow-to-red-belts" then
        return entity.name == "transport-belt" or entity.name == "underground-belt" or entity.name == "splitter"
    elseif task == "red-to-blue-belts" then
        return entity.name == "fast-transport-belt" or entity.name == "fast-underground-belt" or
                   entity.name == "fast-splitter"
    elseif task == "blue-to-green-inserters" then
        return entity.name == "fast-inserter"
    elseif task == "containers" then
        return entity.name == "wooden-chest" or entity.name == "iron-chest"
    end
    return true
end

---Belts are upgraded as connected graphs; inserters and containers are isolated.
function M.grouped(rs)
    local selected_entity = rs.target
    return rs.track_job or (selected_entity and selected_entity.valid and
               (selected_entity.type == "transport-belt" or selected_entity.type == "underground-belt" or
                   selected_entity.type == "splitter"))
end

---Fast-replace while preserving direction, force, last user, and underground type.
local function replace(entity, name)
    local last_user = entity.last_user
    local parameters = {
        name = name,
        position = entity.position,
        direction = entity.direction,
        force = entity.force,
        fast_replace = true,
        spill = false,
        raise_built = true
    }
    if entity.type == "underground-belt" then
        parameters.type = entity.belt_to_ground_type
    end
    local replacement = entity.surface.create_entity(parameters)
    if replacement and last_user then
        -- Passing `player` to create_entity would simulate player fast-replace
        -- and teleport the removed item directly into that player's inventory.
        -- Restore attribution only after the bot-owned replacement is complete.
        replacement.last_user = last_user
    end
    return replacement ~= nil
end

---Count the current entity plus matching remaining members of its discovered
---belt graph, capped so one pickup never drains an unbounded inventory stack.
local function supply_batch_size(rs, anchor, target_prototype_name)
    local count = 1
    local job = rs.track_job
    if not job then
        return config.tasks.upgrade.items_per_trip
    end
    if job and job.entities then
        for i = job.action_index or 1, #job.entities do
            local candidate = job.entities[i]
            if candidate and candidate.valid and upgrades[candidate.name] == target_prototype_name and
                M.valid(candidate, rs, anchor) then
                count = count + 1
                if count >= config.tasks.upgrade.items_per_trip then
                    break
                end
            end
        end
    end
    return count
end

---Keep recovered lower-tier items aboard until the prefetched upgrade batch is
---spent, then let the scheduler return the consolidated cargo in one trip.
function M.should_flush_cargo(rs)
    for _, count in pairs(rs.supplied or {}) do
        if count > 0 then
            return false
        end
    end
    return true
end

function M.finish(rs, anchor)
    supply.return_staged(rs, anchor.player)
end

---Acquire upgrade stock before approaching the selected entity. This avoids a
---wasted target visit followed by a return trip to the player for supplies.
function M.navigate(rs, anchor, bot)
    local entity = rs.target
    local target_prototype_name = entity and entity.valid and upgrades[entity.name]
    if not target_prototype_name then
        return "working", true
    end
    local staged = rs.supplied and (rs.supplied[target_prototype_name] or 0) or 0
    if staged == 0 then
        local supplied = supply.take(rs, anchor.player, entity, bot, target_prototype_name, 1,
            supply_batch_size(rs, anchor, target_prototype_name))
        if supplied == nil then
            return "moving", false
        end
        if supplied == 0 then
            rs.waiting_inventory = target_prototype_name
            return "idle", false
        end
        -- `take` only returns a positive value from already staged stock. Put
        -- it back because the action consumes it after reaching the target.
        rs.supplied[target_prototype_name] = (rs.supplied[target_prototype_name] or 0) + supplied
    end
    local ready = movement.step(bot, entity.position)
    return ready and "working" or "moving", ready
end

---Consume the new item and return either the removed old item or the unused new
---item to its source, depending on whether fast replacement succeeds.
function M.act(rs, anchor, entity)
    local source_prototype_name = entity.name
    local target_prototype_name = upgrades[source_prototype_name]
    local target_recipe = target_prototype_name and anchor.force.recipes[target_prototype_name]
    if target_prototype_name and (not target_recipe or target_recipe.enabled) then
        local upgrade_items_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity,
            target_prototype_name, 1, supply_batch_size(rs, anchor, target_prototype_name))
        if upgrade_items_supplied == nil then
            return false
        end
        if upgrade_items_supplied == 0 then
            rs.waiting_inventory = target_prototype_name
            return false
        end
        if upgrade_items_supplied > 0 then
            local supply_source = rs.last_source
            rs.last_source = nil
            -- Successful replacement recovers the removed lower-tier item;
            -- failure returns the unused higher-tier item instead.
            local returned_item_name = replace(entity, target_prototype_name) and source_prototype_name or
                                           target_prototype_name
            supply.give_or_carry(rs, anchor.player, {name = returned_item_name, count = 1}, supply_source)
        end
    end
    return true
end

return M
