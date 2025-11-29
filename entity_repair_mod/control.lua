---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
-- How often (in ticks) to update the repair bot logic.
-- 60 ticks = 1 second, 1 = every tick (smooth movement).
local REPAIR_BOT_UPDATE_INTERVAL = 5

-- Bot movement speed in tiles per second.
-- Vanilla construction robot is ~4 tiles/second.
local BOT_SPEED_TILES_PER_SECOND = 4.0

-- How often (in ticks) to scan player entities for max health of unknown types.
-- 60 ticks = 1 second, 3600 = 1 minute.
local MAX_HEALTH_SCAN_INTERVAL = 3600

-- Radius (in tiles) around the player to search for damaged entities.
local ENTITY_SEARCH_RADIUS = 256.0

-- Distance (in tiles) at which the bot considers itself "close enough"
-- to a target entity to perform repairs.
local ENTITY_REPAIR_DISTANCE = 2.0

-- Radius (in tiles) around the repair target to actually repair entities.
-- All entities in this radius will be repaired to max health.
local ENTITY_REPAIR_RADIUS = 20.0

-- Vertical offset (in tiles) to move the bot highlight up so it surrounds
-- the flying construction-robot sprite instead of the ground position.
-- Construction robots use a shift of about util.by_pixel(-0.25, -5) (~ -0.156 tiles),
-- so -0.2 is a good starting point.
local BOT_HIGHLIGHT_Y_OFFSET = -1.2

-- Distance (in tiles) the bot tries to maintain from the player
local BOT_FOLLOW_DISTANCE = 1.0

-- Distance the bot moves per update (in tiles).
-- With REPAIR_BOT_UPDATE_INTERVAL = 1, this is tiles per tick.
local BOT_STEP_DISTANCE = 0.8

---------------------------------------------------
-- REPAIR TOOL CONFIGURATION
---------------------------------------------------

-- Name of the item used for repairs.
-- Change this if you use a custom repair item.
local REPAIR_TOOL_NAME = "repair-pack"

-- How many repair tools are consumed per entity fully repaired.
-- You can tune this number.
local REPAIR_TOOLS_PER_ENTITY = 1

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
    ["mekatrol-repair-bot"] = 100,
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
    ["wooden-chest"] = 100,
    ["pumpjack"] = 200,
    ["pipe-to-ground"] = 150,
    ["pipe"] = 100,
    ["storage-tank"] = 500,
    ["offshore-pump"] = 150,
    ["boiler"] = 200,
    ["steam-engine"] = 400
}

