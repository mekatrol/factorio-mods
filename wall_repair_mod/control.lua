---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
-- How often (in ticks) to update the wall bot logic.
-- 60 ticks = 1 second, so 30 = every 0.5 seconds.
local WALL_BOT_UPDATE_INTERVAL = 30

-- Radius (in tiles) around the player to search for damaged walls.
local WALL_SEARCH_RADIUS = 64

-- Distance (in tiles) at which the bot considers itself "close enough"
-- to a target wall to perform repairs.
local WALL_REPAIR_DISTANCE = 20.0

-- Radius (in tiles) around the repair target to actually repair walls.
-- All walls in this radius will be repaired to max health.
local WALL_REPAIR_RADIUS = 20.0

-- The wall maximum health value
local WALL_MAX_HEALTH = 350

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
            -- Whether this player's wall bot is enabled.
            wall_bot_enabled = false,

            -- The actual wall bot entity (LuaEntity) or nil if not spawned.
            wall_bot = nil,

            -- Route of damaged walls to visit (array of LuaEntity walls).
            repair_targets = nil,

            -- Index into repair_targets for the current target.
            current_target_index = 1,

            -- LuaRenderObject to visually highlight the bot (green box).
            highlight_object = nil,

            -- The list of recorded damaged markers (dots).
            damaged_markers = nil,

            -- Line render objects from damaged walls to the player.
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
-- DAMAGED WALL MARKERS (DOTS + LINES)
---------------------------------------------------

-- Destroy and forget all previously drawn green dots and lines for damaged walls.
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

