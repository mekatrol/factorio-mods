----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Purpose:
--   Implements runtime logic for the "mekatrol-game-play-bot" entity.
--
--   This script:
--     * Listens for the custom hotkey "mekatrol-game-play-bot-toggle".
--     * For each player, toggles a hidden helper entity:
--         - If the player has no bot: create one at the player's position.
--         - If the player already has a bot: destroy it.
----------------------------------------------------------------------
---------------------------------------------------
-- MODULES
---------------------------------------------------
local visuals = require("visuals")

---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
local BOT_UPDATE_INTERVAL = 5
local BOT_STEP_DISTANCE = 0.8
local BOT_FOLLOW_DISTANCE = 1.0

----------------------------------------------------------------------
-- PRINT HELPER: print_bot_message(player, color, fmt, ...)
----------------------------------------------------------------------

local function print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    local text
    local ok, result = pcall(string.format, fmt, ...)
    if ok then
        text = result
    else
        text = "<formatting error>"
    end

    local prefix = string.format("[color=%s][Game Play Bot][/color] ", color)
    player.print {"", prefix, text}
end

----------------------------------------------------------------------
-- PERSISTENT STATE LAYOUT (Factorio 2.x: use `storage`)
--
-- storage.game_bot[player_index] = {
--     entity            = <LuaEntity or nil>,
--     vis_bot_highlight = <LuaRenderObject or nil>,
--     bot_enabled       = <boolean or nil>
-- }
----------------------------------------------------------------------

local function ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

----------------------------------------------------------------------
-- Get (and optionally create) per-player state
----------------------------------------------------------------------

local function get_player_state(player_index)
    ensure_storage_tables()

    local all = storage.game_bot
    local state = all[player_index]

    if not state then
        -- New state for this player.
        state = {
            entity = nil,
            visuals = {
                bot_highlight = nil,
                lines = nil
            },
            bot_enabled = false,
            bot_mode = "follow"
        }
        all[player_index] = state

    else
        -- State previously existed: ensure all fields are present.
        state.entity = state.entity or nil

        -- Ensure visuals table exists.
        state.visuals = state.visuals or {}

        -- Ensure expected members in visuals table.
        state.visuals.bot_highlight = state.visuals.bot_highlight or nil
        state.visuals.lines = state.visuals.lines or nil

        -- disabled by default
        state.bot_enabled = state.bot_enabled or false

        -- follow by default
        state.bot_mode = state.bot_mode or "follow"
    end

    return state
end

----------------------------------------------------------------------
-- Destroy a player's bot entity (if present)
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local state = get_player_state(player.index)

    -- destroy the bot if it exists
    local bot = state.entity
    if bot and bot.valid then
        bot.destroy()
    end

    -- clear all visuals
    visuals.clear_all(state)

    state.entity = nil
    state.bot_enabled = false

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

----------------------------------------------------------------------
-- Create a player's bot entity
----------------------------------------------------------------------

local function create_player_bot(player)
    local state = get_player_state(player.index)

    if state.entity and not state.entity.valid then
        state.entity = nil
    end

    if state.entity and state.entity.valid then
        return state.entity
    end

    local surface = player.surface
    local position = player.position

    local bot = surface.create_entity {
        name = "mekatrol-game-play-bot",
        position = {position.x - 2, position.y - 2},
        force = player.force,
        raise_built = true
    }

    if bot then
        state.entity = bot
        state.bot_enabled = true
        bot.destructible = true

        print_bot_message(player, "green", "created")
        return bot
    else
        print_bot_message(player, "red", "create failed")
        return nil
    end
end

----------------------------------------------------------------------
-- TOGGLE HANDLER: Respond to the custom hotkey
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    local state = get_player_state(player.index)
    local bot = state.entity

    if bot and bot.valid then
        destroy_player_bot(player, false)
        return
    end

    create_player_bot(player)
end

----------------------------------------------------------------------
-- CLEANUP: When bot entities die in the world
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
    local all = storage.game_bot

    for player_index, state in pairs(all) do
        if state.entity == entity then
            state.entity = nil
            state.bot_enabled = false

            visuals.clear_bot_highlight(state)

            local player = game.get_player(player_index)
            if player and player.valid then
                print_bot_message(player, "yellow", "destroyed")
            end
        end
    end
end

----------------------------------------------------------------------
-- PLAYER REMOVAL CLEANUP
----------------------------------------------------------------------

local function on_player_removed(event)
    ensure_storage_tables()
    local all = storage.game_bot
    local player_index = event.player_index

    local state = all[player_index]
    if not state then
        return
    end

    local player = game.get_player(player_index)
    if player and player.valid then
        destroy_player_bot(player, true)
    else
        if state.entity and state.entity.valid then
            state.entity.destroy()
        end
    end

    all[player_index] = nil
end

local function move_bot_to(player, bot, target)
    -- Validate bot and target
    if not (bot and bot.valid and target) then
        return
    end

    local tp

    -- Case 1: Factorio-style entity with .position
    if type(target) == "table" and target.position ~= nil then
        tp = target.position

        -- Case 2: {x = ?, y = ?}
    elseif type(target) == "table" and target.x ~= nil and target.y ~= nil then
        tp = target

        -- Case 3: array-like {x, y}
    elseif type(target) == "table" and target[1] ~= nil and target[2] ~= nil then
        tp = {
            x = target[1],
            y = target[2]
        }

        -- Invalid target
    else
        -- tostring() avoids crashing on non-table values and produces "table: 0xABC123"
        local desc = tostring(target)
        print_bot_message(player, "red", "invalid target: %s", desc)
        return
    end

    ----------------------------------------------------------------------
    -- BOT MOVEMENT
    ----------------------------------------------------------------------

    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    -- Already at target?
    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)

    -- If close enough, teleport directly to target
    if dist <= BOT_STEP_DISTANCE then
        bot.teleport {
            x = tp.x,
            y = tp.y
        }
        return
    end

    -- Normalize direction vector (dx, dy)
    local nx = dx / dist
    local ny = dy / dist

    -- Move one step in the direction
    bot.teleport {
        x = bp.x + nx,
        y = bp.y + ny
    }
end

local function follow_player(player, bot)
    if not (player and player.valid and bot and bot.valid) then
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

        move_bot_to(player, bot, target_pos)
    end
end

---------------------------------------------------
-- MAIN PER-TICK BOT UPDATE
---------------------------------------------------

local function update_bot_for_player(player, player_state)
    -- clear any drawn lines
    visuals.clear_lines(player_state)

    -- draw/update rectangle around bot.
    visuals.draw_bot_highlight(player, player_state)

    -- draw any lines
    visuals.draw_bot_player_visuals(player, player_state.entity, player_state)

    -- follow player if in follow mode
    if player_state.bot_mode == "follow" then
        follow_player(player, player_state.entity)
    end
end

----------------------------------------------------------------------
-- LIFECYCLE HOOKS
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

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)
script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

---------------------------------------------------
-- MAIN TICK
---------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local player_state = get_player_state(player.index)
    if not player_state then
        print_bot_message(player, "green", "player found but no state exists.")
        return
    end

    if player_state.bot_enabled and player_state.entity and player_state.entity.valid then
        update_bot_for_player(player, player_state)
    end
end)
