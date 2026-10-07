-- Ammo role policy: recover yellow magazines from gun turrets and return them
-- only to an existing friendly container which already holds yellow magazines.
local config = require("config")
local movement = require("movement")
local supply = require("supply")
local M = {
    tasks = {"follow", "unload"}
}

local function inventory(entity, id)
    return entity and entity.valid and entity.get_inventory and entity.get_inventory(id) or nil
end

local function item_count(inv, quality)
    if not inv then return 0 end
    return inv.get_item_count {name = config.tasks.ammo.item, quality = quality or "normal"}
end

-- Prefer normal quality, then choose deterministically among quality variants.
local function magazine_quality(inv)
    if item_count(inv, "normal") > 0 then return "normal" end
    if not inv or not inv.get_item_quality_counts then return nil end
    local names = {}
    for quality, count in pairs(inv.get_item_quality_counts(config.tasks.ammo.item)) do
        if count > 0 then names[#names + 1] = quality end
    end
    table.sort(names)
    return names[1]
end

local function container_inventory(entity)
    return supply.entity_inventory(entity)
end

local function container_has_magazines(entity)
    local inv = container_inventory(entity)
    return inv and magazine_quality(inv) ~= nil
end

function M.radius()
    return config.tasks.ammo.radius
end

-- Chain searches from wherever the previous trip ended. In particular, a
-- successful delivery leaves the bot at its container, so the next bounded
-- scan expands around that container instead of the player's formation slot.
function M.scan_center(_, _, bot)
    return bot.position
end

function M.filter(_, anchor)
    return {
        type = {"ammo-turret", "container", "logistic-container"},
        force = anchor.force
    }
end

-- Retain the position at which this bounded scan began. Returning "idle" here
-- would let formation following pull the bot back toward the player between
-- scan cells. The controller returns idle after an exhausted scan has no job.
M.scan_phase = "moving"

function M.begin_scan(rs)
    rs.ammo_container = nil
    rs.ammo_container_distance = nil
end

function M.scan_entity(entity, rs, _, bot)
    if entity.type == "ammo-turret" then
        local inv = inventory(entity, defines.inventory.turret_ammo)
        if magazine_quality(inv) then
            local distance = movement.distance2(entity.position, bot.position)
            if not rs.best_distance or distance < rs.best_distance then
                rs.target, rs.best_distance = entity, distance
            end
        end
    elseif container_has_magazines(entity) then
        local distance = movement.distance2(entity.position, bot.position)
        if not rs.ammo_container_distance or distance < rs.ammo_container_distance then
            rs.ammo_container, rs.ammo_container_distance = entity, distance
        end
    end
end

function M.valid(entity)
    local inv = entity.type == "ammo-turret" and
                    inventory(entity, defines.inventory.turret_ammo) or nil
    return magazine_quality(inv) ~= nil
end

function M.after_scan(rs)
    if not (rs.ammo_container and rs.ammo_container.valid) then
        rs.target = nil
        rs.best_distance = nil
    end
end

function M.act(rs, _, turret)
    local destination = rs.ammo_container
    local turret_inv = inventory(turret, defines.inventory.turret_ammo)
    local quality = magazine_quality(turret_inv)
    local destination_inv = container_inventory(destination)
    -- Revalidate immediately before removal. If either endpoint changed during
    -- travel, leave the turret untouched and return to follow mode.
    if not quality or not destination_inv or not container_has_magazines(destination) or
        not destination_inv.can_insert {name = config.tasks.ammo.item, count = 1, quality = quality} then
        return true
    end
    local count = math.min(config.supply.ammo_capacity, item_count(turret_inv, quality))
    if count <= 0 then return true end
    local removed = turret_inv.remove {
        name = config.tasks.ammo.item,
        count = count,
        quality = quality
    }
    if removed > 0 then
        supply.queue_cargo(rs, {name = config.tasks.ammo.item, count = removed, quality = quality})
        local key = quality == "normal" and config.tasks.ammo.item or
                        (config.tasks.ammo.item .. "\31" .. quality)
        rs.cargo_destinations[key] = destination
    end
    return true
end

function M.finish(rs)
    rs.ammo_container = nil
    rs.ammo_container_distance = nil
end

return M
