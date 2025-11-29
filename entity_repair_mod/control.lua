---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
-- How often (in ticks) to update the repair bot logic.
-- 60 ticks = 1 second, so 30 = every 0.5 seconds.
local WALL_BOT_UPDATE_INTERVAL = 30

-- Radius (in tiles) around the player to search for damaged entities.
-- (Name kept for compatibility, but this applies to ANY entity with health.)
local WALL_SEARCH_RADIUS = 64

-- Distance (in tiles) at which the bot considers itself "close enough"
-- to a target entity to perform repairs.
local WALL_REPAIR_DISTANCE = 20.0

-- Radius (in tiles) around the repair target to actually repair entities.
-- All entities in this radius will be repaired to max health.
local WALL_REPAIR_RADIUS = 20.0

---------------------------------------------------
-- HEALTH HELPERS / MAX HEALTH OVERRIDES
---------------------------------------------------
-- Optional static overrides for max health of specific entity names.
-- You can fill this if you want to override prototype.max_health for any entity.
-- Example:
--   ["stone-wall"] = 350
--
-- By default this is empty and the mod uses prototype.max_health.
local ENTITY_MAX_HEALTH = ENTITY_MAX_HEALTH or {
    ["stone-wall"] = 350,
    ["gun-turret"] = 400,
    ["fast-transport-belt"] = 160,
    ["small-electric-pole"] = 100,
    ["fast-inserter"] = 150,
    ["small-lamp"] = 100,
    ["electric-mining-drill"] = 300,
    ["inserter"] = 150,
    ["iron-chest"] = 200,
    ["character"] = 250,
    ["fast-splitter"] = 180,
    ["transport-belt"] = 150,
    ["splitter"] = 170,
    ["stone-furnace"] = 200,
    ["assembling-machine-1"] = 300,
    ["underground-belt"] = 150,
    ["burner-inserter"] = 100,
    ["burner-mining-drill"] = 150,
    ["long-handed-inserter"] = 160,
    ["lab"] = 150,
    ["fast-underground-belt"] = 160,
    ["wooden-chest"] = 100
}

-- Tracks which entity names we have already warned about (so we don't spam chat).
local UNKNOWN_ENTITY_WARNED = UNKNOWN_ENTITY_WARNED or {}

-- Scan all entities of this name for this force and return the highest
-- .health value observed. Also prints a suggested constant to add.
local function infer_max_health_from_world(name, force)
    if not name or not force then
        return nil
    end

    local max_health_seen = 0

    for _, surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered {
            name = name,
            force = force
        }

        for _, e in pairs(entities) do
            if e.valid and e.health and e.health > max_health_seen then
                max_health_seen = e.health
            end
        end
    end

    if max_health_seen > 0 then
        local suggested = math.floor(max_health_seen + 0.5)
        game.print(string.format("[WallRepair][INFO] Observed max health %.1f for '%s' (force=%s). " ..
                                     "Suggested: ENTITY_MAX_HEALTH[\"%s\"] = %d", max_health_seen, name, force.name,
            name, suggested))

        local line = string.format("ENTITY_MAX_HEALTH[\"%s\"] = %d\n", name, suggested)

        game.print("[WallRepair][INFO] " .. line)

        if helpers and helpers.write_file then
            helpers.write_file("repair_mod_maxhealth.txt", line, true)
        else
            -- fallback to avoid crashing
            game.print("[WallRepair][WARN] helpers.write_file not available; cannot write to disk.")
        end

        return suggested
    else
        game.print(string.format(
            "[WallRepair][INFO] Could not infer max health for '%s' (no live entities with health).", name))
        return nil
    end
end

local function get_entity_max_health(entity)
    if not (entity and entity.valid) then
        return nil
    end

    local name = entity.name

    ---------------------------------------------------
    -- 1) Check explicit table first
    ---------------------------------------------------
    local from_table = ENTITY_MAX_HEALTH[name]
    if type(from_table) == "number" and from_table > 0 then
        return from_table
    end

    ---------------------------------------------------
    -- 2) Try to infer from world once, for this entity type
    ---------------------------------------------------
    if not UNKNOWN_ENTITY_WARNED[name] then
        UNKNOWN_ENTITY_WARNED[name] = true
        local inferred = infer_max_health_from_world(name, entity.force)
        if inferred and inferred > 0 then
            -- Return what we inferred for this run (still not stored in table;
            -- you can copy from the print and add it to ENTITY_MAX_HEALTH for next version).
            return inferred
        end
    end

    ---------------------------------------------------
    -- 3) No reliable max health available
    ---------------------------------------------------
    return nil
