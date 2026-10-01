local config = require("config")
local constants = require("constants")
local movement = require("movement")
local player_anchor = require("player_anchor")
local state = require("state")
local target_line = require("target_line")

local cliff_bot = {}
local conf = config.cliff

local function message(player, color, text)
    player.print({"", "[color=" .. color .. "][Cliff Bot][/color] ", text})
end

local function clear_object(value, field)
    local object = value[field]
    if object and object.valid then object.destroy() end
    value[field] = nil
end

local function create(player, value)
    local position, offset = player_anchor.position(player), conf.follow_offset
    value.entity = player_anchor.surface(player).create_entity {
        name = constants.CLIFF_BOT_ENTITY_NAME,
        position = {x = position.x + offset.x, y = position.y + offset.y},
        force = player.force, raise_built = true
    }
    if value.entity and value.entity.valid then value.entity.destructible = true end
    return value.entity and value.entity.valid
end

local function follow(player, value)
    local position = player_anchor.position(player)
    local previous = value.last_player_position
    if previous then
        local dx = position.x - previous.x
        if dx < -constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = math.abs(conf.follow_offset.x)
        elseif dx > constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = -math.abs(conf.follow_offset.x)
        end
    end
    value.last_player_position = {x = position.x, y = position.y}
    local destination = {x = position.x + value.side_offset_x, y = position.y + conf.follow_offset.y}
    if movement.distance_squared(value.entity.position, destination) > config.follow_distance ^ 2 then
        target_line.draw(player, value, destination)
        movement.towards(value.entity, destination)
    else
        target_line.clear(value)
    end
end

