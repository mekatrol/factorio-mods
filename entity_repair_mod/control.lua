---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
local REPAIR_BOT_HEALTH = 100
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
-- REPAIR PACK CONFIGURATION
---------------------------------------------------
local REPAIR_PACK_NAME = "repair-pack"

-- How many packs are consumed at a time when we need *new* durability.
-- With the durability pool logic below this is effectively “packs per top-up”,
-- not “packs per entity”.
local REPAIR_PACKS_PER_INVENTORY_FETCH = 1

-- Fraction of an entity’s max health to *attempt* to repair per step.
-- This is still used to determine the size of each healing step,
-- but actual pack consumption is now pooled and shared across entities.
local REPAIR_PACK_HEALTH_INCREMENT_PCT = 1

-- Total health that a single repair pack can repair across all entities.
-- This is the “durability” per pack. Tune to taste.
local REPAIR_PACK_HEALTH_PER_PACK = 100

---------------------------------------------------
-- HEALTH HELPERS / MAX HEALTH OVERRIDES
---------------------------------------------------
local ENTITY_MAX_HEALTH = ENTITY_MAX_HEALTH or {
    ["mekatrol-repair-bot"] = REPAIR_BOT_HEALTH,
    ["mekatrol-mapping-bot"] = 100,
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
            -- set to true when the bot is enabled using hotkey
            repair_bot_enabled = false,
            repair_bot = nil,

            -- the list of damaged entities
            damaged_entities = nil,

            -- the index of the next damaged enitity to repair
            damaged_entities_next_repair_index = 1,

            -- set to true once the user has been warned there are no repair packs available 
            out_of_repair_packs_warned = false,

            -- pathing
            bot_path = nil,
            bot_path_index = 1,
            bot_path_target = nil,

            -- visuals (rendered on display)
            vis_bot_highlight = nil,
            vis_chest_highlight = nil,
            vis_lines = nil,
            vis_damaged_markers = nil,
            vis_damaged_lines = nil,
            vis_bot_path = nil,
            vis_current_waypoint = nil,

            -- accumulated durability from already-consumed repair packs
            -- measured in "health points" that can be spent across entities
            repair_health_pool = 0,

            -- cached reference to the iron chest where repair packs are stored
            -- (nearest iron chest with repair packs, same force/surface as player)
            repair_chest = nil
        }

        s.players[player.index] = pdata
    else
        -- init enabled state
        if pdata.repair_bot_enabled == nil then
            pdata.repair_bot_enabled = false
        end

        -- tracking damaged entities
        pdata.damaged_entities = pdata.damaged_entities or nil
        pdata.damaged_entities_next_repair_index = pdata.damaged_entities_next_repair_index or 1

        -- pathing
        pdata.bot_path = pdata.bot_path or nil
        pdata.bot_path_index = pdata.bot_path_index or 1
        pdata.bot_path_target = pdata.bot_path_target or nil

        -- visuals (rendered on display)
        pdata.vis_bot_highlight = pdata.vis_bot_highlight or nil
        pdata.vis_chest_highlight = pdata.vis_chest_highlight or nil
        pdata.vis_lines = pdata.vis_lines or pdata.vis_lines
        pdata.vis_damaged_markers = pdata.vis_damaged_markers or nil
        pdata.vis_damaged_lines = pdata.vis_damaged_lines or nil
        pdata.vis_bot_path = pdata.vis_bot_path or nil
        pdata.vis_current_waypoint = pdata.vis_current_waypoint or nil

        -- durability pool may not exist in older saves
        pdata.repair_health_pool = pdata.repair_health_pool or 0

        -- cached repair chest may not exist in older saves
        pdata.repair_chest = pdata.repair_chest or nil
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
-- REPAIR PACK / DURABILITY HELPERS
---------------------------------------------------
-- We track a per-player "repair_health_pool" that represents health points
-- available from already-consumed repair packs. This lets one pack heal
-- multiple entities instead of being consumed per entity.
-- repair packs can be taken from a single iron chest (preferred)
-- only if the chest cannot supply enough durability do we fall back
-- to the player inventory.

local function get_player_repair_data(player)
    if not (player and player.valid) then
        return nil
    end
    local pdata = get_player_data(player.index)
    if not pdata then
        return nil
    end
    pdata.repair_health_pool = pdata.repair_health_pool or 0
    return pdata
end