-- Draw a green dot on each damaged wall and a line from the wall to the player.
-- This does NOT clear old visuals; call clear_damaged_markers first
-- if you want only the current set to be visible.
local function draw_damaged_visuals(player, pdata, damaged_walls)
    if not damaged_walls or #damaged_walls == 0 then
        return
    end

    pdata.damaged_markers = pdata.damaged_markers or {}
    pdata.damaged_lines = pdata.damaged_lines or {}

    local player_pos = player.position

    for _, wall in pairs(damaged_walls) do
        if wall and wall.valid then
            -- Small filled green circle at the wall's position (dot).
            local dot = rendering.draw_circle {
                color = {
                    r = 0,
                    g = 1,
                    b = 0,
                    a = 1
                }, -- solid green
                radius = 0.15,
                filled = true,
                target = wall,
                surface = wall.surface,
                only_in_alt_mode = false
            }
            pdata.damaged_markers[#pdata.damaged_markers + 1] = dot

            -- Line from the wall to the player.
            local line = rendering.draw_line {
                color = {
                    r = 0,
                    g = 1,
                    b = 0,
                    a = 0.4
                }, -- semi-transparent green
                width = 1,
                from = wall, -- start at wall entity
                to = player_pos, -- end at player position
                surface = wall.surface,
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
-- WALL / HEALTH HELPERS
---------------------------------------------------

-- Safely obtain the maximum health for an entity.
-- Uses pcall around the prototype access in case max_health doesn't exist.
local function get_entity_max_health(entity)
    if not (entity and entity.valid) then
        return nil
    end

    local proto = entity.prototype
    if not proto then
        return nil
    end

    -- Access via pcall so missing property doesn't crash.
    local ok, max = pcall(function()
        return proto.max_health
    end)

    if ok and type(max) == "number" and max > 0 then
        return max
    end

    -- If we can't read max_health reliably, return nil.
    return nil
end

-- Determine whether a given wall entity is damaged.
local function is_wall_damaged(wall)
    if not (wall and wall.valid and wall.health) then
        return false
    end

    local max = get_entity_max_health(wall)
    if max then
        -- If we know the maximum health, compare against it.
        return wall.health < max
    end

    -- Fallback if prototype has no max_health:
    -- treat as damaged if below our "full repair" fallback value.
    -- We use WALL_MAX_HEALTH because repair_walls_near sets wall.health = 350
    -- when no proper max can be read.
    return wall.health < WALL_MAX_HEALTH
end

-- Find all damaged walls of this force within a radius of a given point.
local function find_damaged_walls(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    -- Find all wall entities in the area.
    local candidates = surface.find_entities_filtered {
        type = "wall",
        force = force,
        area = area
    }

    local damaged = {}

    -- Track maximum of any wall health value we see.
    local max_wall_health = 0

    -- Optionally: also track maximum prototype max_health, if you care about that too.
    local max_wall_max_health = 0

    for _, wall in pairs(candidates) do
        if wall and wall.valid and wall.health then
            game.print("[WallRepair] wall HP: " .. wall.health)

            -- Track maximum current health.
            if wall.health > max_wall_health then
                max_wall_health = wall.health
            end

            -- Track maximum prototype max_health (uses helper).
            local proto_max = get_entity_max_health(wall)
            if proto_max and proto_max > max_wall_max_health then
                max_wall_max_health = proto_max
            end
        end

        if is_wall_damaged(wall) then
            damaged[#damaged + 1] = wall
        end
    end

    -- Print summary of maximum values we saw.
    if max_wall_health > 0 then
        game.print("[WallRepair] Max current wall HP in area: " .. max_wall_health)
    end

    if max_wall_max_health > 0 then
        game.print("[WallRepair] Max prototype max_health in area: " .. max_wall_max_health)
    end

    return damaged
end

---------------------------------------------------
-- ROUTE BUILDING (NEAREST NEIGHBOUR)
---------------------------------------------------

-- Build an ordered route over a set of wall entities, such that each next wall
-- is the nearest to the previous one. This is a greedy nearest-neighbour TSP approximation.
local function build_nearest_route(walls, start_pos)
    local ordered = {}
    local used = {}
    local remaining = #walls

    -- Start the route from the given starting position (usually the bot position).
    local current_x = start_pos.x
    local current_y = start_pos.y

    while remaining > 0 do
        local best_i, best_d2 = nil, nil

        -- Find the nearest unused, valid wall to the current point.
        for i, wall in ipairs(walls) do
            if not used[i] and wall.valid then
                local wp = wall.position
                local dx = wp.x - current_x
                local dy = wp.y - current_y
                local d2 = dx * dx + dy * dy

                if not best_d2 or d2 < best_d2 then
                    best_d2 = d2
                    best_i = i
                end
            end
        end

        -- If we couldn't find any more valid walls, stop.
        if not best_i then
            break
        end

        -- Add the chosen wall to the ordered route.
        local w = walls[best_i]
        used[best_i] = true
        ordered[#ordered + 1] = w
        remaining = remaining - 1

        -- Advance the "current point" to this wall.
        local wp = w.position
        current_x = wp.x
        current_y = wp.y
    end

    return ordered
end

-- Rebuild the player's current repair route.
-- Damaged walls are FOUND around the PLAYER, but the route itself is still
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

    -- Search for damaged walls around the player.
    local damaged = find_damaged_walls(surface, force, search_center, WALL_SEARCH_RADIUS)

    -- Print how many damaged walls were found
    player.print("[WallRepair] Found " .. #damaged .. " damaged wall(s).")

    -- Always reset markers based on the latest damaged list.
    clear_damaged_markers(pdata)

    if not damaged or #damaged == 0 then
        -- No damaged walls found: clear route and leave no dots/lines.
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        return
    end

    -- Draw a green dot and line for every damaged wall we found near the player.
    draw_damaged_visuals(player, pdata, damaged)

    -- Route is still built to be efficient from the BOT's current position.
    pdata.repair_targets = build_nearest_route(damaged, bot.position)
    pdata.current_target_index = 1
end

---------------------------------------------------
-- BOT SPAWN / MOVEMENT / REPAIR
---------------------------------------------------

-- Spawn the wall bot near the given player and reset its state.
local function spawn_wall_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    local surface = player.surface
    local pos = player.position

    -- Create the bot one tile to the right of the player.
    local bot = surface.create_entity {
        name = "augment-wall-drone",
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

        player.print("[WallRepair] Wall bot spawned.")
    else
        player.print("[WallRepair] Failed to spawn wall bot.")
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

-- Repair all walls within a radius of a given center point.
local function repair_walls_near(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local walls = surface.find_entities_filtered {
        type = "wall",
        force = force,
        area = area
    }

    for _, wall in pairs(walls) do
        if wall.valid and wall.health then
            local max = get_entity_max_health(wall)
            if max then
                -- Set exactly to max health when we know it.
                wall.health = max
            else
                -- Fallback: Factorio will clamp this if there is a max,
                -- and if not, it's still safe.
                wall.health = WALL_MAX_HEALTH
            end
        end
    end
end

-- Main per-tick update for a single player's wall bot.
local function update_wall_bot_for_player(player, pdata)
    -- If the feature is disabled for this player, do nothing.
    if not pdata.wall_bot_enabled then
        return
    end

    -- Ensure the wall bot entity exists.
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

    -- Make sure we have a current list of damaged walls ordered by nearest-neighbour.
    local targets = pdata.repair_targets
    if not targets or #targets == 0 then
        rebuild_repair_route(player, pdata, bot)
        targets = pdata.repair_targets
    end

    -- If still no targets, idle (and clear markers).
    if not targets or #targets == 0 then
        clear_damaged_markers(pdata)
        return
    end

    -- Clamp current index into valid range.
    local idx = pdata.current_target_index or 1
    if idx < 1 or idx > #targets then
        idx = 1
    end

    local target_wall = targets[idx]

    -- Skip invalid or fully repaired walls, advancing through the route.
    while target_wall and (not target_wall.valid or not is_wall_damaged(target_wall)) do
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

        target_wall = targets[idx]
    end

    if not target_wall or not target_wall.valid then
        return
    end

    -- Store the chosen index.
    pdata.current_target_index = idx

    -- Movement and repair logic.
    local tp = target_wall.position
    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq <= (WALL_REPAIR_DISTANCE * WALL_REPAIR_DISTANCE) then
        -- Close enough: repair walls around the target.
        repair_walls_near(bot.surface, bot.force, tp, WALL_REPAIR_RADIUS)

        -- Next tick, proceed to the next wall in the route.
        pdata.current_target_index = idx + 1
    else
        -- Not close enough yet: keep moving towards the target wall.
        move_bot_to(bot, tp)
    end
end

---------------------------------------------------
-- HOTKEY HANDLER
---------------------------------------------------

-- IMPORTANT: this name must match the custom-input name in data.lua
-- Toggles the wall bot for the player who pressed the key.
script.on_event("augment-toggle-wall-bot", function(event)
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
        player.print("[WallRepair] Wall bot enabled.")
    else
        -- Disable: destroy bot and clear state.
        if pdata.wall_bot and pdata.wall_bot.valid then
            pdata.wall_bot.destroy()
        end

        pdata.wall_bot = nil
        pdata.repair_targets = nil
        pdata.current_target_index = 1

        -- Clear all damaged-wall visuals (dots + lines) when disabling.
        clear_damaged_markers(pdata)

        -- Remove highlight if present.
        if pdata.highlight_object then
            local obj = pdata.highlight_object -- LuaRenderObject
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.highlight_object = nil
        end

        player.print("[WallRepair] Wall bot disabled.")
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

    -- Debug print with some player + pdata info
    -- player.print("[WallRepair] Tick " .. event.tick .. " | Player: " .. player.name .. " | Bot Enabled: " ..
    --                  tostring(pdata.wall_bot_enabled) .. " | Repair Targets: " ..
    --                  tostring(pdata.repair_targets and #pdata.repair_targets or 0))

    if pdata.wall_bot_enabled then
        update_wall_bot_for_player(player, pdata)
    end
end)