local function draw_status(player, value)
    clear_object(value, "status_label")
    if not (value.entity and value.entity.valid) then return end
    value.status_label = rendering.draw_text {
        text = string.format("[%s] cliffs: %d", value.mode, #value.queue),
        surface = value.entity.surface, target = value.entity, target_offset = {0, 0.8},
        color = {r = 1, g = 0.55, b = 0.15, a = 1}, scale = 0.7,
        alignment = "center", vertical_alignment = "top", only_in_alt_mode = false,
        players = {player.index}
    }
end

local function remove_marker(value, entity)
    local kept = {}
    for _, record in pairs(value.markers) do
        -- Records replace unit-number keys because cliffs are not guaranteed to
        -- expose a unit number. Legacy render objects are discarded safely.
        if type(record) == "table" and record.target == entity then
            if record.render and record.render.valid then record.render.destroy() end
        elseif type(record) == "table" and record.target and record.target.valid and
                record.render and record.render.valid then
            kept[#kept + 1] = record
        elseif type(record) ~= "table" and record.valid then
            record.destroy()
        end
    end
    value.markers = kept
end

local function prune(value)
    local kept = {}
    for _, entity in ipairs(value.queue) do
        if entity and entity.valid and entity.type == "cliff" then
            kept[#kept + 1] = entity
        end
    end
    value.queue = kept
    local markers = {}
    for _, record in pairs(value.markers) do
        if type(record) == "table" and record.target and record.target.valid and
                record.render and record.render.valid then
            markers[#markers + 1] = record
        elseif type(record) ~= "table" and record.valid then
            record.destroy()
        end
    end
    value.markers = markers
end

function cliff_bot.enable(player)
    local value = state.get_cliff(player.index)
    value.enabled = true
    if not (value.entity and value.entity.valid) and not create(player, value) then
        value.enabled = false
        message(player, constants.COLOR.ERROR, "could not create bot")
        return
    end
    message(player, constants.COLOR.SUCCESS, "enabled")
end

function cliff_bot.disable(player)
    local value = state.get_cliff(player.index)
    state.destroy_cliff(value)
    value.mode, value.target = "follow", nil
    message(player, constants.COLOR.SUCCESS, "disabled; marked cliffs remain queued")
end

function cliff_bot.toggle(player)
    if state.get_cliff(player.index).enabled then cliff_bot.disable(player) else cliff_bot.enable(player) end
end

function cliff_bot.give_selector(player)
    if player.cursor_stack and player.cursor_stack.valid then
        player.clear_cursor()
        if player.cursor_stack.set_stack {name = constants.CLIFF_SELECTOR_NAME, count = 1} then
            message(player, constants.COLOR.INFORMATION,
                "planner ready: drag with the left mouse button to mark cliffs")
        else
            message(player, constants.COLOR.ERROR, "could not put the planner in the cursor")
        end
    end
end

local function cliffs_in_area(player, entities, area)
    -- Base cliffs set selectable_in_game=false, so a selection-tool event may
    -- report an empty entity list. Querying its exact drag area is reliable.
    if area then
        return player.surface.find_entities_filtered {area = area, type = "cliff"}
    end
    return entities or {}
end

function cliff_bot.mark(player, entities, area)
    local value, added = state.get_cliff(player.index), 0
    prune(value)
    for _, entity in ipairs(cliffs_in_area(player, entities, area)) do
        if entity.valid and entity.type == "cliff" then
            local exists = false
            for _, queued in ipairs(value.queue) do
                if queued == entity then exists = true; break end
            end
            if not exists then
                value.queue[#value.queue + 1] = entity
                value.markers[#value.markers + 1] = {target = entity,
                    render = rendering.draw_rectangle {
                    color = {r = 1, g = 0.35, b = 0.05, a = 0.9}, width = 3,
                    filled = false,
                    left_top = entity.bounding_box.left_top,
                    right_bottom = entity.bounding_box.right_bottom,
                    surface = entity.surface, draw_on_ground = false,
                    only_in_alt_mode = false, players = {player.index}
                }}
                added = added + 1
            end
        end
    end
    if added > 0 and not value.enabled then cliff_bot.enable(player) end
    message(player, constants.COLOR.INFORMATION,
        string.format("marked %d cliff%s; %d queued", added, added == 1 and "" or "s", #value.queue))
end

function cliff_bot.unmark(player, entities, area)
    local value, remove = state.get_cliff(player.index), {}
    for _, entity in ipairs(cliffs_in_area(player, entities, area)) do
        if entity.valid and entity.type == "cliff" then remove[entity] = true end
    end
    local kept, count = {}, 0
    for _, entity in ipairs(value.queue) do
        if remove[entity] then remove_marker(value, entity); count = count + 1
        elseif entity.valid then kept[#kept + 1] = entity end
    end
    value.queue = kept
    message(player, constants.COLOR.INFORMATION, string.format("unmarked %d cliff%s", count, count == 1 and "" or "s"))
end

function cliff_bot.clear(player)
    local value = state.get_cliff(player.index)
    for _, record in pairs(value.markers) do
        local marker = type(record) == "table" and record.render or record
        if marker and marker.valid then marker.destroy() end
    end
    value.queue, value.markers, value.target = {}, {}, nil
    message(player, constants.COLOR.SUCCESS, "cleared marked cliffs")
end

function cliff_bot.status(player)
    local value = state.get_cliff(player.index)
    prune(value)
    message(player, constants.COLOR.INFORMATION,
        string.format("enabled=%s mode=%s queued=%d", tostring(value.enabled), value.mode, #value.queue))
end

function cliff_bot.update(player)
    local value = state.get_cliff(player.index)
    if not value.enabled then return end
    if not (value.entity and value.entity.valid) and not create(player, value) then return end
    local player_surface = player_anchor.surface(player)
    if value.entity.surface ~= player_surface then
        value.entity.teleport(player_anchor.position(player), player_surface)
        value.target = nil
    end
    prune(value)
    if value.target and not value.target.valid then value.target = nil end
    if not value.target then
        for _, entity in ipairs(value.queue) do
            if entity.surface == value.entity.surface then value.target = entity; break end
        end
    end
    if value.target then
        value.mode = "destroying"
        target_line.draw(player, value, value.target)
        if movement.distance_squared(value.entity.position, value.target.position) <= conf.work_distance ^ 2 then
            local target = value.target
            remove_marker(value, target)
            value.target = nil
            target.destroy {raise_destroy = true}
            prune(value)
        else
            movement.towards(value.entity, value.target.position)
        end
    else
        value.mode = "follow"
        follow(player, value)
    end
    draw_status(player, value)
end

return cliff_bot
