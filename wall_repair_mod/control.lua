local WALL_BOT_UPDATE_INTERVAL = 30
local WALL_SEARCH_RADIUS = 64
local WALL_REPAIR_DISTANCE = 2.5
local WALL_REPAIR_RADIUS = 2.0
local PERIMETER_REBUILD_TICKS = 60 * 60

---------------------------------------------------
-- STATE INITIALISATION
---------------------------------------------------

local function init_player(player)
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    local s = storage.wall_repair_mod

    s.players = s.players or {}
    local pdata = s.players[player.index]

    if not pdata then
        pdata = {
            wall_bot_enabled = false,
            wall_bot = nil, -- LuaEntity
            perimeter = nil, -- { surface_index = ..., nodes = { {x,y}, ... }, last_built_tick = ... }
            current_node_index = 1,
            highlight_object = nil
        }
        s.players[player.index] = pdata
    else
        if pdata.wall_bot_enabled == nil then
            pdata.wall_bot_enabled = false
        end
        pdata.current_node_index = pdata.current_node_index or 1
    end
end

local function init_all_players()
    for _, player in pairs(game.players) do
        init_player(player)
    end
end

local function draw_bot_highlight(bot, pdata)
    if not (bot and bot.valid) then
        return
    end

    local size = 0.6
    local pos = bot.position

    local left_top = {pos.x - size, pos.y - size}
    local right_bottom = {pos.x + size, pos.y + size}

    -- If we already have a rectangle, update it directly
    if pdata.highlight_object then
        local obj = pdata.highlight_object -- LuaRenderObject
        if obj and obj.valid then
            -- Either use properties:
            obj.left_top = left_top
            obj.right_bottom = right_bottom

            -- or use method:
            -- obj:set_corners(left_top, right_bottom)

            return
        else
            -- stale/invalid object, forget it
            pdata.highlight_object = nil
        end
    end

    -- Otherwise, create a new rectangle and store the LuaRenderObject
    pdata.highlight_object = rendering.draw_rectangle {
        color = {
            r = 0,
            g = 1,
            b = 0,
            a = 0.7
        }, -- green
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = bot.surface,
        only_in_alt_mode = false
    }
end

script.on_init(function()
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    init_all_players()
end)

script.on_configuration_changed(function(_)
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    init_all_players()
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        init_player(player)
    end
end)

script.on_load(function()
    -- storage already restored
end)

local function get_player_data(index)
    storage.wall_repair_mod = storage.wall_repair_mod or {}
    storage.wall_repair_mod.players = storage.wall_repair_mod.players or {}
    local pdata = storage.wall_repair_mod.players[index]
    if not pdata then
        local player = game.get_player(index)
        if player then
            init_player(player)
            pdata = storage.wall_repair_mod.players[index]
        end
    end
    return pdata
end

---------------------------------------------------
-- PERIMETER DISCOVERY
---------------------------------------------------

local function find_nearest_wall(surface, force, pos, radius)
    local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}

    local candidates = surface.find_entities_filtered {
        type = "wall",
        force = force,
        area = area
    }

    local best, best_dist_sq = nil, nil
    for _, wall in pairs(candidates) do
        if wall.valid then
            local wp = wall.position
            local dx = wp.x - pos.x
            local dy = wp.y - pos.y
            local d2 = dx * dx + dy * dy
            if not best_dist_sq or d2 < best_dist_sq then
                best_dist_sq = d2
                best = wall
            end
        end
    end

    return best
end