-- Locate the iron chest that should be used as the repair-pack source.
-- Strategy:
--   * If pdata.repair_chest is still valid and is an iron chest, use it.
--   * Otherwise, search the player's surface for iron chests of the same force
--     that currently contain at least one repair pack.
--   * Prefer the nearest such chest to the player.
local function find_repair_chest(player, pdata)
    if not (player and player.valid) then
        return nil
    end

    pdata = pdata or get_player_repair_data(player)
    if not pdata then
        return nil
    end

    -- Reuse cached chest only if it is still valid and still has repair packs.
    if pdata.repair_chest and pdata.repair_chest.valid and pdata.repair_chest.name == "iron-chest" then
        local inv = pdata.repair_chest.get_inventory(defines.inventory.chest)
        if inv and inv.valid and inv.get_item_count(REPAIR_PACK_NAME) > 0 then
            return pdata.repair_chest
        else
            -- cached chest ran out of packs, drop it
            pdata.repair_chest = nil
        end
    end

    local surface = player.surface
    local force = player.force

    local chests = surface.find_entities_filtered {
        name = "iron-chest",
        force = force
    }

    if not chests or #chests == 0 then
        pdata.repair_chest = nil
        return nil
    end

    local best, best_d2 = nil, nil
    local pp = player.position

    for _, chest in pairs(chests) do
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv and inv.valid and inv.get_item_count(REPAIR_PACK_NAME) > 0 then
                local cp = chest.position
                local dx = cp.x - pp.x
                local dy = cp.y - pp.y
                local d2 = dx * dx + dy * dy
                if not best_d2 or d2 < best_d2 then
                    best = chest
                    best_d2 = d2
                end
            end
        end
    end

    pdata.repair_chest = best
    return best
end

-- Teleport the bot to the repair chest, pull some repair packs, convert them
-- into pooled durability, and teleport the bot back.
-- Returns the amount of health added to the pool.
local function refill_repair_pool_from_chest(player, pdata, bot)
    if not (player and player.valid and pdata and bot and bot.valid) then
        return 0
    end

    local chest = find_repair_chest(player, pdata)
    if not (chest and chest.valid) then
        return 0
    end

    local inv = chest.get_inventory(defines.inventory.chest)
    if not (inv and inv.valid) then
        pdata.repair_chest = nil
        return 0
    end

    local available = inv.get_item_count(REPAIR_PACK_NAME)
    if available <= 0 then
        return 0
    end

    local to_remove = math.min(REPAIR_PACKS_PER_INVENTORY_FETCH, available)
    if to_remove <= 0 then
        return 0
    end

    local old_pos = bot.position

    -- bot “visits” the chest, then returns
    bot.teleport(chest.position)

    local removed = inv.remove {
        name = REPAIR_PACK_NAME,
        count = to_remove
    }

    if removed <= 0 then
        bot.teleport(old_pos)
        return 0
    end

    pdata.repair_health_pool = (pdata.repair_health_pool or 0) + (REPAIR_PACK_HEALTH_PER_PACK * removed)
    pdata.out_of_repair_packs_warned = false

    bot.teleport(old_pos)

    return removed * REPAIR_PACK_HEALTH_PER_PACK
end

-- Returns true if the player has either:
--   * at least one repair pack in inventory, or
--   * any remaining pooled repair health, or
--   * an iron chest that currently contains repair packs.
local function player_has_repair_capacity(player, pdata)
    if not (player and player.valid) then
        return false
    end

    pdata = pdata or get_player_repair_data(player)
    if not pdata then
        return false
    end

    local pool = pdata.repair_health_pool or 0

    local inv = get_player_main_inventory(player)
    local inventory_packs = 0
    if inv and inv.valid then
        inventory_packs = inv.get_item_count(REPAIR_PACK_NAME)
    end

    local chest = find_repair_chest(player, pdata)
    local chest_has_packs = chest ~= nil

    return pool > 0 or inventory_packs > 0 or chest_has_packs
end