-- Tracks which entity names we have already warned about (so we don't spam chat).
local UNKNOWN_ENTITY_WARNED = UNKNOWN_ENTITY_WARNED or {}

-- Round a position to tile coordinates
local function round_to_tile_pos(pos)
    return {
        x = math.floor(pos.x + 0.5),
        y = math.floor(pos.y + 0.5)
    }
end

local function tile_key(x, y)
    return x .. "," .. y
end

-- Build a wall occupancy map and bounding box for A*
-- Returns: wall_map, minx, maxx, miny, maxy
local function build_wall_map(surface, start_pos, target_pos, max_radius)
    local sp = round_to_tile_pos(start_pos)
    local tp = round_to_tile_pos(target_pos)

    max_radius = max_radius or 128

    local minx = math.min(sp.x, tp.x) - max_radius
    local maxx = math.max(sp.x, tp.x) + max_radius
    local miny = math.min(sp.y, tp.y) - max_radius
    local maxy = math.max(sp.y, tp.y) + max_radius

    local area = {{minx - 1, miny - 1}, {maxx + 1, maxy + 1}}

    local walls = surface.find_entities_filtered {
        area = area,
        type = "wall" -- all entities of type 'wall'
    }

    local wall_map = {}

    for _, w in pairs(walls) do
        if w.valid then
            local wp = round_to_tile_pos(w.position)
            wall_map[wp.x] = wall_map[wp.x] or {}
            wall_map[wp.x][wp.y] = true
        end
    end

    return wall_map, minx, maxx, miny, maxy
end

local function is_tile_blocked(wall_map, minx, maxx, miny, maxy, x, y)
    if x < minx or x > maxx or y < miny or y > maxy then
        return true
    end
    local col = wall_map[x]
    return col and col[y] or false
end

-- Simple A* on tiles, avoiding walls.
-- Returns an array of world positions { {x=..., y=...}, ... }.
-- If target is unreachable, returns a path to the closest reachable tile to target.
local function find_path_astar(surface, start_pos, target_pos, max_radius)
    local sp = round_to_tile_pos(start_pos)
    local tp = round_to_tile_pos(target_pos)

    -- Trivial case
    if sp.x == tp.x and sp.y == tp.y then
        return {{
            x = target_pos.x,
            y = target_pos.y
        }}
    end

    local wall_map, minx, maxx, miny, maxy = build_wall_map(surface, start_pos, target_pos, max_radius or 128)

    -- If start is on a wall, give up early (bot is "inside" a wall).
    if is_tile_blocked(wall_map, minx, maxx, miny, maxy, sp.x, sp.y) then
        return nil
    end
    -- IMPORTANT: do NOT early-return if target tile is blocked.
    -- We still search and will pick the closest reachable tile instead.

    local open = {}
    local open_lookup = {}
    local closed = {}
    local came_from = {}

    local function heuristic(x, y)
        local dx = math.abs(x - tp.x)
        local dy = math.abs(y - tp.y)
        -- Chebyshev distance (works well with 8-directional movement)
        return math.max(dx, dy)
    end

    local function push_open(node)
        open[#open + 1] = node
        open_lookup[node.key] = node
    end

    local function pop_best()
        local best_index = nil
        local best_f = nil

        for i, n in ipairs(open) do
            if not best_f or n.f < best_f then
                best_f = n.f
                best_index = i
            end
        end

        if not best_index then
            return nil
        end

        local n = open[best_index]
        table.remove(open, best_index)
        open_lookup[n.key] = nil
        return n
    end

    -- Reconstruct path from start to 'end_node'.
    -- If final_pos is non-nil, the last waypoint is replaced with that exact world position.
    local function reconstruct_path(came_from_tbl, end_node, final_pos)
        local rev = {}
        local node = end_node

        while node do
            if node.parent_key == nil then
                break
            end

            rev[#rev + 1] = {
                x = node.x + 0.5,
                y = node.y + 0.5
            }
            node = came_from_tbl[node.parent_key]
        end

        local path = {}
        for i = #rev, 1, -1 do
            path[#path + 1] = rev[i]
        end

        if final_pos and #path > 0 then
            -- For exact-goal success, snap last point to target_pos.
            path[#path] = {
                x = final_pos.x,
                y = final_pos.y
            }
        end

        return path
    end

    local start_key = tile_key(sp.x, sp.y)
    local start_h = heuristic(sp.x, sp.y)
    local start_node = {
        x = sp.x,
        y = sp.y,
        g = 0,
        h = start_h,
        f = start_h,
        key = start_key,
        parent_key = nil
    }

    push_open(start_node)
    came_from[start_key] = start_node

    -- Track best (closest-to-target) node seen so far.
    local best_node = start_node
    local best_h = start_h

    local NEIGHBORS = {{1, 0}, -- east
    {-1, 0}, -- west
    {0, 1}, -- south
    {0, -1}, -- north
    {1, 1}, -- southeast
    {1, -1}, -- northeast
    {-1, 1}, -- southwest
    {-1, -1} -- northwest
    }

    while true do
        local current = pop_best()
        if not current then
            -- No more nodes: goal unreachable.
            -- Return best path we can (if it's not just the start).
            if best_node and best_node ~= start_node then
                return reconstruct_path(came_from, best_node, nil)
            else
                return nil
            end
        end

        -- Check if we've hit the exact goal tile (only possible if it isn't blocked).
        if current.x == tp.x and current.y == tp.y then
            return reconstruct_path(came_from, current, target_pos)
        end

        closed[current.key] = true

        for _, d in ipairs(NEIGHBORS) do
            local nx = current.x + d[1]
            local ny = current.y + d[2]
            local nkey = tile_key(nx, ny)

            -- Corner-cutting check for diagonals
            if not (d[1] ~= 0 and d[2] ~= 0 and
                (is_tile_blocked(wall_map, minx, maxx, miny, maxy, current.x + d[1], current.y) or
                    is_tile_blocked(wall_map, minx, maxx, miny, maxy, current.x, current.y + d[2]))) then

                if not closed[nkey] and not is_tile_blocked(wall_map, minx, maxx, miny, maxy, nx, ny) then
                    local move_cost = (d[1] ~= 0 and d[2] ~= 0) and 1.41421356237 or 1
                    local tentative_g = current.g + move_cost
                    local existing = open_lookup[nkey]

                    if not existing or tentative_g < existing.g then
                        local h = heuristic(nx, ny)
                        local node = existing or {
                            x = nx,
                            y = ny,
                            key = nkey
                        }
                        node.g = tentative_g
                        node.h = h
                        node.f = tentative_g + h
                        node.parent_key = current.key

                        came_from[nkey] = node

                        -- Update "best reach so far" if closer to target.
                        if h < best_h then
                            best_h = h
                            best_node = node
                        end

                        if not existing then
                            push_open(node)
                        end
                    end
                end
            end
        end
    end
end

-- Single straight-line step, used by the path follower.
local function step_bot_towards(bot, tp)
    if not (bot and bot.valid and tp) then
        return
    end

    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)
    local step = BOT_STEP_DISTANCE

    -- If we're within one step, teleport exactly to the waypoint.
    if dist <= step then
        bot.teleport {
            x = tp.x,
            y = tp.y
        }
        return
    end

    -- Otherwise, move a single step in that direction.
    local scale = step / dist

    bot.teleport {
        x = bp.x + dx * scale,
        y = bp.y + dy * scale
    }
end

-- Persistent discovered max health values (per entity name)
local function get_discovered_table()
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
    local s = storage.mekatrol_repair_mod
    s.discovered_max_health = s.discovered_max_health or {}
    return s.discovered_max_health
end

-- Scan all entities of the given force on all surfaces.
-- For any entity whose name is NOT in ENTITY_MAX_HEALTH, track the highest
-- health seen and write out a suggested constant when it increases.
local function scan_player_entities_for_max_health(force)
    if not force then
        return
    end

    local discovered = get_discovered_table()

    for _, surface in pairs(game.surfaces) do
        -- All entities belonging to this force on this surface
        local entities = surface.find_entities_filtered {
            force = force
        }

        for _, e in pairs(entities) do
            if e.valid and e.health then
                local name = e.name

                -- Skip entities we already have a constant for
                if not ENTITY_MAX_HEALTH[name] then
                    local h = e.health
                    local prev = discovered[name]

                    -- Only care if this is a new maximum
                    if not prev or h > prev then
                        discovered[name] = h
                        local suggested = math.floor(h + 0.5)

                        local line = string.format("[\"%s\"] = %d,\n", name, suggested)

                        -- Print in-game so you can see it immediately
                        game.print("[MekatrolRepairBot][SCAN] " .. line)

                        -- Write to disk if helpers.write_file is available (Factorio 2.0+)
                        if helpers and helpers.write_file then
                            helpers.write_file("mekatrol_repair_mod_maxhealth_scan.txt", line, true)
                        else
                            game.print(
                                "[MekatrolRepairBot][WARN] helpers.write_file not available; cannot write to disk.")
                        end
                    end
                end
            end
        end
    end
end

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
        game.print(string.format("[MekatrolRepairBot][INFO] Observed max health %.1f for '%s' (force=%s). " ..
                                     "Suggested: ENTITY_MAX_HEALTH[\"%s\"] = %d", max_health_seen, name, force.name,
            name, suggested))

        local line = string.format("[\"%s\"] = %d,\n", name, suggested)

        game.print("[MekatrolRepairBot][INFO] " .. line)

        if helpers and helpers.write_file then
            helpers.write_file("mekatrol_repair_mod_maxhealth_scan.txt", line, true)
        else
            -- fallback to avoid crashing
            game.print("[MekatrolRepairBot][WARN] helpers.write_file not available; cannot write to disk.")
        end

        return suggested
    else
        game.print(string.format(
            "[MekatrolRepairBot][INFO] Could not infer max health for '%s' (no live entities with health).", name))
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

-- Get the player's main inventory (or nil if not available).
local function get_player_main_inventory(player)
    if not (player and player.valid) then
        return nil
    end
    local inv = player.get_main_inventory()
    if inv and inv.valid then
        return inv
    end
    return nil
end

---------------------------------------------------
-- PLAYER STATE / INITIALISATION
---------------------------------------------------

-- Initialise persistent data for a single player.
-- This is only called for the specific player that needs it,
-- not for every player in the game.
local function init_player(player)
    -- Root storage table for this mod.
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
    local s = storage.mekatrol_repair_mod

    -- Per-player subtable.
    s.players = s.players or {}
    local pdata = s.players[player.index]

    if not pdata then
        -- First-time initialisation for this player.
        pdata = {
            -- Whether this player's repair bot is enabled.
            repair_bot_enabled = false,

            -- The actual bot entity (LuaEntity) or nil if not spawned.
            repair_bot = nil,

            -- Route of damaged entities to visit (array of LuaEntity).
            repair_targets = nil,

            -- Index into repair_targets for the current target.
            current_target_index = 1,

            -- LuaRenderObject to visually highlight the bot (green box).
            highlight_object = nil,

            -- The list of recorded damaged markers (dots).
            damaged_markers = nil,

            -- Line render objects from damaged entities to the player.
            damaged_lines = nil,

            -- Whether we've already warned this player about being out of repair tools.
            out_of_tools_warned = false,

            -- Pathfinding state
            bot_path = nil, -- array of {x, y} waypoints
            bot_path_index = 1, -- current waypoint index
            bot_path_target = nil, -- {x, y} of target this path was built for
            bot_path_visuals = nil,
            current_wp_visual = nil
        }

        s.players[player.index] = pdata
    else
        -- Backwards compatibility / ensure all fields exist.
        if pdata.repair_bot_enabled == nil then
            pdata.repair_bot_enabled = false
        end

        pdata.repair_targets = pdata.repair_targets or nil
        pdata.current_target_index = pdata.current_target_index or 1
        pdata.highlight_object = pdata.highlight_object or nil
        pdata.damaged_markers = pdata.damaged_markers or nil
        pdata.damaged_lines = pdata.damaged_lines or nil
        pdata.bot_path = pdata.bot_path or nil
        pdata.bot_path_index = pdata.bot_path_index or 1
        pdata.bot_path_target = pdata.bot_path_target or nil
        pdata.bot_path_visuals = pdata.bot_path_visuals or nil
        pdata.current_wp_visual = pdata.current_wp_visual or nil
    end
end

-- Obtain the persistent player data table for a given player index.
-- If it doesn't exist yet, this will initialise it.
local function get_player_data(index)
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
    local s = storage.mekatrol_repair_mod

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

local function clear_bot_path_visuals(pdata)
    if not pdata.bot_path_visuals then
        return
    end

    for _, obj in pairs(pdata.bot_path_visuals) do
        if obj and obj.valid then
            obj:destroy()
        end
    end

    pdata.bot_path_visuals = nil
end

local function reset_bot_path(pdata)
    if not pdata then
        return
    end

    pdata.bot_path = nil
    pdata.bot_path_index = 1
    pdata.bot_path_target = nil

    clear_bot_path_visuals(pdata)

    -- Clear current waypoint highlight
    if pdata.current_wp_visual and pdata.current_wp_visual.valid then
        pdata.current_wp_visual:destroy()
    end
    pdata.current_wp_visual = nil
end

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

-- Draw or update the rectangle around the bot so the player can see it easily.
local function draw_bot_highlight(bot, pdata)
    if not (bot and bot.valid) then
        return
    end

    -- Half-size of the highlight box around the bot.
    local size = 0.6

    -- Base position is the entity position (on the ground).
    local pos = bot.position

    -- Apply a vertical offset so the rectangle is centered on the flying sprite.
    local cx = pos.x
    local cy = pos.y + BOT_HIGHLIGHT_Y_OFFSET

    local left_top = {cx - size, cy - size * 1.5}
    local right_bottom = {cx + size, cy + size}

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
            b = 1,
            a = 0.2
        }, -- semi-transparent blue
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
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
end)

