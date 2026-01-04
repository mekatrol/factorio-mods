-- Must match "name" in info.json
local MOD_NAME = "mekatrol_game_play_mod"

local visual = {}

local config = require("config")
local polygon = require("polygon")
local util = require("util")

local BOT_NAMES = config.bot_names

local SURVEY_TRACE_EDGE_COLOR = {
    r = 0.85,
    g = 0.85,
    b = 0.85,
    a = 0.65
} -- light grey

local SURVEY_TRACE_START_COLOR = {
    r = 1.00,
    g = 0.00,
    b = 1.00,
    a = 0.95
} -- magenta

local SURVEY_TRACE_POINT_COLOR = {
    r = 1.00,
    g = 0.40,
    b = 0.70,
    a = 0.90
} -- pink

local function ensure_entity_groups_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.entity_groups = ps.visual.entity_groups or {}
end

local function ensure_survey_traces_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.survey_traces = ps.visual.survey_traces or {}
end

local function ensure_discovered_entities_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.discovered_entities = ps.visual.discovered_entities or {}
end

function visual.clear_survey_trace(ps, trace_id)
    if not (ps and ps.visual and ps.visual.survey_traces and trace_id) then
        return
    end

    local t = ps.visual.survey_traces[trace_id]
    if not t then
        return
    end

    if t.area_label and t.area_label.valid then
        t.area_label:destroy()
    end

    if t.lines then
        for _, obj in pairs(t.lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end

    if t.points then
        for _, obj in pairs(t.points) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end

    ps.visual.survey_traces[trace_id] = nil
end

function visual.clear_discovered_entities(ps)
    if not ps.visual.discovered_entities then
        return
    end

    for _, obj in pairs(ps.visual.discovered_entities) do
        if obj and obj.valid then
            obj:destroy()
        end
    end
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

        if g.name_label and g.name_label.valid then
            g.name_label:destroy()
        end

        if g.type_label and g.type_label.valid then
            g.type_label:destroy()
        end

        if g.area_label and g.area_label.valid then
            g.area_label:destroy()
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

    if g.name_label and g.name_label.valid then
        g.name_label:destroy()
    end

    if g.type_label and g.type_label.valid then
        g.type_label:destroy()
    end

    if g.area_label and g.area_label.valid then
        g.area_label:destroy()
    end

    ps.visual.entity_groups[group_id] = nil
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

function visual.append_survey_trace(player, ps, trace_id, points)
    if not (player and player.valid and ps and trace_id and points) then
        return
    end

    ensure_survey_traces_table(ps)

    local t = ps.visual.survey_traces[trace_id]
    if not t then
        t = {
            count = 0,
            points = {},
            lines = {},
            area_label = nil
        }
        ps.visual.survey_traces[trace_id] = t
    end

    local start_index = (t.count or 0) + 1
    if start_index > #points then
        -- still update the area label for the current trace
        start_index = #points + 1
    end

    -- Draw new points
    for i = start_index, #points do
        local p = points[i]
        local is_start = (i == 1)

        t.points[#t.points + 1] = rendering.draw_circle {
            surface = player.surface,
            target = p,
            color = is_start and SURVEY_TRACE_START_COLOR or SURVEY_TRACE_POINT_COLOR,
            radius = 0.18,
            filled = true,
            draw_on_ground = true,
            only_in_alt_mode = false,
            players = {player.index}
        }

        -- Draw edge from previous point to this point
        if i > 1 then
            local a = points[i - 1]
            local b = p

            t.lines[#t.lines + 1] = rendering.draw_line {
                surface = player.surface,
                from = a,
                to = b,
                color = SURVEY_TRACE_EDGE_COLOR,
                width = 2,
                draw_on_ground = true,
                only_in_alt_mode = false,
                players = {player.index}
            }
        end
    end

    t.count = #points

    -- Update / create live area label while tracing (treats the polyline as a polygon by closing last->first)
    local area = 0
    if #points >= 3 then
        area = polygon.polygon_area(points)
    end

    -- Label position: average of points, slightly below
    local cx = 0
    local cy = 0
    for i = 1, #points do
        cx = cx + points[i].x
        cy = cy + points[i].y
    end
    cx = cx / math.max(#points, 1)
    cy = cy / math.max(#points, 1)

    local label_text = string.format("Area: %.1f", area)
    local label_target = {
        x = cx,
        y = cy + 0.85
    }

    if t.area_label and t.area_label.valid then
        t.area_label.text = label_text
        t.area_label.target = label_target
    else
        t.area_label = rendering.draw_text {
            text = label_text,
            surface = player.surface,
            target = label_target,
            color = {
                r = 1.0,
                g = 1.0,
                b = 1.0,
                a = 0.95
            },
            scale = 1.4,
            alignment = "center",
            vertical_alignment = "middle",
            draw_on_ground = false,
            only_in_alt_mode = false,
            players = {player.index}
        }
    end
end

function visual.append_discovered_entities(player, ps)
    if not (player and player.valid and ps) then
        return
    end

    local entities = ps.discovered_entities:get_all()

    if not entities or #entities == 0 then
        return
    end

    ensure_discovered_entities_table(ps)

    local discovered_entities = ps.visual.discovered_entities
    local start_index = (discovered_entities.count or 0) + 1

    -- Draw new points
    local start_index = #discovered_entities
    for i = 1, #entities do
        local e = entities[i]

        if e and e.valid then
            local p = e.position

            discovered_entities[start_index + i] = rendering.draw_circle {
                surface = player.surface,
                target = p,
                color = {
                    r = 0.0,
                    g = 0.2,
                    b = 0.5,
                    a = 0.5
                },
                radius = 1,
                filled = true,
                draw_on_ground = false,
                only_in_alt_mode = false,
                players = {player.index}
            }
        end
    end
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

function visual.draw_entity_group(player, ps, group_id, name, type, boundary, center)
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

    local name_label = nil
    local type_label = nil
    local draw_label = true
    local area_label = nil

    if center and draw_label then
        local center_minus = {
            x = center.x,
            y = center.y - 0.4
        }

        local center_plus = {
            x = center.x,
            y = center.y + 0.4
        }

        local center_plus_plus = {
            x = center.x,
            y = center.y + 1.2
        }

        name_label = rendering.draw_text {
            text = name,
            surface = player.surface,
            target = center_minus,
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

        type_label = rendering.draw_text {
            text = type,
            surface = player.surface,
            target = center_plus,
            color = {
                r = 1.0,
                g = 1.0,
                b = 1.0,
                a = 0.95
            },
            scale = 2,
            alignment = "center",
            vertical_alignment = "middle",
            draw_on_ground = false,
            only_in_alt_mode = false,
            players = {player.index}
        }

        local area = 0
        if boundary and #boundary >= 3 then
            area = polygon.polygon_area(boundary)
        end

        area_label = rendering.draw_text {
            text = string.format("Area: %.1f", area),
            surface = player.surface,
            target = center_plus_plus,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 0.95
            },
            scale = 1.6,
            alignment = "center",
            vertical_alignment = "middle",
            draw_on_ground = false,
            only_in_alt_mode = false,
            players = {player.index}
        }
    end

    ps.visual.entity_groups[group_id] = {
        lines = lines,
        name_label = name_label,
        type_label = type_label,
        area_label = area_label
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
