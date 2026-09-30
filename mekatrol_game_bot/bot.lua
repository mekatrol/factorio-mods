local config = require("config")
local constants = require("constants")
local executor = require("upgrade_executor")
local movement = require("movement")
local player_anchor = require("player_anchor")
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
    local position = player_anchor.position(player)
    value.entity = player_anchor.surface(player).create_entity {
        name = constants.BOT_ENTITY_NAME,
        position = {x = position.x + offset.x, y = position.y + offset.y},
        force = player.force,
        raise_built = true
    }
    -- Destructibility makes the helper obey the same environmental risks as the
    -- reference bots rather than acting as an invulnerable utility cursor.
    if value.entity and value.entity.valid then
        value.entity.destructible = true
        draw_mode_label(player, value)
    end
    return value.entity ~= nil and value.entity.valid
end

local function target_candidates(player, value, task)
    local scan = value.target_scan
    local radius = task.search_radius or config.search_radius
    if scan and movement.distance_squared(player_anchor.position(player), scan.origin) >=
            config.all_upgrades_refresh_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
        -- Do not spend the rest of a multi-tick scan walking cells around an
        -- area the player has already left.
        scan = nil
        value.target_scan = nil
    end
    if not scan then
        local position = player_anchor.position(player)
        scan = {
            origin = {x = position.x, y = position.y},
            offset_x = -radius,
            offset_y = -radius,
            radius = radius,
            entities = {},
            seen = {},
            names = registry.source_names(task)
        }
        value.target_scan = scan
    else
        -- Incremental scans retain candidates across ticks. A candidate can be
        -- mined or destroyed before the next cell is processed, and reading
        -- position from that invalid LuaEntity raises a non-recoverable error.
        for index = #scan.entities, constants.FIRST_INDEX, -constants.ITEM_TRANSFER_COUNT do
            local entity = scan.entities[index]
            if not (entity and entity.valid) then table.remove(scan.entities, index) end
        end
    end

    local cell_size = config.target_scan_cell_size
    for _ = constants.ITEM_TRANSFER_COUNT, config.target_scan_cells_per_tick do
        local left = scan.origin.x + scan.offset_x
        local top = scan.origin.y + scan.offset_y
        local entities = player_anchor.surface(player).find_entities_filtered {
            area = {{left, top}, {left + cell_size, top + cell_size}},
            name = scan.names,
            force = player.force
        }
        for _, entity in ipairs(entities) do
            if entity.valid then
                local identity = entity.unit_number
                local mapping = registry.mapping_for(task, entity.name)
                local owner = mapping and mapping.owner_task
                local entity_radius = owner and owner.search_radius or radius
                local within_scan_radius = movement.distance_squared(scan.origin, entity.position) <=
                                               radius ^ constants.DISTANCE_SQUARED_EXPONENT
                local within_owner_radius = not (task.all_upgrades and owner and owner.enforce_player_radius) or
                                                movement.distance_squared(scan.origin, entity.position) <=
                                                    entity_radius ^ constants.DISTANCE_SQUARED_EXPONENT
                if (not identity or not scan.seen[identity]) and within_scan_radius and within_owner_radius and
                        registry.mapping_available(player.force, task, entity.name) then
                    if identity then scan.seen[identity] = true end
                    local nearest = scan.entities[constants.FIRST_INDEX]
                    if not nearest then
                        scan.entities[constants.FIRST_INDEX] = entity
                    elseif task.all_upgrades and movement.distance_squared(value.entity.position, entity.position) <
                            movement.distance_squared(value.entity.position, nearest.position) then
                        -- Composite mode needs the complete local candidate set
                        -- for batch planning, but keeps the nearest entity first
                        -- so it still decides which kind of work to start with.
                        scan.entities[#scan.entities + constants.ITEM_TRANSFER_COUNT] = nearest
                        scan.entities[constants.FIRST_INDEX] = entity
                    elseif task.all_upgrades then
                        scan.entities[#scan.entities + constants.ITEM_TRANSFER_COUNT] = entity
                    elseif movement.distance_squared(value.entity.position, entity.position) <
                            movement.distance_squared(value.entity.position, nearest.position) then
                        scan.entities[constants.FIRST_INDEX] = entity
                    end
                end
            end
        end

        scan.offset_x = scan.offset_x + cell_size
        if scan.offset_x >= radius then
            scan.offset_x = -radius
            scan.offset_y = scan.offset_y + cell_size
        end
        if scan.offset_y >= radius then
            local result = scan.entities
            local origin = scan.origin
            value.target_scan = nil
            return result, false, origin
        end
    end
    return nil, true
end

local function highlight(player, value)
    -- Replace the previous render object rather than accumulating rectangles as
    -- targets change, which would leak visuals into long-running saves.
    if value.highlight and value.highlight.valid then value.highlight.destroy() end
    value.highlight = nil
    if not (value.target and value.target.valid) then return false end
    value.highlight = rendering.draw_rectangle {
        color = config.highlight_color, width = constants.HIGHLIGHT_LINE_WIDTH, filled = false,
        left_top = value.target.bounding_box.left_top,
        right_bottom = value.target.bounding_box.right_bottom,
        surface = value.target.surface, draw_on_ground = true, players = {player.index}
    }
    return true
end

local function cargo_count(value, item_name)
    -- Missing keys represent zero so cargo remains compact and serializable.
    return value.cargo[item_name] or constants.EMPTY_COUNT
end

local function cargo_total(value)
    -- Capacity counts individual items rather than distinct names, allowing a
    -- full batch to contain any mixture required by every enabled mapping.
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
    local player_position = player_anchor.position(player)
    if previous then
        local dx = player_position.x - previous.x
        if dx < -constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = math.abs(config.follow_offset.x)
        elseif dx > constants.HORIZONTAL_DIRECTION_THRESHOLD then
            value.side_offset_x = -math.abs(config.follow_offset.x)
        end
    end
    value.last_player_position = {x = player_position.x, y = player_position.y}
    local position = {x = player_position.x + value.side_offset_x,
                      y = player_position.y + config.follow_offset.y}
    -- A dead band prevents jitter once the bot is acceptably close to its
    -- formation position.
    if movement.distance_squared(value.entity.position, position) >
            config.follow_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
        movement.towards(value.entity, position)
    end
end

local function prepare_job(player, value, task)
    -- Queued plans can outlive their chest or logistic network. They are also
    -- promoted after update's active-reference checks, so validate them here
    -- before the state machine can dereference them later in this same tick.
    while #value.pickup_queue > constants.EMPTY_COUNT do
        local source = value.pickup_queue[constants.FIRST_INDEX].source
        if source and source.entity and source.entity.valid and
                (not source.network or source.network.valid) then break end
        table.remove(value.pickup_queue, constants.FIRST_INDEX)
    end
    while #value.delivery_queue > constants.EMPTY_COUNT do
        local destination = value.delivery_queue[constants.FIRST_INDEX].destination
        if destination and destination.entity and destination.entity.valid and
                (not destination.network or destination.network.valid) then break end
        table.remove(value.delivery_queue, constants.FIRST_INDEX)
    end

    if #value.pickup_queue > constants.EMPTY_COUNT then
        value.supply = value.pickup_queue[constants.FIRST_INDEX].source
        value.phase = constants.PHASE.FETCH
        return true
    end

    -- A finished concrete track unloads recovered items before locking another
    -- line; all-upgrades mode instead checks every local target first.
    if not value.track and not task.all_upgrades and
            #value.delivery_queue > constants.EMPTY_COUNT then
        local delivery = value.delivery_queue[constants.FIRST_INDEX]
        value.return_destination = delivery.destination
        value.return_item = delivery.item_name
        value.phase = constants.PHASE.RETURN
        return true
    end

    -- Lock a connected group before considering supplies. A temporarily starved
    -- track therefore waits instead of letting the bot start another line.
    if not value.track then
        local candidates, scan_in_progress, scan_origin = target_candidates(player, value, task)
        if scan_in_progress then return false, true end
        if task.all_upgrades and scan_origin and
                movement.distance_squared(player_anchor.position(player), scan_origin) >=
                    config.all_upgrades_refresh_distance ^ constants.DISTANCE_SQUARED_EXPONENT then
            -- The player crossed into another area while the incremental scan
            -- was running. Discard its small result and begin near the current
            -- position on the next tick rather than chasing stale targets.
            return false, true
        end
        local seed = candidates[constants.FIRST_INDEX]
        if not seed then
            -- All-upgrades mode delays unloading while another nearby target
            -- can consume any mixed replacement cargo already aboard. Once the
            -- local scan is exhausted, recovered items are returned normally.
            if #value.delivery_queue > constants.EMPTY_COUNT then
                local delivery = value.delivery_queue[constants.FIRST_INDEX]
                value.return_destination = delivery.destination
                value.return_item = delivery.item_name
                value.phase = constants.PHASE.RETURN
                return true
            end
            return false
        end
        -- Composite mode locks belt work onto one physical network, while
        -- independent entities share one local batch so supplies are collected
        -- for many inserters/containers in a single trip.
        value.track = track.discover(seed, task, candidates)
        track.draw(player, value, task)
    end

    local remaining = track.remaining_entities(value.track, task, value.entity.position, player.force, true)
    if #remaining == constants.EMPTY_COUNT then
        -- Only after every upgradeable member is gone may the scheduler choose a
        -- seed from another physical belt component.
        state.clear_track(value)
        if not task.all_upgrades and #value.delivery_queue > constants.EMPTY_COUNT then
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
    local required_item_blocked_by_capacity = nil
    local blocked_pickup_count = constants.EMPTY_COUNT

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
                local source
                -- Composite mappings remember the concrete task that supplied
                -- them, so special sourcing rules remain task-specific.
                local mapping_task = mapping.owner_task or task
                if mapping_task.player_or_red_container_supply then
                    source = supply.find_player_source(player, required_item) or
                                 supply.find_red_container(player, target, value.entity, required_item)
                else
                    source = supply.find_source(player, target, required_item)
                    if not source then
                        source = supply.find_nearby_container(player, target, value.entity, required_item,
                            mapping_task.nearby_container_radius or config.nearby_container_radius)
                    end
                end
                if source then
                    value.pickup_queue[#value.pickup_queue + constants.ITEM_TRANSFER_COUNT] = {
                        item_name = required_item,
                        source = source
                    }
                    planned_count = planned_count + constants.ITEM_TRANSFER_COUNT
                end
            else
                -- Remember that suitable local work is waiting on free cargo
                -- space. After planning finishes, a surplus batch can be
                -- offloaded rather than leaving a full bot permanently idle.
                required_item_blocked_by_capacity = required_item
                blocked_pickup_count = blocked_pickup_count + constants.ITEM_TRANSFER_COUNT
            end
        end
    end

    if #value.pickup_queue > constants.EMPTY_COUNT then
        local pickup = value.pickup_queue[constants.FIRST_INDEX]
        value.supply = pickup.source
        value.phase = constants.PHASE.FETCH
        return true
    end

    if required_item_blocked_by_capacity then
        -- Prefer cargo not reserved against any remaining local target. If all
        -- carried items are reserved, release one item of a different type so
        -- the currently missing replacement can still enter the shared hold.
        local surplus_item = nil
        for item_name, count in pairs(unallocated_cargo) do
            if count > constants.EMPTY_COUNT then surplus_item = item_name; break end
        end
        if not surplus_item then
            for item_name, count in pairs(value.cargo) do
                if count > constants.EMPTY_COUNT and item_name ~= required_item_blocked_by_capacity then
                    surplus_item = item_name
                    break
                end
            end
        end

        if surplus_item then
            local destination = supply.find_red_drop_container(player,
                remaining[constants.FIRST_INDEX], value.entity, surplus_item)
            if destination then
                -- Free the whole useful pickup batch in one return trip instead
                -- of alternating one deposit with one collection. Never exceed
                -- either surplus stock or the chest's live insertable capacity.
                local surplus_count = unallocated_cargo[surplus_item] or constants.EMPTY_COUNT
                if surplus_count <= constants.EMPTY_COUNT then
                    surplus_count = cargo_count(value, surplus_item)
                end
                local deposit_count = math.min(surplus_count, blocked_pickup_count,
                    destination.insertable_count or constants.ITEM_TRANSFER_COUNT)
                for _ = constants.ITEM_TRANSFER_COUNT, deposit_count do
                    -- The item is leaving working cargo, so discard its old
                    -- provenance before a future pickup creates a new origin.
                    consume_cargo_origin(value, surplus_item)
                    value.delivery_queue[#value.delivery_queue + constants.ITEM_TRANSFER_COUNT] = {
                        item_name = surplus_item,
                        destination = destination
                    }
                end
                value.return_destination = destination
                value.return_item = surplus_item
                value.phase = constants.PHASE.RETURN
                return true
            end
        end
    end

    state.clear_target(value)
    return false
end

local function show_blocked_destination(player, value, destination, item_name)
    state.clear_blocked_destination(value)
    if not (destination and destination.entity and destination.entity.valid) then return false end
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
    return true
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
    -- Planned pickups belong to the old task and must not leak into the newly
    -- selected mode. Physical cargo and delivery work remain conserved.
    value.pickup_queue = {}
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
        if not (blocked.destination and blocked.destination.entity and blocked.destination.entity.valid) or
                (blocked.destination.network and not blocked.destination.network.valid) then
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

    -- Saves made before 1.7.2 may contain one composite radius snapshot with
    -- targets from several disconnected lines. Convert it in place to the
    -- component containing its original anchor and discard only stale pickup
    -- plans; physical cargo and queued returns remain conserved.
    if task.all_upgrades and value.track and value.track.snapshot_position then
        state.clear_target(value)
        value.pickup_queue = {}
        track.refresh(player, value, task)
        value.next_scan_tick = tick
    end

    -- Strictly local tasks recheck at execution time. The player may have moved
    -- since discovery while the bot was fetching a replacement item.
    if task.enforce_player_radius and value.phase == constants.PHASE.UPGRADE and
            value.target and value.target.valid and
            movement.distance_squared(player_anchor.position(player), value.target.position) >
                (task.search_radius or config.search_radius) ^ constants.DISTANCE_SQUARED_EXPONENT then
        state.clear_target(value)
        state.clear_track(value)
        value.next_scan_tick = tick
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
            -- Every queued entry may reference the same vanished source. Drop
            -- the stale plan as a batch so selection can immediately consider
            -- another provider, including one much farther across the surface.
            value.pickup_queue = {}
        end
        state.clear_target(value)
        value.next_scan_tick = tick
    end
    if value.return_destination and (not value.return_destination.entity or
            not value.return_destination.entity.valid or
            (value.return_destination.network and not value.return_destination.network.valid)) then
        if #value.delivery_queue > constants.EMPTY_COUNT then
            table.remove(value.delivery_queue, constants.FIRST_INDEX)
        end
        value.return_destination = nil
        value.return_item = nil
        -- Keep undelivered cargo when a destination disappears; silently
        -- deleting the recovered item would violate material conservation.
        value.phase = constants.PHASE.FOLLOW
    end
    if value.phase == constants.PHASE.FOLLOW and not value.target and tick >= value.next_scan_tick then
        local _, scan_in_progress = prepare_job(player, value, task)
        value.next_scan_tick = tick + (scan_in_progress and constants.ITEM_TRANSFER_COUNT or
                                           (task.scan_interval or config.scan_interval))
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
                -- The chosen chest may have supplied several earlier entries
                -- and become empty mid-batch. Replan all outstanding pickups;
                -- retaining them would retry that empty chest one item at a
                -- time instead of selecting another stocked provider.
                value.pickup_queue = {}
                value.supply = nil
                value.phase = constants.PHASE.FOLLOW
                value.next_scan_tick = tick
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
            if not registry.mapping_available(player.force, task, source_name) then
                -- Research can be reversed by commands or scenarios after a
                -- target was planned. Cancel it without consuming cargo.
                state.clear_target(value)
                state.clear_track(value)
                value.next_scan_tick = tick
                return
            end
            local fallback_network = supply.first_network(player, value.target)
            -- In all-upgrades mode execution and return policy belong to the
            -- concrete task that contributed this mapping.
            local mapping_task = mapping.owner_task or task
            local success, detail = executor.execute(player, value.target, mapping, mapping_task)
            if success then
                -- Commit the material exchange only after the world replacement
                -- succeeds: one higher-tier item in, one lower-tier item out.
                cargo_remove(value, mapping.required_item, constants.ITEM_TRANSFER_COUNT)
                local origin = consume_cargo_origin(value, mapping.required_item)
                cargo_add(value, mapping.recovered_item, constants.ITEM_TRANSFER_COUNT)
                value.upgraded = value.upgraded + constants.ITEM_TRANSFER_COUNT
                local destination = mapping_task.return_to_source and origin or
                                        supply.find_drop(origin and origin.network or fallback_network,
                                            mapping.recovered_item)
                if not destination then
                    destination = supply.find_blocked_drop(origin and origin.network or fallback_network,
                        source_position)
                end
                if not destination and origin and origin.local_container and origin.entity and
                        origin.entity.valid then
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
                -- A replacement in composite mode can be the source of its
                -- next tier (yellow -> red -> blue). Rebuild from the locked
                -- anchor so the same network is exhausted before another one.
                if task.all_upgrades and not (value.track and value.track.independent_batch) then
                    track.refresh(player, value, task)
                end
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
                if not show_blocked_destination(player, value, destination, item_name) then
                    -- The destination may have been destroyed after it was
                    -- queued. Retain the cargo and discard the stale delivery.
                    table.remove(value.delivery_queue, constants.FIRST_INDEX)
                    value.next_scan_tick = tick
                end
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
                                             value.entity.valid and value.entity.position or
                                                 player_anchor.position(player), player.force) or
                                         constants.EMPTY_COUNT
    print(player, constants.COLOR.INFORMATION,
        string.format(constants.STATUS_FORMAT,
        tostring(value.enabled), value.task_name, value.phase, value.upgraded, value.failures,
        value.target and value.target.valid and value.target.name or constants.NONE_TEXT,
        #cargo > constants.EMPTY_COUNT and table.concat(cargo, constants.LIST_SEPARATOR) or
            constants.EMPTY_CARGO_TEXT, cargo_total(value), config.cargo_capacity, remaining_track_entities))
end

return bot
