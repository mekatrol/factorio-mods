----------------------------------------------------------------------
-- control.lua
--
-- Mapping bot that:
--   - Spawns an invisible construction-robot-like bot per player.
--   - Builds a map of player-owned entities via BFS (search in radius).
--   - Teleports from entity to entity and "maps" them.
--   - Draws rectangles around mapped entities using visuals.add_mapped_entity_box.
--   - Shares mapped entity data via storage.mapping_bot_mod.shared_mapped_entities.
--
-- NOTE: This version uses `storage` (Factorio 2.0+).
--       For Factorio 1.1, replace all `storage` with `global`.
----------------------------------------------------------------------
---------------------------------------------------
-- CONFIG
---------------------------------------------------

-- How far around a known entity we search for more entities.
local SEARCH_RADIUS = 32

-- Safety cap: how many entities to expand per tick per player.
local MAX_EXPANSIONS_PER_TICK = 50

-- Tiles per tick the bot will move. 0.1 => 6 tiles/sec at 60 UPS.
local BOT_SPEED_PER_TICK = 0.1

---------------------------------------------------
-- MODULES
---------------------------------------------------

local pathfinding = require("pathfinding")
local visuals = require("visuals")

---------------------------------------------------
-- STATIC ENTITY FILTER
---------------------------------------------------
-- Only map entities that do not move around:
--   - Buildings (assemblers, furnaces, chests, belts, etc.)
--   - Resources (ore patches, oil, etc.)
--
-- You can expand this whitelist as needed.
---------------------------------------------------

local STATIC_TYPES = {
    ["assembling-machine"] = true,
    ["furnace"] = true,
    ["container"] = true,
    ["logistic-container"] = true,
    ["inserter"] = true,
    ["transport-belt"] = true,
    ["underground-belt"] = true,
    ["splitter"] = true,
    ["mining-drill"] = true,
    ["pump"] = true,
    ["pipe"] = true,
    ["pipe-to-ground"] = true,
    ["storage-tank"] = true,
    ["electric-pole"] = true,
    ["lamp"] = true,
    ["accumulator"] = true,
    ["generator"] = true,
    ["boiler"] = true,
    ["solar-panel"] = true,
    ["radar"] = true,
    ["lab"] = true,
    ["roboport"] = true,
    ["beacon"] = true,
    ["electric-energy-interface"] = true,
    ["curved-rail"] = true,
    ["straight-rail"] = true,
    ["simple-entity"] = true,
    ["resource"] = true, -- ore patches, oil, etc.
    ["item-entity"] = true -- items on the ground (iron plates, etc.)
}

---------------------------------------------------
-- STATIC ENTITY FILTER (BLACKLIST VERSION)
---------------------------------------------------
-- We consider entities "static" if they are NOT in this blacklist
-- of obviously moving / dynamic things.
---------------------------------------------------

local NON_STATIC_TYPES = {
    ["character"] = true,
    ["car"] = true,
    ["spider-vehicle"] = true,
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,

    ["unit"] = true, -- biters, etc.
    ["unit-spawner"] = true,
    ["turret"] = false,
    ["ammo-turret"] = false,
    ["electric-turret"] = false,
    ["artillery-turret"] = false,

    ["combat-robot"] = true,
    ["construction-robot"] = true,
    ["logistic-robot"] = true,

    ["projectile"] = true,
    ["beam"] = true,
    ["flying-text"] = true,
    ["smoke"] = true,
    ["fire"] = true,
    ["stream"] = true,
    ["decorative"] = true
}

local function is_static_mappable_entity_blackllist(e)
    if not (e and e.valid) then
        return false
    end

    -- Skip known dynamic types
    if NON_STATIC_TYPES[e.type] then
        return false
    end

    -- Everything else (including item-entity, resources, buildings) is allowed.
    return true
end

local function is_static_mappable_entity_whitelist(e)
    if not (e and e.valid) then
        return false
    end

    -- Only types we explicitly consider static
    if not STATIC_TYPES[e.type] then
        return false
    end

    -- Optional: only map entities the player can see / interact with.
    -- If you want *everything* (including enemy turrets etc.), remove this.
    if e.force ~= game.forces.player then
        return false
    end

    return true
end

