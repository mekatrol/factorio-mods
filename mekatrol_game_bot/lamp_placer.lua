local config = require("config")
local constants = require("constants")
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

local function in_power_area(surface, force, position)
    local poles = surface.find_entities_filtered {
        position = position,
        radius = config.lamp_search_radius,
        type = constants.ENTITY_TYPE.ELECTRIC_POLE,
        force = force
    }
    for _, pole in ipairs(poles) do
        local reach = pole.prototype.get_supply_area_distance(pole.quality) or constants.EMPTY_COUNT
        if pole.electric_network_id and math.abs(pole.position.x - position.x) <= reach and
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
