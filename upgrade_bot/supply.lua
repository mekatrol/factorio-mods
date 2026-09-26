local movement = require("movement")
local constants = require("constants")
local supply = {}

local function chest_inventory(entity)
    -- Centralizing inventory access ensures every pickup and return performs the
    -- same validity checks against entities that may be mined between ticks.
    if not (entity and entity.valid) then return nil end
    local inventory = entity.get_inventory(defines.inventory.chest)
    return inventory and inventory.valid and inventory or nil
end

function supply.networks_for(player, target)
    -- Construction-area lookup mirrors vanilla construction eligibility. It
    -- can return multiple networks where disconnected green areas overlap.
    return target.surface.find_logistic_networks_by_construction_area(target.position, player.force)
end

-- Use Factorio's logistic-network selector so active providers, storage,
-- buffers, and passive providers follow the engine's normal source priority.
function supply.find_source(player, target, item_name)
    local networks = supply.networks_for(player, target)
    local best, best_distance
    for _, network in pairs(networks) do
        -- Logistic networks are LuaObjects and can become invalid when their
        -- final roboport is removed while the bot is evaluating work.
        if network.valid then
            local point = network.select_pickup_point {
                name = item_name,
                position = target.position,
                include_buffers = true
            }
            local owner = point and point.owner
            local inventory = chest_inventory(owner)
            if inventory and inventory.get_item_count(item_name) > constants.EMPTY_COUNT then
                local distance = movement.distance_squared(target.position, owner.position)
                -- Where multiple eligible networks overlap, prefer the pickup
                -- selected closest to the construction target, as vanilla does.
                if not best_distance or distance < best_distance then
                    best = {entity = owner, network = network}
                    best_distance = distance
                end
            end
        end
    end
    return best
end

-- Fallback for ordinary player-owned chests that are not logistic providers.
-- Logistic containers remain the responsibility of the network selector.
function supply.find_nearby_container(player, target, bot_entity, item_name, radius)
    -- Only ordinary `container` prototypes belong in this fallback. Logistic
    -- containers must pass through Factorio's priority and network rules above.
    local entities = target.surface.find_entities_filtered {
        position = target.position,
        radius = radius,
        type = constants.ENTITY_TYPE.CONTAINER,
        force = player.force
    }
    local best, best_distance
    for _, entity in pairs(entities) do
        local inventory = chest_inventory(entity)
        if inventory and inventory.get_item_count(item_name) > constants.EMPTY_COUNT then
            local distance = movement.distance_squared(bot_entity.position, entity.position)
            -- Travel to the nearest usable ordinary chest so fallback behavior
            -- does not cause needlessly long flights around the local factory.
            if not best_distance or distance < best_distance then
                best = {entity = entity, network = nil, local_container = true}
                best_distance = distance
            end
        end
    end
    return best
end

function supply.find_nearby_drop_container(player, target, item_name, radius)
    -- Recovery for cargo created before delivery provenance existed uses an
    -- ordinary nearby chest with room. Logistic containers continue to use the
    -- network's storage selector so requester/provider semantics are respected.
    local entities = target.surface.find_entities_filtered {
        position = target.position,
        radius = radius,
        type = constants.ENTITY_TYPE.CONTAINER,
        force = player.force
    }
    local best, best_distance
    for _, entity in pairs(entities) do
        local inventory = chest_inventory(entity)
        if inventory and inventory.can_insert({name = item_name, count = constants.ITEM_TRANSFER_COUNT}) then
            local distance = movement.distance_squared(target.position, entity.position)
            if not best_distance or distance < best_distance then
                best = {entity = entity, network = nil, local_container = true}
                best_distance = distance
            end
        end
    end
    return best
end

function supply.first_network(player, target)
    -- Cargo may already hold the required item. In that case a covering network
    -- is still useful for returning the recovered lower-tier item to storage.
    for _, network in pairs(supply.networks_for(player, target)) do
        if network.valid then return network end
    end
    return nil
end

function supply.find_drop(network, item_name)
    -- Delegating drop selection respects storage filters and vanilla storage
    -- preference instead of inventing a second, incompatible storage policy.
    if not (network and network.valid) then return nil end
    local point = network.select_drop_point {
        stack = {name = item_name, count = constants.ITEM_TRANSFER_COUNT}
    }
    local owner = point and point.owner
    local inventory = chest_inventory(owner)
    if inventory and inventory.can_insert({name = item_name, count = constants.ITEM_TRANSFER_COUNT}) then
        return {entity = owner, network = network}
    end
    return nil
end

function supply.find_blocked_drop(network, position)
    -- When vanilla cannot select a drop point because every storage inventory is
    -- full, retain a concrete network container to visit and mark for the player.
    -- The nearest storage keeps the warning relevant to the completed work.
    if not (network and network.valid) then return nil end
    local best, best_distance
    for _, entity in pairs(network.storages or {}) do
        local inventory = chest_inventory(entity)
        if inventory then
            local distance = movement.distance_squared(position, entity.position)
            if not best_distance or distance < best_distance then
                best = {entity = entity, network = network}
                best_distance = distance
            end
        end
    end
    return best
end

function supply.put_one(destination, item_name)
    -- Revalidate at arrival because inserters and other robots may fill the
    -- destination during the bot's flight.
    if not (destination and destination.entity and destination.entity.valid) then return false end
    if destination.network and not destination.network.valid then return false end
    local inventory = chest_inventory(destination.entity)
    return inventory and inventory.insert({name = item_name, count = constants.ITEM_TRANSFER_COUNT}) ==
               constants.ITEM_TRANSFER_COUNT or false
end

function supply.can_put_one(destination, item_name)
    -- This non-mutating probe lets a blocked bot resume automatically without
    -- consuming or duplicating the item while merely checking available space.
    if not (destination and destination.entity and destination.entity.valid) then return false end
    if destination.network and not destination.network.valid then return false end
    local inventory = chest_inventory(destination.entity)
    return inventory and inventory.can_insert({name = item_name, count = constants.ITEM_TRANSFER_COUNT}) or false
end

function supply.take_one(source, item_name)
    -- The selected source is revalidated at arrival for the same race: another
    -- consumer may remove its final matching item while this bot is travelling.
    if not (source and source.entity and source.entity.valid) then return false end
    if source.network and not source.network.valid then return false end
    -- Remove from the exact source selected above so the chest the bot visits
    -- is also the chest whose visible item count decreases.
    local inventory = chest_inventory(source.entity)
    if not inventory then return false end
    return inventory.remove({name = item_name, count = constants.ITEM_TRANSFER_COUNT}) ==
               constants.ITEM_TRANSFER_COUNT
end

return supply
