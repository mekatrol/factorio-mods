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
    if pdata.vis_highlight_object and pdata.vis_highlight_object.valid then
        pdata.vis_highlight_object:destroy()
    end
    pdata.vis_highlight_object = nil
end

-- Call this every tick (or at your bot update interval)
-- max_health: either a constant or passed in from your get_entity_max_health(bot)
function visuals.update_bot_health_bar(player, bot, pdata, max_health, bot_highlight_y_offset, repair_tool_name)
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

    local player_packs_available = inv.get_item_count(repair_tool_name)

    local chest_packs_available = 0
    local chest = pdata.repair_chest

    if chest and chest.valid and chest.name == "iron-chest" then
        -- Get chest inventory
        local inv = chest.get_inventory(defines.inventory.chest)

        -- Is inventory valid?
        if (inv and inv.valid) then

            -- Get available repair pack items count
            chest_packs_available = inv.get_item_count(repair_tool_name)
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

    local line = rendering.draw_line {
        color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        },
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

    if pdata.vis_highlight_object then
        local obj = pdata.vis_highlight_object
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            pdata.vis_highlight_object = nil
        end
    end

    pdata.vis_highlight_object = rendering.draw_rectangle {
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

-- Master “clear everything” helper:
function visuals.clear_all(pdata)
    if not pdata then
        return
    end

    visuals.clear_bot_health_bar(pdata)
    visuals.clear_bot_highlight(pdata)
    visuals.clear_lines(pdata)
    visuals.clear_damaged_markers(pdata)
end

return visuals

