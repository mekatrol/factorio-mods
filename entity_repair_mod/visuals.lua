local visuals = {}

---------------------------------------------------
-- DAMAGED ENTITY MARKERS (DOTS + LINES)
---------------------------------------------------
function visuals.clear_damaged_markers(pdata)
    if pdata.damaged_markers then
        for _, obj in pairs(pdata.damaged_markers) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.damaged_markers = nil
    end

    if pdata.damaged_lines then
        for _, obj in pairs(pdata.damaged_lines) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
        pdata.damaged_lines = nil
    end
end

function visuals.draw_damaged_visuals(bot, pdata, damaged_entities, bot_highlight_y_offset)
    if not damaged_entities or #damaged_entities == 0 then
        return
    end

    pdata.damaged_markers = pdata.damaged_markers or {}
    pdata.damaged_lines = pdata.damaged_lines or {}

    local y_offset = bot_highlight_y_offset or 0

    for _, ent in pairs(damaged_entities) do
        if ent and ent.valid then
            local dot = rendering.draw_circle {
                color = {
                    r = 0,
                    g = 1,
                    b = 0,
                    a = 1
                },
                radius = 0.15,
                filled = true,
                target = ent,
                surface = ent.surface,
                only_in_alt_mode = false
            }
            pdata.damaged_markers[#pdata.damaged_markers + 1] = dot

            local line = rendering.draw_line {
                color = {
                    r = 1,
                    g = 0,
                    b = 0,
                    a = 0.1
                },
                width = 1,
                from = ent,
                to = bot,
                to_offset = {0, y_offset},
                surface = ent.surface,
                only_in_alt_mode = false
            }
            pdata.damaged_lines[#pdata.damaged_lines + 1] = line
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

    if pdata.highlight_object then
        local obj = pdata.highlight_object
        if obj and obj.valid then
            obj.left_top = left_top
            obj.right_bottom = right_bottom
            return
        else
            pdata.highlight_object = nil
        end
    end

    pdata.highlight_object = rendering.draw_rectangle {
        color = {
            r = 0,
            g = 1,
            b = 1,
            a = 0.2
        },
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = bot.surface,
        only_in_alt_mode = false
    }
end

return visuals
