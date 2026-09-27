local config = require("config")
local constants = require("constants")

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

function lamp_placer.try_place(player)
    -- Factorio reports zero darkness during full daylight. Dusk, night, and
    -- dawn are eligible, while daytime can never trigger lamp placement.
    if player.surface.darkness <= config.lamp_darkness_threshold then return false end
    local inventory, item_name, quality, entity_name = carried_lamp(player)
    if not inventory then return false end

    for _, position in ipairs(candidates(player.position)) do
        if not already_lit(player.surface, position) and
                in_power_area(player.surface, player.force, position) and
                player.surface.can_place_entity {
                    name = entity_name,
                    position = position,
                    force = player.force,
                    build_check_type = defines.build_check_type.manual
                } then
            local lamp = player.surface.create_entity {
                name = entity_name,
                position = position,
                force = player.force,
                quality = quality,
                player = player,
                raise_built = true
            }
            if lamp then
                inventory.remove {name = item_name, quality = quality, count = constants.ITEM_TRANSFER_COUNT}
                return true
            end
        end
    end
    return false
end

return lamp_placer
