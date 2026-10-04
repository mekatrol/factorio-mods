-- Track role policy: traverse and progressively upgrade one connected belt graph.
local config = require("config")
local supply = require("supply")
local upgrades = config.tasks.upgrade.mappings
local M = {
    tasks = {"follow", "track"},
    -- Searching does not own movement, so remain eligible for formation
    -- following until a belt graph has actually been selected.
    scan_phase = "idle"
}

function M.radius()
    return config.tasks.track.radius
end

function M.filter()
    return {type = {"transport-belt", "underground-belt", "splitter"}}
end

---Require a configured, available next tier before starting graph traversal.
function M.valid(entity, _, anchor)
    local target_prototype_name = upgrades[entity.name]
    local target_recipe = target_prototype_name and anchor and anchor.force.recipes[target_prototype_name]
    return target_prototype_name ~= nil and prototypes.entity[target_prototype_name] ~= nil and
               prototypes.item[target_prototype_name] ~= nil and (not target_recipe or target_recipe.enabled)
end

---Every target belongs to the connected graph selected by the shared controller.
function M.grouped()
    return true
end

---Upgrade one graph member per scheduler opportunity while preserving belt type.
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
        if upgrade_items_supplied == 0 then
            rs.waiting_inventory = target_prototype_name
            return false
        end
        if upgrade_items_supplied > 0 then
            local supply_source = rs.last_source
            rs.last_source = nil
            local parameters = {
                name = target_prototype_name,
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
            -- Choose which physical item must be returned based on whether the
            -- world replacement consumed the supplied higher-tier item.
            local returned_item_name = entity.surface.create_entity(parameters) and source_prototype_name or
                                           target_prototype_name
            supply.give_or_carry(rs, anchor.player, {name = returned_item_name, count = 1}, supply_source)
        end
    end
    return true
end

return M
