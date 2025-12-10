----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Purpose:
--   Implements runtime logic for the "mekatrol-game-play-bot" entity.
--
--   High-level behavior:
--     * Listens for custom hotkeys:
--         - "mekatrol-game-play-bot-toggle"
--         - "mekatrol-game-play-bot-next-mode"
--     * Per-player, maintains a hidden helper entity ("bot") that:
--         - Follows the player (default mode).
--         - Wanders randomly and surveys nearby entities (wander mode).
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
--         - visuals.draw_bot_player_visuals(player, bot, player_state, radius)
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
local BOT_UPDATE_INTERVAL = 1

-- Maximum distance the bot moves in a single movement step.
-- Used when interpolating movement towards a target position.
local BOT_STEP_DISTANCE = 0.18

-- Desired distance at which the bot should follow behind the player.
-- If the bot is further away than this, it will move closer.
local BOT_FOLLOW_DISTANCE = 1.0

-- The side distance from the player that the bot targets when positioning
-- (can be -BOT_SIDE_OFFSET_DISTANCE or +BOT_SIDE_OFFSET_DISTANCE depending
-- on player direction).
local BOT_SIDE_OFFSET_DISTANCE = 2.0

----------------------------------------------------------------------
-- WANDER MODE TUNING
--
-- WANDER_STEP_DISTANCE
--   Maximum "random hop" distance when the bot is roaming in wander
--   mode. This is independent of BOT_STEP_DISTANCE, which is the
--   per-tick movement limit.
--
-- WANDER_DETECTION_RADIUS
--   Radius around the bot in which we consider "any entity found".
--   Once something is detected (other than the bot itself), the bot
--   stops roaming and transitions into the "survey" phase.
--
-- WANDER_SURVEY_RADIUS
--   Radius used during the survey phase to enumerate entities in the
--   local area. These are recorded in per-player state and a summary
--   is printed to the player.
----------------------------------------------------------------------

local WANDER_STEP_DISTANCE = 5.0
local WANDER_DETECTION_RADIUS = 6.0
local WANDER_SURVEY_RADIUS = 10.0

----------------------------------------------------------------------
-- BOT MODES
--
-- BOT_MODES:
--   Ordered list of supported behaviors. The "mode cycle" hotkey
--   uses this array to advance to the next mode in sequence.
--
-- BOT_MODE_INDEX:
--   Reverse lookup: mode_name -> index in BOT_MODES.
--   This allows O(1) lookups when cycling or validating modes.
----------------------------------------------------------------------

local BOT_MODES = {"follow", "wander"}

local BOT_MODE_INDEX = {}
for i, mode_name in ipairs(BOT_MODES) do
    BOT_MODE_INDEX[mode_name] = i
end

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
--       bot_entity   = <LuaEntity or nil>,
--       visuals      = {
--           bot_highlight = <LuaRenderObject or nil>,
--           lines         = <array of LuaRenderObject or nil>
--       },
--       bot_enabled  = <boolean>,                -- Whether bot logic is active.
--       bot_mode     = <string>,                 -- "follow", "wander", etc.
--       last_player_position      = {x, y} or nil,
--       last_player_side_offset_x = <number>,    -- last chosen side offset (+/- BOT_SIDE_OFFSET_DISTANCE)
--
--       -- WANDER MODE STATE:
--       --   * wander_target_position:
--       --       Current roam target (random point) or nil.
--       --   * wander_found_anchor:
--       --       Anchor position where entities were detected; once
--       --       set, the bot stops and performs a survey.
--       --   * wander_mapped_entities:
--       --       Cached results of the last survey, stored as simple
--       --       tables ({name=..., position={x=...,y=...}}, ...).
--       wander_target_position  = {x, y} or nil,
--       wander_found_anchor     = {x, y} or nil,
--       wander_mapped_entities  = <array of tables> or nil
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
                lines = nil,
                radius_circle = nil
            },
            bot_enabled = false, -- default: bot off until toggled
            bot_mode = "follow", -- default behavior: follow player
            last_player_position = nil, -- used to infer player movement direction
            last_player_side_offset_x = -BOT_SIDE_OFFSET_DISTANCE,

            -- Wander mode fields (start with clean slate).
            wander_target_position = nil,
            wander_found_anchor = nil,
            wander_mapped_entities = nil
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
        player_state.visuals.radius_circle = player_state.visuals.radius_circle or nil

        if player_state.bot_enabled == nil then
            player_state.bot_enabled = false
        end

        player_state.bot_mode = player_state.bot_mode or "follow"
        player_state.last_player_position = player_state.last_player_position or nil
        player_state.last_player_side_offset_x = player_state.last_player_side_offset_x or -BOT_SIDE_OFFSET_DISTANCE

        -- Backfill wander-related fields for saves that predate wander mode.
        player_state.wander_target_position = player_state.wander_target_position or nil
        player_state.wander_found_anchor = player_state.wander_found_anchor or nil
        player_state.wander_mapped_entities = player_state.wander_mapped_entities or nil
    end

    return player_state
