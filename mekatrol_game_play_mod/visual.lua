-- Must match "name" in info.json
local MOD_NAME = "mekatrol_game_play_mod"

---------------------------------------------------
-- MODULE TABLE
---------------------------------------------------
local visual = {}

local config = require("config")
local state = require("state")
local util = require("util")

-- Iterator over all per-bot visual bookkeeping tables.
-- Returns the same iterator tuple as pairs(ps.visual.bot_visuals).
--
-- Usage:
--   for bot_name, bot_visual in iter_bot_visuals(ps) do
--       ...
--   end
local function iter_bot_visuals(ps)
    state.ensure_visuals(ps)
    return pairs(ps.visual.bot_visuals)
end

-- Returns the visual state table for a specific bot role, creating it if needed.
local function get_bot_visual(ps, bot_name)
    state.ensure_visuals(ps)

    local bv = ps.visual[bot_name]
    
    if not bv then
        bv = {
            -- rendering.draw_line ids for the bot path overlay
            lines = {}
        }
        ps.visual.bot_visuals[bot_name] = bv
    end
    bv.lines = bv.lines or {}
    return bv
end

local function ensure_lines_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.lines = ps.visual.lines or {}
end

local function ensure_entity_groups_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.entity_groups = ps.visual.entity_groups or {}
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
-- FUNCTION: clear_bot_highlight(ps)
--
-- Purpose:
--   Removes any existing highlight rectangle for the player's bot.
--
-- Parameters:
--   ps : table
--       The per-player state table that contains:
--         * ps.visual.bot_highlight — a LuaRenderObject or nil.
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
function visual.clear_bot_highlight(ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    state.ensure_visuals(ps)

    -- If a role is specified, clear only that bot's highlight.
    if bot_name then
        local bv = get_bot_visual(ps, bot_name)
        local obj = bv.bot_highlight
        if obj and obj.valid then
            obj:destroy()
        end
        bv.bot_highlight = nil
        return
    end

    -- Otherwise clear all bots' highlights.
    for _, bv in iter_bot_visuals(ps) do
        local obj = bv.bot_highlight
        if obj and obj.valid then
            obj:destroy()
        end
        bv.bot_highlight = nil
    end

    -- Legacy fallback (pre multi-bot).
    local legacy = ps.visual.bot_highlight
    if legacy and legacy.valid then
        legacy:destroy()
    end
    ps.visual.bot_highlight = nil
end

---------------------------------------------------
-- FUNCTION: clear_lines(ps)
--
-- Purpose:
--   Destroys and clears all line render objects associated with the
--   player's bot visual.
--
-- Parameters:
--   ps : table
--       The per-player state table that contains:
--         * ps.visual.lines — an array of LuaRenderObject
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
function visual.clear_lines(ps, bot_name)
    state.ensure_visuals(ps)

    if not (ps and ps.visual) then
        return
    end

    -- If a role is specified, clear only that bot's path lines.
    if bot_name then
        local bv = get_bot_visual(ps, bot_name)
        local lines = bv.lines
        if not lines then
            return
        end

        for _, line_obj in pairs(lines) do
            if line_obj and line_obj.valid then
                line_obj:destroy()
            end
        end

        bv.lines = nil
        return
    end

    -- Otherwise clear all bots' path lines.
    for role, bv in iter_bot_visuals(ps) do
        if bv.lines then
            for _, line_obj in pairs(bv.lines) do
                if line_obj and line_obj.valid then
                    line_obj:destroy()
                end
            end
            bv.lines = nil
        end
    end

    -- Legacy fallback (pre multi-bot): clear any existing shared lines field.
    local legacy_lines = ps.visual.lines
    if legacy_lines then
        for _, line_obj in pairs(legacy_lines) do
            if line_obj and line_obj.valid then
                line_obj:destroy()
            end
        end
        ps.visual.lines = nil
    end
end

---------------------------------------------------
-- FUNCTION: clear_radius_circle(ps)
--
-- Purpose:
--   Destroys and clears the radius circle render object (if any)
--   associated with the player's bot visual.
--
-- Parameters:
--   ps : table
--       The per-player state table that contains:
--         * ps.visual.radius_circle — a LuaRenderObject or nil.
--
-- Behavior:
--   * If a radius circle exists and is valid, calls :destroy().
--   * Clears the reference (sets it to nil) afterwards.
--
-- Notes:
--   * Safe to call when no radius circle exists or when visual is nil.
---------------------------------------------------
function visual.clear_radius_circle(ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    state.ensure_visuals(ps)

    -- If a role is specified, clear only that bot's radius circle.
    if bot_name then
        local bv = get_bot_visual(ps, bot_name)
        local obj = bv.radius_circle
        if obj and obj.valid then
            obj:destroy()
        end
        bv.radius_circle = nil
        return
    end

    -- Otherwise clear all bots' radius circles.
    for _, bv in iter_bot_visuals(ps) do
        local obj = bv.radius_circle
        if obj and obj.valid then
            obj:destroy()
        end
        bv.radius_circle = nil
    end

    -- Legacy fallback (pre multi-bot).
    local legacy = ps.visual.radius_circle
    if legacy and legacy.valid then
        legacy:destroy()
    end
    ps.visual.radius_circle = nil
end

function visual.clear_overlay(ps)
    if not (ps and ps.visual) then
        return
    end

    local overlays = ps.visual.overlay_texts
    if overlays then
        for _, obj in pairs(overlays) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end

    ps.visual.overlay_texts = {}
end

function visual.clear_entity_groups(ps)
    if not (ps and ps.visual) then
        return
    end

    local groups = ps.visual.entity_groups
    if not groups then
        return
    end

    for _, g in pairs(groups) do
        if g.lines then
            for _, line_obj in pairs(g.lines) do
                if line_obj and line_obj.valid then
                    line_obj:destroy()
                end
            end
        end

        if g.label and g.label.valid then
            g.label:destroy()
        end
    end

    ps.visual.entity_groups = {}
end

function visual.clear_entity_group(ps, group_id)
    if not (ps and ps.visual and ps.visual.entity_groups) then
        return
    end

    local g = ps.visual.entity_groups[group_id]
    if not g then
        return
    end

    if g.lines then
        for _, line_obj in pairs(g.lines) do
            if line_obj and line_obj.valid then
                line_obj:destroy()
            end
        end
    end

    if g.label and g.label.valid then
        g.label:destroy()
    end

    ps.visual.entity_groups[group_id] = nil
end

function visual.clear_bot_light(ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    state.ensure_visuals(ps)

    -- If a role is specified, clear only that bot's light.
    if bot_name then
        local bv = get_bot_visual(ps, bot_name)
        local obj = bv.bot_light
        if obj and obj.valid then
            obj:destroy()
        end
        bv.bot_light = nil
        return
    end

    -- Otherwise clear all bots' lights.
    for _, bv in iter_bot_visuals(ps) do
        local obj = bv.bot_light
        if obj and obj.valid then
            obj:destroy()
        end
        bv.bot_light = nil
    end

    -- Legacy fallback (pre multi-bot).
    local legacy = ps.visual.bot_light
    if legacy and legacy.valid then
        legacy:destroy()
    end
    ps.visual.bot_light = nil
end

function visual.clear_player_light(ps)
    if not (ps and ps.visual) then
        return
    end

    local obj = ps.visual.player_light
    if obj then
        obj.destroy()
    end

    ps.visual.player_light = nil
end

---------------------------------------------------
-- FUNCTION: clear_all(ps)
--
-- Purpose:
--   Convenience helper that clears all known render objects belonging
--   to the player's bot visual (highlight, lines, radius circle,
--   mapped entities).
---------------------------------------------------
function visual.clear_all(ps)
    if not ps then
        return
    end

    visual.clear_lines(ps)
    visual.clear_bot_highlight(ps)
    visual.clear_radius_circle(ps)
    visual.clear_entity_groups(ps)
    visual.clear_bot_light(ps)
    visual.clear_player_light(ps)
    visual.clear_overlay(ps)
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

-- Compute the world-space position that corresponds
-- to the top-left corner of the screen for this player.
local function get_screen_top_left_world(player)
    -- Fallbacks in case any field is missing
    local res = player.display_resolution or {
        width = 1920,
        height = 1080
    }
    local scale = player.display_scale or 1
    local zoom = player.zoom or 1

    -- “Effective” resolution after UI scaling
    local w_pixels = res.width / scale
    local h_pixels = res.height / scale

    -- 1 tile = 32 pixels at zoom = 1
    local tiles_per_pixel = 1 / (32 * zoom)

    local half_w_tiles = (w_pixels * tiles_per_pixel) / 2
    local half_h_tiles = (h_pixels * tiles_per_pixel) / 2

    local cx = player.position.x
    local cy = player.position.y

    -- world position of top-left corner
    return {
        x = cx - half_w_tiles,
        y = cy - half_h_tiles
    }
end

function visual.update_overlay(player, ps, lines)
    if not (player and player.valid) then
        return
    end

    visual.clear_overlay(ps)

    -------------------------------------------------------
    -- Keep text the same size regardless of zoom
    -------------------------------------------------------
    local base_scale = 1.5
    local zoom = player.zoom or 1
    local effective_scale = base_scale / zoom

    -------------------------------------------------------
    -- Top-left of the current camera + small margin
    -------------------------------------------------------
    local tl = get_screen_top_left_world(player)

    local margin_tiles_x = 0.5
    local margin_tiles_y = 0.5

    local base_pos = {
        x = tl.x + margin_tiles_x,
        y = tl.y + margin_tiles_y
    }

    -------------------------------------------------------
    -- Draw or update the text
    -------------------------------------------------------

    -- Line spacing in tiles, scaled with text size
    local base_line_spacing_tiles = 0.8
    local line_spacing = base_line_spacing_tiles * (effective_scale / base_scale)

    -- Update/create one visual per line
    for index, line in ipairs(lines) do
        local line_pos = {
            x = base_pos.x,
            y = base_pos.y + (index - 1) * line_spacing
        }

        local color = {
            r = 1,
            g = 1,
            b = 0,
            a = 0.8
        } -- semi-transparent yellow

        if index > 1 then
            line_pos.x = line_pos.x + (0.5 * effective_scale)

            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 0.8
            } -- white

            line = "> " .. line
        end

        -- Ensure container exists
        local overlays = ps.visual.overlay_texts
        if not overlays then
            overlays = {}
            ps.visual.overlay_texts = overlays
        end

        local obj = overlays[index]

        if obj and obj.valid then
            obj.text = line
            obj.target = line_pos
            obj.scale = effective_scale
        else
            overlays[index] = rendering.draw_text {
                text = line,
                surface = player.surface,
                target = line_pos,
                color = color,
                scale = effective_scale,
                alignment = "left",
                vertical_alignment = "top",
                draw_on_ground = false,
                only_in_alt_mode = false
            }
        end
    end
end

---------------------------------------------------
-- FUNCTION: draw_radius_circle(player, ps, bot_entity, radius, color)
--
-- Purpose:
--   Draws a circle around the bot to visualize a radius (for example,
--   a detection or survey radius used in game logic).
--
-- Parameters:
--   player       : LuaPlayer
--       The player who will see this circle.
--
--   ps : table
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
--   * Stores the render reference in ps.visual.radius_circle.
---------------------------------------------------
function visual.draw_radius_circle(player, ps, bot_name, bot_entity, radius, color)
    if not (player and player.valid and bot_entity and bot_entity.valid and radius) then
        return
    end

    state.ensure_visuals(ps)

    -- Clear existing radius circle for this bot.
    visual.clear_radius_circle(ps, bot_name)

    local bv = get_bot_visual(ps, bot_name)
    bv.radius_circle = rendering.draw_circle {
        color = color or {
            r = 1,
            g = 1,
            b = 1,
            a = 0.25
        },
        radius = radius,
        width = 2,
        target = bot_entity,
        surface = bot_entity.surface,
        filled = false,
        draw_on_ground = true,
        players = {player.index}
    }
end

function visual.draw_bot_highlight(player, ps, bot_name)
    if not (player and player.valid and ps and ps.visual) then
        return
    end

    state.ensure_visuals(ps)

    ------------------------------------------------------------------
    -- Draw a highlight rectangle for each bot role.
    ------------------------------------------------------------------
    local bot = state.get_bot_by_name(player, ps, bot_name)
    local bot_conf = config.get_bot_config(bot_name)

    if bot then
        local bv = get_bot_visual(ps, bot_name)

        local left_top = {
            x = bot.entity.position.x - 0.5,
            y = bot.entity.position.y - 0.7
        }

        local right_bottom = {
            x = bot.entity.position.x + 0.5,
            y = bot.entity.position.y + 0.3
        }

        if bv.highlight and not bv.highlight.valid then
            bv.highlight = nil
        end

        if not bv.highlight then
            bv.highlight = rendering.draw_rectangle {
                color = bot_conf.highlight_color,
                filled = false,
                width = 2,
                left_top = left_top,
                right_bottom = right_bottom,
                surface = bot.entity.surface,
                draw_on_ground = true,
                only_in_alt_mode = false,
                players = {player.index}
            }
        else
            bv.highlight.set_corners(left_top, right_bottom)
        end
    end
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
-- FUNCTION: draw_lines(player, ps, bot_entity, line_color)
--
-- Purpose:
--   Draws visual lines that connect the player to their bot.
--
-- Parameters:
--   player       : LuaPlayer
--       The player who will see the visual.
--
--   ps : table
--       The per-player state containing:
--         * ps.visual.lines   — array of LuaRenderObject
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
--   2. Ensures ps.visual and visual.lines exist.
--   3. Draws a line from the player's position to the bot's position.
--   4. Stores the created render object in ps.visual.lines.
--
-- Notes:
--   * The caller is responsible for clearing lines between ticks by
--     calling visual.clear_lines(ps) to prevent buildup.
---------------------------------------------------
function visual.draw_lines(player, ps, bot_name, bot_entity, target_pos, color)
    if not (player and player.valid and bot_entity and bot_entity.valid and target_pos) then
        return
    end

    state.ensure_visuals(ps)

    -- Clear existing lines for this bot.
    visual.clear_lines(ps, bot_name)

    local bv = get_bot_visual(ps, bot_name)
    bv.lines = bv.lines or {}

    -- Draw a simple two-segment line: bot -> target.
    bv.lines[1] = rendering.draw_line {
        color = color or {
            r = 1,
            g = 1,
            b = 1,
            a = 1
        },
        width = 2,
        from = bot_entity,
        to = target_pos,
        surface = bot_entity.surface,
        draw_on_ground = true,
        players = {player.index}
    }
end

---------------------------------------------------
-- FUNCTION: draw_mapped_entity_box(player, ps, entity)
--
-- Purpose:
--   Draws a green box around a mapped entity to mark it visually.
--
-- Parameters:
--   player       : LuaPlayer
--       Player who will see the box.
--
--   ps : table
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
function visual.draw_mapped_entity_box(player, ps, entity)
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
        players = {player.index},
        draw_on_ground = false
    }

    return box_render
