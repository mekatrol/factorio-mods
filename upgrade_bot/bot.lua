local config = require("config")
local constants = require("constants")
local executor = require("upgrade_executor")
local movement = require("movement")
local registry = require("task_registry")
local state = require("state")
local supply = require("supply")
local bot = {}

local function print(player, color, message)
    -- A consistent prefix distinguishes autonomous-bot feedback from Factorio's
    -- own messages while the caller-provided color communicates severity.
    player.print({"", "[color=" .. color .. "][" .. constants.MOD_PREFIX .. "][/color] ", message})
end

local function create(player, value)
    -- Spawn near the player's configured follow position so activation does not
    -- place the bot on top of the character or an unrelated factory entity.
    local offset = config.follow_offset
    value.entity = player.surface.create_entity {
        name = constants.BOT_ENTITY_NAME,
        position = {x = player.position.x + offset.x, y = player.position.y + offset.y},
        force = player.force,
        raise_built = true
    }
    -- Destructibility makes the helper obey the same environmental risks as the
    -- reference bots rather than acting as an invulnerable utility cursor.
    if value.entity then value.entity.destructible = true end
    return value.entity ~= nil
end

local function target_candidates(player, value, task)
    -- Automatic discovery remains local to the player. Supply lookup is allowed
    -- to span a connected network, but scanning an entire surface every tick is
    -- both surprising and expensive on mature factories.
    local entities = player.surface.find_entities_filtered {
        position = player.position,
        radius = task.search_radius or config.search_radius,
        name = registry.source_names(task),
        force = player.force
    }
    -- Nearest-first ordering minimizes travel and makes selection deterministic
    -- enough for a player to understand what the bot will work on next.
    table.sort(entities, function(a, b)
        return movement.distance_squared(value.entity.position, a.position) <
                   movement.distance_squared(value.entity.position, b.position)
    end)
    return entities
end

local function highlight(player, value)
    -- Replace the previous render object rather than accumulating rectangles as
    -- targets change, which would leak visuals into long-running saves.
    if value.highlight and value.highlight.valid then value.highlight.destroy() end
    value.highlight = rendering.draw_rectangle {
        color = config.highlight_color, width = constants.HIGHLIGHT_LINE_WIDTH, filled = false,
        left_top = value.target.bounding_box.left_top,
        right_bottom = value.target.bounding_box.right_bottom,
        surface = value.target.surface, draw_on_ground = true, players = {player.index}
    }
end

local function cargo_count(value, item_name)
    -- Missing keys represent zero so cargo remains compact and serializable.
    return value.cargo[item_name] or constants.EMPTY_COUNT
end

local function cargo_add(value, item_name, count)
    -- Ignore incomplete mappings and non-positive transfers rather than creating
    -- unusable cargo entries that would obscure status output.
    if not item_name or count <= constants.EMPTY_COUNT then return end
    value.cargo[item_name] = cargo_count(value, item_name) + count
end

local function cargo_remove(value, item_name, count)
    -- Refuse underflow: resource accounting must never manufacture an upgrade
    -- by allowing a negative cargo balance.
    if cargo_count(value, item_name) < count then return false end
    value.cargo[item_name] = value.cargo[item_name] - count
    if value.cargo[item_name] == constants.EMPTY_COUNT then value.cargo[item_name] = nil end
    return true
end

local function follow_player(player, value)
    -- Mirror the reference mod's side switching: when the player changes
    -- horizontal direction, move the bot to the trailing side of travel.
    local previous = value.last_player_position
    if previous then
        local dx = player.position.x - previous.x
        if dx < -constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = math.abs(config.follow_offset.x)
        elseif dx > constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = -math.abs(config.follow_offset.x)
        end
    end
    value.last_player_position = {x = player.position.x, y = player.position.y}
    local position = {x = player.position.x + value.side_offset_x, y = player.position.y + config.follow_offset.y}
    -- A dead band prevents jitter once the bot is acceptably close to its
    -- formation position.
    if movement.distance_squared(value.entity.position, position) >
            config.follow_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
        movement.towards(value.entity, position)
    end