end

-- Generic damage check for any entity type.
-- Returns true if the entity has health and is below its max health.
local function is_entity_damaged(entity)
    if not (entity and entity.valid and entity.health) then
        return false
    end

    local max = get_entity_max_health(entity)
    if not max then
        return false
    end

    return entity.health < max
end

---------------------------------------------------
-- PLAYER STATE / INITIALISATION
---------------------------------------------------

-- Initialise persistent data for a single player.
-- This is only called for the specific player that needs it,
-- not for every player in the game.
local function init_player(player)
    -- Root storage table for this mod.
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    local s = storage.wall_repair_mod

    -- Per-player subtable.
    s.players = s.players or {}
    local pdata = s.players[player.index]

    if not pdata then
        -- First-time initialisation for this player.
        pdata = {
            -- Whether this player's repair bot is enabled.
            wall_bot_enabled = false,

            -- The actual bot entity (LuaEntity) or nil if not spawned.
            wall_bot = nil,

            -- Route of damaged entities to visit (array of LuaEntity).
            repair_targets = nil,

            -- Index into repair_targets for the current target.
            current_target_index = 1,

            -- LuaRenderObject to visually highlight the bot (green box).
            highlight_object = nil,

            -- The list of recorded damaged markers (dots).
            damaged_markers = nil,

            -- Line render objects from damaged entities to the player.
            damaged_lines = nil
        }

        s.players[player.index] = pdata
    else
        -- Backwards compatibility / ensure all fields exist.
        if pdata.wall_bot_enabled == nil then
            pdata.wall_bot_enabled = false
        end

        pdata.repair_targets = pdata.repair_targets or nil
        pdata.current_target_index = pdata.current_target_index or 1
        pdata.highlight_object = pdata.highlight_object or nil
        pdata.damaged_markers = pdata.damaged_markers or nil
        pdata.damaged_lines = pdata.damaged_lines or nil
    end
end

-- Obtain the persistent player data table for a given player index.
-- If it doesn't exist yet, this will initialise it.
local function get_player_data(index)
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    local s = storage.wall_repair_mod

    s.players = s.players or {}
    local pdata = s.players[index]

    if not pdata then
        local player = game.get_player(index)
        if player then
            init_player(player)
            pdata = s.players[index]
        end
    end

    return pdata
end

---------------------------------------------------
-- DAMAGED ENTITY MARKERS (DOTS + LINES)
---------------------------------------------------

