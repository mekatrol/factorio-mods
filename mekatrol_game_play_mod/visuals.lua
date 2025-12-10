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
--           lines         = <array of LuaRenderObject or nil>
--       },
--       ...
--   }
--
----------------------------------------------------------------------
local visuals = {}

----------------------------------------------------------------------
-- CLEAR HELPERS
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
--   * This does NOT clear the highlight rectangle. Use
--     visuals.clear_bot_highlight for that.
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
-- FUNCTION: clear_all(player_state)
--
-- PURPOSE:
--   Convenience helper that clears all known render objects belonging
--   to the player's bot visuals (both highlight and lines).
--
-- PARAMETERS:
--   player_state : table
--
-- BEHAVIOR:
--   * Calls clear_lines(player_state).
--   * Calls clear_bot_highlight(player_state).
---------------------------------------------------
function visuals.clear_all(player_state)
    if not player_state then
        return
    end

    visuals.clear_lines(player_state)
    visuals.clear_bot_highlight(player_state)
end

----------------------------------------------------------------------
-- DRAW HELPERS
----------------------------------------------------------------------

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
--         * player_state.bot_entity          — the bot entity.
--         * player_state.visuals.bot_highlight — existing highlight
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
        -- Rectangle color (semi-transparent turquoise/greenish).
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
-- FUNCTION: draw_bot_player_visuals(player, bot_entity, player_state)
--
-- PURPOSE:
--   Draws a line between the player and the bot to visually indicate
--   their relationship. The line color depends on the bot mode.
--
--   This function assumes that:
--     * The highlight rectangle is handled separately (e.g. via
--       visuals.draw_bot_highlight in control.lua).
--     * player_state.visuals exists and is used to store render
--       objects under visuals.lines.
--
-- PARAMETERS:
--   player      : LuaPlayer
--       The player who will see the line.
--
--   bot_entity  : LuaEntity
--       The bot entity to connect to the player.
--
--   player_state : table
--       The per-player state containing:
--         * player_state.bot_mode         — string indicating the
--           current behavior mode.
--         * player_state.visuals.lines    — array of LuaRenderObject
--           or nil, tracking previously drawn lines.
--
-- BEHAVIOR:
--   1. Validates player and bot.
--   2. Ensures player_state.visuals and player_state.visuals.lines
--      exist for storing line render objects.
--   3. Chooses a line color based on bot_mode:
--        - "wander" → red-ish, clearly visible.
--        - "follow" → grey.
--        - anything else → no line.
--   4. Draws a line from the player's position to the bot's position
--      (optionally offset slightly).
--   5. Stores the created render object in player_state.visuals.lines.
--
-- NOTES:
--   * The caller is responsible for clearing lines between ticks by
--     calling visuals.clear_lines(player_state). This prevents old
--     lines from accumulating.
---------------------------------------------------
function visuals.draw_bot_player_visuals(player, bot_entity, player_state)
    -- Validate player and bot first.
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
    -- 3. Choose line color based on bot mode
    ------------------------------------------------------------------
    local line_color = nil
    if player_state.bot_mode == "wander" then
        -- Wander mode: a more striking red-ish color.
        line_color = {
            r = 0.5,
            g = 0.1,
            b = 0.1,
            a = 0.7
        }
    elseif player_state.bot_mode == "follow" then
        -- Follow mode: a softer grey.
        line_color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        }
    else
        -- Unknown or unsupported mode: do not draw a line.
        line_color = nil
    end

    if not line_color then
        return
    end

    ------------------------------------------------------------------
    -- 4. Draw the line from the player to the bot
    ------------------------------------------------------------------
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

----------------------------------------------------------------------
-- Return the module table.
----------------------------------------------------------------------
return visuals
