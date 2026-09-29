local config = require("config")
local constants = require("constants")
local lamp_placer = require("lamp_placer")
local movement = require("movement")
local player_anchor = require("player_anchor")
local state = require("state")

local lamp_bot = {}
local conf = config.lamp

local function message(player, color, text)
    player.print({"", "[color=" .. color .. "][Lamp Bot][/color] ", text})
end

local function clear_status(value)
    if value.status_label and value.status_label.valid then value.status_label.destroy() end
    value.status_label = nil
end

local function draw_status(player, value)
    clear_status(value)
    if not (value.entity and value.entity.valid) then return end
    value.status_label = rendering.draw_text {
        text = "[" .. value.mode .. "] lamps",
        surface = value.entity.surface,
        target = value.entity,
        target_offset = {0, 0.8},
        color = {r = 1, g = 0.9, b = 0.25, a = 1},
        scale = 0.7,
        alignment = "center",
        vertical_alignment = "top",
        only_in_alt_mode = false,
        players = {player.index}
    }
end

local function create(player, value)
    -- Spawn directly in the lamp bot's formation slot so enabling it never
    -- overlaps either the player or one of the other two helpers.
    local player_position = player_anchor.position(player)
    local offset = conf.follow_offset
    value.entity = player_anchor.surface(player).create_entity {
        name = constants.LAMP_BOT_ENTITY_NAME,
        position = {x = player_position.x + offset.x, y = player_position.y + offset.y},
        force = player.force,
        raise_built = true
    }
    if value.entity then value.entity.destructible = true end
    return value.entity ~= nil
end

local function follow(player, value)
    -- This is the same trailing-side scheme as mekatrol_game_play_mod: record
    -- horizontal player movement and put idle bots on the opposite side.
    local player_position = player_anchor.position(player)
    local previous = value.last_player_position
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
    -- The dead band avoids tiny movements after the bot reaches its slot.
    if movement.distance_squared(value.entity.position, target) >
            config.follow_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
        movement.towards(value.entity, target)
    end
end

function lamp_bot.enable(player)
    local value = state.get_lamp(player.index)
    value.enabled = true
    if not (value.entity and value.entity.valid) and not create(player, value) then
        value.enabled = false
        message(player, constants.COLOR.ERROR, "could not create bot")
        return
    end
    value.next_scan_tick = constants.NO_TICK_DELAY
    message(player, constants.COLOR.SUCCESS, "enabled")
end

function lamp_bot.disable(player)
    local value = state.get_lamp(player.index)
    state.destroy_lamp(value)
    value.mode, value.target, value.supply = "follow", nil, nil
    message(player, constants.COLOR.SUCCESS, "disabled")
end

function lamp_bot.toggle(player)
    if state.get_lamp(player.index).enabled then lamp_bot.disable(player) else lamp_bot.enable(player) end
end

function lamp_bot.status(player)
    local value = state.get_lamp(player.index)
    message(player, constants.COLOR.INFORMATION,
        string.format("enabled=%s mode=%s target=%s", tostring(value.enabled), value.mode,
            value.target and string.format("%.1f,%.1f", value.target.x, value.target.y) or constants.NONE_TEXT))
end

function lamp_bot.update(player, tick)
    local value = state.get_lamp(player.index)
    if not value.enabled then return end
    -- Recreate a bot destroyed in combat; its logical work can safely resume
    -- because lamp targets and supply records contain no reserved materials.
    if not (value.entity and value.entity.valid) and not create(player, value) then return end

    if value.supply and not (value.supply.entity and value.supply.entity.valid) then value.supply = nil end

    if not value.target and not value.supply and tick >= value.next_scan_tick then
        value.next_scan_tick = tick + config.scan_interval
        value.target = lamp_placer.find_target(player)
        if not value.target and not lamp_placer.has_carried_lamp(player) and
                player_anchor.surface(player).darkness > config.lamp_darkness_threshold then
            value.supply = lamp_placer.find_red_container(player, value.entity)
        end
    end

    if value.supply then
        value.mode = "fetching"
        if movement.distance_squared(value.entity.position, value.supply.entity.position) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            local collected = lamp_placer.take_from_red_container(player, value.supply)
            value.supply = nil
            value.next_scan_tick = collected and tick or tick + config.scan_interval
        else
            movement.towards(value.entity, value.supply.entity.position)
        end
    elseif value.target then
        value.mode = "placing"
        -- Placement happens only after visible arrival at the selected tile.
        if movement.distance_squared(value.entity.position, value.target) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            lamp_placer.try_place_at(player, value.target)
            value.target = nil
            -- Delay the next scan so the new lamp participates in exclusion.
            value.next_scan_tick = tick + config.scan_interval
        else
            movement.towards(value.entity, value.target)
        end
    else
        value.mode = "follow"
        follow(player, value)
    end

    draw_status(player, value)
end

return lamp_bot
