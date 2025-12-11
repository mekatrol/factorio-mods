----------------------------------------------------------------------
-- visuals.lua
--
-- Purpose:
--   This module provides helper functions for drawing and managing
--   visual overlays around the player's bot entity using Factorio’s
--   rendering API (Factorio 2.x).
--
--   The visuals implemented here are:
--     * A rectangular highlight around the bot.
--     * An optional line between the player and the bot whose color
--       depends on the bot's current mode.
--     * An optional radius circle around the bot (e.g. detection radius).
--
--   All render objects are stored in the per-player state under
--   player_state.visuals and must be explicitly destroyed when no
--   longer needed. This module intentionally does NOT perform any
--   game logic or persistent storage configuration; it only operates
--   on the data it is given.
--
-- Expected state layout (as used by control.lua):
--
--   player_state = {
--       bot_entity = <LuaEntity or nil>,
--       bot_mode   = <string> or nil, -- e.g. "follow", "wander"
--       visuals    = {
--           bot_highlight = <LuaRenderObject or nil>,
--           lines         = <array of LuaRenderObject or nil>,
--           radius_circle = <LuaRenderObject or nil>
--       },
--       ...
--   }
--
----------------------------------------------------------------------
-- Must match "name" in info.json
local MOD_NAME = "mekatrol_game_play_mod"

---------------------------------------------------
-- MODULE TABLE
---------------------------------------------------
local visuals = {}

----------------------------------------------------------------------
-- CLEAR HELPERS
--
-- Purpose:
--   Centralized helpers for destroying all render objects owned by
--   this module. Rendering objects are not cleaned up automatically
--   by the game and must be explicitly destroyed.
----------------------------------------------------------------------

---------------------------------------------------
-- FUNCTION: clear_bot_highlight(player_state)
--
-- PURPOSE:
--   Removes any existing highlight rectangle for the player's bot.
--
-- PARAMETERS:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visuals.bot_highlight — a LuaRenderObject or nil.
--
-- BEHAVIOR:
--   * If a highlight exists and is still valid, it is explicitly
--     destroyed via :destroy() to clean up the rendering object.
--   * The reference is then cleared (set to nil) so the next rendering
--     update knows that no highlight is currently active.
--
-- NOTES:
--   * Rendering objects are NOT removed automatically when entities
--     disappear; they must always be explicitly destroyed.
--   * This function is safe to call even if no highlight exists.
---------------------------------------------------
function visuals.clear_bot_highlight(player_state)
    if not (player_state and player_state.visuals) then
        return
    end

    local highlight = player_state.visuals.bot_highlight
    if highlight and highlight.valid then
        highlight:destroy()
    end

    player_state.visuals.bot_highlight = nil
end

---------------------------------------------------
-- FUNCTION: clear_lines(player_state)
--
-- PURPOSE:
--   Destroys and clears all line render objects associated with the
--   player's bot visuals.
--
-- PARAMETERS:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visuals.lines — an array of LuaRenderObject
--           or nil.
--
-- BEHAVIOR:
--   * Iterates over all stored line objects.
--   * For each valid render object, calls :destroy().
--   * Clears the array reference (sets it to nil) after cleanup.
--
-- NOTES:
--   * This does NOT clear the highlight rectangle or radius circle.
--     Use visuals.clear_bot_highlight / visuals.clear_radius_circle
--     for those.
---------------------------------------------------
function visuals.clear_lines(player_state)
    if not (player_state and player_state.visuals) then
        return
    end

    local lines = player_state.visuals.lines
    if not lines then
        return
    end

    for _, line_obj in pairs(lines) do
        if line_obj and line_obj.valid then
            line_obj:destroy()
        end
    end

    player_state.visuals.lines = nil
end

---------------------------------------------------
-- FUNCTION: clear_radius_circle(player_state)
--
-- PURPOSE:
--   Destroys and clears the radius circle render object (if any)
--   associated with the player's bot visuals.
--
-- PARAMETERS:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visuals.radius_circle — a LuaRenderObject or nil.
--
-- BEHAVIOR:
--   * If a radius circle exists and is valid, calls :destroy().
--   * Clears the reference (sets it to nil) afterwards.
--
-- NOTES:
--   * Safe to call when no radius circle exists or when visuals is nil.
---------------------------------------------------
function visuals.clear_radius_circle(player_state)
    if not (player_state and player_state.visuals) then
        return
    end

    local circle = player_state.visuals.radius_circle
    if circle and circle.valid then
        circle:destroy()
    end

    player_state.visuals.radius_circle = nil
end

function visuals.clear_mapped_entities(player_state)
    ---------------------------------------------------------------
    -- 1. Wipe ALL rendering objects created by this mod
    ----------------------------------------------------------------
    pcall(rendering.clear, MOD_NAME)

    ----------------------------------------------------------------
    -- 2. Reset per-player mapping state
    ----------------------------------------------------------------
    player_state.visuals.mapped_entities = {}