-- Convert repair packs into "health points" and spend from that pool.
-- requested_health is how much health we would like to repair right now.
-- Returns the actual health value we are allowed to apply (<= requested_health).
-- If the pool is empty and we need durability, first refill from the iron chest.
-- Only if that is insufficient do we fall back to the player's inventory.
local function consume_repair_health(player, pdata, requested_health, bot)
    if not (player and player.valid and pdata) then
        return 0
    end

    if requested_health <= 0 then
        return 0
    end

    local inv = get_player_main_inventory(player)
    if not inv then
        return 0
    end

    pdata.repair_health_pool = pdata.repair_health_pool or 0
    local pool = pdata.repair_health_pool

    -- If we don't have enough durability, top up from chest (preferred) then inventory.
    if requested_health > pool then
        -- First: if pool is depleted, try to refill from iron chest.
        if pool <= 0 then
            refill_repair_pool_from_chest(player, pdata, bot)
            pool = pdata.repair_health_pool or 0
        end

        -- If we still need more, fall back to the player's inventory.
        local remaining_needed = math.max(0, requested_health - pool)

        while remaining_needed > 0 do
            local packs_available = inv.get_item_count(REPAIR_PACK_NAME)
            if packs_available <= 0 then
                break
            end

            local removed = inv.remove {
                name = REPAIR_PACK_NAME,
                count = REPAIR_PACKS_PER_INVENTORY_FETCH
            }

            if removed <= 0 then
                break
            end

            -- Each removed pack adds a fixed amount of repair capacity.
            pool = pool + (REPAIR_PACK_HEALTH_PER_PACK * removed)
            remaining_needed = math.max(0, requested_health - pool)
            pdata.out_of_repair_packs_warned = false
        end
    end

    -- Spend from the pool.
    local spent = math.min(requested_health, pool)
    if spent <= 0 then
        pdata.repair_health_pool = pool
        return 0
    end

    pool = pool - spent
    pdata.repair_health_pool = pool

    return spent
end