end

----------------------------------------------------------------------
-- reset_wander_state(player_state)
--
-- PURPOSE:
--   Clears all wander-specific state so that the next time the bot
--   enters wander mode it starts with a clean slate.
----------------------------------------------------------------------

local function reset_wander_state(player_state)
    if not player_state then
        return
    end

    player_state.wander_target_position = nil
    player_state.wander_found_anchor = nil
    player_state.wander_mapped_entities = nil
end

----------------------------------------------------------------------
-- set_player_bot_mode(player, player_state, new_mode)
--
-- PURPOSE:
--   Safely updates the behavior mode for a player's bot. This:
--     * Validates the mode against BOT_MODES.
--     * Resets wander state when leaving wander.
--     * Prints a feedback message to the player.
----------------------------------------------------------------------

local function set_player_bot_mode(player, player_state, new_mode)
    if not player_state then
        return
    end

    -- Validate new_mode; fall back to "follow" if unknown.
    if not BOT_MODE_INDEX[new_mode] then
        new_mode = "follow"
    end

    local old_mode = player_state.bot_mode or "follow"
    if old_mode == new_mode then
        print_bot_message(player, "yellow", "mode remains %s", new_mode)
        return
    end

    -- If we are leaving wander mode, clear any wander-specific state.
    if old_mode == "wander" then
        reset_wander_state(player_state)
    end

    player_state.bot_mode = new_mode

    print_bot_message(player, "green", "mode set to %s", new_mode)
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

    -- Clear any wander-related state for cleanliness.
    reset_wander_state(player_state)

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
-- follow_player(player, bot_entity, player_state)
--
-- PURPOSE:
--   Keeps the bot near the player, and chooses which side (left/right)
--   to follow on. The X offset is only changed when the player
--   actually changes horizontal movement direction:
--
--     * If player starts moving left (dx < -ε) and was not already
--       "right side", we flip the bot to the RIGHT side (+x offset).
--
--     * If player starts moving right (dx > +ε) and was not already
--       "left side", we flip the bot to the LEFT side (-x offset).
--
--   If the player is standing still or moving mostly vertically,
--   we keep the current side (no offset change).
----------------------------------------------------------------------

local function follow_player(player, bot_entity, player_state)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    local bot_pos = bot_entity.position
    local player_pos = player.position

    ------------------------------------------------------------------
    -- 1. Determine player movement along X and update side only
    --    when direction changes.
    ------------------------------------------------------------------
    local prev_pos = player_state.last_player_position
    local moving_left = false
    local moving_right = false

    if prev_pos then
        local dx_move = player_pos.x - prev_pos.x
        local epsilon = 0.1 -- small threshold to ignore tiny jitter

        if dx_move < -epsilon then
            moving_left = true
        elseif dx_move > epsilon then
            moving_right = true
        end
    end

    -- Update stored previous position for next tick.
    player_state.last_player_position = {
        x = player_pos.x,
        y = player_pos.y
    }

    ------------------------------------------------------------------
    -- 2. Choose side offset X.
    --
    -- We only change side_offset_x when the player actually moves
    -- left/right past the epsilon threshold. Otherwise we keep the
    -- previous offset stored in state.
    ------------------------------------------------------------------
    local side_offset_x = player_state.last_player_side_offset_x or -BOT_SIDE_OFFSET_DISTANCE

    if moving_left and side_offset_x ~= BOT_SIDE_OFFSET_DISTANCE then
        -- Player is moving left-ish; flip bot to the RIGHT side.
        side_offset_x = BOT_SIDE_OFFSET_DISTANCE
    elseif moving_right and side_offset_x ~= -BOT_SIDE_OFFSET_DISTANCE then
        -- Player is moving right-ish; flip bot to the LEFT side.
        side_offset_x = -BOT_SIDE_OFFSET_DISTANCE
    end

    -- Persist the chosen side offset so we only change it on direction changes.
    player_state.last_player_side_offset_x = side_offset_x

    ------------------------------------------------------------------
    -- 3. Check follow distance (radial).
    ------------------------------------------------------------------
    local dx = player_pos.x - bot_pos.x
    local dy = player_pos.y - bot_pos.y
    local dist_sq = dx * dx + dy * dy
    local desired_sq = BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE

    -- Only move if we are further than the desired follow distance.
    if dist_sq <= desired_sq then
        return
    end

    ------------------------------------------------------------------
    -- 4. Build target position using the chosen side offset.
    --
    -- Vertical offset remains constant so the bot sits slightly
    -- "behind" the player.
    ------------------------------------------------------------------
    local offset_y = -2.0

    local target_pos = {
        x = player_pos.x + side_offset_x,
        y = player_pos.y + offset_y
    }

    ------------------------------------------------------------------
    -- 5. Move bot towards the chosen side position.
    ------------------------------------------------------------------
    move_bot_towards(player, bot_entity, target_pos)
