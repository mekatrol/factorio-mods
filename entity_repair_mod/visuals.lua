local visuals = {}

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

    local cy = pos.y + (bot_highlight_y_offset or 0)
    local cx = pos.x

    local left_top = {cx - size, cy - size * 1.5}
    local right_bottom = {cx + size, cy + size}

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

return visuals