-- Called when mod configuration (version, dependencies, etc.) changes.
script.on_configuration_changed(function(_)
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
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
    local damaged = find_damaged_entities(surface, force, search_center, ENTITY_SEARCH_RADIUS)

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
local function spawn_repair_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    local surface = player.surface
    local pos = player.position

    local bot = surface.create_entity {
        name = "mekatrol-repair-bot",
        position = {pos.x - 1, pos.y - 1},
        force = player.force
    }

    if bot then
        bot.destructible = false
        pdata.repair_bot = bot

        -- Reset current route.
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        reset_bot_path(pdata)

        player.print("[MekatrolRepairBot] Repair bot spawned.")
    else
        player.print("[MekatrolRepairBot] Failed to spawn repair bot.")
    end
end

-- Returns true if the given position is "inside" a wall tile.
local function is_position_blocked_by_wall(surface, pos)
    if not (surface and pos) then
        return false
    end

    -- Walls are 1x1 entities; a radius of ~0.4 tiles around the center is enough
    local area = {{pos.x - 0.4, pos.y - 0.4}, {pos.x + 0.4, pos.y + 0.4}}

    local walls = surface.find_entities_filtered {
        area = area,
        type = "wall" -- catches stone-wall and modded walls with type = "wall"
        -- if you only want vanilla walls: name = "stone-wall"
    }

    return walls and #walls > 0
end

-- Ensure we have a path to 'target_pos' stored in pdata; rebuild if target changed.
local function ensure_bot_path(bot, target_pos, pdata)
    if not (bot and bot.valid and target_pos and pdata) then
        return
    end

    local tp = {
        x = target_pos.x,
        y = target_pos.y
    }

    if pdata.bot_path_target then
        local dx = pdata.bot_path_target.x - tp.x
        local dy = pdata.bot_path_target.y - tp.y
        local d2 = dx * dx + dy * dy

        -- If target has not moved much, keep existing path.
        if d2 < 0.25 and pdata.bot_path and #pdata.bot_path > 0 then
            return
        end
    end

    local surface = bot.surface

    -- Rebuild path
    local path = find_path_astar(surface, bot.position, tp, 32)

    -- Clear any old visuals
    clear_bot_path_visuals(pdata)

    -- Draw new visuals
    pdata.bot_path_visuals = {}

    local target_circle = rendering.draw_circle {
        color = {
            r = 1,
            g = 0,
            b = 1,
            a = 1
        }, -- magenta
        radius = 0.5,
        filled = true,
        target = tp, -- tp is {x, y}
        surface = surface,
        only_in_alt_mode = false
    }
    table.insert(pdata.bot_path_visuals, target_circle)

    local line = rendering.draw_line {
        color = {
            r = 1,
            g = 1,
            b = 1,
            a = 0.5
        },
        width = 1,
        from = bot.position, -- {x, y}
        to = tp, -- {x, y}
        surface = surface,
        only_in_alt_mode = false
    }
    table.insert(pdata.bot_path_visuals, line)

    if path and #path > 0 then
        pdata.bot_path = path
        pdata.bot_path_index = 1
        pdata.bot_path_target = tp

        local prev = nil
        for i, wp in ipairs(path) do
            -- Waypoint circle
            local circle = rendering.draw_circle {
                color = {
                    r = 1,
                    g = 1,
                    b = 0,
                    a = 1
                }, -- yellow
                radius = 0.2,
                filled = true,
                target = wp, -- wp is {x, y}
                surface = surface,
                only_in_alt_mode = false
            }
            table.insert(pdata.bot_path_visuals, circle)

            -- Line from previous waypoint
            if prev then
                local line = rendering.draw_line {
                    color = {
                        r = 1,
                        g = 1,
                        b = 0,
                        a = 0.5
                    },
                    width = 1,
                    from = prev, -- {x, y}
                    to = wp, -- {x, y}
                    surface = surface,
                    only_in_alt_mode = false
                }
                table.insert(pdata.bot_path_visuals, line)
            end

            prev = wp
        end
    else
        pdata.bot_path = nil
        pdata.bot_path_index = 1
        pdata.bot_path_target = nil
    end
end

local function move_bot_to(bot, target)
    if not (bot and bot.valid and target) then
        return
    end

    local tp

    if type(target) == "table" and target.position ~= nil then
        -- entity
        tp = target.position

    elseif type(target) == "table" and target.x ~= nil and target.y ~= nil then
        -- {x=..., y=...}
        tp = target

    elseif type(target) == "table" and target[1] ~= nil and target[2] ~= nil then
        -- {x, y} numeric indices; auto-convert
        tp = {
            x = target[1],
            y = target[2]
        }
    else
        local desc = serpent and serpent.line(target) or "<no serpent>"
        return
    end

    local bp = bot.position

    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)

    if dist <= BOT_STEP_DISTANCE then
        bot.teleport {
            x = tp.x,
            y = tp.y
        }
        return
    end

    local nx = dx / dist
    local ny = dy / dist

    bot.teleport {
        x = bp.x + nx,
        y = bp.y + ny
    }
