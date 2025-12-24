local visual = {}

-- Must match "name" in info.json
local MOD_NAME = "entity_repair_mod"

----------------------------------------------------------------
-- Wipe ALL rendering objects created by this mod
----------------------------------------------------------------
function visual.force_clear_mod_objects(ps)
    if not ps then
        return
    end

    pcall(rendering.clear, MOD_NAME)
end

function visual.clear_bot_health_bar(ps)
    if ps.bot_health_bg and ps.bot_health_bg.valid then
        ps.bot_health_bg:destroy()
    end
    if ps.bot_health_fg and ps.bot_health_fg.valid then
        ps.bot_health_fg:destroy()
    end
    if ps.bot_health_text and ps.bot_health_text.valid then
        ps.bot_health_text:destroy()
    end
    ps.bot_health_bg = nil
    ps.bot_health_fg = nil
    ps.bot_health_text = nil
end

function visual.clear_bot_highlight(ps)
    if ps.vis_bot_highlight and ps.vis_bot_highlight.valid then
        ps.vis_bot_highlight:destroy()
    end
    ps.vis_bot_highlight = nil
end

function visual.clear_chest_highlight(ps)
    if ps.vis_chest_highlight and ps.vis_chest_highlight.valid then
        ps.vis_chest_highlight:destroy()
    end
    ps.vis_chest_highlight = nil
end

---------------------------------------------------
-- DESTROYED ENTITIES OVERLAY
--  - Shows list in top-left of screen (camera)
--  - Low opacity text so map is visible underneath
--  - Large font scale
---------------------------------------------------

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