-- Destroy and forget all previously drawn green dots and lines for damaged entities.
local function clear_damaged_markers(pdata)
    if pdata.damaged_markers then
        for _, obj in pairs(pdata.damaged_markers) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.damaged_markers = nil
    end

    if pdata.damaged_lines then
        for _, obj in pairs(pdata.damaged_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.damaged_lines = nil
    end
end

-- Draw a green dot on each damaged entity and a line from the entity to the player.
-- This does NOT clear old visuals; call clear_damaged_markers first
-- if you want only the current set to be visible.
local function draw_damaged_visuals(player, pdata, damaged_entities)
    if not damaged_entities or #damaged_entities == 0 then
        return
    end

    pdata.damaged_markers = pdata.damaged_markers or {}
    pdata.damaged_lines = pdata.damaged_lines or {}

    local player_target = player.character or player

    for _, ent in pairs(damaged_entities) do
        if ent and ent.valid then
            -- Small filled green circle at the entity's position (dot).
            local dot = rendering.draw_circle {
                color = {
                    r = 0,
                    g = 1,
                    b = 0,
                    a = 1
                }, -- solid green
                radius = 0.15,
                filled = true,
                target = ent,
                surface = ent.surface,
                only_in_alt_mode = false
            }
            pdata.damaged_markers[#pdata.damaged_markers + 1] = dot

            -- Line from the entity to the player.
            local line = rendering.draw_line {
                color = {
                    r = 1,
                    g = 0,
                    b = 0,
                    a = 0.1
                }, -- semi-transparent red
                width = 1,
                from = ent, -- start at entity
                to = player_target, -- end at player entity (follows movement)
                surface = ent.surface,
                only_in_alt_mode = false
            }
            pdata.damaged_lines[#pdata.damaged_lines + 1] = line
        end
    end
end

---------------------------------------------------
-- VISUALS (BOT HIGHLIGHT)
---------------------------------------------------

-- Draw or update a green rectangle around the bot so the player can see it easily.
local function draw_bot_highlight(bot, pdata)
    if not (bot and bot.valid) then
        return
    end

    -- Half-size of the highlight box around the bot.
    local size = 0.6
    local pos = bot.position

    local left_top = {pos.x - size, pos.y - size}
    local right_bottom = {pos.x + size, pos.y + size}

    -- If we already have a rectangle, update it in-place.
    if pdata.highlight_object then
        local obj = pdata.highlight_object -- LuaRenderObject
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            -- If the object has become invalid, forget it.
            pdata.highlight_object = nil
        end
    end

    -- Create a new rectangle and store the LuaRenderObject handle.
    pdata.highlight_object = rendering.draw_rectangle {
        color = {
            r = 0,
            g = 1,
            b = 0,
            a = 0.7
        }, -- semi-transparent green
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = bot.surface,
        only_in_alt_mode = false
    }
end

---------------------------------------------------
-- LIFECYCLE EVENTS
---------------------------------------------------

-- Called once when the mod is first initialised for a save.
script.on_init(function()
    storage.wall_repair_mod = storage.wall_repair_mod or {}
end)

-- Called when mod configuration (version, dependencies, etc.) changes.
script.on_configuration_changed(function(_)
    storage.wall_repair_mod = storage.wall_repair_mod or {}
end)

-- Called when a new player is created (e.g. new game or new MP player).
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        init_player(player)
    end
end)

-- Called when the control.lua is loaded.
-- storage is already restored by Factorio, so nothing needed here.
script.on_load(function()
end)

---------------------------------------------------
-- DAMAGED ENTITY SEARCH
---------------------------------------------------

-- Find all damaged entities of this force on the given surface
-- within a radius around "center".
-- This is now generic: ANY entity with health can be a candidate.
local function find_damaged_entities(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    -- We search all entities of this force in the area.
    -- is_entity_damaged() will filter out those without health or not damaged.
    local candidates = surface.find_entities_filtered {
        force = force,
        area = area
    }

    local damaged = {}

    for _, ent in pairs(candidates) do
        if is_entity_damaged(ent) then
            damaged[#damaged + 1] = ent
        end
    end

    return damaged
end

---------------------------------------------------
-- ROUTE BUILDING (NEAREST NEIGHBOUR)
---------------------------------------------------

-- Build an ordered route over a set of entities, such that each next entity
-- is the nearest to the previous one. This is a greedy nearest-neighbour TSP approximation.
local function build_nearest_route(entities, start_pos)
    local ordered = {}
    local used = {}
    local remaining = #entities

    -- Start the route from the given starting position (usually the bot position).
    local current_x = start_pos.x
    local current_y = start_pos.y

    while remaining > 0 do
        local best_i, best_d2 = nil, nil

        -- Find the nearest unused, valid entity to the current point.
        for i, ent in ipairs(entities) do
            if not used[i] and ent.valid then
                local ep = ent.position
                local dx = ep.x - current_x
                local dy = ep.y - current_y
                local d2 = dx * dx + dy * dy

                if not best_d2 or d2 < best_d2 then
                    best_d2 = d2
                    best_i = i
                end
            end
        end

        -- If we couldn't find any more valid entities, stop.
        if not best_i then
            break
        end

        -- Add the chosen entity to the ordered route.
        local e = entities[best_i]
        used[best_i] = true
        ordered[#ordered + 1] = e
        remaining = remaining - 1

        -- Advance the "current point" to this entity.
        local ep = e.position
        current_x = ep.x
        current_y = ep.y
    end

    return ordered
end

-- Rebuild the player's current repair route.
-- Damaged entities are FOUND around the PLAYER, but the route itself is still
-- built starting from the BOT position (so the bot travels efficiently).
local function rebuild_repair_route(player, pdata, bot)
    if not (bot and bot.valid) then
        -- No bot => no route => no markers.
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        clear_damaged_markers(pdata)
        return
    end

    if not (player and player.valid) then
        -- No valid player; safest is to clear and bail.
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        clear_damaged_markers(pdata)
        return
    end

    local surface = bot.surface
    local force = bot.force

    -- Search center is the PLAYER position, not the bot.
    local search_center = player.position

    -- Search for damaged entities around the player.
    local damaged = find_damaged_entities(surface, force, search_center, WALL_SEARCH_RADIUS)

    -- Always reset markers based on the latest damaged list.
    clear_damaged_markers(pdata)

    if not damaged or #damaged == 0 then
        -- No damaged entities found: clear route and leave no dots/lines.
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        return
    end

    -- Draw a green dot and line for every damaged entity we found near the player.
    draw_damaged_visuals(player, pdata, damaged)

    -- Route is still built to be efficient from the BOT's current position.
    pdata.repair_targets = build_nearest_route(damaged, bot.position)
    pdata.current_target_index = 1
end

---------------------------------------------------
-- BOT SPAWN / MOVEMENT / REPAIR
---------------------------------------------------

-- Spawn the repair bot near the given player and reset its state.
local function spawn_wall_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    local surface = player.surface
    local pos = player.position

    -- Create the bot one tile to the right of the player.
    local bot = surface.create_entity {
        name = "mekatrol-repair-bot",
        position = {pos.x + 1, pos.y},
        force = player.force
    }

    if bot then
        -- Make sure it can't be killed accidentally.
        bot.destructible = false

        pdata.wall_bot = bot

        -- Reset current route.
        pdata.repair_targets = nil
        pdata.current_target_index = 1

        player.print("[WallRepair] Repair bot spawned.")
    else
        player.print("[WallRepair] Failed to spawn repair bot.")
    end
end

-- Issue a go-to command to the bot to move toward a target position.
local function move_bot_to(bot, target_pos)
    if not (bot and bot.valid and target_pos) then
        return
    end

    local cmd = bot.commandable
    if not (cmd and cmd.valid) then
        return
    end

    cmd.set_command {
        type = defines.command.go_to_location,
        destination = target_pos,
        radius = 0.5,
        distraction = defines.distraction.none
    }
end

-- Repair all damaged entities within a radius of a given center point.
local function repair_entities_near(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local entities = surface.find_entities_filtered {
        force = force,
        area = area
    }

    for _, ent in pairs(entities) do
        if ent.valid and ent.health then
            local max = get_entity_max_health(ent)
            if max then
                -- Set exactly to max health when we know it.
                ent.health = max
            end
        end
    end
end

-- Main per-tick update for a single player's repair bot.
local function update_wall_bot_for_player(player, pdata)
    -- If the feature is disabled for this player, do nothing.
    if not pdata.wall_bot_enabled then
        return
    end

    -- Ensure the bot entity exists.
    local bot = pdata.wall_bot
    if not (bot and bot.valid) then
        spawn_wall_bot_for_player(player, pdata)
        bot = pdata.wall_bot
        if not (bot and bot.valid) then
            return
        end
    end

    -- Always update the visual highlight around the bot.
    draw_bot_highlight(bot, pdata)

    ---------------------------------------------------
    -- Always rebuild the damaged-entity route so that:
    -- - entities repaired by the bot are removed
    -- - entities repaired by the PLAYER (or anything else)
    --   are also removed from the list and their
    --   markers/lines disappear on the next update.
    ---------------------------------------------------
    rebuild_repair_route(player, pdata, bot)

    -- Make sure we have a current list of damaged entities ordered by nearest-neighbour.
    local targets = pdata.repair_targets

    -- If no targets, idle (and clear markers).
    if not targets or #targets == 0 then
        clear_damaged_markers(pdata)
        return
    end

    -- Clamp current index into valid range.
    local idx = pdata.current_target_index or 1
    if idx < 1 or idx > #targets then
        idx = 1
    end

    local target_entity = targets[idx]

    -- Skip invalid or fully repaired entities, advancing through the route.
    while target_entity and (not target_entity.valid or not is_entity_damaged(target_entity)) do
        idx = idx + 1
        if idx > #targets then
            -- We've exhausted the current route; rebuild to pick up any new damage.
            rebuild_repair_route(player, pdata, bot)
            targets = pdata.repair_targets
            idx = pdata.current_target_index or 1

            if not targets or #targets == 0 then
                clear_damaged_markers(pdata)
                return
            end
        end

        target_entity = targets[idx]
    end

    if not target_entity or not target_entity.valid then
        return
    end

    -- Store the chosen index.
    pdata.current_target_index = idx

    -- Movement and repair logic.
    local tp = target_entity.position
    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq <= (WALL_REPAIR_DISTANCE * WALL_REPAIR_DISTANCE) then
        -- Close enough: repair entities around the target.
        repair_entities_near(bot.surface, bot.force, tp, WALL_REPAIR_RADIUS)

        -- Immediately rebuild the damaged-entity list since health changed.
        rebuild_repair_route(player, pdata, bot)
        targets = pdata.repair_targets

        -- Next tick, proceed to the next entity in the route.
        pdata.current_target_index = idx + 1
    else
        -- Not close enough yet: keep moving towards the target entity.
        move_bot_to(bot, tp)
    end
end

---------------------------------------------------
-- HOTKEY HANDLER
---------------------------------------------------

-- IMPORTANT: this name must match the custom-input name in data.lua
-- Toggles the repair bot for the player who pressed the key.
script.on_event("mekatrol-toggle-repair-bot", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    -- Toggle on/off.
    pdata.wall_bot_enabled = not pdata.wall_bot_enabled

    if pdata.wall_bot_enabled then
        -- Enable: spawn bot if needed.
        if not (pdata.wall_bot and pdata.wall_bot.valid) then
            spawn_wall_bot_for_player(player, pdata)
        end
        player.print("[WallRepair] Repair bot enabled.")
    else
        -- Disable: destroy bot and clear state.
        if pdata.wall_bot and pdata.wall_bot.valid then
            pdata.wall_bot.destroy()
        end

        pdata.wall_bot = nil
        pdata.repair_targets = nil
        pdata.current_target_index = 1

        -- Clear all damaged-entity visuals (dots + lines) when disabling.
        clear_damaged_markers(pdata)

        -- Remove highlight if present.
        if pdata.highlight_object then
            local obj = pdata.highlight_object -- LuaRenderObject
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.highlight_object = nil
        end

        player.print("[WallRepair] Repair bot disabled.")
    end
end)

---------------------------------------------------
-- MAIN TICK (SINGLE-PLAYER / LOCAL PLAYER ONLY)
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    -- Only run the logic every WALL_BOT_UPDATE_INTERVAL ticks.
    if event.tick % WALL_BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    -- In single-player, we just use player index 1.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local pdata = get_player_data(player.index)
    if not pdata then
        player.print("[WallRepair] Player found but no pdata exists.")
        return
    end

    if pdata.wall_bot_enabled then
        update_wall_bot_for_player(player, pdata)
    end
end)