end

----------------------------------------------------------------------
-- WANDER MODE: RANDOM ROAM + AREA SURVEY
--
-- wander_bot(player, bot_entity, player_state)
--
-- PURPOSE:
--   Implements "wander" behavior in two phases:
--
--   1) Roam phase:
--        * Bot picks random nearby points and walks towards them,
--          continually choosing new random targets as it arrives.
--        * After each movement, it scans a detection radius
--          (WANDER_DETECTION_RADIUS) for any entities.
--        * If any entity (other than itself) is found, the bot:
--            - Records the current position as an "anchor".
--            - Stops moving.
--            - Transitions into the survey phase.
--
--   2) Survey phase:
--        * Bot stays at the anchor position.
--        * Once per survey, it enumerates all entities in a larger
--          radius (WANDER_SURVEY_RADIUS) around the anchor.
--        * Results are stored in player_state.wander_mapped_entities
--          as simple, serializable tables.
--        * A summary is printed to the player.
--
--   The bot remains stationary at the anchor until the player changes
--   mode via the mode-cycle hotkey or other script action.
----------------------------------------------------------------------

local function wander_bot(player, bot_entity, player_state)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    local surface = bot_entity.surface
    local bot_pos = bot_entity.position

    ------------------------------------------------------------------
    -- 1) SURVEY PHASE:
    --
    --    If an anchor already exists, the bot has finished roaming
    --    and is now in survey mode. It does not move; it merely
    --    records and reports entities once.
    ------------------------------------------------------------------
    if player_state.wander_found_anchor then
        local anchor = player_state.wander_found_anchor

        -- Only perform the survey once per anchor. If results already
        -- exist, keep the bot idle.
        if not player_state.wander_mapped_entities then
            local entities = surface.find_entities_filtered {
                position = anchor,
                radius = WANDER_SURVEY_RADIUS
            }

            local mapped = {}
            local count = 0

            for _, entity in ipairs(entities) do
                if entity.valid and entity.name ~= "mekatrol-game-play-bot" then
                    count = count + 1
                    mapped[#mapped + 1] = {
                        name = entity.name,
                        position = {
                            x = entity.position.x,
                            y = entity.position.y
                        }
                    }
                end
            end

            player_state.wander_mapped_entities = mapped

            if count > 0 then
                print_bot_message(player, "green", "wander survey at (%.1f, %.1f): mapped %d entities.", anchor.x,
                    anchor.y, count)
            else
                print_bot_message(player, "yellow", "wander survey at (%.1f, %.1f): no entities found.", anchor.x,
                    anchor.y)
            end
        end

        -- Stay put at the anchor until the mode is changed.
        return
    end

    ------------------------------------------------------------------
    -- 2) ROAM PHASE:
    --
    --    No anchor yet, so we roam by picking random local targets and
    --    walking towards them. After each move we scan for entities.
    ------------------------------------------------------------------
    local target = player_state.wander_target_position
    if not target then
        -- Pick a new random target near the current position.
        --
        -- math.random() in Factorio is deterministic per save and is
        -- safe for gameplay logic.
        local dx = (math.random() * 2 - 1) * WANDER_STEP_DISTANCE
        local dy = (math.random() * 2 - 1) * WANDER_STEP_DISTANCE

        target = {
            x = bot_pos.x + dx,
            y = bot_pos.y + dy
        }

        player_state.wander_target_position = target
    end

    -- Move one step towards the wander target using the same
    -- movement helper used by other behaviors.
    move_bot_towards(player, bot_entity, target)

    -- If we got close to the target, clear it so a new one is chosen
    -- on the next tick, producing a random walk.
    local new_pos = bot_entity.position
    local ddx = target.x - new_pos.x
    local ddy = target.y - new_pos.y
    local dist_sq = ddx * ddx + ddy * ddy
    if dist_sq <= (BOT_STEP_DISTANCE * BOT_STEP_DISTANCE) then
        player_state.wander_target_position = nil
    end

    ------------------------------------------------------------------
    -- 3) DETECTION AFTER MOVEMENT:
    --
    --    After moving, scan a detection radius around the bot. If any
    --    entities (besides the bot) are found, record an anchor and
    --    transition to survey mode. The survey itself will run next
    --    tick.
    ------------------------------------------------------------------
    local nearby = surface.find_entities_filtered {
        position = new_pos,
        radius = WANDER_DETECTION_RADIUS
    }

    local found_any = false
    for _, entity in ipairs(nearby) do
        if entity.valid and entity ~= bot_entity then
            found_any = true
            break
        end
    end

    if found_any then
        player_state.wander_found_anchor = {
            x = new_pos.x,
            y = new_pos.y
        }
        player_state.wander_target_position = nil
        player_state.wander_mapped_entities = nil

        print_bot_message(player, "yellow", "wander detected entities near (%.1f, %.1f); stopping to survey.",
            new_pos.x, new_pos.y)
    end
