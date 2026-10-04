-- Track role policy: traverse and progressively upgrade one connected belt graph.
local config = require("config")
local supply = require("supply")
local movement = require("movement")
local upgrades = config.tasks.upgrade.mappings
local M = {
    tasks = {"follow", "track"},
    -- Searching does not own movement, so remain eligible for formation
    -- following until a belt graph has actually been selected.
    scan_phase = "idle"
}

local function supply_batch_size(rs, anchor, target_prototype_name)
    local count = 1
    local job = rs.track_job
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
        rs.supplied[target_prototype_name] = (rs.supplied[target_prototype_name] or 0) + supplied
    end
    local ready = movement.step(bot, entity.position)
    return ready and "working" or "moving", ready
end

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
            local last_user = entity.last_user
            local parameters = {
                name = target_prototype_name,
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
            -- Choose which physical item must be returned based on whether the
            -- world replacement consumed the supplied higher-tier item.
            local replacement = entity.surface.create_entity(parameters)
            if replacement and last_user then
                replacement.last_user = last_user
            end
            local returned_item_name = replacement and source_prototype_name or target_prototype_name
            supply.give_or_carry(rs, anchor.player, {name = returned_item_name, count = 1}, supply_source)
        end
    end
    return true
end

return M
