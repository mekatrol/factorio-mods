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
--         - Follows the player (follow mode).
--         - Wanders randomly and surveys nearby entities (wander mode).
--         - Surveys the surrounding area and records entities (survey mode).
--     * Draws simple visuals (highlight + line + optional radius).
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
--         - visuals.clear_radius_circle(player_state)
--         - visuals.draw_bot_highlight(player, player_state)
--         - visuals.draw_radius_circle(player, player_state, bot_entity, radius, color)
--         - visuals.draw_lines(player, player_state, bot_entity, line_color)
--         - visuals.draw_mapped_entity_box(player, player_state, entity)
----------------------------------------------------------------------
---------------------------------------------------
-- MODULES
---------------------------------------------------
local visuals = require("visuals")

---------------------------------------------------
-- CONFIGURATION CONSTANTS
---------------------------------------------------

-- Per-tick update interval (in game ticks).
local BOT_UPDATE_INTERVAL = 1

-- Maximum distance the bot moves in a single movement step.
local BOT_STEP_DISTANCE = 0.18

-- Desired distance at which the bot should follow behind the player.
local BOT_FOLLOW_DISTANCE = 1.0

-- Horizontal offset used when the bot follows to the side of the player.
local BOT_SIDE_OFFSET_DISTANCE = 2.0

----------------------------------------------------------------------
-- WANDER / SURVEY TUNING
----------------------------------------------------------------------

-- Maximum random hop distance when the bot is roaming in wander mode.
local WANDER_STEP_DISTANCE = 5.0

-- Radius around the bot for detecting "any entity found" to trigger survey.
local WANDER_DETECTION_RADIUS = 5.0

-- Radius used during survey mode to enumerate entities in the local area.
local SURVEY_RADIUS = 6.0

----------------------------------------------------------------------
-- BOT MODES
----------------------------------------------------------------------

local BOT_MODES = {"follow", "wander", "survey"}

-- Reverse lookup: mode_name -> index in BOT_MODES.
local BOT_MODE_INDEX = {}
for i, mode_name in ipairs(BOT_MODES) do
    BOT_MODE_INDEX[mode_name] = i
end

----------------------------------------------------------------------
-- NON-STATIC BLACKLIST
--
-- Any type listed here is NOT mapped. Everything else is eligible.
----------------------------------------------------------------------

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

    ["fish"] = true,

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

----------------------------------------------------------------------
-- PRINT HELPER
--
-- print_bot_message(player, color, fmt, ...)
--
-- Purpose:
--   Prints a formatted, color-tagged message to a specific player,
--   prefixed with "[Game Play Bot]".
----------------------------------------------------------------------

local function print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    local formatted_text
    local ok, result = pcall(string.format, fmt, ...)
    if ok then
        formatted_text = result
    else
        formatted_text = "<formatting error>"
    end

    local prefix = string.format("[color=%s][Game Play Bot][/color] ", color)
    player.print({"", prefix, formatted_text})
end

----------------------------------------------------------------------
-- PERSISTENT STATE (Factorio 2.x: storage)
----------------------------------------------------------------------

-- ensure_storage_tables()
--
-- Purpose:
--   Guarantees that the top-level storage table for this mod exists.
local function ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

-- get_player_state(player_index)
--
-- Purpose:
--   Retrieves the per-player bot state from storage, creating it if
--   it does not yet exist.
--
-- Returns:
--   player_state : table (always non-nil).
local function get_player_state(player_index)
    ensure_storage_tables()

    local all_states = storage.game_bot
    local player_state = all_states[player_index]

    if not player_state then
        player_state = {
            bot_entity = nil,
            visuals = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                mapped_entities = {}
            },
            bot_enabled = false,
            bot_mode = "follow",
            last_player_position = nil,
            last_player_side_offset_x = -BOT_SIDE_OFFSET_DISTANCE,

            -- Wander mode fields.
            wander_target_position = nil,

            -- Survey mode fields.
            survey_mapped_entities = {}
        }

        all_states[player_index] = player_state
    else
        -- Backfill and normalise existing state.
        player_state.bot_entity = player_state.bot_entity or nil

        player_state.visuals = player_state.visuals or {}
        player_state.visuals.bot_highlight = player_state.visuals.bot_highlight or nil
        player_state.visuals.lines = player_state.visuals.lines or nil
        player_state.visuals.radius_circle = player_state.visuals.radius_circle or nil
        player_state.visuals.mapped_entities = player_state.visuals.mapped_entities or {}

        if player_state.bot_enabled == nil then
            player_state.bot_enabled = false
        end

        player_state.bot_mode = player_state.bot_mode or "follow"
        player_state.last_player_position = player_state.last_player_position or nil
        player_state.last_player_side_offset_x = player_state.last_player_side_offset_x or -BOT_SIDE_OFFSET_DISTANCE

        player_state.wander_target_position = player_state.wander_target_position or nil
        player_state.survey_mapped_entities = player_state.survey_mapped_entities or {}
    end

    return player_state