end

----------------------------------------------------------------------
-- MODE CYCLING: HOTKEY HANDLER
--
-- on_cycle_bot_mode(event)
--
-- PURPOSE:
--   Handler for the "mekatrol-game-play-bot-next-mode" hotkey.
--   Advances the mode:
--       follow -> wander -> follow -> ...
--
--   This does NOT create or destroy the bot. It only changes the mode
--   stored in state. If the bot is currently active, it will react to
--   the new mode on the next tick.
----------------------------------------------------------------------

local function on_cycle_bot_mode(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then
        return
    end

    local player_state = get_player_state(player.index)
    if not player_state then
        return
    end

    local current_mode = player_state.bot_mode or "follow"
    local current_index = BOT_MODE_INDEX[current_mode] or 1

    local next_index = current_index + 1
    if next_index > #BOT_MODES then
        next_index = 1
    end

    local next_mode = BOT_MODES[next_index]
    set_player_bot_mode(player, player_state, next_mode)
end

---------------------------------------------------
-- MAIN PER-TICK BOT UPDATE
--
-- update_bot_for_player(player, player_state)
--
-- PURPOSE:
--   Performs all per-tick logic for a single player's bot:
--     * Clear and update visuals (lines + highlight).
--     * Run behavior appropriate for the current mode (follow/wander).
---------------------------------------------------

local function update_bot_for_player(player, player_state)
    local bot_entity = player_state.bot_entity
    if not (bot_entity and bot_entity.valid) then
        return
    end

    -- Clear existing lines from previous tick before drawing new ones.
    visuals.clear_lines(player_state)

    -- Draw any lines (e.g. line from player to bot).
    -- Line color already depends on player_state.bot_mode in visuals.lua.
    visuals.draw_bot_player_visuals(player, bot_entity, player_state, WANDER_DETECTION_RADIUS)

    ------------------------------------------------------------------
    -- Behavior dispatch based on current mode.
    ------------------------------------------------------------------
    if player_state.bot_mode == "follow" then
        follow_player(player, bot_entity, player_state)

    elseif player_state.bot_mode == "wander" then
        wander_bot(player, bot_entity, player_state)
    else
        -- Unknown mode: do nothing except visuals.
        -- This is intentionally silent; mode validation is handled by
        -- set_player_bot_mode.
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

-- Cycle bot modes (follow -> wander -> follow -> ...).
-- Custom input name must match the custom-input prototype in data.lua:
--   name = "mekatrol-game-play-bot-next-mode"
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_bot_mode)

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
