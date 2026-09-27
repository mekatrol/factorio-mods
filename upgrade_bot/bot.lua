local config = require("config")
local constants = require("constants")
local executor = require("upgrade_executor")
local lamp_placer = require("lamp_placer")
local movement = require("movement")
local registry = require("task_registry")
local state = require("state")
local supply = require("supply")
local track = require("track")
local bot = {}

local function draw_mode_label(player, value)
    if value.mode_label and value.mode_label.valid then value.mode_label.destroy() end
    value.mode_label = nil
    if not (value.entity and value.entity.valid) then return end
    local task = registry.get(value.task_name)
    value.mode_label = rendering.draw_text {
        text = task and (task.label or task.name) or value.task_name,
        surface = value.entity.surface,
        target = value.entity,
        target_offset = constants.MODE_LABEL_OFFSET,
        color = config.highlight_color,
        scale = constants.MODE_LABEL_SCALE,
        alignment = "center",
        vertical_alignment = "top",
        only_in_alt_mode = false,
        players = {player.index}
    }
end

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
    if value.entity then
        value.entity.destructible = true
        draw_mode_label(player, value)
    end
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

local function cargo_total(value)
    -- Capacity counts individual items rather than distinct names, allowing a
    -- five-item batch to contain any mixture required by belts and splitters.
    local total = constants.EMPTY_COUNT
    for _, count in pairs(value.cargo) do total = total + count end
    return total
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

local function upgradeable_underground_peer(entity, task)
    if not (entity and entity.valid and entity.type == constants.ENTITY_TYPE.UNDERGROUND_BELT) then return nil end
    local peer = entity.neighbours
    if peer and peer.valid and peer.type == constants.ENTITY_TYPE.UNDERGROUND_BELT and
            task.mappings[peer.name] then
        return peer
    end
    return nil
end