function visual.clear_destroyed_overlay(ps)
    if not ps then
        return
    end

    -- Backwards compatibility: single text object
    if ps.destroyed_overlay_text and ps.destroyed_overlay_text.valid then
        ps.destroyed_overlay_text:destroy()
    end
    ps.destroyed_overlay_text = nil

    -- New: multiple text objects, one per line
    if ps.destroyed_overlay_texts then
        for _, obj in pairs(ps.destroyed_overlay_texts) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end
    ps.destroyed_overlay_texts = nil

    -- Lines from player to destroyed entities
    if ps.destroyed_overlay_lines then
        for _, obj in pairs(ps.destroyed_overlay_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end
    ps.destroyed_overlay_lines = nil
end

-- destroyed_list: array or map of {name=..., type=..., position=..., surface=...}
function visual.update_destroyed_overlay(player, ps, destroyed_list)
    if not (player and player.valid) then
        return
    end

    destroyed_list = destroyed_list or {}

    -- Check if there is anything to show
    local has_any = false
    for _ in pairs(destroyed_list) do
        has_any = true
        break
    end
    if not has_any then
        visual.clear_destroyed_overlay(ps)
        return
    end

    -------------------------------------------------------
    -- Keep text the same size regardless of zoom
    -------------------------------------------------------
    local base_scale = 2.2
    local zoom = player.zoom or 1
    local effective_scale = base_scale / zoom

    -------------------------------------------------------
    -- Build overlay text
    -------------------------------------------------------
    local lines = {"Destroyed entities:"}
    local entity_positions = {}

    local i = 0
    for _, e in pairs(destroyed_list) do
        i = i + 1
        local pos = e.position or {
            x = e.x or 0,
            y = e.y or 0
        }

        lines[#lines + 1] = string.format("%d) [%.1f, %.1f]→%s", i, pos.x, pos.y, e.name or "?")
        entity_positions[#entity_positions + 1] = pos
    end

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
    -- Clear any legacy single-text usage
    if ps.destroyed_overlay_text and ps.destroyed_overlay_text.valid then
        ps.destroyed_overlay_text:destroy()
    end
    ps.destroyed_overlay_text = nil

    -- Ensure table exists
    ps.destroyed_overlay_texts = ps.destroyed_overlay_texts or {}

    -- Line spacing in tiles, scaled with text size
    local base_line_spacing_tiles = 0.8
    local line_spacing = base_line_spacing_tiles * (effective_scale / base_scale)

    -- Update/create one visual per line
    for index, line in ipairs(lines) do
        local line_pos = {
            x = base_pos.x,
            y = base_pos.y + (index - 1) * line_spacing
        }

        local obj = ps.destroyed_overlay_texts[index]
        if obj and obj.valid then
            obj.text = line
            obj.target = line_pos
            obj.scale = effective_scale
        else
            ps.destroyed_overlay_texts[index] = rendering.draw_text {
                text = line,
                surface = player.surface,
                target = line_pos,
                color = {
                    r = 1,
                    g = 1,
                    b = 0,
                    a = 0.8
                }, -- semi-transparent yellow
                scale = effective_scale,
                alignment = "left",
                vertical_alignment = "top",
                draw_on_ground = false,
                only_in_alt_mode = false
            }
        end
    end

    -- Destroy any extra visual if the list shrank
    local count = #ps.destroyed_overlay_texts
    local needed = #lines
    if count > needed then
        for idx = needed + 1, count do
            local obj = ps.destroyed_overlay_texts[idx]
            if obj and obj.valid then
                obj:destroy()
            end
            ps.destroyed_overlay_texts[idx] = nil
        end
    end

    -------------------------------------------------------
    -- Draw / update lines from player to each destroyed site
    -------------------------------------------------------
    -- Clear old lines
    if ps.destroyed_overlay_lines then
        for _, obj in pairs(ps.destroyed_overlay_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end
    ps.destroyed_overlay_lines = {}

    local player_pos = player.position

    for _, pos in ipairs(entity_positions) do
        local line = rendering.draw_line {
            color = {
                r = 1,
                g = 0.2,
                b = 0.2,
                a = 0.4
            }, -- soft red, semi-transparent
            width = 2,
            from = {
                x = player_pos.x,
                y = player_pos.y
            },
            to = {
                x = pos.x,
                y = pos.y
            },
            surface = player.surface,
            draw_on_ground = true,
            only_in_alt_mode = false
        }
        ps.destroyed_overlay_lines[#ps.destroyed_overlay_lines + 1] = line
    end
end

-- Call this every tick (or at your bot update interval)
-- max_health: either a constant or passed in from your get_entity_max_health(bot)
function visual.update_bot_health_bar(player, bot, ps, max_health, repair_pack_name)
    if not (bot and bot.valid and max_health and max_health > 0) then
        -- Cleanup if bot missing
        if ps.bot_health_bg and ps.bot_health_bg.valid then
            ps.bot_health_bg:destroy()
        end
        if ps.bot_health_fg and ps.bot_health_fg.valid then
            ps.bot_health_fg:destroy()
        end
        if ps.bot_health_text and ps.bot_health_text.valid then
            ps.bot_health_text:destroy()
        end
        ps.bot_health_bg = nil
        ps.bot_health_fg = nil
        ps.bot_health_text = nil
        return
    end

    local health = bot.health or max_health
    local ratio = math.max(0, math.min(1, health / max_health))

    -------------------------------------------------------
    -- Shared "UI baseline" for all bot overlays
    -------------------------------------------------------
    local pos = bot.position
    local ui_y = pos.y + 0.3

    local bar_width = 0.8
    local bar_height = 0.10

    local highlight_size = 0.6
    local bar_y_start = (ui_y + highlight_size) + 0.05

    -- Offsets relative to bot (for ScriptRenderTarget)
    local lt_offset = {
        x = -bar_width / 2,
        y = bar_y_start - pos.y
    }

    local rb_offset_full = {
        x = bar_width / 2,
        y = (bar_y_start + bar_height) - pos.y
    }

    local rb_offset_fg = {
        x = -bar_width / 2 + bar_width * ratio,
        y = (bar_y_start + bar_height) - pos.y
    }

    -------------------------------------------------------
    -- Background rectangle (full bar area, dark)
    -------------------------------------------------------
    if ps.bot_health_bg and ps.bot_health_bg.valid then
        ps.bot_health_bg.left_top = {
            entity = bot,
            offset = lt_offset
        }
        ps.bot_health_bg.right_bottom = {
            entity = bot,
            offset = rb_offset_full
        }
    else
        ps.bot_health_bg = rendering.draw_rectangle {
            color = {
                r = 0,
                g = 0,
                b = 0,
                a = 0.7
            }, -- dark background
            filled = true,
            left_top = {
                entity = bot,
                offset = lt_offset
            },
            right_bottom = {
                entity = bot,
                offset = rb_offset_full
            },
            surface = bot.surface,
            draw_on_ground = true,
            only_in_alt_mode = false
        }
    end

    -------------------------------------------------------
    -- Foreground (current health) rectangle (green)
    -- Destroy + recreate every tick so it always renders on top
    -------------------------------------------------------
    if ps.bot_health_fg and ps.bot_health_fg.valid then
        ps.bot_health_fg:destroy()
        ps.bot_health_fg = nil
    end

    ps.bot_health_fg = rendering.draw_rectangle {
        color = {
            r = 0,
            g = 1,
            b = 0,
            a = 0.9
        }, -- green bar
        filled = true,
        left_top = {
            entity = bot,
            offset = lt_offset
        },
        right_bottom = {
            entity = bot,
            offset = rb_offset_fg
        },
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }

    -------------------------------------------------------
    -- Text (e.g. "75→100→30") just below the bar
    -------------------------------------------------------
    local inv = player.get_main_inventory()
    if not inv then
        return
    end

    local player_packs_available = inv.get_item_count(repair_pack_name)

    local chest_packs_available = 0
    local chest = ps.repair_chest

    if chest and chest.valid and (chest.type == "container" or chest.type == "logistic-container") then
        -- Get chest inventory (always defines.inventory.chest for these types)
        local inv = chest.get_inventory(defines.inventory.chest)

        if inv and inv.valid then
            -- Get available repair pack items count
            chest_packs_available = inv.get_item_count(repair_pack_name)
        end
    end

    local text_y = bar_y_start + bar_height + 0.15
    local text_pos = {
        x = pos.x,
        y = text_y
    }

    local text_value = string.format("%d→%d→%d", ps.repair_health_pool, chest_packs_available,
        player_packs_available)

    if ps.bot_health_text and ps.bot_health_text.valid then
        ps.bot_health_text.target = text_pos
        ps.bot_health_text.text = text_value
    else
        ps.bot_health_text = rendering.draw_text {
            text = text_value,
            surface = bot.surface,
            target = text_pos,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 1
            },
            scale = 0.75,
            draw_on_ground = true,
            alignment = "center",
            only_in_alt_mode = false
        }
    end
end

function visual.clear_lines(ps)
    if ps.vis_lines then
        for _, obj in pairs(ps.vis_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        ps.vis_lines = nil
    end
end

function visual.draw_bot_player_visuals(player, bot, ps)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local y_offset = 0

    local bot_pos = bot.position
    local to_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    ps.vis_lines = ps.vis_lines or {}

    -- choose line color based on bot mode
    -- red when repairing, grey when following or anything else
    local line_color
    if ps.last_mode == "repair" then
        line_color = {
            r = 0.5,
            g = 0.1,
            b = 0.1,
            a = 0.7
        } -- bright red, clearly visible
    else
        line_color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        } -- original grey
    end

    local line = rendering.draw_line {
        color = line_color,
        width = 1,
        from = player.position,
        to = to_pos,
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }

    ps.vis_lines[#ps.vis_lines + 1] = line
end

---------------------------------------------------
-- DAMAGED ENTITY MARKERS (DOTS + LINES)
---------------------------------------------------
function visual.clear_damaged_markers(ps)
    if ps.vis_damaged_markers then
        for _, obj in pairs(ps.vis_damaged_markers) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        ps.vis_damaged_markers = nil
    end

    if ps.vis_damaged_lines then
        for _, obj in pairs(ps.vis_damaged_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        ps.vis_damaged_lines = nil
    end
end

function visual.draw_damaged_visuals(bot, ps, damaged_entities)
    if not damaged_entities or #damaged_entities == 0 then
        return
    end

    local bot_pos = bot.position
    local to_pos = {
        x = bot_pos.x,
        y = bot_pos.y
    }

    ps.vis_damaged_markers = ps.vis_damaged_markers or {}
    ps.vis_damaged_lines = ps.vis_damaged_lines or {}

    for _, ent in pairs(damaged_entities) do
        if ent and ent.valid then
            local dot = rendering.draw_circle {
                color = {
                    r = 0,
                    g = 0.3,
                    b = 0,
                    a = 0.1
                },
                radius = 0.15,
                filled = true,
                target = ent,
                surface = ent.surface,
                draw_on_ground = true,
                only_in_alt_mode = false
            }
            ps.vis_damaged_markers[#ps.vis_damaged_markers + 1] = dot

            local line = rendering.draw_line {
                color = {
                    r = 1,
                    g = 0,
                    b = 0,
                    a = 0.1
                },
                width = 1,
                from = ent.position,
                to = bot_pos,
                surface = ent.surface,
                draw_on_ground = true,
                only_in_alt_mode = false
            }
            ps.vis_damaged_lines[#ps.vis_damaged_lines + 1] = line
        end
    end
end

---------------------------------------------------
-- BOT HIGHLIGHT
---------------------------------------------------
function visual.draw_bot_highlight(bot, ps)
    if not (bot and bot.valid) then
        return
    end

    local size = 0.6
    local pos = bot.position

    -- Shared baseline:
    local ui_y = pos.y
    local cx = pos.x

    local left_top = {cx - size, ui_y - size * 1.5}
    local right_bottom = {cx + size, ui_y + size}

    if ps.vis_bot_highlight then
        local obj = ps.vis_bot_highlight
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            ps.vis_bot_highlight = nil
        end
    end

    ps.vis_bot_highlight = rendering.draw_rectangle {
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
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }
end

---------------------------------------------------
-- CHEST HIGHLIGHT
---------------------------------------------------
function visual.draw_chest_highlight(chest, ps, chest_highlight_y_offset)
    if not (chest and chest.valid) then
        visual.clear_chest_highlight(ps)
        return
    end

    local size = 0.6
    local pos = chest.position

    -- Shared baseline:
    local ui_y = pos.y + (chest_highlight_y_offset or 0)
    local cx = pos.x

    local left_top = {cx - size, ui_y - size}
    local right_bottom = {cx + size, ui_y + size}

    if ps.vis_chest_highlight then
        local obj = ps.vis_chest_highlight
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            ps.vis_chest_highlight = nil
        end
    end

    ps.vis_chest_highlight = rendering.draw_rectangle {
        color = {
            r = 0.8,
            g = 0.0,
            b = 0.8,
            a = 0.1
        },
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = chest.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }
end

-- Master “clear everything” helper:
function visual.clear_all(ps)
    if not ps then
        return
    end

    visual.clear_bot_health_bar(ps)
    visual.clear_bot_highlight(ps)
    visual.clear_chest_highlight(ps)
    visual.clear_lines(ps)
    visual.clear_damaged_markers(ps)
    visual.clear_destroyed_overlay(ps)
end

return visual
