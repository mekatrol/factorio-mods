---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
local REPAIR_BOT_HEALTH = 100

local SEARCH_RADIUS = 32

-- Must match "name" in info.json
local MOD_NAME = "mapping_bot_mod"

---------------------------------------------------
-- MODULES
---------------------------------------------------
local visuals = require("visuals")

---------------------------------------------------
-- NON-STATIC BLACKLIST
-- Any type listed here is *not* mapped.
-- Everything else (including item-entity and turrets) IS mapped.
---------------------------------------------------
local NON_STATIC_TYPES = {
    ["character"] = true,
    ["car"] = true,
    ["spider-vehicle"] = true,
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,

    ["unit"] = true,
    ["unit-spawner"] = true,

    ["corpse"] = true,
    ["character-corpse"] = true,

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

local function is_static_mappable(e)
    if not (e and e.valid) then
        return false
    end

    -- Anything explicitly marked as NON_STATIC is *ignored*
    if NON_STATIC_TYPES[e.type] then
        return false
    end

    -- Everything else counts as static:
    --   turrets, belts, inserters, chests, resources,
    --   pipes, rails, item-on-ground, etc.
    return true
end

---------------------------------------------------
-- ROOT STORAGE
---------------------------------------------------
local function ensure_root()
    storage.mapping_bot_mod = storage.mapping_bot_mod or {}
    storage.mapping_bot_mod.players = storage.mapping_bot_mod.players or {}
    storage.mapping_bot_mod.shared_mapped_entities = storage.mapping_bot_mod.shared_mapped_entities or {}
    return storage.mapping_bot_mod
end

---------------------------------------------------
-- PER-PLAYER DATA
---------------------------------------------------
local function get_player_data(idx)
    local root = ensure_root()
    local pdata = root.players[idx]

    if not pdata then
        pdata = {
            mapping_bot_enabled = false,
            mapping_bot = nil,
            mapped_entities = {},
            mapped_entity_visuals = {},
            vis_search_radius_circle = nil
        }
        root.players[idx] = pdata
    end

    return pdata
end

---------------------------------------------------
-- ENTITY KEY
---------------------------------------------------
local function get_entity_key(entity)
    if entity.unit_number then
        return entity.unit_number
    end

    local p = entity.position
    return entity.name .. "@" .. p.x .. "," .. p.y .. "#" .. entity.surface.index
end

---------------------------------------------------
-- UPSERT MAPPED ENTITY
---------------------------------------------------
local function upsert_mapped_entity(player, pdata, entity, tick)
    local key = get_entity_key(entity)
    if not key then
        return
    end

    local shared = ensure_root().shared_mapped_entities
    local info = shared[key]

    if not info then
        -- Create new mapping entry
        info = {
            name = entity.name,
            surface_index = entity.surface.index,
            position = {
                x = entity.position.x,
                y = entity.position.y
            },
            force_name = entity.force and entity.force.name or nil,
            last_seen_tick = tick,
            discovered_by_player_index = player.index
        }
        shared[key] = info
        pdata.mapped_entities[key] = true

        -- Draw rectangle
        if visuals.add_mapped_entity_box then
            local id = visuals.add_mapped_entity_box(player, pdata, entity)
            pdata.mapped_entity_visuals[key] = id
        end
    else
        -- Update existing entry
        info.position.x = entity.position.x
        info.position.y = entity.position.y
        info.last_seen_tick = tick
    end
end

---------------------------------------------------
-- BOT MANAGEMENT
---------------------------------------------------
local function ensure_bot_for_player(player, pdata)
    if not (player and player.valid and player.character) then
        return
    end

    if pdata.mapping_bot and pdata.mapping_bot.valid then
        return pdata.mapping_bot
    end

    local surface = player.surface
    local pos = player.position

    local bot = surface.create_entity {
        name = "mekatrol-mapping-bot",
        position = {pos.x + 2, pos.y - 1},
        force = player.force
    }

    if bot then
        bot.destructible = true
        bot.health = REPAIR_BOT_HEALTH
        pdata.mapping_bot = bot

        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1

        player.print("[MekatrolMappingBot] bot spawned.")
    else
        player.print("[MekatrolMappingBot] failed to spawn bot.")
    end

    pdata.mapping_bot = bot
    return bot
end

local function update_bot(player, pdata, tick)
    local bot = ensure_bot_for_player(player, pdata)
    if not (bot and bot.valid) then
        return
    end

    -- FOLLOW PLAYER
    local pos = player.position
    local offset = {pos.x + 3, pos.y - 2}
    bot.teleport(offset)

    -- BLUE SEARCH CIRCLE (every tick)
    if visuals.update_search_radius_circle then
        visuals.update_search_radius_circle(player, pdata, bot, SEARCH_RADIUS)
    end

    -- MAP ENTITIES IN RADIUS
    local found = bot.surface.find_entities_filtered {
        position = bot.position,
        radius = SEARCH_RADIUS
    }

    for _, e in ipairs(found) do
        if e ~= bot and e ~= player and is_static_mappable(e) then
            upsert_mapped_entity(player, pdata, e, tick)
        end
    end
end

---------------------------------------------------
-- CLEAR ALL MAP DATA (ENTITIES + VISUALS)
---------------------------------------------------
local function clear_all_mapped_entities(pdata)
    if not pdata then
        return
    end

    ----------------------------------------------------------------
    -- 1. Wipe ALL rendering objects created by this mod
    --    This removes:
    --      - All mapped entity boxes
    --      - Any search-radius circles
    --      - Any other rendering from this mod
    ----------------------------------------------------------------
    pcall(rendering.clear, MOD_NAME)

    ----------------------------------------------------------------
    -- 2. Reset per-player mapping state
    ----------------------------------------------------------------
    pdata.mapped_entities = {}
    pdata.mapped_entity_visuals = {}
    pdata.vis_search_radius_circle = nil

    ----------------------------------------------------------------
    -- 3. Reset shared global map
    ----------------------------------------------------------------
    local root = ensure_root()
    root.shared_mapped_entities = {}
end

---------------------------------------------------
-- EVENTS
---------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
    for _, player in pairs(game.connected_players) do
        local pdata = get_player_data(player.index)
        if pdata.mapping_bot_enabled then
            update_bot(player, pdata, event.tick)
        end
    end
end)

script.on_event("mekatrol-mapping-bot-toggle", function(event)
    local player = game.get_player(event.player_index)
    local pdata = get_player_data(event.player_index)

    pdata.mapping_bot_enabled = not pdata.mapping_bot_enabled

    if pdata.mapping_bot_enabled then
        ensure_bot_for_player(player, pdata)
    else
        if pdata.mapping_bot and pdata.mapping_bot.valid then
            pdata.mapping_bot.destroy()
        end
        pdata.mapping_bot = nil
        player.print("[MappingBot] Bot disabled.")
    end
end)

script.on_event("mekatrol-mapping-bot-clear", function(event)
    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    clear_all_mapped_entities(pdata)
end)
