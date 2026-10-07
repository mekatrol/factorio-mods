-- Ammo role policy: recover yellow magazines from gun turrets and return them
-- only to an existing friendly container which already holds yellow magazines.
local config = require("config")
local movement = require("movement")
local supply = require("supply")
local scanner = require("entity_scanner")
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

local function inventory_load(inv)
    return inv.get_item_count()
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

-- A known destination owns the bot's position. Without one, scanning remains
-- passive so formation following can carry the bot toward a container while
-- the bounded scan continues around its latest starting point.
function M.scan_phase(rs)
    return (rs.ammo_chain_scan or
               (rs.ammo_container and (rs.target or rs.ammo_waiting_turret))) and "moving" or "idle"
end

-- When carried ammo has no remaining matching destination, formation following
-- moves the bot's next bounded cargo scan to a new area. A concrete container
-- takes movement ownership again for delivery.
function M.cargo_phase(destination)
    return destination == false and "idle" or "working"
end

-- The scheduler renders this with an independently owned line so the turret
-- and destination remain visible at the same time. Once ammo is onboard, the
-- cargo destination is authoritative; before pickup, use the scan selection.
function M.secondary_target(rs)
    if rs.ammo_pickup_scan then return nil end
    local key = rs.cargo_order and rs.cargo_order[rs.cargo_cursor or 1]
    local destination = key and rs.cargo_destinations and rs.cargo_destinations[key]
    if destination and destination ~= false and destination.valid then
        return destination
    end
    return nil
end

-- Before leaving the pickup turret, scan its neighbourhood and retain the
-- nearest loaded turret as a fallback. Cargo delivery starts only after this
-- bounded scan finishes, so the bot never has to travel back to run it later.
function M.before_cargo(rs, _, bot)
    local scan = rs.ammo_pickup_scan
    if not scan then return nil end
    if not scan.done then
        local _, found = scanner.step(scan)
        for _, entity in ipairs(found) do
            if M.valid(entity) then
                local distance = movement.distance2(entity.position, scan.center)
                if not rs.ammo_fallback_distance or distance < rs.ammo_fallback_distance then
                    rs.ammo_fallback_turret = entity
                    rs.ammo_fallback_distance = distance
                end
            end
        end
    end
    if not scan.done then return "moving" end
    rs.ammo_pickup_scan = nil
    rs.ammo_fallback_distance = nil
end

function M.begin_scan(rs)
    rs.ammo_container = nil
    rs.ammo_container_load = nil
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
        local inv = container_inventory(entity)
        local quality = magazine_quality(inv)
        if not inv.can_insert {name = config.tasks.ammo.item, count = 1, quality = quality} then
            return
        end
        local load = inventory_load(inv)
        local distance = movement.distance2(entity.position, bot.position)
        if not rs.ammo_container_load or load < rs.ammo_container_load or
            (load == rs.ammo_container_load and
                (not rs.ammo_container_distance or distance < rs.ammo_container_distance)) then
            rs.ammo_container, rs.ammo_container_load, rs.ammo_container_distance = entity, load, distance
        end
    end
end

function M.valid(entity)
    local inv = entity.type == "ammo-turret" and
                    inventory(entity, defines.inventory.turret_ammo) or nil
    return magazine_quality(inv) ~= nil
end

function M.after_scan(rs)
    -- A completed delivery holds position only for this immediately chained
    -- scan. Once its bounded search is complete, normal target/wait policy can
    -- either start a job or release the bot back to formation following.
    rs.ammo_chain_scan = nil
    local turret = rs.target
    if not turret and rs.ammo_waiting_turret and M.valid(rs.ammo_waiting_turret) then
        turret = rs.ammo_waiting_turret
    end
    if not turret and rs.ammo_fallback_turret and M.valid(rs.ammo_fallback_turret) then
        turret = rs.ammo_fallback_turret
    end
    rs.ammo_fallback_turret = nil
    rs.ammo_fallback_distance = nil
    if turret and rs.ammo_container and rs.ammo_container.valid then
        rs.target = turret
        rs.ammo_waiting_turret = nil
        rs.waiting_ammo_container = nil
    elseif turret then
        -- Preserve the remote turret while following the player. A later scan
        -- may find the required container even after the turret leaves range.
        rs.ammo_waiting_turret = turret
        rs.waiting_ammo_container = true
        rs.target = nil
        rs.best_distance = nil
    else
        rs.ammo_waiting_turret = nil
        rs.waiting_ammo_container = nil
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
        rs.cargo_lowest_inventory[key] = true
        rs.ammo_fallback_turret = nil
        rs.ammo_fallback_distance = nil
        rs.ammo_pickup_scan = scanner.start(turret.surface, turret.position, config.tasks.ammo.radius, {
            type = "ammo-turret",
            force = turret.force
        })
    end
    rs.ammo_waiting_turret = nil
    rs.waiting_ammo_container = nil
    return true
end

function M.finish(rs)
    rs.ammo_container = nil
    rs.ammo_container_load = nil
    rs.ammo_container_distance = nil
end

return M
