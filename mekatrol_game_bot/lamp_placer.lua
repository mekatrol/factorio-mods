local config = require("config")
local constants = require("constants")
local movement = require("movement")
local player_anchor = require("player_anchor")

local lamp_placer = {}

local function carried_lamp(player)
    local inventory = player.get_main_inventory()
    if not inventory then return nil end
    for _, stack in ipairs(inventory.get_contents()) do
        if stack.count > constants.EMPTY_COUNT then
            local item = prototypes.item[stack.name]
            local placed = item and item.place_result
            if placed and placed.type == constants.ENTITY_TYPE.LAMP then
                return inventory, stack.name, stack.quality, placed.name
            end
        end
    end
    return nil
end

function lamp_placer.has_carried_lamp(player)
    return carried_lamp(player) ~= nil
end

local function lamp_stack(inventory)
    if not (inventory and inventory.valid) then return nil end
    for _, stack in ipairs(inventory.get_contents()) do
        if stack.count > constants.EMPTY_COUNT then
            local item = prototypes.item[stack.name]
            local placed = item and item.place_result
            if placed and placed.type == constants.ENTITY_TYPE.LAMP then return stack end
        end
    end
    return nil
end

function lamp_placer.find_red_container(player, bot_entity)
    -- Factorio rejects unknown names in entity filters. A missing logistics
    -- prototype therefore means lamp supply is unavailable, not a fatal error.
    if not prototypes.entity[constants.PASSIVE_PROVIDER_CHEST_NAME] then return nil end
    local best, best_distance
    local surface = player_anchor.surface(player)
    for _, chest in pairs(surface.find_entities_filtered {
        name = constants.PASSIVE_PROVIDER_CHEST_NAME,
        force = player.force
    }) do
        local inventory = chest.valid and chest.get_inventory(defines.inventory.chest)
        local stack = lamp_stack(inventory)
        if stack then
            local distance = movement.distance_squared(bot_entity.position, chest.position)
            if not best_distance or distance < best_distance then
                best = {entity = chest, item_name = stack.name, quality = stack.quality}
                best_distance = distance
            end
        end
    end
    return best
end

function lamp_placer.take_from_red_container(player, source)
    if not (source and source.entity and source.entity.valid) then return false end
    local chest_inventory = source.entity.get_inventory(defines.inventory.chest)
    local player_inventory = player.get_main_inventory()
    if not (chest_inventory and chest_inventory.valid and player_inventory) then return false end

    -- Factorio keeps the bot's working lamps in the player's inventory. Limit
    -- the batch by configuration, available chest stock, and free inventory
    -- capacity so a partly full inventory can still receive a smaller batch.
    local item = {name = source.item_name, quality = source.quality}
    local pickup_limit = math.max(constants.EMPTY_COUNT, math.floor(config.lamp_pickup_count))
    local count = math.min(
        pickup_limit,
        chest_inventory.get_item_count(item),
        player_inventory.get_insertable_count(item)
    )
    if count <= constants.EMPTY_COUNT then return false end

    local transfer = {name = item.name, quality = item.quality, count = count}
    local removed = chest_inventory.remove(transfer)
    if removed <= constants.EMPTY_COUNT then return false end

    transfer.count = removed
    local inserted = player_inventory.insert(transfer)
    -- Preserve anything that could not be inserted if inventory capacity
    -- changed between calculating the batch and performing the transfer.
    if inserted < removed then
        transfer.count = removed - inserted
        chest_inventory.insert(transfer)
    end
    return inserted > constants.EMPTY_COUNT
end

local function in_power_area(surface, force, position)
    local poles = surface.find_entities_filtered {
        position = position,
        radius = config.lamp_search_radius,
        type = constants.ENTITY_TYPE.ELECTRIC_POLE,
        force = force
    }
    for _, pole in ipairs(poles) do
        local reach = pole.valid and pole.prototype.get_supply_area_distance(pole.quality) or
                          constants.EMPTY_COUNT
        if pole.valid and pole.electric_network_id and math.abs(pole.position.x - position.x) <= reach and
                math.abs(pole.position.y - position.y) <= reach then
            return true
        end
    end
    return false
end

local function already_lit(surface, position)
    return #surface.find_entities_filtered {
        position = position,
        radius = config.lamp_light_radius,
        type = constants.ENTITY_TYPE.LAMP
    } > constants.EMPTY_COUNT
end

local function candidates(origin)
    local result = {}
    local radius = config.lamp_search_radius
    local spacing = config.lamp_candidate_spacing
    local centre = {x = math.floor(origin.x) + 0.5, y = math.floor(origin.y) + 0.5}
    for ring = spacing, radius, spacing do
        for x = -ring, ring, spacing do
            result[#result + 1] = {x = centre.x + x, y = centre.y - ring}
            result[#result + 1] = {x = centre.x + x, y = centre.y + ring}
        end
        for y = -ring + spacing, ring - spacing, spacing do
            result[#result + 1] = {x = centre.x - ring, y = centre.y + y}
            result[#result + 1] = {x = centre.x + ring, y = centre.y + y}
        end
    end
    return result
end

local function placeable(player, entity_name, position)
    local surface = player_anchor.surface(player)
    return not already_lit(surface, position) and
               in_power_area(surface, player.force, position) and
               surface.can_place_entity {
                   name = entity_name,
                   position = position,
                   force = player.force,
                   build_check_type = defines.build_check_type.manual
               }
end

function lamp_placer.find_target(player)
    -- Factorio reports zero darkness during full daylight. Dusk, night, and
    -- dawn are eligible, while daytime can never trigger lamp placement.
    if player_anchor.surface(player).darkness <= config.lamp_darkness_threshold then return nil end
    local inventory, _, _, entity_name = carried_lamp(player)
    if not inventory then return nil end

    for _, position in ipairs(candidates(player_anchor.position(player))) do
        if placeable(player, entity_name, position) then return position end
    end
    return nil
end

function lamp_placer.try_place_at(player, position)
    local surface = player_anchor.surface(player)
    if surface.darkness <= config.lamp_darkness_threshold then return false end
    local inventory, item_name, quality, entity_name = carried_lamp(player)
    if not inventory or not placeable(player, entity_name, position) then return false end

    local lamp = surface.create_entity {
        name = entity_name,
        position = position,
        force = player.force,
        quality = quality,
        player = player,
        raise_built = true
    }
    if not lamp then return false end
    inventory.remove {name = item_name, quality = quality, count = constants.ITEM_TRANSFER_COUNT}
    return true
end

return lamp_placer