end

local function follow_player(bot, player)
    if not (bot and bot.valid and player and player.valid) then
        return
    end

    local bp = bot.position
    local pp = player.position

    local dx = pp.x - bp.x
    local dy = pp.y - bp.y
    local dist_sq = dx * dx + dy * dy
    local desired_sq = BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE

    -- Only move if the bot is “too far” from the player.
    if dist_sq > desired_sq then
        -- Optional: small offset so it doesn't sit exactly on the player
        local offset_x = -2.0
        local offset_y = -2.0

        local target_pos = {
            x = pp.x + offset_x,
            y = pp.y + offset_y
        }

        -- Reuse your existing movement (currently teleport)
        move_bot_to(bot, target_pos)
    end
end

-- Path-aware move: follows A* path, which never enters wall tiles.
local function move_bot_to_a_star(bot, target, pdata)
    if not (bot and bot.valid and target and pdata) then
        return
    end

    local tp

    if type(target) == "table" and target.position ~= nil then
        tp = target.position
    elseif type(target) == "table" and target.x ~= nil and target.y ~= nil then
        tp = target
    elseif type(target) == "table" and target[1] ~= nil and target[2] ~= nil then
        tp = {
            x = target[1],
            y = target[2]
        }
    else
        return
    end

    ensure_bot_path(bot, tp, pdata)

    local path = pdata.bot_path
    if not path or #path == 0 then
        -- No path found (e.g. target unreachable within radius): just stop.
        return
    end

    local idx = pdata.bot_path_index or 1
    if idx < 1 then
        idx = 1
    elseif idx > #path then
        idx = #path
    end

    local bp = bot.position
    local waypoint = path[idx]

    -- If we are very close to this waypoint, advance to next.
    local dx = waypoint.x - bp.x
    local dy = waypoint.y - bp.y
    local d2 = dx * dx + dy * dy

    if d2 < 0.04 then
        idx = idx + 1
        if idx > #path then
            -- At final waypoint, nothing more to do.
            reset_bot_path(pdata)
            return
        end
        waypoint = path[idx]
        bp = bot.position
    end

    ----------------------------------------------------------------
    -- NEW: skip any waypoints that are NOT in the direction
    -- of the final target (i.e. they increase distance to target).
    ----------------------------------------------------------------
    local final_target = pdata.bot_path_target or tp

    local function dist_sq(ax, ay, bx, by)
        local ddx = bx - ax
        local ddy = by - ay
        return ddx * ddx + ddy * ddy
    end

    -- Current distance from bot to final target
    local bot_to_target_sq = dist_sq(bp.x, bp.y, final_target.x, final_target.y)

    -- Advance idx while waypoint is further from target than bot is
    while idx <= #path do
        waypoint = path[idx]
        local wp_to_target_sq = dist_sq(waypoint.x, waypoint.y, final_target.x, final_target.y)

        -- If waypoint is not worse (<=) than current position wrt target, use it
        if wp_to_target_sq <= bot_to_target_sq + 0.0001 then
            break
        end

        -- Otherwise skip this waypoint and try the next
        idx = idx + 1
    end

    -- If we ran out of waypoints, clear path and stop
    if idx > #path then
        reset_bot_path(pdata)
        return
    end

    waypoint = path[idx]
    pdata.bot_path_index = idx

    ---------------------------------------------------
    -- Highlight current waypoint in bright color
    ---------------------------------------------------
    if pdata.current_wp_visual and pdata.current_wp_visual.valid then
        pdata.current_wp_visual.target = waypoint
    else
        pdata.current_wp_visual = rendering.draw_circle {
            color = {
                r = 1,
                g = 1,
                b = 0,
                a = 1
            }, -- bright yellow
            radius = 0.6,
            filled = false,
            target = waypoint,
            surface = bot.surface,
            only_in_alt_mode = false
        }
    end

    -- Take one step towards current waypoint.
    step_bot_towards(bot, waypoint)
