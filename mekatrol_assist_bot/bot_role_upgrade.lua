-- Upgrade role policy: replace configured entities while preserving topology.
local config = require("config")
local supply = require("supply")
local upgrades = config.tasks.upgrade.mappings
local M = {
    tasks = {"follow", "yellow-to-red-belts", "red-to-blue-belts", "blue-to-green-inserters", "containers",
             "combined"},
    scan_phase = "moving"
}

-- Supplying prototype names to the engine avoids scanning unrelated entities.
local names = {}
for name in pairs(upgrades) do
    names[#names + 1] = name
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

---Fast-replace while preserving direction, force, user, and underground type.
local function replace(entity, name)
    local parameters = {
        name = name,
        position = entity.position,
        direction = entity.direction,
        force = entity.force,
        player = entity.last_user,
        fast_replace = true,
        spill = false,
        raise_built = true
    }
    if entity.type == "underground-belt" then
        parameters.type = entity.belt_to_ground_type
    end
    return entity.surface.create_entity(parameters) ~= nil
end

---Consume the new item and return either the removed old item or the unused new
---item to its source, depending on whether fast replacement succeeds.
function M.act(rs, anchor, entity)
    local source_prototype_name = entity.name
    local target_prototype_name = upgrades[source_prototype_name]
    local target_recipe = target_prototype_name and anchor.force.recipes[target_prototype_name]
    if target_prototype_name and (not target_recipe or target_recipe.enabled) then
        local upgrade_items_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity,
            target_prototype_name, 1)
        if upgrade_items_supplied == nil then
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