---------------------------------------------------
-- ROOT STATE
---------------------------------------------------
-- storage.mapping_bot_mod is the root for this mod's persistent state.
-- It contains:
--   - players[player_index]              : per-player state
--   - shared_mapped_entities[entity_key] : data about mapped entities
---------------------------------------------------

local function ensure_root()
    storage.mapping_bot_mod = storage.mapping_bot_mod or {}
    local s = storage.mapping_bot_mod

    -- Per-player state.
    s.players = s.players or {}

    -- Shared mapping across all players.
    s.shared_mapped_entities = s.shared_mapped_entities or {}

    return s
end

---------------------------------------------------
-- PER-PLAYER STATE
---------------------------------------------------

local function get_player_data(player_index)
    local s = ensure_root()
    local pdata = s.players[player_index]

    ---------------------------------------------------------------
    -- First time: create a new fully-populated pdata table.
    ---------------------------------------------------------------
    if not pdata then
        pdata = {
            ------------------------------------------------------------------
            -- Toggles / mode
            ------------------------------------------------------------------
            mapping_bot_enabled = false, -- hotkey toggle
            last_mode = "off",

            ------------------------------------------------------------------
            -- Bot entity and basic pathing
            ------------------------------------------------------------------
            mapping_bot = nil, -- LuaEntity for the bot
            bot_path = nil, -- reserved for pathfinding module
            bot_path_index = 1,
            bot_path_target = nil,

            ------------------------------------------------------------------
            -- Movement state (for smooth movement)
            ------------------------------------------------------------------
            movement_target_position = nil, -- {x, y} of current destination
            movement_target_name = nil, -- entity name (for expand lookup)

            ------------------------------------------------------------------
            -- Visuals
            ------------------------------------------------------------------
            vis_highlight_object = nil,
            vis_lines = nil,
            vis_bot_path = nil,
            vis_current_waypoint = nil,
            vis_search_radius_circle = nil,

            ------------------------------------------------------------------
            -- Mapping state
            ------------------------------------------------------------------
            mapped_entities = {}, -- [entity_key] = true
            mapped_entity_visuals = {}, -- [entity_key] = rendering_id
            frontier = {} -- queue of entity_keys to expand from
        }

        s.players[player_index] = pdata
        return pdata
    end

    ---------------------------------------------------------------
    -- Backfill: existing saves may have older pdata without new
    -- fields; ensure everything we rely on exists and is a table.
    ---------------------------------------------------------------
    if pdata.mapping_bot_enabled == nil then
        pdata.mapping_bot_enabled = false
    end
    if pdata.last_mode == nil then
        pdata.last_mode = "off"
    end

    if pdata.bot_path_index == nil then
        pdata.bot_path_index = 1
    end

    if pdata.mapped_entities == nil then
        pdata.mapped_entities = {}
    end
    if pdata.mapped_entity_visuals == nil then
        pdata.mapped_entity_visuals = {}
    end
    if pdata.frontier == nil then
        pdata.frontier = {}
    end

    return pdata
end

---------------------------------------------------
-- MAPPED ENTITY UTILITIES
---------------------------------------------------

-- Generate a stable key for a given entity.
-- Uses unit_number when available, otherwise a string based on name/position/surface.
local function get_entity_key(entity)
    if not (entity and entity.valid) then
        return nil
    end

    if entity.unit_number then
        return entity.unit_number
    end

    local pos = entity.position
    return entity.name .. "@" .. pos.x .. "," .. pos.y .. "#" .. entity.surface.index
end

-- Shortcut for the shared mapping table.
local function get_shared_table()
    local s = ensure_root()
    return s.shared_mapped_entities
end