---------------------------------------------------
-- DAMAGED ENTITY SEARCH
---------------------------------------------------
local function find_damaged_entities(bot, center, radius)
    local surface = bot.surface
    local force = bot.force
    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local candidates = surface.find_entities_filtered {
        force = force,
        area = area
    }

    local damaged = {}

    for _, ent in pairs(candidates) do
        if ent ~= bot and is_entity_damaged(ent) then
            damaged[#damaged + 1] = ent
        end
    end

    return damaged
end

---------------------------------------------------
-- ROUTE BUILDING (NEAREST NEIGHBOUR)
---------------------------------------------------
local function build_nearest_route(entities, bot)
    local ordered = {}
    local used = {}
    local remaining = #entities

    local start_pos = bot.position
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

local function rebuild_repair_route(player, bot, pdata)
    visuals.clear_damaged_markers(pdata)

    -- If bot or player is invalid, clear route and stop
    if not (bot and bot.valid and player and player.valid) then
        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1
        return
    end

    local search_center = player.position

    visuals.draw_bot_player_visuals(player, bot, pdata, BOT_HIGHLIGHT_Y_OFFSET)

    local damaged = find_damaged_entities(bot, search_center, ENTITY_SEARCH_RADIUS)

    if not damaged or #damaged == 0 then
        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1
        return
    end

    visuals.draw_damaged_visuals(bot, pdata, damaged, BOT_HIGHLIGHT_Y_OFFSET)

    pdata.damaged_entities = build_nearest_route(damaged, bot)
    pdata.damaged_entities_next_repair_index = 1
end

---------------------------------------------------
-- BOT SPAWN / SIMPLE MOVEMENT / FOLLOW
---------------------------------------------------
local function ensure_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    if pdata.repair_bot and pdata.repair_bot.valid then
        return pdata.repair_bot
    end

    local surface = player.surface
    local pos = player.position

    local bot = surface.create_entity {
        name = "mekatrol-repair-bot",
        position = {pos.x - 1, pos.y - 1},
        force = player.force
    }

    if bot then
        bot.destructible = true
        bot.health = REPAIR_BOT_HEALTH
        pdata.repair_bot = bot

        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1
        pathfinding.reset_bot_path(pdata)

        player.print("[MekatrolRepairBot] bot spawned.")
    else
        player.print("[MekatrolRepairBot] failed to spawn bot.")
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
local function repair_bot_self_heal(player, bot, pdata)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    pdata = pdata or get_player_repair_data(player)
    if not pdata then
        return
    end

    -- If there is neither inventory nor pooled durability (and no chest packs), bail and warn once.
    if not player_has_repair_capacity(player, pdata) then
        if not pdata.out_of_repair_packs_warned then
            pdata.out_of_repair_packs_warned = true
            player.print("[MekatrolRepairBot] No repair packs in chest or inventory. Bot cannot repair.")
        end
        return
    end

    -- only self heal if damaged
    local max = get_entity_max_health(bot)
    if not max or bot.health >= max then
        return
    end

    local missing = max - bot.health
    if missing <= 0 then
        return
    end

    -- requested step: fraction of max health, clamped to missing.
    local base_increment = max * REPAIR_PACK_HEALTH_INCREMENT_PCT
    if base_increment <= 0 then
        return
    end

    local requested = math.min(missing, base_increment)
    local spent = consume_repair_health(player, pdata, requested, bot)

    if spent > 0 then
        local before_health = bot.health
        bot.health = math.min(max, bot.health + spent)
        pdata.out_of_repair_packs_warned = false
        -- DEBUG: you can log before/after if needed
        -- player.print(string.format("[MekatrolRepairBot] Bot self-healed %.1f (%.1f -> %.1f)", spent, before_health, bot.health))
    else
        -- No durability available anymore – warn once.
        if not pdata.out_of_repair_packs_warned and not player_has_repair_capacity(player, pdata) then
            pdata.out_of_repair_packs_warned = true
            player.print("[MekatrolRepairBot] Out of repair packs; bot cannot self-repair.")
        end
    end
end

local function repair_entities_near(player, surface, force, center, radius, bot)
    if not (player and player.valid) then
        return
    end

    local pdata = get_player_repair_data(player)
    if not pdata then
        return
    end

    -- If we have neither inventory nor pooled durability (and no chest packs), warn once.
    if not player_has_repair_capacity(player, pdata) then
        if not pdata.out_of_repair_packs_warned then
            pdata.out_of_repair_packs_warned = true
            player.print("[MekatrolRepairBot] No repair packs in chest or inventory. Bot cannot repair.")
        end
        return
    end

    local area = {{center.x - radius, center.y - radius}, {center.x + radius, center.y + radius}}

    local entities = surface.find_entities_filtered {
        force = force,
        area = area
    }

    for _, ent in pairs(entities) do
        if not (ent and ent.valid and ent.health) then
            goto continue_entity
        end

        local max = get_entity_max_health(ent)
        if not max or ent.health >= max then
            goto continue_entity
        end

        -- How much we *could* repair this entity in a single step.
        local missing = max - ent.health
        local base_increment = max * REPAIR_PACK_HEALTH_INCREMENT_PCT
        if base_increment <= 0 then
            goto continue_entity
        end

        local requested = math.min(missing, base_increment)

        -- Spend from the pooled durability, topping up from chest (when pool is 0) and then inventory as needed.
        local spent = consume_repair_health(player, pdata, requested, bot)

        if spent > 0 then
            ent.health = math.min(max, ent.health + spent)
            pdata.out_of_repair_packs_warned = false
        else
            -- No more durability available; check if we truly ran out and warn once.
            if not player_has_repair_capacity(player, pdata) then
                if not pdata.out_of_repair_packs_warned then
                    pdata.out_of_repair_packs_warned = true
                    player.print("[MekatrolRepairBot] Out of repair packs; stopping repairs.")
                end
                return
            end
        end

        ::continue_entity::
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
        ensure_bot_for_player(player, pdata)
        bot = pdata.repair_bot
        if not (bot and bot.valid) then
            return
        end
    end

    -- clear any drawn lines
    visuals.clear_lines(pdata)

    local max = get_entity_max_health(bot) or REPAIR_BOT_HEALTH
    visuals.update_bot_health_bar(player, bot, pdata, max, BOT_HIGHLIGHT_Y_OFFSET, REPAIR_PACK_NAME)

    -- draw rect around bot
    visuals.draw_bot_highlight(bot, pdata, BOT_HIGHLIGHT_Y_OFFSET)

    -- draw rect around chest
    local chest = pdata.repair_chest
    if (chest and chest.valid) then
        visuals.draw_chest_highlight(chest, pdata, 0)
    end

    -- Build/refresh the list of damaged entities around the player.
    -- This must run before we look at pdata.damaged_entities, otherwise
    -- we will never have any targets to repair.
    rebuild_repair_route(player, bot, pdata)

    -- the bot should repair itself first
    repair_bot_self_heal(player, bot, pdata)

    local targets = pdata.damaged_entities

    if not targets or #targets == 0 then
        if pdata.last_mode ~= "follow" then
            pdata.last_mode = "follow"
        end
        visuals.clear_damaged_markers(pdata)

        pathfinding.reset_bot_path(pdata)

        follow_player(bot, player)
        return
    else
        if pdata.last_mode ~= "repair" then
            pdata.last_mode = "repair"
        end
    end

    local idx = pdata.damaged_entities_next_repair_index or 1
    if idx < 1 or idx > #targets then
        idx = 1
    end

    local target_entity = targets[idx]

    while target_entity and (not target_entity.valid or not is_entity_damaged(target_entity)) do
        idx = idx + 1
        if idx > #targets then
            rebuild_repair_route(player, bot, pdata)
            targets = pdata.damaged_entities
            idx = pdata.damaged_entities_next_repair_index or 1

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

    pdata.damaged_entities_next_repair_index = idx

    local tp = target_entity.position
    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq <= (ENTITY_REPAIR_DISTANCE * ENTITY_REPAIR_DISTANCE) then
        if pdata.last_mode ~= "repair" then
            pdata.last_mode = "repair"
        end

        repair_entities_near(player, bot.surface, bot.force, tp, ENTITY_REPAIR_RADIUS, bot)

        rebuild_repair_route(player, bot, pdata)
        targets = pdata.damaged_entities

        pdata.damaged_entities_next_repair_index = idx + 1
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
-- MAPPING BOT MOD EVENTS
---------------------------------------------------
local mapping_bot_event
local mapping_bot_event_registered = false
local mapping_bot_event_registered = false

local seen_mapped_entities = {}

local function on_mapping_bot_entity_mapped(e)
    if seen_mapped_entities[e.key] then
        return -- ignore updates; already processed this entity
    end
    seen_mapped_entities[e.key] = true

    local info = e.info or {}
    -- Do whatever the repair bot should do with this entity
    local msg = string.format("[MekatrolRepairBot] NEW mapped entity: key=%s, name=%s, surface=%d (first_seen=%d)",
        tostring(e.key), info.name or "<nil>", info.surface_index or -1, info.last_seen_tick or -1)
    -- game.print(msg)
end

local function on_mapping_bot_entities_cleared(e)
    local msg = string.format("[MekatrolRepairBot] Mapping cleared (reason=%s, player_index=%s, tick=%d)",
        tostring(e.reason), tostring(e.player_index), e.tick or -1)
    -- game.print(msg)

    seen_mapped_entities = {}
end

local function register_mapping_bot_event()
    if mapping_bot_event_registered then
        return
    end

    if remote.interfaces["mapping_bot_mod"] then
        local iface = remote.interfaces["mapping_bot_mod"]

        if iface.get_event then
            mapping_bot_event = remote.call("mapping_bot_mod", "get_event")
            script.on_event(mapping_bot_event, on_mapping_bot_entity_mapped)
        end

        if iface.get_clear_event then
            mapping_bot_clear_event = remote.call("mapping_bot_mod", "get_clear_event")
            script.on_event(mapping_bot_clear_event, on_mapping_bot_entities_cleared)
        end

        mapping_bot_event_registered = true
    end
end

---------------------------------------------------
-- LIFECYCLE EVENTS
---------------------------------------------------
script.on_init(function()
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}

    -- Register mapping-bot event listener
    register_mapping_bot_event()
end)

