----------------------------------------------------------------------
-- visuals.lua
--
-- Purpose:
--   This module provides helper functions for drawing and managing a
--   visual highlight around the player's bot entity using Factorio’s
--   rendering API (Factorio 2.x).
--
--   Highlights are implemented as rectangles drawn on the world
--   surface. Each highlight is stored in the player's persistent state
--   (`visuals.bot_highlight`) and updated or destroyed depending on the
--   bot's position or lifecycle.
--
--   This file intentionally does NOT perform entity logic or storage
--   management; it focuses strictly on rendering behavior.
----------------------------------------------------------------------
local visuals = {}

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
--   * Calling this before redrawing ensures old rectangles do not
--     remain on screen.
---------------------------------------------------
function visuals.clear_bot_highlight(player_state)
    -- If a highlight exists and the LuaRenderObject is still alive:
    if player_state.visuals.bot_highlight and player_state.visuals.bot_highlight.valid then
        -- Destroy it to remove the rectangle from the world.
        player_state.visuals.bot_highlight:destroy()
    end

    -- Ensure reference is cleared even if it wasn't valid.
    player_state.visuals.bot_highlight = nil
end

function visuals.clear_lines(player_state)
    if player_state.visuals.lines then
        for _, obj in pairs(player_state.visuals.lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        player_state.visuals.lines = nil
    end
end

function visuals.draw_bot_player_visuals(player, bot, player_state)
    -- Validate player and bot first.
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local y_offset = 0

    local bot_pos = bot.position
    local to_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    -- Ensure visuals + lines tables exist.
    player_state.visuals = player_state.visuals or {}
    player_state.visuals.lines = player_state.visuals.lines or {}

    -- Choose line color based on bot mode:
    --   * "wander": red-ish, visible
    --   * "follow": grey
    --   * anything else: no line
    local line_color
    if player_state.bot_mode == "wander" then
        line_color = {
            r = 0.5,
            g = 0.1,
            b = 0.1,
            a = 0.7
        } -- red-ish
    elseif player_state.bot_mode == "follow" then
        line_color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        } -- grey
    else
        line_color = nil
    end

    if line_color then
        local line = rendering.draw_line {
            color = line_color,
            width = 1,
            from = player.position,
            to = to_pos,
            surface = bot.surface,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player} -- only this player sees the line
        }

        player_state.visuals.lines[#player_state.visuals.lines + 1] = line
    end
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
--         * player_state.entity            — the bot entity.
--         * player_state.visuals.bot_highlight — existing highlight or nil.
--
-- BEHAVIOR:
--   1. If the bot does not exist or is invalid, the function exits.
--   2. Computes a rectangular bounding area around the bot.
--   3. If an existing highlight exists:
--        * If still valid, its coordinates are updated in-place.
--        * If invalid, it gets cleared and a new one is created.
--   4. If no highlight exists, a new rectangle is created with
--      rendering.draw_rectangle and stored.
--
-- NOTES:
--   * "draw_on_ground = true" makes the rectangle appear below entities.
--   * "only_in_alt_mode = false" makes it visible at all times.
--   * "players = {player}" ensures only this player sees the highlight.
--   * The highlight stays positioned by updating left_top/right_bottom.
---------------------------------------------------
function visuals.draw_bot_highlight(player, player_state)

    ------------------------------------------------------------------
    -- 1. Validate bot existence
    ------------------------------------------------------------------
    local bot = player_state.entity
    if not (bot and bot.valid) then
        -- No valid bot to draw around; do nothing.
        return
    end

    ------------------------------------------------------------------
    -- 2. Compute rectangle coordinates
    ------------------------------------------------------------------
    -- Size controls how large the highlight appears around the bot.
    local size = 0.6

    -- Bot world position.
    local pos = bot.position

    -- Horizontal center x-coordinate and baseline y-coordinate.
    local cx = pos.x
    local ui_y = pos.y

    -- Compute top-left and bottom-right corners of the rectangle.
    local left_top = {cx - size, ui_y - size * 1.5}
    local right_bottom = {cx + size, ui_y + size}

    -- Do nothing if visuals not defined
    if not player_state.visuals then
        return
    end

    ------------------------------------------------------------------
    -- 3. Update existing highlight (if it exists)
    ------------------------------------------------------------------
    if player_state.visuals.bot_highlight then
        local obj = player_state.visuals.bot_highlight

        if obj and obj.valid then
            -- A valid rectangle already exists; update its geometry
            -- so it tracks the bot's new position.
            obj.left_top = left_top
            obj.right_bottom = right_bottom
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
        surface = bot.surface,

        -- Draw it on the ground layer.
        draw_on_ground = true,

        -- Always visible (not limited to Alt-mode).
        only_in_alt_mode = false,

        -- Only the specified player sees this highlight.
        players = {player}
    }
end

----------------------------------------------------------------------
-- “clear everything” helper:
----------------------------------------------------------------------
function visuals.clear_all(player_state)
    if not player_state then
        return
    end

    visuals.clear_lines(player_state)
    visuals.clear_bot_highlight(player_state)
end

----------------------------------------------------------------------
-- Return the module table.
----------------------------------------------------------------------
return visuals