end

local function follow_player_a_star(bot, player, pdata)
    if not (bot and bot.valid and player and player.valid) then
        return
    end

    local bp = bot.position
    local pp = player.position

    -- desired follow position (2 tiles up-left of player)
    local target_pos = {
        x = pp.x - 2.0,
        y = pp.y - 2.0
    }

    local dx = target_pos.x - bp.x
    local dy = target_pos.y - bp.y
    local dist_sq = dx * dx + dy * dy

    -- how close the bot should try to be to the follow position
    local desired_sq = BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE
    -- or just a small tolerance, e.g.:
    -- local desired_sq = 0.25  -- within 0.5 tiles

    if dist_sq > desired_sq then
        move_bot_to_a_star(bot, target_pos, pdata)
    end
end

-- Repair all damaged entities within a radius of a given center point,
-- consuming repair tools from the PLAYER'S inventory.
local function repair_entities_near(player, surface, force, center, radius)
    if not (player and player.valid) then
        return
    end

    local inv = get_player_main_inventory(player)
    if not inv then
        return
    end

    if inv.get_item_count(REPAIR_TOOL_NAME) <= 0 then
        local pdata = get_player_data(player.index)
        if pdata and not pdata.out_of_tools_warned then
            pdata.out_of_tools_warned = true
            player.print("[MekatrolRepairBot] No repair tools in your inventory. Bot cannot repair.")
        end
        return
    end

    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local entities = surface.find_entities_filtered {
        force = force,
        area = area
    }

    for _, ent in pairs(entities) do
        -- Stop if we have run out of tools.
        if inv.get_item_count(REPAIR_TOOL_NAME) <= 0 then
            return
        end

        if ent.valid and ent.health then
            local max = get_entity_max_health(ent)
            if max and ent.health < max then
                -- Consume the repair tools needed for this entity.
                local removed = inv.remove {
                    name = REPAIR_TOOL_NAME,
                    count = REPAIR_TOOLS_PER_ENTITY
                }

                -- Only repair if we actually consumed tools.
                if removed > 0 then
                    ent.health = max
                    local pdata = get_player_data(player.index)
                    if pdata then
                        pdata.out_of_tools_warned = false
                    end
                else
                    -- Could not remove tools (race condition or other mod),
                    -- abort repairs.
                    return
                end
            end
        end
    end
