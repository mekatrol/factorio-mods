-- Must match "name" in info.json
local MOD_NAME = "mekatrol_game_play_mod"

local visual = {}

local config = require("config")
local state = require("state")
local util = require("util")

local BOT_NAMES = config.bot_names

local function ensure_lines_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.lines = ps.visual.lines or {}
end

local function ensure_entity_groups_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.entity_groups = ps.visual.entity_groups or {}
end

function visual.clear_bot_highlight(player, ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not bot then
        return
    end

    local obj = bot.visual.highlight
    if obj and obj.valid then
        obj:destroy()
    end

    ps.visual.highlight = nil
end

function visual.clear_lines(player, ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not bot then
        return
    end

    local lines = bot.visual.lines

    if not lines then
        return
    end

    for _, line_obj in pairs(lines) do
        if line_obj and line_obj.valid then
            line_obj:destroy()
        end
    end

    bot.visual.lines = nil
end

function visual.clear_bot_circle(player, ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not bot then
        return
    end

    local obj = bot.circle
    if obj and obj.valid then
        obj:destroy()
    end

    ps.visual.circle = nil
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

function visual.clear_bot_light(player, ps, bot_name)
    if not (ps and ps.visual) then
        return
    end

    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not bot then
        return
    end

    local obj = bot.light

    if obj and obj.valid then
        obj:destroy()
    end

    bot.light = nil
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

function visual.draw_bot_circle(player, ps, bot_name, bot_entity, radius, color)
    if not (player and player.valid and bot_entity and bot_entity.valid and radius) then
        return
    end

    -- Clear existing radius circle for this bot.
    visual.clear_bot_circle(player, ps, bot_name)

    local bot = state.get_bot_by_name(player, ps, bot_name)
    bot.visual.circle = rendering.draw_circle {
        color = color or {
            r = 1,
            g = 1,
            b = 1,
            a = 0.25
        },
        radius = radius,
        width = 2,
        target = bot.entity,
        surface = bot.entity.surface,
        filled = false,
        draw_on_ground = true,
        players = {player.index}
    }
end

function visual.draw_bot_highlight(player, ps, bot_name)
    if not (player and player.valid and ps and ps.visual) then
        return
    end

    ------------------------------------------------------------------
    -- Draw a highlight rectangle for each bot role.
    ------------------------------------------------------------------
    local bot = state.get_bot_by_name(player, ps, bot_name)
    local bot_conf = config.get_bot_config(bot_name)

    local left_top = {
        x = bot.entity.position.x - 0.5,
        y = bot.entity.position.y - 0.7
    }

    local right_bottom = {
        x = bot.entity.position.x + 0.5,
        y = bot.entity.position.y + 0.3
    }

    if bot.visual.highlight and not bot.visual.highlight.valid then
        bot.visual.highlight = nil
    end

    if not bot.visual.highlight then
        bot.visual.highlight = rendering.draw_rectangle {
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
        bot.visual.highlight.set_corners(left_top, right_bottom)
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

function visual.draw_lines(player, ps, bot_name, bot_entity, target_pos, color)
    if not (player and player.valid and bot_entity and bot_entity.valid and target_pos) then
        return
    end

    -- Clear existing lines for this bot.
    visual.clear_lines(player, ps, bot_name)

    local bot = state.get_bot_by_name(player, ps, bot_name)
    bot.lines = bot.lines or {}

    -- Draw a simple two-segment line: bot -> target.
    bot.lines[1] = rendering.draw_line {
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

    local bot = state.get_bot_by_name(player, ps, bot_name)
    local obj = bot.visual.light
    if obj and obj.valid then
        return -- already exists; stays attached to target
    end

    bot.visual.light = rendering.draw_light {
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
