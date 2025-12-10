----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Purpose:
--   Implements runtime logic for the "mekatrol-game-play-bot" entity.
--
--   High-level behavior:
--     * Listens for the custom hotkey "mekatrol-game-play-bot-toggle".
--     * Per-player, maintains a hidden helper entity ("bot") that:
--         - Follows the player (default mode).
--         - Draws simple visuals (highlight + line) so the player can
--           see where the bot is and how it is linked to them.
--     * Handles lifecycle:
--         - Creation and destruction via hotkey.
--         - Cleanup when the bot dies.
--         - Cleanup when the player is removed.
--
--   This file assumes:
--     * The bot prototype "mekatrol-game-play-bot" is defined in data.lua.
--     * A "visuals" module exists providing:
--         - visuals.clear_all(player_state)
--         - visuals.clear_lines(player_state)
--         - visuals.clear_bot_highlight(player_state)
--         - visuals.draw_bot_highlight(player, player_state)
--         - visuals.draw_bot_player_visuals(player, bot, player_state)
----------------------------------------------------------------------
---------------------------------------------------
-- MODULES
---------------------------------------------------
-- Visual helpers for drawing rectangles/lines around the bot.
local visuals = require("visuals")

---------------------------------------------------
-- CONFIGURATION CONSTANTS
---------------------------------------------------

-- Per-tick update interval (in game ticks).
-- Example: 5 means "update bot every 5 ticks".
local BOT_UPDATE_INTERVAL = 5

-- Maximum distance the bot moves in a single movement step.
-- Used when interpolating movement towards a target position.
local BOT_STEP_DISTANCE = 0.8

-- Desired distance at which the bot should follow behind the player.
-- If the bot is further away than this, it will move closer.
local BOT_FOLLOW_DISTANCE = 1.0

----------------------------------------------------------------------
-- UTILITY: PRINT HELPER
--
-- print_bot_message(player, color, fmt, ...)
--
-- PURPOSE:
--   Prints a formatted, color-tagged message to a specific player.
--
--   The message is prefixed with "[Game Play Bot]" in a given color.
--
-- PARAMETERS:
--   player : LuaPlayer
--       Player to receive the message.
--
--   color : string
--       Rich-text color name, e.g. "red", "green", "yellow".
--
--   fmt : string
--       Lua string.format pattern (may contain %s, %d, etc.).
--
--   ... : any
--       Arguments to string.format.
----------------------------------------------------------------------

local function print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    -- Safely format the message text.
    local formatted_text
    local ok, result = pcall(string.format, fmt, ...)
    if ok then
        formatted_text = result
    else
        formatted_text = "<formatting error>"
    end

    -- Prefix with a colored tag so messages are recognizable.
    local prefix = string.format("[color=%s][Game Play Bot][/color] ", color)

    -- Use localized array form so Factorio concatenates pieces.
    player.print {"", prefix, formatted_text}
end

----------------------------------------------------------------------
-- PERSISTENT STATE (Factorio 2.x: use `storage`)
--
-- We store state per-player under storage.game_bot[player_index].
--
-- Layout:
--   storage.game_bot[player_index] = {
--       bot_entity   = <LuaEntity or nil>,       -- The bot entity itself.
--       visuals      = {
--           bot_highlight = <LuaRenderObject or nil>,
--           lines         = <array of LuaRenderObject or nil>
--       },
--       bot_enabled  = <boolean>,                -- Whether bot logic is active.
--       bot_mode     = <string>                  -- "follow", "wander", etc.
--   }
----------------------------------------------------------------------

----------------------------------------------------------------------
-- ensure_storage_tables()
--
-- PURPOSE:
--   Guarantees that the top-level storage table for this mod exists.
----------------------------------------------------------------------

local function ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

----------------------------------------------------------------------
-- get_player_state(player_index)
--
-- PURPOSE:
--   Retrieves the per-player bot state from storage, creating it if
--   it does not yet exist.
--
-- PARAMETERS:
--   player_index : uint
--       Index of the player (player.index).
--
-- RETURNS:
--   player_state : table
--       The per-player state table (always non-nil).
----------------------------------------------------------------------