end

local function prepare_job(player, value, task)
    -- Evaluate candidates until one has a real material path. An unavailable
    -- belt type must not block another mapping whose supplies are available.
    for _, target in ipairs(target_candidates(player, value, task)) do
        local mapping = registry.mapping_for(task, target.name)
        local required_item = mapping and mapping.required_item
        if required_item then
            local source = nil
            local network = nil
            if cargo_count(value, required_item) == constants.EMPTY_COUNT then
                -- Prefer the vanilla network selector; ordinary containers are
                -- a deliberate fallback only when the network cannot supply.
                source = supply.find_source(player, target, required_item)
                if not source then
                    source = supply.find_nearby_container(player, target, value.entity, required_item,
                        task.nearby_container_radius or config.nearby_container_radius)
                end
                network = source and source.network
            else
                network = supply.first_network(player, target)
            end
            if cargo_count(value, required_item) > constants.EMPTY_COUNT or source then
                value.target = target
                value.supply = source
                value.job_network = network
                value.source_container = source and source.local_container and source or nil
                value.phase = source and constants.PHASE.FETCH or constants.PHASE.UPGRADE
                highlight(player, value)
                return true
            end
        end
    end
    state.clear_target(value)
    return false
end

function bot.enable(player)
    local value = state.get(player.index)
    if not (value.entity and value.entity.valid) and not create(player, value) then
        print(player, constants.COLOR.ERROR, "could not create bot")
        return
    end
    -- An immediate scan makes activation responsive instead of waiting through
    -- the normal idle polling interval.
    value.enabled, value.next_scan_tick = true, constants.NO_TICK_DELAY
    print(player, constants.COLOR.SUCCESS, "enabled; task: " .. value.task_name)
end

function bot.disable(player)
    state.destroy(state.get(player.index))
    print(player, constants.COLOR.WARNING, "disabled")
end

function bot.toggle(player)
    if state.get(player.index).enabled then bot.disable(player) else bot.enable(player) end
end

function bot.select_task(player, task_name)
    local task = registry.get(task_name)
    if not task then
        print(player, constants.COLOR.ERROR, "unknown task '" .. tostring(task_name) .. "'")
        return false
    end
    local value = state.get(player.index)
    state.clear_target(value)
    value.task_name, value.next_scan_tick = task.name, constants.NO_TICK_DELAY
    print(player, constants.COLOR.SUCCESS, "task selected: " .. task.name)
    return true
end

