----------------------------------------------------------------------
-- control.lua
--
-- NOTE: This version uses `storage` for persistent state, which is the
--       Factorio 2.0+ style. If you are targeting 1.1, replace every
--       `storage` with `global`.
----------------------------------------------------------------------
-- Run logic once every 60 seconds (60 * 60 ticks at 60 UPS).
local TICK_INTERVAL = 60 * 60

---------------------------------------------------
-- MODULES
---------------------------------------------------
local pathfinding = require("pathfinding")
local visuals = require("visuals")

---------------------------------------------------
-- INTERNAL STATE ROOT
---------------------------------------------------
-- Ensures the root storage table and players table exist.
-- Returns the root for convenience.
---------------------------------------------------
local function ensure_root()
    storage.mapping_bot_mod = storage.mapping_bot_mod or {}
    local s = storage.mapping_bot_mod
    s.players = s.players or {}
    return s
end

---------------------------------------------------
-- PLAYER STATE ACCESS / INITIALISATION
---------------------------------------------------
-- get_player_data(player_index)
--   - Returns the per-player data table.
--   - Creates and initialises it if missing.
---------------------------------------------------
local function get_player_data(player_index)
    local s = ensure_root()
    local pdata = s.players[player_index]

    if not pdata then
        -- Default initial state for a player.
        pdata = {
            -- Enabled flag toggled via hotkey.
            mapping_bot_enabled = false,

            -- The actual bot entity we spawn.
            mapping_bot = nil,

            -- Pathing information (consumed by pathfinding module).
            bot_path = nil,
            bot_path_index = 1,
            bot_path_target = nil,

            -- Visuals (rendered overlays, markers, etc.).
            vis_highlight_object = nil,
            vis_lines = nil,
            vis_damaged_markers = nil,
            vis_damaged_lines = nil,
            vis_bot_path = nil,
            vis_current_waypoint = nil,

            -- Damaged entities / repair tracking (if used by your logic).
            damaged_entities = nil,
            damaged_entities_next_repair_index = 1,

            -- Misc state.
            last_mode = "off"
        }

        s.players[player_index] = pdata
    end

    return pdata
end

---------------------------------------------------
-- init_player(player)
--   - Ensures player data exists.
--   - Used on player created / config change.
---------------------------------------------------
local function init_player(player)
    if not player or not player.valid then
        return
    end
    get_player_data(player.index)
end

---------------------------------------------------
-- MAPPING BOT SPAWN / DESPAWN
---------------------------------------------------
-- spawn_mapping_bot_for_player(player, pdata)
--   - Spawns the invisible mapping bot entity tied to the player.
--   - Replaces any existing bot on that player.
---------------------------------------------------
local function spawn_mapping_bot_for_player(player, pdata)
    -- Safety: ensure pdata exists.
    if not pdata then
        pdata = get_player_data(player.index)
    end

    -- Remove old bot if still around to avoid duplicates.
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
        -- You can add other properties if needed (e.g. raise_built)
    }

    if bot then
        pdata.mapping_bot = bot
    else
        -- If creation fails, disable the feature so we don't spam errors.
        pdata.mapping_bot_enabled = false
        pdata.last_mode = "off"
        player.print("[MekatrolMappingBot] Failed to spawn mapping bot.")
    end
end

---------------------------------------------------
-- LIFECYCLE EVENTS
---------------------------------------------------

-- Called once when the save is first created with this mod.
script.on_init(function()
    ensure_root()
    -- Backfill all existing players (e.g. in scenarios).
    for _, player in pairs(game.players) do
        init_player(player)
    end
end)

-- Called when mod configuration changes (version updates, added/removed mods).
script.on_configuration_changed(function(_)
    ensure_root()
    -- Re-initialise player data so new fields are populated.
    for _, player in pairs(game.players) do
        init_player(player)
    end
end)

-- Called whenever a new player is created (joins the game for the first time).
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        init_player(player)
    end
end)

-- on_load: only needed if you have upvalue references you need to reconstruct.
-- For this simple setup we do not need to do anything.
script.on_load(function()
    -- No on_load logic needed currently.
end)

---------------------------------------------------
-- HOTKEY HANDLER: "mekatrol-mapping-bot-toggle"
---------------------------------------------------
-- Toggles the mapping bot for the player pressing the hotkey.
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

    -- Toggle the enabled flag.
    pdata.mapping_bot_enabled = not pdata.mapping_bot_enabled

    if pdata.mapping_bot_enabled then
        -- Ensure bot exists when enabling.
        if not (pdata.mapping_bot and pdata.mapping_bot.valid) then
            spawn_mapping_bot_for_player(player, pdata)
        end

        pdata.last_mode = "mapping" -- or "follow", depending on your design
        player.print("[MekatrolMappingBot] bot enabled.")
        player.print("[MekatrolMappingBot] mode: MAPPING")
    else
        -- Turning off: clean up entity and visuals.
        if pdata.mapping_bot and pdata.mapping_bot.valid then
            pdata.mapping_bot.destroy()
        end

        pdata.mapping_bot = nil
        pdata.damaged_entities = nil
        pdata.damaged_entities_next_repair_index = 1

        -- Clear any visual markers / paths.
        visuals.clear_damaged_markers(pdata)
        pathfinding.reset_bot_path(pdata)

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

---------------------------------------------------
-- MAIN TICK HANDLER
---------------------------------------------------
-- Runs every TICK_INTERVAL ticks (60 seconds at 60 UPS).
-- Currently only prints a debug message when enabled.
-- Expand this to call your pathfinding / mapping logic.
---------------------------------------------------
script.on_event(defines.events.on_tick, function(event)
    -- Only do work every Nth tick to reduce CPU usage.
    if event.tick % TICK_INTERVAL ~= 0 then
        return
    end

    -- Iterate over all connected players.
    for _, player in pairs(game.connected_players) do
        local pdata = get_player_data(player.index)

        -- Only act if the mapping bot is enabled for this player.
        if pdata.mapping_bot_enabled then
            -- Debug output; replace with real logic as needed.
            player.print("[MekatrolMappingBot] periodic tick.")

            -- Example hook point:
            -- pathfinding.update_mapping_bot(player, pdata)
            -- visuals.update_path_visuals(player, pdata)
        end
    end
end)
