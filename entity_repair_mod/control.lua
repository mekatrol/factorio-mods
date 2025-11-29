---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
local REPAIR_BOT_UPDATE_INTERVAL = 5
local BOT_SPEED_TILES_PER_SECOND = 4.0
local MAX_HEALTH_SCAN_INTERVAL = 3600
local ENTITY_SEARCH_RADIUS = 256.0
local ENTITY_REPAIR_DISTANCE = 2.0
local ENTITY_REPAIR_RADIUS = 20.0
local BOT_HIGHLIGHT_Y_OFFSET = -1.2
local BOT_FOLLOW_DISTANCE = 1.0
local BOT_STEP_DISTANCE = 0.8

---------------------------------------------------
-- MODULES
---------------------------------------------------
local pathfinding = require("pathfinding")
local visuals = require("visuals")

---------------------------------------------------
-- REPAIR TOOL CONFIGURATION
---------------------------------------------------
local REPAIR_TOOL_NAME = "repair-pack"
local REPAIR_TOOLS_PER_ENTITY = 1
local REPAIR_TOOL_HEALTH_INCREMENT_PCT = 0.1

---------------------------------------------------
-- HEALTH HELPERS / MAX HEALTH OVERRIDES
---------------------------------------------------
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

local UNKNOWN_ENTITY_WARNED = UNKNOWN_ENTITY_WARNED or {}

local function get_discovered_table()
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
    local s = storage.mekatrol_repair_mod
    s.discovered_max_health = s.discovered_max_health or {}
    return s.discovered_max_health
end

local function scan_player_entities_for_max_health(force)
    if not force then
        return
    end

    local discovered = get_discovered_table()

    for _, surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered {
            force = force
        }

        for _, e in pairs(entities) do
            if e.valid and e.health then
                local name = e.name

                if not ENTITY_MAX_HEALTH[name] then
                    local h = e.health
                    local prev = discovered[name]

                    if not prev or h > prev then
                        discovered[name] = h
                        local suggested = math.floor(h + 0.5)
                        local line = string.format("[\"%s\"] = %d,\n", name, suggested)

                        game.print("[MekatrolRepairBot][SCAN] " .. line)

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
        game.print(string.format(
            "[MekatrolRepairBot][INFO] Observed max health %.1f for '%s' (force=%s). Suggested: ENTITY_MAX_HEALTH[\"%s\"] = %d",
            max_health_seen, name, force.name, name, suggested))

        local line = string.format("[\"%s\"] = %d,\n", name, suggested)
        game.print("[MekatrolRepairBot][INFO] " .. line)

        if helpers and helpers.write_file then
            helpers.write_file("mekatrol_repair_mod_maxhealth_scan.txt", line, true)
        else
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

    local from_table = ENTITY_MAX_HEALTH[name]
    if type(from_table) == "number" and from_table > 0 then
        return from_table
    end

    if not UNKNOWN_ENTITY_WARNED[name] then
        UNKNOWN_ENTITY_WARNED[name] = true
        local inferred = infer_max_health_from_world(name, entity.force)
        if inferred and inferred > 0 then
            return inferred
        end
    end

    return nil