end

----------------------------------------------------------------------
-- BOT MODE MANAGEMENT
----------------------------------------------------------------------

-- set_player_bot_mode(player, player_state, new_mode)
--
-- Purpose:
--   Safely updates the behavior mode for a player's bot.
local function set_player_bot_mode(player, player_state, new_mode)
    if not player_state then
        return
    end

    if not BOT_MODE_INDEX[new_mode] then
        new_mode = "follow"
    end

    local old_mode = player_state.bot_mode or "follow"
    if old_mode == new_mode then
        return
    end

    player_state.bot_mode = new_mode
    print_bot_message(player, "green", "mode set to %s", new_mode)
end

----------------------------------------------------------------------
-- BOT LIFECYCLE: DESTROY BOT
----------------------------------------------------------------------

-- destroy_player_bot(player, silent)
--
-- Purpose:
--   Destroys the bot entity for the given player, clears all bot
--   visuals and state flags.
local function destroy_player_bot(player, silent)
    local player_state = get_player_state(player.index)

    local bot_entity = player_state.bot_entity
    if bot_entity and bot_entity.valid then
        bot_entity.destroy()
    end

    visuals.clear_all(player_state)

    player_state.bot_entity = nil
    player_state.bot_enabled = false

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

----------------------------------------------------------------------
-- BOT LIFECYCLE: CREATE BOT
----------------------------------------------------------------------

-- create_player_bot(player)
--
-- Purpose:
--   Creates (or reuses) a bot entity for the given player and updates
--   the per-player state.
--
-- Returns:
--   bot_entity : LuaEntity or nil
local function create_player_bot(player)
    local player_state = get_player_state(player.index)

    if player_state.bot_entity and not player_state.bot_entity.valid then
        player_state.bot_entity = nil
    end

    if player_state.bot_entity and player_state.bot_entity.valid then
        return player_state.bot_entity
    end

    local surface = player.surface
    local player_pos = player.position

    local bot_entity = surface.create_entity {
        name = "mekatrol-game-play-bot",
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
-- HOTKEY HANDLERS
----------------------------------------------------------------------

-- on_toggle_bot(event)
--
-- Purpose:
--   Responds to the "mekatrol-game-play-bot-toggle" hotkey:
--     * If the player has a bot -> destroy it.
--     * Otherwise -> create a new bot.
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

-- on_cycle_bot_mode(event)
--
-- Purpose:
--   Handler for "mekatrol-game-play-bot-next-mode".
--   Advances the mode:
--       follow -> wander -> survey -> follow -> ...
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

----------------------------------------------------------------------
-- POSITION RESOLUTION / MOVEMENT HELPERS
----------------------------------------------------------------------

-- resolve_target_position(target)
--
-- Purpose:
--   Coerces various target formats into a simple {x, y} position table.
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
        local desc = tostring(target)
        return nil, desc
    end
end

-- move_bot_towards(player, bot_entity, target)
--
-- Purpose:
--   Moves the bot one step towards a target position or entity.
local function move_bot_towards(player, bot_entity, target)
    if not (bot_entity and bot_entity.valid and target) then
        return
    end

    local target_pos, error_desc = resolve_target_position(target)
    if not target_pos then
        print_bot_message(player, "red", "invalid target: %s", error_desc or "<unknown>")
        return
    end

    local bot_pos = bot_entity.position
    local dx = target_pos.x - bot_pos.x
    local dy = target_pos.y - bot_pos.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)

    if dist <= BOT_STEP_DISTANCE then
        bot_entity.teleport({
            x = target_pos.x,
            y = target_pos.y
        })
        return
    end

    local nx = dx / dist
    local ny = dy / dist

    bot_entity.teleport({
        x = bot_pos.x + nx * BOT_STEP_DISTANCE,
        y = bot_pos.y + ny * BOT_STEP_DISTANCE
    })
end

----------------------------------------------------------------------
-- FOLLOW MODE
----------------------------------------------------------------------

