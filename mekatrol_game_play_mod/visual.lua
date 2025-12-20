----------------------------------------------------------------------
-- visual.lua
--
-- Purpose:
--   This module provides helper functions for drawing and managing
--   visual overlays around the player's bot entity using Factorio’s
--   rendering API (Factorio 2.x).
--
--   The visual implemented here are:
--     * A rectangular highlight around the bot.
--     * An optional line between the player and the bot whose color
--       depends on the bot's current mode.
--     * An optional radius circle around the bot (e.g. detection radius).
--     * Optional boxes around mapped entities.
--
--   All render objects are stored in the per-player state under
--   player_state.visual and must be explicitly destroyed when no
--   longer needed. This module intentionally does NOT perform any
--   game logic or persistent storage configuration; it only operates
--   on the data it is given.
--
-- Expected state layout (as used by control.lua):
--
--   player_state = {
--       bot_entity = <LuaEntity or nil>,
--       bot_mode   = <string> or nil, -- e.g. "follow", "wander"
--       visual    = {
--           bot_highlight   = <LuaRenderObject or nil>,
--           lines           = <array of LuaRenderObject or nil>,
--           radius_circle   = <LuaRenderObject or nil>,
--           mapped_entities = <table<string, LuaRenderObject or nil>>
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
local visual = {}

local function ensure_lines_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.lines = ps.visual.lines or {}
end

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
-- Purpose:
--   Removes any existing highlight rectangle for the player's bot.
--
-- Parameters:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visual.bot_highlight — a LuaRenderObject or nil.
--
-- Behavior:
--   * If a highlight exists and is still valid, it is explicitly
--     destroyed via :destroy() to clean up the rendering object.
--   * The reference is then cleared (set to nil).
--
-- Notes:
--   * Rendering objects are NOT removed automatically when entities
--     disappear; they must always be explicitly destroyed.
--   * This function is safe to call even if no highlight exists.
---------------------------------------------------
function visual.clear_bot_highlight(player_state)
    if not (player_state and player_state.visual) then
        return
    end

    local highlight = player_state.visual.bot_highlight
    if highlight and highlight.valid then
        highlight:destroy()
    end

    player_state.visual.bot_highlight = nil
end

function visual.clear_survey_frontier(player_state)
    if not (player_state and player_state.visual) then
        return
    end

    local frontier = player_state.visual.survey_frontier
    if not frontier then
        return
    end

    for _, frontier_obj in pairs(frontier) do
        if frontier_obj and frontier_obj.valid then
            frontier_obj:destroy()
        end
    end

    player_state.visual.survey_frontier = {}
end

function visual.clear_survey_done(player_state)
    if not (player_state and player_state.visual) then
        return
    end

    local done = player_state.visual.survey_done
    if not done then
        return
    end

    for _, done_obj in pairs(done) do
        if done_obj and done_obj.valid then
            done_obj:destroy()
        end
    end

    player_state.visual.survey_done = {}
end

---------------------------------------------------
-- FUNCTION: clear_lines(player_state)
--
-- Purpose:
--   Destroys and clears all line render objects associated with the
--   player's bot visual.
--
-- Parameters:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visual.lines — an array of LuaRenderObject
--           or nil.
--
-- Behavior:
--   * Iterates over all stored line objects.
--   * For each valid render object, calls :destroy().
--   * Clears the array reference (sets it to nil) after cleanup.
--
-- Notes:
--   * This does NOT clear the highlight rectangle or radius circle.
--     Use visual.clear_bot_highlight / visual.clear_radius_circle
--     for those.
---------------------------------------------------
function visual.clear_lines(player_state)
    if not (player_state and player_state.visual) then
        return
    end

    local lines = player_state.visual.lines
    if not lines then
        return
    end

    for _, line_obj in pairs(lines) do
        if line_obj and line_obj.valid then
            line_obj:destroy()
        end
    end

    player_state.visual.lines = {}
end

---------------------------------------------------
-- FUNCTION: clear_radius_circle(player_state)
--
-- Purpose:
--   Destroys and clears the radius circle render object (if any)
--   associated with the player's bot visual.
--
-- Parameters:
--   player_state : table
--       The per-player state table that contains:
--         * player_state.visual.radius_circle — a LuaRenderObject or nil.
--
-- Behavior:
--   * If a radius circle exists and is valid, calls :destroy().
--   * Clears the reference (sets it to nil) afterwards.
--
-- Notes:
--   * Safe to call when no radius circle exists or when visual is nil.
---------------------------------------------------
function visual.clear_radius_circle(player_state)
    if not (player_state and player_state.visual) then
        return
    end

    local circle = player_state.visual.radius_circle
    if circle and circle.valid then
        circle:destroy()
    end

    player_state.visual.radius_circle = nil
end

---------------------------------------------------
-- FUNCTION: clear_mapped_entities(player_state)
--
-- Purpose:
--   Clears all mapping-related visual and resets the mapped_entities
--   tracking table for the player.
--
-- Parameters:
--   player_state : table
--       The per-player state containing:
--         * player_state.visual.mapped_entities — table of
--           entity-key -> LuaRenderObject id mappings.
--
-- Behavior:
--   * Calls rendering.clear(MOD_NAME) to remove all render objects
--     owned by this mod.
--   * Resets player_state.visual.mapped_entities to an empty table.
--
-- Notes:
--   * This is a coarse clear: it removes all render objects created
--     by this mod, not only mapped-entity boxes for this player.
--   * Intended for full visual reset (e.g. when destroying the bot).
---------------------------------------------------
function visual.clear_mapped_entities(player_state)
    if not player_state then
        return
    end

    if not player_state.visual then
        player_state.visual = {}
    end

    -- Wipe all rendering objects created by this mod.
    pcall(rendering.clear, MOD_NAME)

    -- Reset per-player mapping state.
    player_state.visual.mapped_entities = {}
end

---------------------------------------------------
-- FUNCTION: clear_all(player_state)
--
-- Purpose:
--   Convenience helper that clears all known render objects belonging
--   to the player's bot visual (highlight, lines, radius circle,
--   mapped entities).
--
-- Parameters:
--   player_state : table
--
-- Behavior:
--   * Calls clear_lines(player_state).
--   * Calls clear_bot_highlight(player_state).
--   * Calls clear_radius_circle(player_state).
--   * Calls clear_mapped_entities(player_state).
---------------------------------------------------
function visual.clear_all(player_state)
    if not player_state then
        return
    end

    visual.clear_lines(player_state)
    visual.clear_bot_highlight(player_state)
    visual.clear_radius_circle(player_state)
    visual.clear_mapped_entities(player_state)
    visual.clear_survey_frontier(player_state)
    visual.clear_survey_done(player_state)
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
-- FUNCTION: draw_radius_circle(player, player_state, bot_entity, radius, color)
--
-- Purpose:
--   Draws a circle around the bot to visualize a radius (for example,
--   a detection or survey radius used in game logic).
--
-- Parameters:
--   player       : LuaPlayer
--       The player who will see this circle.
--
--   player_state : table
--       The per-player state whose visual table will track the circle.
--
--   bot_entity   : LuaEntity
--       The bot entity at the center of the circle.
--
--   radius       : number
--       Circle radius in tiles. If nil or <= 0, no circle is drawn.
--
--   color        : table
--       Color to render the radius (RGBA table).
--
-- Behavior:
--   * Clears any existing radius circle via visual.clear_radius_circle.
--   * If bot is valid and radius is positive, draws a new circle
--     anchored to the bot entity.
--   * Stores the render reference in player_state.visual.radius_circle.
---------------------------------------------------
function visual.draw_radius_circle(player, player_state, bot_entity, radius, color)
    if not (player_state and player_state.visual) then
        return
    end

    -- Destroy old circle if it exists.
    visual.clear_radius_circle(player_state)

    if not (bot_entity and bot_entity.valid) then
        return
    end

    if not radius or radius <= 0 then
        -- Caller did not request a valid radius; do not draw anything.
        return
    end

    -- Draw a new circle, anchored to the bot so it follows movement.
    local circle = rendering.draw_circle {
        color = color,
        radius = radius,
        width = 1,
        filled = false,
        target = bot_entity,
        surface = bot_entity.surface,
        players = {player},
        draw_on_ground = true
    }

    -- Store the render object so we can destroy it later.
    player_state.visual.radius_circle = circle
end

---------------------------------------------------
-- FUNCTION: draw_bot_highlight(player, player_state)
--
-- Purpose:
--   Draws (or updates) a visual rectangle around the player's bot in
--   the world. This helps indicate its position visually.
--
-- Parameters:
--   player : LuaPlayer
--       The player who will see the highlight.
--
--   player_state : table
--       The per-player state containing:
--         * player_state.bot_entity             — the bot entity.
--         * player_state.visual.bot_highlight  — existing highlight
--           render object or nil.
--
-- Behavior:
--   1. Validates that a bot entity exists and is valid.
--   2. Computes a rectangular bounding area around the bot.
--   3. If an existing highlight exists:
--        * If still valid, its coordinates are updated in-place.
--        * If invalid, the reference is cleared and a new rectangle
--          is created.
--   4. If no highlight exists, a new rectangle is created with
--      rendering.draw_rectangle and stored.
---------------------------------------------------
function visual.draw_bot_highlight(player, player_state)
    if not (player and player.valid and player_state and player_state.visual) then
        return
    end

    ------------------------------------------------------------------
    -- 1. Validate bot existence
    ------------------------------------------------------------------
    local bot_entity = player_state.bot_entity
    if not (bot_entity and bot_entity.valid) then
        return
    end

    ------------------------------------------------------------------
    -- 2. Compute rectangle coordinates
    ------------------------------------------------------------------
    local size = 0.6
    local pos = bot_entity.position

    local cx = pos.x
    local base_y = pos.y

    local left_top = {cx - size, base_y - size * 1.5}
    local right_bottom = {cx + size, base_y + size}

    ------------------------------------------------------------------
    -- 3. Update existing highlight (if it exists)
    ------------------------------------------------------------------
    local existing = player_state.visual.bot_highlight
    if existing then
        if existing.valid then
            existing.left_top = left_top
            existing.right_bottom = right_bottom
            return
        else
            player_state.visual.bot_highlight = nil
        end
    end

    ------------------------------------------------------------------
    -- 4. Create a new highlight rectangle for this bot
    ------------------------------------------------------------------
    player_state.visual.bot_highlight = rendering.draw_rectangle {
        color = {
            r = 0,
            g = 0.2,
            b = 0.2,
            a = 0.1
        },
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = bot_entity.surface,
        draw_on_ground = true,
        only_in_alt_mode = false,
        players = {player}
    }
end

function visual.draw_line(player, ps, a, b, color, width)
    if not (player and player.valid) then
        return nil
    end

    ensure_lines_table(ps)

    local id = rendering.draw_line {
        surface = player.surface,
        from = {a.x, a.y},
        to = {b.x, b.y},
        color = color or {
            r = 1,
            g = 1,
            b = 1,
            a = 1
        },
        width = width or 2,
        time_to_live = 2 * 60, -- adjust if you want persistent
        players = {player.index},
        draw_on_ground = true
    }

    ps.visual.lines[#ps.visual.lines + 1] = id
    return id
end

---------------------------------------------------
-- FUNCTION: draw_lines(player, player_state, bot_entity, line_color)
--
-- Purpose:
--   Draws visual lines that connect the player to their bot.
--
-- Parameters:
--   player       : LuaPlayer
--       The player who will see the visual.
--
--   player_state : table
--       The per-player state containing:
--         * player_state.visual.lines   — array of LuaRenderObject
--           or nil, tracking previously drawn lines.
--
--   bot_entity   : LuaEntity
--       The bot entity to visualize.
--
--   line_color   : table|nil
--       Optional line color to draw the line. If nil, no line is drawn.
--
-- Behavior:
--   1. Validates player, bot, and state.
--   2. Ensures player_state.visual and visual.lines exist.
--   3. Draws a line from the player's position to the bot's position.
--   4. Stores the created render object in player_state.visual.lines.
--
-- Notes:
--   * The caller is responsible for clearing lines between ticks by
--     calling visual.clear_lines(player_state) to prevent buildup.
---------------------------------------------------
function visual.draw_lines(player, player_state, bot_entity, target_pos, line_color)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    if not player_state then
        return
    end

    ------------------------------------------------------------------
    -- 1. Ensure visual containers exist
    ------------------------------------------------------------------
    player_state.visual = player_state.visual or {}
    player_state.visual.lines = player_state.visual.lines or {}

    ------------------------------------------------------------------
    -- 2. Compute target position for the line end
    ------------------------------------------------------------------
    local y_offset = 0

    local bot_pos = bot_entity.position
    local bot_line_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    ------------------------------------------------------------------
    -- 3. Draw the line from the bot to the target
    ------------------------------------------------------------------
    if target_pos and line_color then
        local line = rendering.draw_line {
            color = line_color,
            width = 1,
            from = bot_line_pos,
            to = target_pos,
            surface = bot_entity.surface,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player}
        }

        player_state.visual.lines[#player_state.visual.lines + 1] = line
    end
end

function visual.draw_survey_frontier(player, player_state, bot_entity)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    if not player_state then
        return
    end

    local survey_frontier = player_state.survey_frontier
    if #survey_frontier == 0 then
        return
    end

    ------------------------------------------------------------------
    -- Draw each frontier location
    ------------------------------------------------------------------
    local color = {
        r = 1.0,
        g = 0.1,
        b = 0.1,
        a = 1.0
    }

    for _, f in ipairs(survey_frontier) do
        local frontier = rendering.draw_circle {
            color = color,
            radius = 0.15,
            filled = true,
            target = f,
            surface = bot_entity.surface,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player}
        }

        player_state.visual.survey_frontier[#player_state.visual.survey_frontier + 1] = frontier
    end
end

function visual.draw_survey_done(player, player_state, bot_entity)
    if not (player and player.valid and bot_entity and bot_entity.valid) then
        return
    end

    if not player_state then
        return
    end

    local survey_done = player_state.survey_done
    if #survey_done == 0 then
        return
    end

    ------------------------------------------------------------------
    -- Draw each survey done location
    ------------------------------------------------------------------
    local color = {
        r = 0.1,
        g = 1.0,
        b = 0.1,
        a = 1.0
    }

    for _, f in ipairs(survey_done) do
        local done = rendering.draw_circle {
            color = color,
            radius = 0.15,
            filled = true,
            target = f,
            surface = bot_entity.surface,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player}
        }

        player_state.visual.survey_done[#player_state.visual.survey_done + 1] = done
    end
end

---------------------------------------------------
-- FUNCTION: draw_mapped_entity_box(player, player_state, entity)
--
-- Purpose:
--   Draws a green box around a mapped entity to mark it visually.
--
-- Parameters:
--   player       : LuaPlayer
--       Player who will see the box.
--
--   player_state : table
--       Per-player state (visual table is not modified here; the
--       caller stores the returned render id/object).
--
--   entity       : LuaEntity
--       Entity to highlight.
--
-- Returns:
--   box_render   : LuaRenderObject|uint|nil
--       Render object (or id) returned by rendering.draw_rectangle,
--       or nil if no box could be drawn.
---------------------------------------------------
function visual.draw_mapped_entity_box(player, player_state, entity)
    if not (entity and entity.valid) then
        return nil
    end

    local box = entity.selection_box or entity.bounding_box
    if not box then
        return nil
    end

    local box_render = rendering.draw_rectangle {
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
        surface = entity.surface,
        players = {player},
        draw_on_ground = false
    }

    return box_render
end

----------------------------------------------------------------------
-- MODULE RETURN
--
-- Expose the visual API for use by control.lua and other modules.
----------------------------------------------------------------------
return visual