end

---------------------------------------------------
-- FUNCTION: clear_all(player_state)
--
-- PURPOSE:
--   Convenience helper that clears all known render objects belonging
--   to the player's bot visuals (highlight, lines, radius circle).
--
-- PARAMETERS:
--   player_state : table
--
-- BEHAVIOR:
--   * Calls clear_lines(player_state).
--   * Calls clear_bot_highlight(player_state).
--   * Calls clear_radius_circle(player_state).
---------------------------------------------------
function visuals.clear_all(player_state)
    if not player_state then
        return
    end

    visuals.clear_lines(player_state)
    visuals.clear_bot_highlight(player_state)
    visuals.clear_radius_circle(player_state)
    visuals.clear_mapped_entities(player_state)
end

----------------------------------------------------------------------
-- DRAW HELPERS
--
-- Purpose:
--   Functions that create or update render objects to visualize the
--   bot and its relationship to the player. All functions assume the
--   caller will manage per-tick lifecycle (e.g. clearing lines before
--   redrawing).
----------------------------------------------------------------------

---------------------------------------------------
-- FUNCTION: draw_radius_circle(player, player_state, bot, radius)
--
-- PURPOSE:
--   Draws a circle around the bot to visualize a radius (for example,
--   a detection or survey radius used in game logic).
--
-- PARAMETERS:
--   player       : LuaPlayer
--       The player who will see this circle.
--
--   player_state : table
--       The per-player state whose visuals table will track the circle.
--
--   bot          : LuaEntity
--       The bot entity at the center of the circle.
--
--   radius       : number
--       Circle radius in tiles. If nil or <= 0, no circle is drawn.
--   color        : table
--       Color to render the radius.
--
-- BEHAVIOR:
--   * Clears any existing radius circle via visuals.clear_radius_circle.
--   * If bot is valid and radius is positive, draws a new circle
--     anchored to the bot entity.
--   * Stores the render reference in player_state.visuals.radius_circle.
---------------------------------------------------
function visuals.draw_radius_circle(player, player_state, bot, radius, color)
    if not (player_state and player_state.visuals) then
        return
    end

    -- Destroy old circle if it exists.
    visuals.clear_radius_circle(player_state)

    if not (bot and bot.valid) then
        return
    end

    if not radius or radius <= 0 then
        -- Caller did not request a valid radius; do not draw anything.
        return
    end

    -- Draw a new circle, anchored to the bot so it follows movement.
    local id = rendering.draw_circle {
        color = color,
        radius = radius,
        width = 1,
        filled = false,
        target = bot, -- anchor so it follows the bot
        surface = bot.surface,
        players = {player},
        draw_on_ground = true
    }

    -- Store the numeric id so we can destroy it later.
    player_state.visuals.radius_circle = id
end

---------------------------------------------------
-- FUNCTION: draw_bot_highlight(player, player_state)
--
-- PURPOSE:
--   Draws (or updates) a visual rectangle around the player's bot in
--   the world. This helps indicate its position visually, especially
--   when the entity is not selectable or is invisible.
--
-- PARAMETERS:
--   player : LuaPlayer
--       The player who will see the highlight. This is passed to the
--       rendering API so only this player sees the effect.
--
--   player_state : table
--       The per-player state containing:
--         * player_state.bot_entity             — the bot entity.
--         * player_state.visuals.bot_highlight  — existing highlight
--           render object or nil.
--
-- BEHAVIOR:
--   1. Validates that a bot entity exists and is valid.
--   2. Computes a rectangular bounding area around the bot.
--   3. If an existing highlight exists:
--        * If still valid, its coordinates are updated in-place.
--        * If invalid, the reference is cleared and a new rectangle
--          is created.
--   4. If no highlight exists, a new rectangle is created with
--      rendering.draw_rectangle and stored.
--
-- VISUAL DETAILS:
--   * "draw_on_ground = true" makes the rectangle appear below entities.
--   * "only_in_alt_mode = false" makes it visible at all times.
--   * "players = {player}" ensures only this player sees the highlight.
---------------------------------------------------
function visuals.draw_bot_highlight(player, player_state)
    if not (player and player.valid and player_state and player_state.visuals) then
        return
    end

    ------------------------------------------------------------------
    -- 1. Validate bot existence
    ------------------------------------------------------------------
    local bot_entity = player_state.bot_entity
    if not (bot_entity and bot_entity.valid) then
        -- No valid bot to draw around; do nothing.
        return
    end

    ------------------------------------------------------------------
    -- 2. Compute rectangle coordinates
    ------------------------------------------------------------------
    -- Size controls how large the highlight appears around the bot.
    local size = 0.6

    -- Bot world position.
    local pos = bot_entity.position

    -- Horizontal center x-coordinate and baseline y-coordinate.
    local cx = pos.x
    local base_y = pos.y

    -- Compute top-left and bottom-right corners of the rectangle.
    local left_top = {cx - size, base_y - size * 1.5}
    local right_bottom = {cx + size, base_y + size}

    ------------------------------------------------------------------
    -- 3. Update existing highlight (if it exists)
    ------------------------------------------------------------------
    local existing = player_state.visuals.bot_highlight
    if existing then
        if existing.valid then
            -- A valid rectangle already exists; update its geometry
            -- so it tracks the bot's new position.
            existing.left_top = left_top
            existing.right_bottom = right_bottom
            return
        else
            -- The old rendering object reference is invalid, so clear it.
            player_state.visuals.bot_highlight = nil
        end
    end

    ------------------------------------------------------------------
    -- 4. Create a new highlight rectangle for this bot
    ------------------------------------------------------------------
    player_state.visuals.bot_highlight = rendering.draw_rectangle {
        -- Rectangle color (semi-transparent dark greenish).
        color = {
            r = 0,
            g = 0.2,
            b = 0.2,
            a = 0.1
        },

        -- Draw only the outline (not filled).
        filled = false,

        -- Line thickness of the rectangle.
        width = 2,

        -- Coordinates of the rectangle.
        left_top = left_top,
        right_bottom = right_bottom,

        -- Draw on the bot’s surface layer.
        surface = bot_entity.surface,

        -- Draw it on the ground layer.
        draw_on_ground = true,

        -- Always visible (not limited to Alt-mode).
        only_in_alt_mode = false,

        -- Only the specified player sees this highlight.
        players = {player}
    }