local function get_player_state(player_index)
    ensure_storage_tables()

    local all_states = storage.game_bot
    local player_state = all_states[player_index]

    if not player_state then
        ------------------------------------------------------------------
        -- New state for this player.
        ------------------------------------------------------------------
        player_state = {
            bot_entity = nil,
            visuals = {
                bot_highlight = nil,
                lines = nil
            },
            bot_enabled = false, -- default: bot off until toggled
            bot_mode = "follow" -- default behavior: follow player
        }
        all_states[player_index] = player_state

    else
        ------------------------------------------------------------------
        -- Existing state: ensure all expected fields exist.
        ------------------------------------------------------------------
        player_state.bot_entity = player_state.bot_entity or nil

        player_state.visuals = player_state.visuals or {}
        player_state.visuals.bot_highlight = player_state.visuals.bot_highlight or nil
        player_state.visuals.lines = player_state.visuals.lines or nil

        -- Defaults for booleans/strings if missing from older saves.
        if player_state.bot_enabled == nil then
            player_state.bot_enabled = false
        end
        player_state.bot_mode = player_state.bot_mode or "follow"
    end

    return player_state
end

----------------------------------------------------------------------
-- BOT LIFECYCLE: DESTROY BOT
--
-- destroy_player_bot(player, silent)
--
-- PURPOSE:
--   Destroys the bot entity for the given player, if it exists, and
--   clears all bot visuals and state flags.
--
-- PARAMETERS:
--   player : LuaPlayer
--   silent : boolean|nil
--       If true, no chat message is printed.
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local player_state = get_player_state(player.index)

    -- Destroy the bot entity if it exists.
    local bot_entity = player_state.bot_entity
    if bot_entity and bot_entity.valid then
        bot_entity.destroy()
    end

    -- Clear all visual artifacts associated with this bot.
    visuals.clear_all(player_state)

    -- Reset core state.
    player_state.bot_entity = nil
    player_state.bot_enabled = false

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

----------------------------------------------------------------------
-- BOT LIFECYCLE: CREATE BOT
--
-- create_player_bot(player)
--
-- PURPOSE:
--   Creates (or reuses) a bot entity for the given player.
--
--   Spawns the bot near the player, marks it destructible, and updates
--   the per-player state.
--
-- RETURNS:
--   bot_entity : LuaEntity or nil
----------------------------------------------------------------------

local function create_player_bot(player)
    local player_state = get_player_state(player.index)

    -- Clear stale entity reference if the stored one is invalid.
    if player_state.bot_entity and not player_state.bot_entity.valid then
        player_state.bot_entity = nil
    end

    -- If an active bot already exists, reuse it.
    if player_state.bot_entity and player_state.bot_entity.valid then
        return player_state.bot_entity
    end

    local surface = player.surface
    local player_pos = player.position

    -- Spawn the bot a small offset away from the player.
    local bot_entity = surface.create_entity {
        name = "mekatrol-game-play-bot", -- must match data.lua prototype
        position = {player_pos.x - 2, player_pos.y - 2},
        force = player.force,
        raise_built = true
    }

    if bot_entity then
        player_state.bot_entity = bot_entity
        player_state.bot_enabled = true
        bot_entity.destructible = true

        print_bot_message(player, "green", "created")
        return bot_entity
    else
        print_bot_message(player, "red", "create failed")
        return nil
    end
end

----------------------------------------------------------------------
-- BOT LIFECYCLE: TOGGLE HANDLER
--
-- on_toggle_bot(event)
--
-- PURPOSE:
--   Responds to the custom hotkey "mekatrol-game-play-bot-toggle".
--
--   Behavior:
--     * If the player currently has a bot -> destroy it.
--     * Otherwise -> create a new bot.
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then
        return
    end

    local player_state = get_player_state(player.index)
    local bot_entity = player_state.bot_entity

    if bot_entity and bot_entity.valid then
        destroy_player_bot(player, false)
        return
    end

    create_player_bot(player)