end

-- Main per-tick update for a single player's repair bot.
local function update_repair_bot_for_player(player, pdata)
    -- If the feature is disabled for this player, do nothing.
    if not pdata.repair_bot_enabled then
        clear_bot_path_visuals(pdata)
        return
    end

    -- Ensure the bot entity exists.
    local bot = pdata.repair_bot
    if not (bot and bot.valid) then
        spawn_repair_bot_for_player(player, pdata)
        bot = pdata.repair_bot
        if not (bot and bot.valid) then
            return
        end
    end

    -- Always update the visual highlight around the bot.
    -- draw_bot_highlight(bot, pdata)

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
        if pdata.last_mode ~= "follow" then
            player.print("[MekatrolRepairBot] mode: FOLLOWING PLAYER")
            pdata.last_mode = "follow"
        end
        clear_damaged_markers(pdata)

        -- We're switching to follow mode → old repair path is irrelevant.
        reset_bot_path(pdata)

        follow_player(bot, player, pdata)
        return
    else
        if pdata.last_mode ~= "repair" then
            player.print("[MekatrolRepairBot] mode: REPAIRING DAMAGE")
            pdata.last_mode = "repair"
        end
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

    if dist_sq <= (ENTITY_REPAIR_DISTANCE * ENTITY_REPAIR_DISTANCE) then
        if pdata.last_mode ~= "repair" then
            player.print("[MekatrolRepairBot] mode: REPAIRING DAMAGE")
            pdata.last_mode = "repair"
        end

        -- Close enough: repair entities around the target,
        -- consuming repair tools from the player's inventory.
        repair_entities_near(player, bot.surface, bot.force, tp, ENTITY_REPAIR_RADIUS)

        -- Immediately rebuild the damaged-entity list since health changed.
        rebuild_repair_route(player, pdata, bot)
        targets = pdata.repair_targets

        -- Next tick, proceed to the next entity in the route.
        pdata.current_target_index = idx + 1
    else
        -- Not close enough yet: move towards the target entity via A* path.
        move_bot_to(bot, {
            x = tp.x,
            y = tp.y
        }, pdata)
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
    pdata.repair_bot_enabled = not pdata.repair_bot_enabled

    if pdata.repair_bot_enabled then
        -- Enable: spawn bot if needed.
        if not (pdata.repair_bot and pdata.repair_bot.valid) then
            spawn_repair_bot_for_player(player, pdata)
        end

        -- Set and print mode when enabling
        pdata.last_mode = "follow"
        player.print("[MekatrolRepairBot] Repair bot enabled.")
        player.print("[MekatrolRepairBot] mode: FOLLOWING PLAYER")
    else
        -- Disable: destroy bot and clear state.
        if pdata.repair_bot and pdata.repair_bot.valid then
            pdata.repair_bot.destroy()
        end

        pdata.repair_bot = nil
        pdata.repair_targets = nil
        pdata.current_target_index = 1

        -- Clear all damaged-entity visuals (dots + lines) when disabling.
        clear_damaged_markers(pdata)

        -- Remove bot path & its visuals
        reset_bot_path(pdata)

        -- Remove highlight if present.
        if pdata.highlight_object then
            local obj = pdata.highlight_object -- LuaRenderObject
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.highlight_object = nil
        end

        -- Set and print mode when disabling
        pdata.last_mode = "off"
        player.print("[MekatrolRepairBot] Repair bot disabled.")
        player.print("[MekatrolRepairBot] mode: OFF")
    end
end)

---------------------------------------------------
-- MAIN TICK (SINGLE-PLAYER / LOCAL PLAYER ONLY)
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    -- Only run the main logic every REPAIR_BOT_UPDATE_INTERVAL ticks.
    if event.tick % REPAIR_BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    -- In single-player, we just use player index 1.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local pdata = get_player_data(player.index)
    if not pdata then
        player.print("[MekatrolRepairBot] Player found but no pdata exists.")
        return
    end

    -- Periodic scan of all player-force entities for unknown max health
    if event.tick % MAX_HEALTH_SCAN_INTERVAL == 0 then
        scan_player_entities_for_max_health(player.force)
    end

    if pdata.repair_bot_enabled then
        update_repair_bot_for_player(player, pdata)
    end
end)