-- follow_player(player, player_state, bot_entity)
--
-- Purpose:
--   Keeps the bot near the player, choosing which side (left/right)
--   to follow on based on movement direction.
local function follow_player(player, player_state, bot_entity)
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
        local epsilon = 0.1

        if dx_move < -epsilon then
            moving_left = true
        elseif dx_move > epsilon then
            moving_right = true
        end
    end

    player_state.last_player_position = {
        x = player_pos.x,
        y = player_pos.y
    }

    ------------------------------------------------------------------
    -- 2. Choose side offset X.
    ------------------------------------------------------------------
    local side_offset_x = player_state.last_player_side_offset_x or -BOT_SIDE_OFFSET_DISTANCE

    if moving_left and side_offset_x ~= BOT_SIDE_OFFSET_DISTANCE then
        side_offset_x = BOT_SIDE_OFFSET_DISTANCE
    elseif moving_right and side_offset_x ~= -BOT_SIDE_OFFSET_DISTANCE then
        side_offset_x = -BOT_SIDE_OFFSET_DISTANCE
    end

    player_state.last_player_side_offset_x = side_offset_x

    ------------------------------------------------------------------
    -- 3. Check follow distance.
    ------------------------------------------------------------------
    local dx = player_pos.x - bot_pos.x
    local dy = player_pos.y - bot_pos.y
    local dist_sq = dx * dx + dy * dy
    local desired_sq = BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE

    if dist_sq <= desired_sq then
        return
    end

    ------------------------------------------------------------------
    -- 4. Build target position using the chosen side offset.
    ------------------------------------------------------------------
    local offset_y = -2.0

    local target_pos = {
        x = player_pos.x + side_offset_x,
        y = player_pos.y + offset_y
    }

    move_bot_towards(player, bot_entity, target_pos)
end

----------------------------------------------------------------------
-- WANDER TARGET PICKER
----------------------------------------------------------------------

local function pick_new_wander_target(bot_pos)
    -- Choose a random direction and a distance in [min_dist, max_dist]
    local angle = math.random() * 2 * math.pi

    local min_dist = WANDER_STEP_DISTANCE * 0.4
    local max_dist = WANDER_STEP_DISTANCE

    local dist = min_dist + (max_dist - min_dist) * math.random()

    return {
        x = bot_pos.x + math.cos(angle) * dist,
        y = bot_pos.y + math.sin(angle) * dist
    }
end

----------------------------------------------------------------------
-- WANDER MODE
----------------------------------------------------------------------

-- wander_bot(player, player_state, bot_entity)
--
-- Purpose:
--   Implements "wander" behavior, picking random nearby targets and
--   scanning for entities to trigger survey mode.
local function wander_bot(player, player_state, bot_entity)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    local surface = bot_entity.surface
    local bot_pos = bot_entity.position

    ------------------------------------------------------------------
    -- 1. Ensure we have a wander target; pick one if not.
    ------------------------------------------------------------------
    local target = player_state.wander_target_position
    if not target then
        target = pick_new_wander_target(bot_pos)
        player_state.wander_target_position = target
    end

    ------------------------------------------------------------------
    -- 2. Step towards the target.
    ------------------------------------------------------------------
    move_bot_towards(player, bot_entity, target)

    local new_pos = bot_entity.position
    local ddx = target.x - new_pos.x
    local ddy = target.y - new_pos.y
    local dist_sq = ddx * ddx + ddy * ddy
    if dist_sq <= (BOT_STEP_DISTANCE * BOT_STEP_DISTANCE) then
        -- Once we reach the target, clear it so a new one will be
        -- chosen next tick.
        player_state.wander_target_position = nil
    end

    ------------------------------------------------------------------
    -- 3. Detection: check for nearby entities to trigger survey mode.
    ------------------------------------------------------------------
    local nearby = surface.find_entities_filtered {
        position = new_pos,
        radius = WANDER_DETECTION_RADIUS
    }

    local player_character = player.character
    local found_any = false

    for _, entity in ipairs(nearby) do
        if entity.valid and entity ~= bot_entity and (not player_character or entity ~= player_character) then
            found_any = true
            break
        end
    end

    if found_any then
        -- Clear wander target; survey will drive behaviour now.
        player_state.wander_target_position = nil
        set_player_bot_mode(player, player_state, "survey")
    end
end

----------------------------------------------------------------------
-- MAPPING HELPERS
----------------------------------------------------------------------

-- is_static_mappable(entity)
--
-- Purpose:
--   Returns true if an entity should be considered for static mapping.
local function is_static_mappable(entity)
    if not (entity and entity.valid) then
        return false
    end

    if NON_STATIC_TYPES[entity.type] then
        return false
    end

    return true
end

