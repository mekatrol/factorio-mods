local visuals = {}

-- Must match "name" in info.json
local MOD_NAME = "entity_repair_mod"

----------------------------------------------------------------
-- Wipe ALL rendering objects created by this mod
----------------------------------------------------------------
function visuals.force_clear_mod_objects(pdata)
    if not pdata then
        return
    end

    pcall(rendering.clear, MOD_NAME)
end

function visuals.clear_bot_health_bar(pdata)
    if pdata.bot_health_bg and pdata.bot_health_bg.valid then
        pdata.bot_health_bg:destroy()
    end
    if pdata.bot_health_fg and pdata.bot_health_fg.valid then
        pdata.bot_health_fg:destroy()
    end
    if pdata.bot_health_text and pdata.bot_health_text.valid then
        pdata.bot_health_text:destroy()
    end
    pdata.bot_health_bg = nil
    pdata.bot_health_fg = nil
    pdata.bot_health_text = nil
end

function visuals.clear_bot_highlight(pdata)
    if pdata.vis_bot_highlight and pdata.vis_bot_highlight.valid then
        pdata.vis_bot_highlight:destroy()
    end
    pdata.vis_bot_highlight = nil
end

function visuals.clear_chest_highlight(pdata)
    if pdata.vis_chest_highlight and pdata.vis_chest_highlight.valid then
        pdata.vis_chest_highlight:destroy()
    end
    pdata.vis_chest_highlight = nil
end

---------------------------------------------------
-- DESTROYED ENTITIES OVERLAY (SAFE VERSION)
---------------------------------------------------

function visuals.clear_destroyed_overlay(pdata)
    if pdata.destroyed_overlay_text and pdata.destroyed_overlay_text.valid then
        pdata.destroyed_overlay_text:destroy()
    end
    pdata.destroyed_overlay_text = nil
end

local function get_surface_name_from_entry(e)
    -- Prefer an actual surface handle if you stored it
    if e.surface and e.surface.valid then
        return e.surface.name
    end

    -- Next, try a surface_index if present and valid
    if e.surface_index ~= nil then
        local surf = game.surfaces[e.surface_index]
        if surf then
            return surf.name
        end
    end

    -- Or a stored name
    if e.surface_name ~= nil then
        return e.surface_name
    end

    -- Fallback
    return "?"
end

-- destroyed_list: array/map of { position={x,y}, type, name, surface/surface_index/surface_name }
function visuals.update_destroyed_overlay(player, pdata, destroyed_list)
    if not (player and player.valid) then
        return
    end

    destroyed_list = destroyed_list or {}

    -- empty list → clear overlay
    local has_any = false
    for _ in pairs(destroyed_list) do
        has_any = true
        break
    end
    if not has_any then
        visuals.clear_destroyed_overlay(pdata)
        return
    end

    -------------------------------------------------------
    -- Build text block
    -------------------------------------------------------
    local lines = {"[Destroyed entities]"}
    local idx = 0

    for _, e in pairs(destroyed_list) do
        idx = idx + 1

        local pos = e.position or {
            x = 0,
            y = 0
        }
        local sname = (e.surface and e.surface.valid and e.surface.name) or "?"
        local name = e.name or "?"
        local etype = e.type or "?"

        lines[#lines + 1] = string.format("%d) %s (%s) @ %s [%.1f, %.1f]", idx, name, etype, sname, pos.x, pos.y)
    end

    local text = table.concat(lines, "\n")

    -------------------------------------------------------
    -- Decide what to anchor to
    -- Prefer the player CHARACTER (LuaEntity); otherwise
    -- fall back to a world position near the player.
    -------------------------------------------------------
    local anchor_entity = player.character
    local target

    if anchor_entity and anchor_entity.valid then
        -- HUD-style anchor relative to the character
        target = {
            entity = anchor_entity,
            offset = {
                x = -10,
                y = -8
            } -- tweak for “top-left”
        }
    else
        -- No character (e.g. god/editor mode) → approximate using position
        local pp = player.position
        target = {
            x = pp.x - 10,
            y = pp.y - 8
        }
    end

    -------------------------------------------------------
    -- Create or update the rendering text
    -------------------------------------------------------
    if pdata.destroyed_overlay_text and pdata.destroyed_overlay_text.valid then
        pdata.destroyed_overlay_text.text = text
        pdata.destroyed_overlay_text.target = target
    else
        pdata.destroyed_overlay_text = rendering.draw_text {
            text = text,
            surface = player.surface,
            target = target,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 0.55
            }, -- semi-transparent
            scale = 2.8, -- bigger font
            alignment = "left",
            vertical_alignment = "top",
            draw_on_ground = false,
            only_in_alt_mode = false
        }
    end
end