-- Simple FIFO queue functions for the BFS frontier.
local function push_frontier(pdata, key)
    pdata.frontier = pdata.frontier or {}
    pdata.frontier[#pdata.frontier + 1] = key
end

local function pop_frontier(pdata)
    local f = pdata.frontier
    if not f then
        return nil
    end

    local key = f[1]
    if not key then
        return nil
    end
    table.remove(f, 1)
    return key
end

---------------------------------------------------
-- MAPPING: UPSERT + VISUALS
---------------------------------------------------
-- upsert_mapped_entity:
--   - If this entity is new:
--       * mark mapped for this player
--       * store info in shared table
--       * draw rectangle (once)
--       * optionally push to frontier
--   - If this entity was already known:
--       * update position + last_seen_tick (to track movement)
---------------------------------------------------

local function upsert_mapped_entity(player, pdata, entity, tick, add_to_frontier)
    if not (entity and entity.valid) then
        return
    end

    local key = get_entity_key(entity)
    if not key then
        return
    end

    pdata.mapped_entities = pdata.mapped_entities or {}
    pdata.mapped_entity_visuals = pdata.mapped_entity_visuals or {}

    local shared = get_shared_table()
    local info = shared[key]

    if not info then
        -- New entity for the shared map.
        info = {
            name = entity.name,
            surface_index = entity.surface.index,
            position = {
                x = entity.position.x,
                y = entity.position.y
            },
            force_name = entity.force.name,
            last_seen_tick = tick,
            discovered_by_player_index = player.index
        }
        shared[key] = info

        -- Mark as mapped for this player.
        pdata.mapped_entities[key] = true

        -- Draw rectangle once.
        if visuals.add_mapped_entity_box then
            local id = visuals.add_mapped_entity_box(player, pdata, entity)
            pdata.mapped_entity_visuals[key] = id
        else
            -- Fallback rectangle if helper not present.
            local box = entity.selection_box or entity.bounding_box
            if box then
                local id = rendering.draw_rectangle {
                    color = {
                        r = 0,
                        g = 1,
                        b = 0,
                        a = 0.35
                    },
                    width = 2,
                    filled = false,
                    left_top = box.left_top,
                    right_bottom = box.right_bottom,
                    surface = entity.surface,
                    players = {player},
                    draw_on_ground = true
                }
                pdata.mapped_entity_visuals[key] = id
            end
        end

        -- Only new entities are pushed into BFS frontier.
        if add_to_frontier then
            push_frontier(pdata, key)
        end
    else
        -- Known entity: update position + last_seen_tick
        info.position.x = entity.position.x
        info.position.y = entity.position.y
        info.last_seen_tick = tick
        -- No need to redraw rectangle or push to frontier again.
    end
end

-- BFS-style expansion: search around a given entity within SEARCH_RADIUS
-- for more entities owned by the player's force, and upsert them with
-- add_to_frontier = true so exploration continues.
local function expand_from_entity(player, pdata, entity, tick)
    if not (entity and entity.valid) then
        return
    end

    local surface = entity.surface

    local found = surface.find_entities_filtered {
        position = entity.position,
        radius = SEARCH_RADIUS
    }

    local expansions = 0
    for _, e in ipairs(found) do
        if e ~= entity and is_static_mappable_entity_blackllist(e) then
            upsert_mapped_entity(player, pdata, e, tick, true)
            expansions = expansions + 1
            if expansions >= MAX_EXPANSIONS_PER_TICK then
                break
            end
        end
    end
end

---------------------------------------------------
-- BOT SPAWN / DESPAWN
---------------------------------------------------

local spawn_mapping_bot_for_player

-- Create or replace the mapping bot entity for this player.
spawn_mapping_bot_for_player = function(player, pdata)
    if not pdata then
        pdata = get_player_data(player.index)
    end

    -- Remove any existing bot to avoid duplicates.
    if pdata.mapping_bot and pdata.mapping_bot.valid then
        pdata.mapping_bot.destroy()
    end

    local surface = player.surface
    local position = player.position

    -- Create our custom bot entity defined in data.lua.
    local bot = surface.create_entity {
        name = "mekatrol-mapping-bot",
        position = position,
        force = player.force
        -- Optionally: raise_built = true
    }

    if bot then
        pdata.mapping_bot = bot
    else
        pdata.mapping_bot_enabled = false
        pdata.last_mode = "off"
        player.print("[MekatrolMappingBot] Failed to spawn mapping bot.")
    end
end

-- Ensure a bot exists for this player, spawning a new one if needed.
local function ensure_bot_for_player(player, pdata)
    if not (pdata.mapping_bot and pdata.mapping_bot.valid) then
        spawn_mapping_bot_for_player(player, pdata)
    end
    return pdata.mapping_bot
end

---------------------------------------------------
-- TARGET SELECTION AND MOVEMENT
---------------------------------------------------

-- Choose the next entity from the BFS frontier and return the live LuaEntity.
-- Invalid or missing entities are skipped until a valid one is found.
local function pick_next_target_entity(player, pdata)
    while true do
        local key = pop_frontier(pdata)
        if not key then
            -- Frontier exhausted.
            return nil
        end

        local shared = get_shared_table()
        local info = shared[key]
        if info then
            local surface = game.surfaces[info.surface_index]
            if surface then
                -- For static entities, this should find the same entity.
                local ent = surface.find_entity(info.name, info.position)
                if ent and ent.valid then
                    return ent
                end
            end
        end
        -- If this entity doesn't exist anymore, or moved beyond
        -- find_entity, continue to next key.
    end
end

-- For now, movement is implemented as an instant teleport to the target entity.
-- You can replace this with proper pathfinding if desired.
local function move_bot_to_entity(bot, entity)
    if not (bot and bot.valid and entity and entity.valid) then
        return
    end
    bot.teleport(entity.position)
end

---------------------------------------------------
-- MAPPING SEEDING + DYNAMIC RESCAN
---------------------------------------------------

-- On first run for a player, seed the mapping around the player so the BFS
-- has something to start from.
local function seed_mapping_if_needed(player, pdata, tick)
    pdata.mapped_entities = pdata.mapped_entities or {}

    if next(pdata.mapped_entities) ~= nil then
        return
    end

    local surface = player.surface
    local origin = player.position

    local initial = surface.find_entities_filtered {
        position = origin,
        radius = SEARCH_RADIUS
    }

    for _, e in ipairs(initial) do
        if is_static_mappable_entity_blackllist(e) then
            upsert_mapped_entity(player, pdata, e, tick, true)
        end
    end
end

-- Dynamic rescan around the bot:
--   - Ensures moving entities (player, vehicles, other bots, etc.)
--     continuously update their position in the shared map.
--   - Uses add_to_frontier = false because BFS is driven by static expansion.
local function rescan_dynamic_area(player, pdata, bot, tick)
    if not (bot and bot.valid) then
        return
    end

    local surface = bot.surface
    local origin = bot.position

    local dynamic = surface.find_entities_filtered {
        position = origin,
        radius = SEARCH_RADIUS
    }

    for _, e in ipairs(dynamic) do
        if is_static_mappable_entity_blackllist(e) then
            -- Dynamic rescan: keep positions updated, but don't grow BFS frontier.
            upsert_mapped_entity(player, pdata, e, tick, false)
        end
    end
end

local function clear_all_mapped_entities(player, pdata)
    -- Clear rectangles
    if pdata.mapped_entity_visuals then
        for _, id in pairs(pdata.mapped_entity_visuals) do
            local ok, obj = pcall(rendering.get_object_by_id, id)
            if ok and obj and obj.valid then
                obj.destroy()
            end
        end
    end

    pdata.mapped_entity_visuals = {}
    pdata.mapped_entities = {}
    pdata.frontier = {}

    -- Clear shared global map too
    local s = ensure_root()
    s.shared_mapped_entities = {}

    -- Clear search radius circle (via visuals helper if you have it)
    if visuals.clear_search_radius_circle then
        visuals.clear_search_radius_circle(pdata)
    else
        pdata.vis_search_radius_circle = nil
    end

    player.print("[MekatrolMappingBot] Mapped entity database cleared.")
end

---------------------------------------------------
-- PER-TICK MAPPING UPDATE
---------------------------------------------------

local function update_bot_movement(player, pdata, event)
    local bot = pdata.mapping_bot
    local target_pos = pdata.movement_target_position

    if not (bot and bot.valid and target_pos) then
        return
    end

    local pos = bot.position
    local dx = target_pos.x - pos.x
    local dy = target_pos.y - pos.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq == 0 then
        -- Already at target.
        dx, dy = 0, 0
    end

    local step = BOT_SPEED_PER_TICK

    if dist_sq <= step * step then
        -- Arrive this tick: snap to target and perform expansion there.
        bot.teleport(target_pos)

        -- Find the entity at/near this position for expansion.
        local surface = bot.surface
        local entity = nil

        if pdata.movement_target_name then
            entity = surface.find_entity(pdata.movement_target_name, target_pos)
        end

        if not entity then
            local nearby = surface.find_entities_filtered {
                position = target_pos,
                radius = 0.5
            }
            entity = nearby[1]
        end

        if entity and entity.valid then
            expand_from_entity(player, pdata, entity, event.tick)
        end

        -- Clear movement target so a new one can be picked on the next
        -- mapping update.
        pdata.movement_target_position = nil
        pdata.movement_target_name = nil
        return
    end

    -- Move a small step towards the target.
    local dist = math.sqrt(dist_sq)
    local nx = dx / dist
    local ny = dy / dist

    local new_pos = {
        x = pos.x + nx * step,
        y = pos.y + ny * step
    }

    bot.teleport(new_pos)
end

local function update_mapping_bot(player, pdata, event)
    local tick = event.tick

    local bot = ensure_bot_for_player(player, pdata)
    if not bot then
        return
    end

    -- Seed initial entities if needed.
    seed_mapping_if_needed(player, pdata, tick)

    -- Dynamic rescan around the bot so moving entities stay up-to-date.
    rescan_dynamic_area(player, pdata, bot, tick)

    -- If we already have a movement target, let per-tick movement handle it.
    if pdata.movement_target_position then
        return
    end

    -- Pick the next entity from the frontier as a new movement target.
    local target_entity = pick_next_target_entity(player, pdata)
    if not target_entity then
        -- Nothing left to explore this mapping step.
        return
    end

    pdata.movement_target_position = {
        x = target_entity.position.x,
        y = target_entity.position.y
    }
    pdata.movement_target_name = target_entity.name
end

---------------------------------------------------
-- PLAYER INITIALISATION
---------------------------------------------------

local function init_player(player)
    if not player or not player.valid then
        return
    end
    get_player_data(player.index)
end

---------------------------------------------------
-- LIFECYCLE EVENTS
---------------------------------------------------

script.on_init(function()
    ensure_root()
    for _, player in pairs(game.players) do
        init_player(player)
    end
end)

script.on_configuration_changed(function(_)
    ensure_root()
    for _, player in pairs(game.players) do
        init_player(player)
    end
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
-- HOTKEY: "mekatrol-mapping-bot-toggle"
---------------------------------------------------

script.on_event("mekatrol-mapping-bot-toggle", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    pdata.mapping_bot_enabled = not pdata.mapping_bot_enabled

    if pdata.mapping_bot_enabled then
        if not (pdata.mapping_bot and pdata.mapping_bot.valid) then
            spawn_mapping_bot_for_player(player, pdata)
        end

        pdata.last_mode = "mapping"
        player.print("[MekatrolMappingBot] bot enabled.")
        player.print("[MekatrolMappingBot] mode: MAPPING")
    else
        if pdata.mapping_bot and pdata.mapping_bot.valid then
            pdata.mapping_bot.destroy()
        end

        pdata.mapping_bot = nil

        -- Remove search radius circle
        if pdata.vis_search_radius_circle then
            visuals.clear_search_radius_circle(pdata)
        else
            -- fallback, in case helper missing
            pdata.vis_search_radius_circle = nil
        end

        if pathfinding and pathfinding.reset_bot_path then
            pathfinding.reset_bot_path(pdata)
        end

        if pdata.vis_highlight_object then
            local obj = pdata.vis_highlight_object
            if obj and obj.valid then
                obj:destroy()
            end
            pdata.vis_highlight_object = nil
        end

        pdata.last_mode = "off"
        player.print("[MekatrolMappingBot] bot disabled.")
        player.print("[MekatrolMappingBot] mode: OFF")
    end
end)

script.on_event("mekatrol-mapping-bot-clear", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    clear_all_mapped_entities(player, pdata)
end)

---------------------------------------------------
-- MAIN TICK HANDLER
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    for _, player in pairs(game.connected_players) do
        local pdata = get_player_data(player.index)

        if pdata.mapping_bot_enabled then
            -- Ensure bot exists
            local bot = ensure_bot_for_player(player, pdata)

            -- Draw/update the blue search-radius circle every tick (if you have this)
            if bot and bot.valid and visuals.update_search_radius_circle then
                visuals.update_search_radius_circle(player, pdata, bot, SEARCH_RADIUS)
            end

            -- Smooth movement every tick
            update_bot_movement(player, pdata, event)

            -- Target selection + mapping logic every tick, but it will
            -- only pick a new target when there is none.
            update_mapping_bot(player, pdata, event)
        end
    end
end)