end

function visual.draw_entity_group(player, ps, group_id, name, boundary, center)
    if not (player and player.valid and ps) then
        return
    end

    ensure_entity_groups_table(ps)

    -- Replace existing visuals for this group id
    visual.clear_entity_group(ps, group_id)

    local lines = {}
    if boundary and #boundary >= 2 then
        for i = 1, #boundary do
            local a = boundary[i]
            local b = boundary[(i % #boundary) + 1]

            lines[#lines + 1] = rendering.draw_line {
                surface = player.surface,
                from = a,
                to = b,
                color = {
                    r = 0.1,
                    g = 1.0,
                    b = 0.2,
                    a = 0.95
                },
                width = 2,
                draw_on_ground = true,
                only_in_alt_mode = false,
                players = {player.index}
            }
        end
    end

    local label = nil
    if center then
        label = rendering.draw_text {
            text = name,
            surface = player.surface,
            target = center,
            color = {
                r = 0.1,
                g = 1.0,
                b = 0.2,
                a = 0.95
            },
            scale = 2,
            alignment = "center",
            vertical_alignment = "middle",
            draw_on_ground = false,
            only_in_alt_mode = false,
            players = {player.index}
        }
    end

    ps.visual.entity_groups[group_id] = {
        lines = lines,
        label = label
    }
end

function visual.draw_bot_light(player, ps, bot_name, bot)
    if not (player and player.valid and ps and ps.visual and bot and bot.valid) then
        return
    end

    state.ensure_visuals(ps)

    local bv = get_bot_visual(ps, bot_name)
    local obj = bv.bot_light
    if obj and obj.valid then
        return -- already exists; stays attached to target
    end

    bv.bot_light = rendering.draw_light {
        sprite = "utility/light_medium",
        scale = 0.7,
        intensity = 0.6,
        minimum_darkness = 0.2,
        oriented = false,
        target = bot,
        surface = bot.surface,
        players = {player.index}
    }
end

function visual.draw_player_light(player, ps)
    if not (player and player.valid and ps and ps.visual) then
        return
    end

    local obj = ps.visual.player_light
    if obj and obj.valid then
        return -- already exists; stays attached to target :contentReference[oaicite:3]{index=3}
    end

    ps.visual.player_light = rendering.draw_light {
        sprite = "utility/light_medium",
        target = player.character,
        surface = player.surface,

        scale = 20,
        intensity = 4,
        minimum_darkness = 0.05,

        players = {player.index},
        render_mode = "game"
    }
end

----------------------------------------------------------------------
-- MODULE RETURN
--
-- Expose the visual API for use by control.lua and other modules.
----------------------------------------------------------------------
return visual