script.on_configuration_changed(function(_)
    storage.mekatrol_repair_mod = storage.mekatrol_repair_mod or {}

    -- Re-register in case event id changed or mod set changed
    register_mapping_bot_event()
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
        ensure_bot_for_player(player, pdata)

        pdata.last_mode = "follow"
        player.print("[MekatrolRepairBot] Repair bot enabled.")
    else
        if pdata.repair_bot and pdata.repair_bot.valid then
            pdata.repair_bot.destroy()
        end

        pdata.repair_bot = nil
        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1

        -- clear all visuals
        visuals.clear_all(pdata)
        visuals.force_clear_mod_objects(pdata)

        pathfinding.reset_bot_path(pdata)

        if pdata.vis_bot_highlight then
            local obj = pdata.vis_bot_highlight
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.vis_bot_highlight = nil
        end

        if pdata.vis_chest_highlight then
            local obj = pdata.vis_chest_highlight
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.vis_chest_highlight = nil
        end

        pdata.last_mode = "off"
        player.print("[MekatrolRepairBot] Repair bot disabled.")
    end
end)

---------------------------------------------------
-- MAIN TICK
---------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
    -- Ensure we are subscribed to the mapping-bot event.
    if not mapping_bot_event_registered then
        register_mapping_bot_event()
    end

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