end

---------------------------------------------------
-- FUNCTION: draw_lines(player, bot_entity, player_state, line_color)
--
-- PURPOSE:
--   Draws visual elements that connect the player to their bot:
--     * Ensures the bot highlight rectangle is up to date.
--     * Draws a line between the player and the bot whose color
--       depends on the bot mode.
--
-- PARAMETERS:
--   player       : LuaPlayer
--       The player who will see the visuals.
--
--   bot_entity   : LuaEntity
--       The bot entity to visualize.
--
--   player_state : table
--       The per-player state containing:
--         * player_state.bot_mode        — string indicating the
--           current behavior mode (e.g. "follow", "wander").
--         * player_state.visuals.lines   — array of LuaRenderObject
--           or nil, tracking previously drawn lines.
--
--   line_color   : table|nil
--       Optional line color to draw line. If nil line is not drawn..
--
-- BEHAVIOR:
--   1. Validates player, bot, and state.
--   2. Ensures player_state.visuals and visuals.lines exist.
--   3. Draws/updates the bot highlight rectangle.
--   5. Draws a line from the player's position to the bot's position.
--   6. Stores the created render object in player_state.visuals.lines.
--
-- NOTES:
--   * The caller is responsible for clearing lines between ticks by
--     calling visuals.clear_lines(player_state). This prevents old
--     lines from accumulating.
---------------------------------------------------
function visuals.draw_lines(player, bot_entity, player_state, line_color)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    if not player_state then
        return
    end

    ------------------------------------------------------------------
    -- 1. Ensure visuals containers exist
    ------------------------------------------------------------------
    player_state.visuals = player_state.visuals or {}
    player_state.visuals.lines = player_state.visuals.lines or {}

    ------------------------------------------------------------------
    -- 2. Compute target position for the line end
    ------------------------------------------------------------------
    local y_offset = 0

    local bot_pos = bot_entity.position
    local line_end_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    ------------------------------------------------------------------
    -- 3. Draw the line from the player to the bot
    ------------------------------------------------------------------
    if line_color then
        local line = rendering.draw_line {
            color = line_color,
            width = 1,
            from = player.position,
            to = line_end_pos,
            surface = bot_entity.surface,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player} -- only this player sees the line
        }
        -- Track this render object for later cleanup.
        player_state.visuals.lines[#player_state.visuals.lines + 1] = line
    end
end

---------------------------------------------------
-- Green box around mapped entities
---------------------------------------------------
function visuals.add_mapped_entity_box(player, player_state, bot_entity)
    if not (bot_entity and bot_entity.valid) then
        return nil
    end

    local box = bot_entity.selection_box or bot_entity.bounding_box
    if not box then
        return nil
    end

    local id = rendering.draw_rectangle {
        color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.35
        },
        width = 1,
        filled = false,
        left_top = box.left_top,
        right_bottom = box.right_bottom,
        surface = bot_entity.surface,
        players = {player},
        draw_on_ground = false
    }

    return id
end

----------------------------------------------------------------------
-- MODULE RETURN
--
-- Expose the visuals API for use by control.lua and other modules.
----------------------------------------------------------------------
return visuals