end

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
local function init_player(player)
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
    local s = storage.mekatrol_repair_mod

    s.players = s.players or {}
    local pdata = s.players[player.index]

    if not pdata then
        pdata = {
            repair_bot_enabled = false,
            repair_bot = nil,

            repair_targets = nil,
            current_target_index = 1,

            highlight_object = nil,
            damaged_markers = nil,
            damaged_lines = nil,

            out_of_tools_warned = false,

            bot_path = nil,
            bot_path_index = 1,
            bot_path_target = nil,
            bot_path_visuals = nil,
            current_wp_visual = nil
        }

        s.players[player.index] = pdata
    else
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
-- DAMAGED ENTITY SEARCH
---------------------------------------------------
local function find_damaged_entities(surface, force, center, radius)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

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
local function build_nearest_route(entities, start_pos)
    local ordered = {}
    local used = {}
    local remaining = #entities

    local current_x = start_pos.x
    local current_y = start_pos.y

    while remaining > 0 do
        local best_i, best_d2 = nil, nil

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

        if not best_i then
            break
        end

        local e = entities[best_i]
        used[best_i] = true
        ordered[#ordered + 1] = e
        remaining = remaining - 1

        local ep = e.position
        current_x = ep.x
        current_y = ep.y
    end

    return ordered
end

local function rebuild_repair_route(player, pdata, bot)
    if not (bot and bot.valid) then
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        visuals.clear_damaged_markers(pdata)
        return
    end

    if not (player and player.valid) then
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        visuals.clear_damaged_markers(pdata)
        return
    end

    local surface = bot.surface
    local force = bot.force
    local search_center = player.position

    local damaged = find_damaged_entities(surface, force, search_center, ENTITY_SEARCH_RADIUS)

    visuals.clear_damaged_markers(pdata)

    if not damaged or #damaged == 0 then
        pdata.repair_targets = nil
        pdata.current_target_index = 1
        return
    end

    visuals.draw_damaged_visuals(bot, pdata, damaged, BOT_HIGHLIGHT_Y_OFFSET)

    pdata.repair_targets = build_nearest_route(damaged, bot.position)
    pdata.current_target_index = 1
end

---------------------------------------------------
-- BOT SPAWN / SIMPLE MOVEMENT / FOLLOW
---------------------------------------------------
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

        pdata.repair_targets = nil
        pdata.current_target_index = 1
        pathfinding.reset_bot_path(pdata)

        player.print("[MekatrolRepairBot] Repair bot spawned.")
    else
        player.print("[MekatrolRepairBot] Failed to spawn repair bot.")
    end
end

-- Simple straight-line move (non–A*).
local function move_bot_to(bot, target)
    if not (bot and bot.valid and target) then
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

    if dist_sq > desired_sq then
        local offset_x = -2.0
        local offset_y = -2.0

        local target_pos = {
            x = pp.x + offset_x,
            y = pp.y + offset_y
        }

        move_bot_to(bot, target_pos)
    end
end

---------------------------------------------------
-- REPAIR LOGIC
---------------------------------------------------
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

    local pdata = get_player_data(player.index)
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local entities = surface.find_entities_filtered {
        force = force,
        area = area
    }

    for _, ent in pairs(entities) do
        if inv.get_item_count(REPAIR_TOOL_NAME) <= 0 then
            if pdata then
                pdata.out_of_tools_warned = true
                player.print("[MekatrolRepairBot] Out of repair tools; stopping repairs.")
            end
            return
        end

        if ent.valid and ent.health then
            local max = get_entity_max_health(ent)
            if max and ent.health < max then
                local removed = inv.remove {
                    name = REPAIR_TOOL_NAME,
                    count = REPAIR_TOOLS_PER_ENTITY
                }

                if removed > 0 then
                    local health_increment = max * REPAIR_TOOL_HEALTH_INCREMENT_PCT
                    ent.health = math.min(max, ent.health + health_increment)

                    if pdata then
                        pdata.out_of_tools_warned = false
                    end
                else
                    return
                end
            end
        end
    end
end

---------------------------------------------------
-- MAIN PER-TICK BOT UPDATE
---------------------------------------------------
local function update_repair_bot_for_player(player, pdata)
    if not pdata.repair_bot_enabled then
        pathfinding.clear_bot_path_visuals(pdata)
        return
    end

    local bot = pdata.repair_bot
    if not (bot and bot.valid) then
        spawn_repair_bot_for_player(player, pdata)
        bot = pdata.repair_bot
        if not (bot and bot.valid) then
            return
        end
    end

    -- visuals.draw_bot_highlight(bot, pdata, BOT_HIGHLIGHT_Y_OFFSET)

    rebuild_repair_route(player, pdata, bot)

    local targets = pdata.repair_targets

    if not targets or #targets == 0 then
        if pdata.last_mode ~= "follow" then
            player.print("[MekatrolRepairBot] mode: FOLLOWING PLAYER")
            pdata.last_mode = "follow"
        end
        visuals.clear_damaged_markers(pdata)

        pathfinding.reset_bot_path(pdata)

        follow_player(bot, player)
        return
    else
        if pdata.last_mode ~= "repair" then
            player.print("[MekatrolRepairBot] mode: REPAIRING DAMAGE")
            pdata.last_mode = "repair"
        end
    end

    local idx = pdata.current_target_index or 1
    if idx < 1 or idx > #targets then
        idx = 1
    end

    local target_entity = targets[idx]

    while target_entity and (not target_entity.valid or not is_entity_damaged(target_entity)) do
        idx = idx + 1
        if idx > #targets then
            rebuild_repair_route(player, pdata, bot)
            targets = pdata.repair_targets
            idx = pdata.current_target_index or 1

            if not targets or #targets == 0 then
                visuals.clear_damaged_markers(pdata)
                return
            end
        end

        target_entity = targets[idx]
    end

    if not target_entity or not target_entity.valid then
        return
    end

    pdata.current_target_index = idx

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

        repair_entities_near(player, bot.surface, bot.force, tp, ENTITY_REPAIR_RADIUS)

        rebuild_repair_route(player, pdata, bot)
        targets = pdata.repair_targets

        pdata.current_target_index = idx + 1
    else
        -- still using simple move; if you want A*, replace this with:
        -- pathfinding.move_bot_to_a_star(bot, tp, pdata, BOT_STEP_DISTANCE)
        move_bot_to(bot, {
            x = tp.x,
            y = tp.y
        })
    end
end

---------------------------------------------------
-- LIFECYCLE EVENTS
---------------------------------------------------
script.on_init(function()
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
end)

script.on_configuration_changed(function(_)
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        init_player(player)
    end
end)

script.on_load(function()
end)

---------------------------------------------------
-- HOTKEY HANDLER
---------------------------------------------------
script.on_event("mekatrol-toggle-repair-bot", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    pdata.repair_bot_enabled = not pdata.repair_bot_enabled

    if pdata.repair_bot_enabled then
        if not (pdata.repair_bot and pdata.repair_bot.valid) then
            spawn_repair_bot_for_player(player, pdata)
        end

        pdata.last_mode = "follow"
        player.print("[MekatrolRepairBot] Repair bot enabled.")
        player.print("[MekatrolRepairBot] mode: FOLLOWING PLAYER")
    else
        if pdata.repair_bot and pdata.repair_bot.valid then
            pdata.repair_bot.destroy()
        end

        pdata.repair_bot = nil
        pdata.repair_targets = nil
        pdata.current_target_index = 1

        visuals.clear_damaged_markers(pdata)
        pathfinding.reset_bot_path(pdata)

        if pdata.highlight_object then
            local obj = pdata.highlight_object
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.highlight_object = nil
        end

        pdata.last_mode = "off"
        player.print("[MekatrolRepairBot] Repair bot disabled.")
        player.print("[MekatrolRepairBot] mode: OFF")
    end
end)

---------------------------------------------------
-- MAIN TICK
---------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
    if event.tick % REPAIR_BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local pdata = get_player_data(player.index)
    if not pdata then
        player.print("[MekatrolRepairBot] Player found but no pdata exists.")
        return
    end

    if event.tick % MAX_HEALTH_SCAN_INTERVAL == 0 then
        scan_player_entities_for_max_health(player.force)
    end

    if pdata.repair_bot_enabled then
        update_repair_bot_for_player(player, pdata)
    end
end)