local function remember_cargo_origin(value, item_name, source)
    value.cargo_origins[item_name] = value.cargo_origins[item_name] or {}
    local origins = value.cargo_origins[item_name]
    origins[#origins + constants.ITEM_TRANSFER_COUNT] = source
end

local function consume_cargo_origin(value, item_name)
    local origins = value.cargo_origins[item_name]
    if not origins or #origins == constants.EMPTY_COUNT then return nil end
    local source = table.remove(origins, constants.FIRST_INDEX)
    if #origins == constants.EMPTY_COUNT then value.cargo_origins[item_name] = nil end
    return source
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
    if #value.pickup_queue > constants.EMPTY_COUNT then
        value.supply = value.pickup_queue[constants.FIRST_INDEX].source
        value.phase = constants.PHASE.FETCH
        return true
    end

    -- A finished track must unload recovered items before locking another line;
    -- otherwise five occupied slots could strand useful cargo indefinitely.
    if not value.track and #value.delivery_queue > constants.EMPTY_COUNT then
        local delivery = value.delivery_queue[constants.FIRST_INDEX]
        value.return_destination = delivery.destination
        value.return_item = delivery.item_name
        value.phase = constants.PHASE.RETURN
        return true
    end

    -- Lock a connected group before considering supplies. A temporarily starved
    -- track therefore waits instead of letting the bot start another line.
    if not value.track then
        local candidates = target_candidates(player, value, task)
        local seed = candidates[constants.FIRST_INDEX]
        if not seed then return false end
        value.track = track.discover(seed, task)
        track.draw(player, value, task)
    end

    local remaining = track.remaining_entities(value.track, task, value.entity.position)
    if #remaining == constants.EMPTY_COUNT then
        -- Only after every upgradeable member is gone may the scheduler choose a
        -- seed from another physical belt component.
        state.clear_track(value)
        if #value.delivery_queue > constants.EMPTY_COUNT then
            local delivery = value.delivery_queue[constants.FIRST_INDEX]
            value.return_destination = delivery.destination
            value.return_item = delivery.item_name
            value.phase = constants.PHASE.RETURN
            return true
        end
        return false
    end

    -- Finish a reserved underground pair before considering any other entity.
    -- Replacing the first endpoint can make Factorio remove the live neighbour
    -- relationship, so the original LuaEntity reference is the pair contract.
    local paired_target = value.paired_underground_target
    if paired_target and not (paired_target.valid and task.mappings[paired_target.name]) then
        value.paired_underground_target = nil
        paired_target = nil
    end
    if paired_target then
        local mapping = registry.mapping_for(task, paired_target.name)
        if mapping and cargo_count(value, mapping.required_item) > constants.EMPTY_COUNT then
            value.target = paired_target
            value.phase = constants.PHASE.UPGRADE
            highlight(player, value)
            return true
        end
    end

    -- Consume every useful replacement already on board before considering
    -- either unloading or another collection trip. An intact underground pair
    -- is selected only when both replacements are aboard; the second item is
    -- thereby reserved even if replacing the first endpoint disconnects it.
    for _, target in ipairs(remaining) do
        local mapping = registry.mapping_for(task, target.name)
        local peer = upgradeable_underground_peer(target, task)
        local required_count = peer and constants.UNDERGROUND_PAIR_SIZE or constants.ITEM_TRANSFER_COUNT
        if mapping and cargo_count(value, mapping.required_item) >= required_count then
            value.paired_underground_target = peer
            value.target = target
            value.phase = constants.PHASE.UPGRADE
            highlight(player, value)
            return true
        end
    end

    -- Recover cargo produced by older versions that did not retain a delivery
    -- instruction when network storage was unavailable. This migration path
    -- prevents a full legacy cargo hold from permanently stopping the bot.
    local queued_by_item = {}
    for _, delivery in pairs(value.delivery_queue) do
        queued_by_item[delivery.item_name] = (queued_by_item[delivery.item_name] or constants.EMPTY_COUNT) +
                                                 constants.ITEM_TRANSFER_COUNT
    end
    for source_name in pairs(task.mappings) do
        local mapping = registry.mapping_for(task, source_name)
        local recovered_item = mapping and mapping.recovered_item
        local missing_deliveries = recovered_item and
                                       (cargo_count(value, recovered_item) -
                                           (queued_by_item[recovered_item] or constants.EMPTY_COUNT)) or
                                       constants.EMPTY_COUNT
        if missing_deliveries > constants.EMPTY_COUNT then
            local network = supply.first_network(player, remaining[constants.FIRST_INDEX])
            local destination = supply.find_drop(network, recovered_item) or
                                    supply.find_blocked_drop(network, value.entity.position) or
                                    supply.find_nearby_drop_container(player, remaining[constants.FIRST_INDEX],
                                        recovered_item, config.nearby_container_radius)
            if destination then
                for _ = constants.ITEM_TRANSFER_COUNT, missing_deliveries do
                    value.delivery_queue[#value.delivery_queue + constants.ITEM_TRANSFER_COUNT] = {
                        item_name = recovered_item,
                        destination = destination
                    }
                end
            end
        end
    end

    -- Once no carried replacement can advance this track, empty every queued
    -- recovered item before collecting again. Returning only one item would
    -- create one free slot and degrade all later trips into one-item batches.
    if #value.delivery_queue > constants.EMPTY_COUNT then
        local delivery = value.delivery_queue[constants.FIRST_INDEX]
        value.return_destination = delivery.destination
        value.return_item = delivery.item_name
        value.phase = constants.PHASE.RETURN
        return true
    end

    -- Reserve existing replacement cargo against nearby targets before planning
    -- pickups. This prevents collecting duplicates while another item type in
    -- the same configured-size batch is still needed.
    local unallocated_cargo = {}
    for item_name, count in pairs(value.cargo) do unallocated_cargo[item_name] = count end
    local planned_count = constants.EMPTY_COUNT

    for _, target in ipairs(remaining) do
        local mapping = registry.mapping_for(task, target.name)
        local required_item = mapping and mapping.required_item
        if required_item then
            if (unallocated_cargo[required_item] or constants.EMPTY_COUNT) > constants.EMPTY_COUNT then
                unallocated_cargo[required_item] = unallocated_cargo[required_item] -
                                                       constants.ITEM_TRANSFER_COUNT
            elseif cargo_total(value) + planned_count < config.cargo_capacity then
                -- Prefer vanilla logistic selection, then fall back to an
                -- ordinary local container exactly as single-item mode did.
                local source = supply.find_source(player, target, required_item)
                if not source then
                    source = supply.find_nearby_container(player, target, value.entity, required_item,
                        task.nearby_container_radius or config.nearby_container_radius)
                end
                if source then
                    value.pickup_queue[#value.pickup_queue + constants.ITEM_TRANSFER_COUNT] = {
                        item_name = required_item,
                        source = source
                    }
                    planned_count = planned_count + constants.ITEM_TRANSFER_COUNT
                end
            end
        end
    end

    if #value.pickup_queue > constants.EMPTY_COUNT then
        local pickup = value.pickup_queue[constants.FIRST_INDEX]
        value.supply = pickup.source
        value.phase = constants.PHASE.FETCH
        return true
    end

    state.clear_target(value)
    return false
end

local function show_blocked_destination(player, value, destination, item_name)
    state.clear_blocked_destination(value)
    value.blocked_destination = {destination = destination, item_name = item_name}
    value.blocked_highlight = rendering.draw_rectangle {
        color = config.blocked_container_color,
        width = constants.BLOCKED_CONTAINER_LINE_WIDTH,
        filled = false,
        left_top = destination.entity.bounding_box.left_top,
        right_bottom = destination.entity.bounding_box.right_bottom,
        surface = destination.entity.surface,
        draw_on_ground = true,
        players = {player.index}
    }
    -- The item icon and explanatory text appear on both the map and minimap.
    value.blocked_tag = player.force.add_chart_tag(destination.entity.surface, {
        position = destination.entity.position,
        icon = {type = "item", name = item_name},
        text = constants.BLOCKED_CONTAINER_TAG_TEXT
    })
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
    draw_mode_label(player, value)
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
    state.clear_track(value)
    value.task_name, value.next_scan_tick = task.name, constants.NO_TICK_DELAY
    draw_mode_label(player, value)
    print(player, constants.COLOR.SUCCESS, "task selected: " .. task.name)
    return true
end

function bot.next_task(player)
    local value = state.get(player.index)
    local task = registry.next(value.task_name)
    return task and bot.select_task(player, task.name) or false
end

function bot.refresh_track(player)
    local value = state.get(player.index)
    local task = registry.get(value.task_name)
    if not value.track then
        print(player, constants.COLOR.WARNING, "there is no active track to refresh")
        return false
    end
    if not task or not track.refresh(player, value, task) then
        print(player, constants.COLOR.WARNING, "the active track no longer has a valid anchor")
        return false
    end
    value.track_refresh_requested = false
    print(player, constants.COLOR.SUCCESS, "active track outline refreshed")
    return true
end

function bot.request_track_refresh(entity)
    -- World-change events are global. Mark only active bots on the same surface
    -- and force so another player's unrelated factory does not trigger work.
    if not (entity and entity.valid) then return end
    state.ensure()
    for _, value in pairs(storage[constants.STORAGE_KEY].players) do
        -- The bot's own fast replacement fires script_raised_built while an
        -- underground pair can be temporarily disconnected by mixed tiers.
        -- Preserve the locked group for that internal event; player/robot edits
        -- in every other phase still request a full graph rebuild.
        if value.enabled and value.track and value.entity and value.entity.valid and
                value.entity.surface == entity.surface and value.entity.force == entity.force and
                value.phase ~= constants.PHASE.UPGRADE then
            value.track_refresh_requested = true
        end
    end
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

    -- Backfill the label for bots created by saves from before mode labels were
    -- introduced. Once created it follows the entity without per-tick redraws.
    if not (value.mode_label and value.mode_label.valid) then draw_mode_label(player, value) end

    -- While storage is full the helper follows the player and performs no new
    -- upgrades. A non-mutating capacity probe resumes the return automatically.
    if value.blocked_destination then
        local blocked = value.blocked_destination
        if not (blocked.destination and blocked.destination.entity and blocked.destination.entity.valid) then
            -- A destroyed destination cannot ever become writable. Keep the
            -- physical cargo, discard only the obsolete delivery instruction.
            state.clear_blocked_destination(value)
            table.remove(value.delivery_queue, constants.FIRST_INDEX)
        elseif supply.can_put_one(blocked.destination, blocked.item_name) then
            state.clear_blocked_destination(value)
            value.return_destination = blocked.destination
            value.return_item = blocked.item_name
            value.phase = constants.PHASE.RETURN
        else
            value.phase = constants.PHASE.FOLLOW
            follow_player(player, value)
            return
        end
    end
    local task = registry.get(value.task_name)
    if not task then
        -- A removed task cannot safely reinterpret its persisted mappings, so
        -- stop the bot and require an explicit valid task selection.
        value.enabled = false
        print(player, constants.COLOR.ERROR, "task is no longer registered")
        return
    end

    if task.kind == constants.LAMP_MODE_KIND then
        follow_player(player, value)
        if tick >= value.next_scan_tick then
            value.next_scan_tick = tick + (task.scan_interval or config.scan_interval)
            -- Place at most one lamp per scan. The following scan sees that new
            -- lamp and excludes the area it has just illuminated.
            lamp_placer.try_place(player)
        end
        return
    end

    -- Event handlers defer rebuilding until the next normal bot tick. By then a
    -- mined entity is gone and a built or rotated entity has final connections.
    if value.track_refresh_requested then
        value.track_refresh_requested = false
        track.refresh(player, value, task)
    end

    if value.target and not value.target.valid then state.clear_target(value) end
    if value.supply and (not value.supply.entity or not value.supply.entity.valid or
            (value.supply.network and not value.supply.network.valid)) then
        if value.phase == constants.PHASE.FETCH and #value.pickup_queue > constants.EMPTY_COUNT then
            table.remove(value.pickup_queue, constants.FIRST_INDEX)
        end
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

    if value.phase == constants.PHASE.FETCH and value.supply then
        local pickup = value.pickup_queue[constants.FIRST_INDEX]
        local required_item = pickup and pickup.item_name
        if movement.distance_squared(value.entity.position, value.supply.entity.position) <=
                config.work_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            -- Withdrawal occurs only after physical arrival, making the visible
            -- chest count and bot animation describe the same transaction.
            if supply.take_one(value.supply, required_item) then
                cargo_add(value, required_item, constants.ITEM_TRANSFER_COUNT)
                remember_cargo_origin(value, required_item, pickup.source)
                table.remove(value.pickup_queue, constants.FIRST_INDEX)
                value.supply = nil
                if #value.pickup_queue > constants.EMPTY_COUNT then
                    value.supply = value.pickup_queue[constants.FIRST_INDEX].source
                    value.phase = constants.PHASE.FETCH
                else
                    value.phase = constants.PHASE.FOLLOW
                    value.next_scan_tick = tick
                end
            else
                table.remove(value.pickup_queue, constants.FIRST_INDEX)
                value.supply = nil
                value.phase = constants.PHASE.FOLLOW
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
            local source_position = {x = value.target.position.x, y = value.target.position.y}
            local mapping = registry.mapping_for(task, source_name)
            local fallback_network = supply.first_network(player, value.target)
            local success, detail = executor.execute(player, value.target, mapping, task)
            if success then
                -- Commit the material exchange only after the world replacement
                -- succeeds: one higher-tier item in, one lower-tier item out.
                cargo_remove(value, mapping.required_item, constants.ITEM_TRANSFER_COUNT)
                local origin = consume_cargo_origin(value, mapping.required_item)
                cargo_add(value, mapping.recovered_item, constants.ITEM_TRANSFER_COUNT)
                value.upgraded = value.upgraded + constants.ITEM_TRANSFER_COUNT
                local destination = supply.find_drop(origin and origin.network or fallback_network,
                    mapping.recovered_item)
                if not destination then
                    destination = supply.find_blocked_drop(origin and origin.network or fallback_network,
                        source_position)
                end
                if not destination and origin and origin.local_container and origin.entity.valid then
                    destination = origin
                end
                if not destination and origin and origin.entity and origin.entity.valid then
                    -- A provider network may have ample replacement stock but no
                    -- storage chest. Returning the recovered item to its source
                    -- is preferable to filling cargo with an undeliverable item.
                    destination = origin
                end
                local completed_reserved_endpoint = value.paired_underground_target == value.target
                state.clear_target(value)
                if completed_reserved_endpoint then
                    value.paired_underground_target = nil
                end
                if destination then
                    value.delivery_queue[#value.delivery_queue + constants.ITEM_TRANSFER_COUNT] = {
                        item_name = mapping.recovered_item,
                        destination = destination
                    }
                end
                -- Continue consuming the batch before making a storage trip.
                value.phase = constants.PHASE.FOLLOW
                -- Internal replacements deliberately suppress graph rebuilding,
                -- so redraw against the locked group to remove only completed
                -- entities while retaining unmatched underground endpoints.
                track.draw(player, value, task)
            else
                value.failures = value.failures + constants.ITEM_TRANSFER_COUNT
                value.paired_underground_target = nil
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
                table.remove(value.delivery_queue, constants.FIRST_INDEX)
                value.return_destination = nil
                value.return_item = nil
                value.phase = constants.PHASE.FOLLOW
                value.next_scan_tick = tick
            else
                local destination = value.return_destination
                local item_name = value.return_item
                value.return_destination = nil
                value.return_item = nil
                value.phase = constants.PHASE.FOLLOW
                show_blocked_destination(player, value, destination, item_name)
            end
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
    local task = registry.get(value.task_name)
    local remaining_track_entities = task and value.track and
                                         #track.remaining_entities(value.track, task, value.entity and
                                             value.entity.valid and value.entity.position or player.position) or
                                         constants.EMPTY_COUNT
    print(player, constants.COLOR.INFORMATION,
        string.format(constants.STATUS_FORMAT,
        tostring(value.enabled), value.task_name, value.phase, value.upgraded, value.failures,
        value.target and value.target.valid and value.target.name or constants.NONE_TEXT,
        #cargo > constants.EMPTY_COUNT and table.concat(cargo, constants.LIST_SEPARATOR) or
            constants.EMPTY_CARGO_TEXT, cargo_total(value), config.cargo_capacity, remaining_track_entities))
end

return bot