end

----------------------------------------------------------------------
-- BOT MOVEMENT HELPER: resolve_target_position(target)
--
-- PURPOSE:
--   Coerces various target formats into a simple {x, y} position table.
--
-- SUPPORTED FORMATS:
--   * <LuaEntity> with .position field
--   * {x = number, y = number}
--   * { [1] = number, [2] = number }
--
-- PARAMETERS:
--   target : any
--
-- RETURNS:
--   pos : {x = number, y = number} or nil
--   err : string or nil (error description if pos is nil)
----------------------------------------------------------------------

local function resolve_target_position(target)
    if type(target) == "table" and target.position ~= nil then
        return target.position, nil

    elseif type(target) == "table" and target.x ~= nil and target.y ~= nil then
        return target, nil

    elseif type(target) == "table" and target[1] ~= nil and target[2] ~= nil then
        return {
            x = target[1],
            y = target[2]
        }, nil

    else
        -- Fallback: return a simple description of what we got.
        local desc = tostring(target)
        return nil, desc
    end
end

----------------------------------------------------------------------
-- BOT MOVEMENT: move_bot_towards(player, bot_entity, target)
--
-- PURPOSE:
--   Moves the bot one step towards a target position or entity.
--
--   Uses BOT_STEP_DISTANCE as the maximum movement per call. If the
--   bot is within BOT_STEP_DISTANCE of the target, it teleports
--   directly onto the target.
--
-- PARAMETERS:
--   player     : LuaPlayer
--   bot_entity : LuaEntity
--   target     : position-like value (entity/coords, see resolver above)
----------------------------------------------------------------------

local function move_bot_towards(player, bot_entity, target)
    if not (bot_entity and bot_entity.valid and target) then
        return
    end

    -- Coerce input into a simple {x, y} position.
    local target_pos, error_desc = resolve_target_position(target)
    if not target_pos then
        print_bot_message(player, "red", "invalid target: %s", error_desc or "<unknown>")
        return
    end

    local bot_pos = bot_entity.position
    local dx = target_pos.x - bot_pos.x
    local dy = target_pos.y - bot_pos.y
    local dist_sq = dx * dx + dy * dy

    -- Already at target (or extremely close).
    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)

    -- If target is within one step, snap directly to it.
    if dist <= BOT_STEP_DISTANCE then
        bot_entity.teleport {
            x = target_pos.x,
            y = target_pos.y
        }
        return
    end

    -- Normalize direction and move one step of BOT_STEP_DISTANCE.
    local nx = dx / dist
    local ny = dy / dist

    bot_entity.teleport {
        x = bot_pos.x + nx * BOT_STEP_DISTANCE,
        y = bot_pos.y + ny * BOT_STEP_DISTANCE
    }
end

----------------------------------------------------------------------
-- BOT MOVEMENT: FOLLOW PLAYER
--
-- follow_player(player, bot_entity)
--
-- PURPOSE:
--   Keeps the bot at approximately BOT_FOLLOW_DISTANCE behind the
--   player. If the bot drifts too far, it moves closer.
----------------------------------------------------------------------

local function follow_player(player, bot_entity)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    local bot_pos = bot_entity.position
    local player_pos = player.position

    local dx = player_pos.x - bot_pos.x
    local dy = player_pos.y - bot_pos.y
    local dist_sq = dx * dx + dy * dy
    local desired_sq = BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE

    -- Only move if we are further than the desired follow distance.
    if dist_sq > desired_sq then
        -- Target position: a slight offset behind the player, so the bot
        -- isn't overlapping them directly.
        local offset_x = -2.0
        local offset_y = -2.0

        local target_pos = {
            x = player_pos.x + offset_x,
            y = player_pos.y + offset_y
        }

        move_bot_towards(player, bot_entity, target_pos)
    end
end