function bot.update(player, tick)
    -- Disabled players retain state and cargo but consume no scan or movement
    -- work, which keeps idle multiplayer overhead proportional to active bots.
    local value = state.get(player.index)
    if not value.enabled then return end
    if not (value.entity and value.entity.valid) then
        value.enabled = false
        print(player, constants.COLOR.ERROR, "was destroyed")
        return
    end
    local task = registry.get(value.task_name)
    if not task then
        -- A removed task cannot safely reinterpret its persisted mappings, so
        -- stop the bot and require an explicit valid task selection.
        value.enabled = false
        print(player, constants.COLOR.ERROR, "task is no longer registered")
        return
    end

    if value.target and not value.target.valid then state.clear_target(value) end
    if value.supply and (not value.supply.entity or not value.supply.entity.valid or
            (value.supply.network and not value.supply.network.valid)) then
        state.clear_target(value)
    end
    if value.return_destination and (not value.return_destination.entity or
            not value.return_destination.entity.valid or
            (value.return_destination.network and not value.return_destination.network.valid)) then
        value.return_destination = nil
        value.return_item = nil
        -- Keep undelivered cargo when a destination disappears; silently
        -- deleting the recovered item would violate material conservation.
        value.phase = constants.PHASE.FOLLOW
    end
    if value.phase == constants.PHASE.FOLLOW and not value.target and tick >= value.next_scan_tick then
        value.next_scan_tick = tick + (task.scan_interval or config.scan_interval)
        prepare_job(player, value, task)
    end

    if value.phase == constants.PHASE.FETCH and value.target and value.supply then
        local mapping = registry.mapping_for(task, value.target.name)
        local required_item = mapping and mapping.required_item
        if movement.distance_squared(value.entity.position, value.supply.entity.position) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            -- Withdrawal occurs only after physical arrival, making the visible
            -- chest count and bot animation describe the same transaction.
            if supply.take_one(value.supply, required_item) then
                cargo_add(value, required_item, constants.ITEM_TRANSFER_COUNT)
                value.supply = nil
                value.phase = constants.PHASE.UPGRADE
            else
                state.clear_target(value)
                value.next_scan_tick = tick + config.scan_interval
            end
        else
            movement.towards(value.entity, value.supply.entity.position)
        end
    elseif value.phase == constants.PHASE.UPGRADE and value.target then
        if movement.distance_squared(value.entity.position, value.target.position) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            -- Capture mapping and source identity before fast replacement makes
            -- the original LuaEntity invalid.
            local source_name = value.target.name
            local mapping = registry.mapping_for(task, source_name)
            local success, detail = executor.execute(player, value.target, mapping, task)
            if success then
                -- Commit the material exchange only after the world replacement
                -- succeeds: one higher-tier item in, one lower-tier item out.
                cargo_remove(value, mapping.required_item, constants.ITEM_TRANSFER_COUNT)
                cargo_add(value, mapping.recovered_item, constants.ITEM_TRANSFER_COUNT)
                value.upgraded = value.upgraded + constants.ITEM_TRANSFER_COUNT
                local destination = supply.find_drop(value.job_network, mapping.recovered_item)
                if not destination and value.source_container and value.source_container.entity.valid then
                    destination = value.source_container
                end
                state.clear_target(value)
                if destination then
                    value.return_destination = destination
                    value.return_item = mapping.recovered_item
                    value.phase = constants.PHASE.RETURN
                end
            else
                value.failures = value.failures + constants.ITEM_TRANSFER_COUNT
                print(player, constants.COLOR.ERROR, "could not upgrade " .. source_name .. ": " .. tostring(detail))
            end
            if not success then state.clear_target(value) end
            value.next_scan_tick = tick
        else
            movement.towards(value.entity, value.target.position)
        end
    elseif value.phase == constants.PHASE.RETURN and value.return_destination and value.return_item then
        if movement.distance_squared(value.entity.position, value.return_destination.entity.position) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            -- Deposit only after arrival. A failed insertion leaves the item in
            -- cargo, preserving it for status inspection and a future policy.
            if supply.put_one(value.return_destination, value.return_item) then
                cargo_remove(value, value.return_item, constants.ITEM_TRANSFER_COUNT)
            end
            value.return_destination = nil
            value.return_item = nil
            value.phase = constants.PHASE.FOLLOW
            value.next_scan_tick = tick
        else
            movement.towards(value.entity, value.return_destination.entity.position)
        end
    else
        follow_player(player, value)
    end
end

function bot.status(player)
    local value = state.get(player.index)
    local cargo = {}
    for name, count in pairs(value.cargo) do cargo[#cargo + constants.ITEM_TRANSFER_COUNT] = name .. "=" .. count end
    table.sort(cargo)
    -- Sorting cargo produces stable output that is easy to compare between
    -- repeated diagnostics and log captures.
    print(player, constants.COLOR.INFORMATION,
        string.format(constants.STATUS_FORMAT,
        tostring(value.enabled), value.task_name, value.phase, value.upgraded, value.failures,
        value.target and value.target.valid and value.target.name or constants.NONE_TEXT,
        #cargo > constants.EMPTY_COUNT and table.concat(cargo, constants.LIST_SEPARATOR) or
            constants.EMPTY_CARGO_TEXT))
end

return bot