-- Call this every tick (or at your bot update interval)
-- max_health: either a constant or passed in from your get_entity_max_health(bot)
function visuals.update_bot_health_bar(player, bot, pdata, max_health, bot_highlight_y_offset, repair_pack_name)
    if not (bot and bot.valid and max_health and max_health > 0) then
        -- Cleanup if bot missing
        if pdata.bot_health_bg and pdata.bot_health_bg.valid then
            pdata.bot_health_bg:destroy()
        end
        if pdata.bot_health_fg and pdata.bot_health_fg.valid then
            pdata.bot_health_fg:destroy()
        end
        if pdata.bot_health_text and pdata.bot_health_text.valid then
            pdata.bot_health_text:destroy()
        end
        pdata.bot_health_bg = nil
        pdata.bot_health_fg = nil
        pdata.bot_health_text = nil
        return
    end

    local health = bot.health or max_health
    local ratio = math.max(0, math.min(1, health / max_health))

    -------------------------------------------------------
    -- Shared "UI baseline" for all bot overlays
    -------------------------------------------------------
    local pos = bot.position
    local ui_y = pos.y + (bot_highlight_y_offset or 0) + 0.3

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
    if pdata.bot_health_bg and pdata.bot_health_bg.valid then
        pdata.bot_health_bg.left_top = {
            entity = bot,
            offset = lt_offset
        }
        pdata.bot_health_bg.right_bottom = {
            entity = bot,
            offset = rb_offset_full
        }
    else
        pdata.bot_health_bg = rendering.draw_rectangle {
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
    if pdata.bot_health_fg and pdata.bot_health_fg.valid then
        pdata.bot_health_fg:destroy()
        pdata.bot_health_fg = nil
    end

    pdata.bot_health_fg = rendering.draw_rectangle {
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
    local chest = pdata.repair_chest

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

    local text_value = string.format("%d→%d→%d", pdata.repair_health_pool or 0, chest_packs_available,
        player_packs_available)

    if pdata.bot_health_text and pdata.bot_health_text.valid then
        pdata.bot_health_text.target = text_pos
        pdata.bot_health_text.text = text_value
    else
        pdata.bot_health_text = rendering.draw_text {
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

function visuals.clear_lines(pdata)
    if pdata.vis_lines then
        for _, obj in pairs(pdata.vis_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.vis_lines = nil
    end
end

function visuals.draw_bot_player_visuals(player, bot, pdata, bot_highlight_y_offset)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local y_offset = bot_highlight_y_offset or 0

    local bot_pos = bot.position
    local to_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    pdata.vis_lines = pdata.vis_lines or {}

    -- choose line color based on bot mode
    -- red when repairing, grey when following or anything else
    local line_color
    if pdata.last_mode == "repair" then
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

    pdata.vis_lines[#pdata.vis_lines + 1] = line
end

---------------------------------------------------
-- DAMAGED ENTITY MARKERS (DOTS + LINES)
---------------------------------------------------
function visuals.clear_damaged_markers(pdata)
    if pdata.vis_damaged_markers then
        for _, obj in pairs(pdata.vis_damaged_markers) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.vis_damaged_markers = nil
    end

    if pdata.vis_damaged_lines then
        for _, obj in pairs(pdata.vis_damaged_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.vis_damaged_lines = nil
    end
end

function visuals.draw_damaged_visuals(bot, pdata, damaged_entities, bot_highlight_y_offset)
    if not damaged_entities or #damaged_entities == 0 then
        return
    end

    local y_offset = bot_highlight_y_offset or 0

    local bot_pos = bot.position
    local to_pos = {
        x = bot_pos.x,
        y = bot_pos.y + y_offset
    }

    pdata.vis_damaged_markers = pdata.vis_damaged_markers or {}
    pdata.vis_damaged_lines = pdata.vis_damaged_lines or {}

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
            pdata.vis_damaged_markers[#pdata.vis_damaged_markers + 1] = dot

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
            pdata.vis_damaged_lines[#pdata.vis_damaged_lines + 1] = line
        end
    end
end

---------------------------------------------------
-- BOT HIGHLIGHT
---------------------------------------------------
function visuals.draw_bot_highlight(bot, pdata, bot_highlight_y_offset)
    if not (bot and bot.valid) then
        return
    end

    local size = 0.6
    local pos = bot.position

    -- Shared baseline:
    local ui_y = pos.y + (bot_highlight_y_offset or 0)
    local cx = pos.x

    local left_top = {cx - size, ui_y - size * 1.5}
    local right_bottom = {cx + size, ui_y + size}

    if pdata.vis_bot_highlight then
        local obj = pdata.vis_bot_highlight
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            pdata.vis_bot_highlight = nil
        end
    end

    pdata.vis_bot_highlight = rendering.draw_rectangle {
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
function visuals.draw_chest_highlight(chest, pdata, chest_highlight_y_offset)
    if not (chest and chest.valid) then
        visuals.clear_chest_highlight(pdata)
        return
    end

    local size = 0.6
    local pos = chest.position

    -- Shared baseline:
    local ui_y = pos.y + (chest_highlight_y_offset or 0)
    local cx = pos.x

    local left_top = {cx - size, ui_y - size}
    local right_bottom = {cx + size, ui_y + size}

    if pdata.vis_chest_highlight then
        local obj = pdata.vis_chest_highlight
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            pdata.vis_chest_highlight = nil
        end
    end

    pdata.vis_chest_highlight = rendering.draw_rectangle {
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
function visuals.clear_all(pdata)
    if not pdata then
        return
    end

    visuals.clear_bot_health_bar(pdata)
    visuals.clear_bot_highlight(pdata)
    visuals.clear_chest_highlight(pdata)
    visuals.clear_lines(pdata)
    visuals.clear_damaged_markers(pdata)
    visuals.clear_destroyed_overlay(pdata)
end

return visuals