---------------------------------------------------
-- MAIN PER-TICK BOT UPDATE
--
-- update_bot_for_player(player, player_state)
--
-- PURPOSE:
--   Performs all per-tick logic for a single player's bot:
--     * Clear and update visuals (lines + highlight).
--     * Run behavior appropriate for the current mode (e.g. follow).
---------------------------------------------------

local function update_bot_for_player(player, player_state)
    -- Safety: must have a valid bot to do anything.
    local bot_entity = player_state.bot_entity
    if not (bot_entity and bot_entity.valid) then
        return
    end

    -- Clear existing lines from previous tick before drawing new ones.
    visuals.clear_lines(player_state)

    -- Draw or update the rectangle highlight around the bot.
    visuals.draw_bot_highlight(player, player_state)

    -- Draw any lines (e.g. line from player to bot).
    visuals.draw_bot_player_visuals(player, bot_entity, player_state)

    -- Behavior: follow player if in follow mode.
    if player_state.bot_mode == "follow" then
        follow_player(player, bot_entity)
    end
end

----------------------------------------------------------------------
-- EVENT HANDLER: ENTITY DIED
--
-- on_entity_died(event)
--
-- PURPOSE:
--   When any entity dies, check if it is one of our bots. If so:
--     * Clear the stored bot reference.
--     * Disable the bot for that player.
--     * Clear visuals.
--     * Notify the player.
----------------------------------------------------------------------

local function on_entity_died(event)
    local entity = event.entity
    if not entity then
        return
    end

    if entity.name ~= "mekatrol-game-play-bot" then
        return
    end

    ensure_storage_tables()
    local all_states = storage.game_bot

    for player_index, player_state in pairs(all_states) do
        if player_state.bot_entity == entity then
            player_state.bot_entity = nil
            player_state.bot_enabled = false

            visuals.clear_all(player_state)

            local player = game.get_player(player_index)
            if player and player.valid then
                print_bot_message(player, "yellow", "destroyed")
            end
        end
    end
end

----------------------------------------------------------------------
-- EVENT HANDLER: PLAYER REMOVED
--
-- on_player_removed(event)
--
-- PURPOSE:
--   Cleans up per-player state when a player is removed from the game:
--     * Destroys their bot.
--     * Clears their entry from storage.game_bot.
----------------------------------------------------------------------

local function on_player_removed(event)
    ensure_storage_tables()
    local all_states = storage.game_bot
    local player_index = event.player_index

    local player_state = all_states[player_index]
    if not player_state then
        return
    end

    local player = game.get_player(player_index)
    if player and player.valid then
        -- Silent to avoid printing to a player that no longer exists.
        destroy_player_bot(player, true)
    else
        if player_state.bot_entity and player_state.bot_entity.valid then
            player_state.bot_entity.destroy()
        end
    end

    all_states[player_index] = nil
end

----------------------------------------------------------------------
-- LIFECYCLE HOOKS (INIT / CONFIG CHANGE)
----------------------------------------------------------------------

script.on_init(function()
    ensure_storage_tables()
end)

script.on_configuration_changed(function(_)
    ensure_storage_tables()
end)

----------------------------------------------------------------------
-- EVENT REGISTRATION
----------------------------------------------------------------------

-- Custom input name must match the custom-input prototype in data.lua:
--   name = "mekatrol-game-play-bot-toggle"
script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

---------------------------------------------------
-- MAIN TICK HANDLER
--
-- PURPOSE:
--   Periodically updates the bot for a single player (player 1).
--   This is a simple single-player implementation. For multiplayer,
--   you would typically loop over all connected players.
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    -- Throttle updates to every BOT_UPDATE_INTERVAL ticks.
    if event.tick % BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    -- For now, we only manage the bot for player 1.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local player_state = get_player_state(player.index)
    if not player_state then
        print_bot_message(player, "green", "player found but no state exists.")
        return
    end

    if player_state.bot_enabled and player_state.bot_entity and player_state.bot_entity.valid then
        update_bot_for_player(player, player_state)
    end
end)