-- get_entity_key(entity)
--
-- Purpose:
--   Returns a stable key for an entity used as a map index.
local function get_entity_key(entity)
    if entity.unit_number then
        return entity.unit_number
    end

    local p = entity.position
    return entity.name .. "@" .. p.x .. "," .. p.y .. "#" .. entity.surface.index
end

-- upsert_mapped_entity(player, player_state, entity, tick)
--
-- Purpose:
--   Inserts or updates a mapped-entity record for survey mode and
--   draws a highlight box when first discovered.
local function upsert_mapped_entity(player, player_state, entity, tick)
    local key = get_entity_key(entity)
    if not key then
        return false
    end

    local mapped_entities = player_state.survey_mapped_entities
    local info = mapped_entities[key]
    local is_new = false

    if not info then
        is_new = true

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
        mapped_entities[key] = info

        -- Draw the highlight only when first discovered.
        local box_id = visuals.draw_mapped_entity_box(player, player_state, entity)
        player_state.visuals.mapped_entities[key] = box_id
    else
        -- Already known: just update position/last_seen.
        info.position.x = entity.position.x
        info.position.y = entity.position.y
        info.last_seen_tick = tick
    end

    -- Caller decides what to do with is_new.
    return is_new
end

----------------------------------------------------------------------
-- SURVEY MODE
----------------------------------------------------------------------

-- survey_location(player, player_state, bot_entity, tick)
--
-- Purpose:
--   Implements survey mode: scans SURVEY_RADIUS around the bot and
--   records mappable entities.
local function survey_location(player, player_state, bot_entity, tick)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    local found = bot_entity.surface.find_entities_filtered {
        position = bot_entity.position,
        radius = SURVEY_RADIUS
    }

    local found_new = false

    for _, entity in ipairs(found) do
        if entity ~= bot_entity and entity ~= player and is_static_mappable(entity) then
            local is_new = upsert_mapped_entity(player, player_state, entity, tick)
            if is_new then
                found_new = true
            end
        end
    end

    -- If we are in survey mode and did not discover anything new in
    -- this pass, return to follow mode.
    if not found_new then
        set_player_bot_mode(player, player_state, "follow")
    end
end

----------------------------------------------------------------------
-- PER-TICK BOT UPDATE
----------------------------------------------------------------------

-- update_bot_for_player(player, player_state, tick)
--
-- Purpose:
--   Performs all per-tick logic for a single player's bot:
--     * Clear and update visuals.
--     * Run behavior for the current mode.
local function update_bot_for_player(player, player_state, tick)
    local bot_entity = player_state.bot_entity
    if not (bot_entity and bot_entity.valid) then
        return
    end

    -- Clear existing lines from previous tick before drawing new ones.
    visuals.clear_lines(player_state)

    -- Update highlight.
    player_state.bot_entity = bot_entity
    visuals.draw_bot_highlight(player, player_state)

    local radius = nil
    local radius_color = nil
    local line_color = nil

    if player_state.bot_mode == "wander" then
        radius = WANDER_DETECTION_RADIUS
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color

    elseif player_state.bot_mode == "survey" then
        radius = SURVEY_RADIUS
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color

    elseif player_state.bot_mode == "follow" then
        line_color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        }
    end

    if radius and radius > 0 then
        visuals.draw_radius_circle(player, player_state, bot_entity, radius, radius_color)
    else
        visuals.clear_radius_circle(player_state)
    end

    if line_color then
        visuals.draw_lines(player, player_state, bot_entity, line_color)
    end

    ------------------------------------------------------------------
    -- Behavior dispatch based on current mode.
    ------------------------------------------------------------------
    if player_state.bot_mode == "follow" then
        follow_player(player, player_state, bot_entity)

    elseif player_state.bot_mode == "wander" then
        wander_bot(player, player_state, bot_entity)

    elseif player_state.bot_mode == "survey" then
        survey_location(player, player_state, bot_entity, tick)
    end
end

----------------------------------------------------------------------
-- EVENT HANDLERS
----------------------------------------------------------------------

-- on_entity_died(event)
--
-- Purpose:
--   When any entity dies, if it is one of our bots, clear state and
--   notify the owning player.
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

-- on_player_removed(event)
--
-- Purpose:
--   Cleans up per-player state when a player is removed from the game.
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

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_bot_mode)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

----------------------------------------------------------------------
-- MAIN TICK HANDLER
--
-- Purpose:
--   Periodically updates the bot for player 1.
--   For multiplayer, extend this to loop over connected players.
----------------------------------------------------------------------

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

    if player_state.bot_enabled and player_state.bot_entity and player_state.bot_entity.valid then
        update_bot_for_player(player, player_state, event.tick)
    end
end)
