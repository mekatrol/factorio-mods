local config = require("config")
local constants = require("constants")
local movement = require("movement")
local player_anchor = require("player_anchor")
local state = require("state")

local cleanup = {}
local conf = config.cleanup
local container_types = {constants.ENTITY_TYPE.CONTAINER, constants.ENTITY_TYPE.LOGISTIC_CONTAINER}

local function message(player, color, text)
    player.print({"", "[color=" .. color .. "][Cleanup Bot][/color] ", text})
end

local function cargo_total(value)
    local total = 0
    for _, count in pairs(value.cargo) do total = total + count end
    return total
end

local function clear_object(value, name)
    local object = value[name]
    if object and object.valid then object.destroy() end
    value[name] = nil
end

local function draw_status(player, value)
    clear_object(value, "status_label")
    if not (value.entity and value.entity.valid) then return end
    local names = {}
    for name in pairs(value.unplaceable) do names[#names + 1] = name end
    table.sort(names)
    local count = cargo_total(value)
    local text = #names > 0 and ("NO CONTAINER: " .. table.concat(names, ", ")) or
                     (count > 0 and string.format("Carrying: %d/%d", count, conf.cargo_capacity) or
                         "[" .. value.mode .. "] items: 0")
    value.status_label = rendering.draw_text {
        text = text, surface = value.entity.surface, target = value.entity,
        target_offset = {0, 0.8}, color = {r = 0.3, g = 0.9, b = 1, a = 1},
        scale = 0.7, alignment = "center", vertical_alignment = "top",
        only_in_alt_mode = false, players = {player.index}
    }
end

local function draw_target(value)
    clear_object(value, "target_line")
    if value.mode ~= "pickup" or not value.target then return end
    value.target_line = rendering.draw_line {
        color = {r = 1, g = 0.2, b = 0.2, a = 0.7}, width = 1,
        from = value.entity, to = value.target, surface = value.entity.surface,
        draw_on_ground = true, only_in_alt_mode = false
    }
end

local function create(player, value)
    local offset = conf.follow_offset
    local position = player_anchor.position(player)
    value.entity = player_anchor.surface(player).create_entity {
        name = constants.CLEANUP_BOT_ENTITY_NAME,
        position = {x = position.x + offset.x, y = position.y + offset.y},
        force = player.force, raise_built = true
    }
    if value.entity then value.entity.destructible = true end
    return value.entity ~= nil
end

local function follow(player, value)
    local previous = value.last_player_position
    local player_position = player_anchor.position(player)
    if previous then
        local dx = player_position.x - previous.x
        if dx < -constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = math.abs(conf.follow_offset.x)
        elseif dx > constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = -math.abs(conf.follow_offset.x)
        end
    end
    value.last_player_position = {x = player_position.x, y = player_position.y}
    local target = {x = player_position.x + value.side_offset_x,
                    y = player_position.y + conf.follow_offset.y}
    if movement.distance_squared(value.entity.position, target) > config.follow_distance ^ 2 then
        movement.towards(value.entity, target)
    end
end

local function nearest_item(surface, center)
    local found = surface.find_entities_filtered {
        position = center, radius = conf.search_radius, type = "item-entity"
    }
    local best, best_distance
    for _, entity in pairs(found) do
        if entity.valid and entity.stack and entity.stack.valid_for_read then
            local distance = movement.distance_squared(center, entity.position)
            if not best_distance or distance < best_distance then
                best, best_distance = entity, distance
            end
        end
    end
    return best
end

local function pickup(value)
    local free = conf.cargo_capacity - cargo_total(value)
    if free <= 0 then return end
    local items = value.entity.surface.find_entities_filtered {
        position = value.entity.position, radius = 1, type = "item-entity"
    }
    for _, entity in pairs(items) do
        if free <= 0 then break end
        if entity.valid and entity.stack and entity.stack.valid_for_read then
            local name, count = entity.stack.name, entity.stack.count
            local taken = math.min(count, free)
            value.cargo[name] = (value.cargo[name] or 0) + taken
            free = free - taken
            if taken == count then entity.destroy() else entity.stack.count = count - taken end
        end
    end
end

local function matching_container(player, value, item_name)
    local candidates = value.entity.surface.find_entities_filtered {
        position = value.entity.position, radius = conf.container_radius,
        force = player.force, type = container_types
    }
    local best, best_distance
    for _, entity in pairs(candidates) do
        local inventory = entity.valid and entity.get_inventory(defines.inventory.chest)
        if inventory and inventory.valid and inventory.get_item_count(item_name) > 0 and
                inventory.can_insert {name = item_name, count = 1} then
            local distance = movement.distance_squared(value.entity.position, entity.position)
            if not best_distance or distance < best_distance then
                best, best_distance = entity, distance
            end
        end
    end
    return best
end

local function destination(player, value)
    local best, best_distance
    for name, count in pairs(value.cargo) do
        if count > 0 then
            local entity = matching_container(player, value, name)
            if entity then
                local distance = movement.distance_squared(value.entity.position, entity.position)
                if not best_distance or distance < best_distance then best, best_distance = entity, distance end
            end
        end
    end
    if best then return best end
    local inventory = player.get_main_inventory()
    for name, count in pairs(value.cargo) do
        if count > 0 and inventory and inventory.can_insert {name = name, count = 1} then return player end
    end
end

local function deposit(player, value, target)
    local inventory = target == player and player.get_main_inventory() or
                          target.get_inventory(defines.inventory.chest)
    for name, count in pairs(value.cargo) do
        local matching = matching_container(player, value, name)
        if count > 0 and ((target == player and not matching) or target == matching) then
            local inserted = inventory.insert {name = name, count = count}
            if inserted == count then value.cargo[name] = nil else value.cargo[name] = count - inserted end
            if inserted > 0 then value.unplaceable[name] = nil end
        end
    end
end

function cleanup.enable(player)
    local value = state.get_cleanup(player.index)
    value.enabled = true
    if not (value.entity and value.entity.valid) and not create(player, value) then
        value.enabled = false
        message(player, constants.COLOR.ERROR, "could not create bot")
        return
    end
    message(player, constants.COLOR.SUCCESS, "enabled")
end

function cleanup.disable(player)
    local value = state.get_cleanup(player.index)
    state.destroy_cleanup(value)
    value.target = nil
    value.mode = "follow"
    message(player, constants.COLOR.SUCCESS, "disabled")
end

function cleanup.toggle(player)
    if state.get_cleanup(player.index).enabled then cleanup.disable(player) else cleanup.enable(player) end
end

function cleanup.status(player)
    local value = state.get_cleanup(player.index)
    local cargo = {}
    for name, count in pairs(value.cargo) do cargo[#cargo + 1] = name .. "=" .. count end
    table.sort(cargo)
    message(player, constants.COLOR.INFORMATION,
        string.format("enabled=%s mode=%s cargo=%s count=%d/%d", tostring(value.enabled), value.mode,
            #cargo > 0 and table.concat(cargo, ",") or "empty", cargo_total(value), conf.cargo_capacity))
end

function cleanup.update(player)
    local value = state.get_cleanup(player.index)
    if not value.enabled then return end
    if not (value.entity and value.entity.valid) and not create(player, value) then return end

    pickup(value)
    local carried = cargo_total(value)
    local item = carried < conf.cargo_capacity and
                     (nearest_item(value.entity.surface, value.entity.position) or
                         nearest_item(value.entity.surface, player_anchor.position(player))) or nil

    if item and item.valid then
        value.mode = "pickup"
        value.target = {x = item.position.x, y = item.position.y}
        movement.towards(value.entity, value.target)
    elseif carried > 0 then
        local target = destination(player, value)
        local target_position = target == player and player_anchor.position(player) or
                                    (target and target.position)
        if target and target.valid and movement.distance_squared(value.entity.position, target_position) <=
                conf.work_distance ^ 2 then
            deposit(player, value, target)
            value.mode, value.target = "follow", nil
        elseif target and target.valid then
            value.mode = "returning"
            value.target = {x = target_position.x, y = target_position.y}
            movement.towards(value.entity, value.target)
        else
            value.mode, value.target = "no-container", nil
            for name, count in pairs(value.cargo) do
                if count > 0 and not value.unplaceable[name] then
                    value.unplaceable[name] = true
                    message(player, constants.COLOR.WARNING,
                        "no matching container or player inventory space for '" .. name .. "'")
                end
            end
            follow(player, value)
        end
    else
        value.mode, value.target = "follow", nil
        follow(player, value)
    end

    draw_status(player, value)
    draw_target(value)
end

return cleanup