local function build_perimeter_from(start_wall)
    if not (start_wall and start_wall.valid) then
        return nil
    end

    local surface = start_wall.surface
    local force = start_wall.force

    local open = {start_wall}
    local head = 1
    local visited_by_unit = {}
    local nodes = {}

    local function mark_visited(w)
        if w.valid and not visited_by_unit[w.unit_number] then
            visited_by_unit[w.unit_number] = true
            nodes[#nodes + 1] = {
                x = w.position.x,
                y = w.position.y
            }
            open[#open + 1] = w
        end
    end

    visited_by_unit[start_wall.unit_number] = true
    nodes[1] = {
        x = start_wall.position.x,
        y = start_wall.position.y
    }

    while head <= #open do
        local w = open[head]
        head = head + 1

        if w.valid then
            local wp = w.position

            for dx = -1, 1 do
                for dy = -1, 1 do
                    if not (dx == 0 and dy == 0) then
                        local nx = wp.x + dx
                        local ny = wp.y + dy
                        local area = {{nx - 0.4, ny - 0.4}, {nx + 0.4, ny + 0.4}}

                        local neighbours = surface.find_entities_filtered {
                            type = "wall",
                            force = force,
                            area = area
                        }

                        for _, n in pairs(neighbours) do
                            if n.valid and not visited_by_unit[n.unit_number] then
                                mark_visited(n)
                            end
                        end
                    end
                end
            end
        end
    end

    if #nodes == 0 then
        return nil
    end

    return {
        surface_index = surface.index,
        nodes = nodes,
        last_built_tick = game.tick
    }
end

local function ensure_perimeter(player, pdata)
    local bot = pdata.wall_bot
    if not (bot and bot.valid) then
        return
    end

    local perimeter = pdata.perimeter
    if perimeter then
        if game.tick - (perimeter.last_built_tick or 0) < PERIMETER_REBUILD_TICKS then
            return
        end
    end

    local surface = bot.surface
    local force = bot.force

    local start_wall = find_nearest_wall(surface, force, bot.position, WALL_SEARCH_RADIUS)
    if not start_wall then
        player.print("[WallRepair] No wall found near bot to build perimeter.")
        pdata.perimeter = nil
        pdata.current_node_index = 1
        return
    end

    local new_perimeter = build_perimeter_from(start_wall)
    if new_perimeter and new_perimeter.nodes and #new_perimeter.nodes > 0 then
        pdata.perimeter = new_perimeter
        pdata.current_node_index = 1
        player.print("[WallRepair] Perimeter built with " .. #new_perimeter.nodes .. " wall segments.")
    else
        player.print("[WallRepair] Failed to build perimeter.")
        pdata.perimeter = nil
        pdata.current_node_index = 1
    end
end

---------------------------------------------------
-- BOT SPAWN / MOVEMENT / REPAIR
---------------------------------------------------

local function spawn_wall_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    local surface = player.surface
    local pos = player.position

    local bot = surface.create_entity {
        name = "augment-wall-drone",
        position = {pos.x + 1, pos.y},
        force = player.force
    }

    if bot then
        bot.destructible = false
        pdata.wall_bot = bot
        pdata.perimeter = nil
        pdata.current_node_index = 1
        player.print("[WallRepair] Wall bot spawned.")
    else
        player.print("[WallRepair] Failed to spawn wall bot.")
    end
end

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

local function repair_walls_near(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local walls = surface.find_entities_filtered {
        type = "wall",
        force = force,
        area = area
    }

    for _, wall in pairs(walls) do
        if wall.valid and wall.health then
            -- Factorio will clamp this to the entity's real maximum health
            wall.health = 1000
        end
    end
end

local function update_wall_bot_for_player(player, pdata)
    if not pdata.wall_bot_enabled then
        return
    end

    local bot = pdata.wall_bot
    if not (bot and bot.valid) then
        spawn_wall_bot_for_player(player, pdata)
        bot = pdata.wall_bot
        if not (bot and bot.valid) then
            return
        end
    end

    draw_bot_highlight(bot, pdata)
    ensure_perimeter(player, pdata)
    local perimeter = pdata.perimeter
    if not (perimeter and perimeter.nodes and #perimeter.nodes > 0) then
        return
    end

    local nodes = perimeter.nodes
    local idx = pdata.current_node_index or 1
    if idx < 1 or idx > #nodes then
        idx = 1
    end

    local target = nodes[idx]
    local bp = bot.position
    local dx = target.x - bp.x
    local dy = target.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq <= (WALL_REPAIR_DISTANCE * WALL_REPAIR_DISTANCE) then
        repair_walls_near(bot.surface, bot.force, target, WALL_REPAIR_RADIUS)

        idx = idx + 1
        if idx > #nodes then
            idx = 1
        end
        pdata.current_node_index = idx
        target = nodes[idx]
    end

    move_bot_to(bot, target)
end

---------------------------------------------------
-- HOTKEY HANDLER
---------------------------------------------------

-- IMPORTANT: this name must match the custom-input name in data.lua
script.on_event("augment-toggle-wall-bot", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    pdata.wall_bot_enabled = not pdata.wall_bot_enabled

    if pdata.wall_bot_enabled then
        if not (pdata.wall_bot and pdata.wall_bot.valid) then
            spawn_wall_bot_for_player(player, pdata)
        end
        player.print("[WallRepair] Wall bot enabled.")
    else
        if pdata.wall_bot and pdata.wall_bot.valid then
            pdata.wall_bot.destroy()
        end

        pdata.wall_bot = nil
        pdata.perimeter = nil
        pdata.current_node_index = 1
        player.print("[WallRepair] Wall bot disabled.")

        if pdata.highlight_object then
            local obj = pdata.highlight_object -- LuaRenderObject
            if obj.valid then
                obj:destroy()
            end
            pdata.highlight_object = nil
        end
    end
end)

---------------------------------------------------
-- MAIN TICK
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % WALL_BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    for _, player in pairs(game.connected_players) do
        local pdata = get_player_data(player.index)
        if pdata and pdata.wall_bot_enabled then
            update_wall_bot_for_player(player, pdata)
        end
    end
end)
