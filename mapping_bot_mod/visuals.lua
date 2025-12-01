local visuals = {}

---------------------------------------------------
-- Helper to safely destroy a rendering object
---------------------------------------------------
local function destroy_render_handle(handle)
    if not handle then
        return
    end

    local t = type(handle)

    -- If it's a numeric id (normal case)
    if t == "number" then
        local ok, obj = pcall(rendering.get_object_by_id, handle)
        if ok and obj and obj.valid then
            obj.destroy()
        end
        return
    end

    -- If it's a rendering object/userdata from previous code
    if (t == "userdata" or t == "table") and handle.destroy then
        if handle.valid ~= false then
            handle:destroy()
        end
    end
end

---------------------------------------------------
-- BOT HEALTH BAR
-- Call this every tick (or at your bot update interval)
-- max_health: either a constant or passed in from your get_entity_max_health(bot)
---------------------------------------------------
function visuals.update_bot_health_bar(bot, pdata, max_health, bot_highlight_y_offset)
    if not (bot and bot.valid and max_health and max_health > 0) then
        -- Cleanup if bot missing
        destroy_render_handle(pdata.bot_health_bg)
        destroy_render_handle(pdata.bot_health_fg)
        destroy_render_handle(pdata.bot_health_text)
        pdata.bot_health_bg = nil
        pdata.bot_health_fg = nil
        pdata.bot_health_text = nil
        return
    end

    local health = bot.health or max_health
    local ratio = math.max(0, math.min(1, health / max_health))

    local pos = bot.position
    local y_offset = bot_highlight_y_offset or 0

    -- Position/size for the bar (just below the bot)
    local bar_width = 0.8
    local bar_height = 0.10
    local bar_y_off = 0.6 -- vertical offset below bot

    local x1 = pos.x - bar_width / 2
    local x2 = pos.x + bar_width / 2
    local y1 = pos.y + bar_y_off + y_offset
    local y2 = y1 + bar_height

    local fg_x2 = x1 + bar_width * ratio

    -------------------------------------------------------
    -- Background rectangle
    -------------------------------------------------------
    if pdata.bot_health_bg and pdata.bot_health_bg.valid then
        pdata.bot_health_bg.left_top = {x1, y1}
        pdata.bot_health_bg.right_bottom = {x2, y2}
    else
        pdata.bot_health_bg = rendering.draw_rectangle {
            color = {
                r = 0,
                g = 0,
                b = 0,
                a = 0.7
            }, -- dark background
            filled = true,
            left_top = {x1, y1},
            right_bottom = {x2, y2},
            surface = bot.surface,
            draw_on_ground = true,
            only_in_alt_mode = false
        }
    end

    -------------------------------------------------------
    -- Foreground (current health) rectangle
    -------------------------------------------------------
    if pdata.bot_health_fg and pdata.bot_health_fg.valid then
        pdata.bot_health_fg.left_top = {x1, y1}
        pdata.bot_health_fg.right_bottom = {fg_x2, y2}
    else
        pdata.bot_health_fg = rendering.draw_rectangle {
            color = {
                r = 0,
                g = 1,
                b = 0,
                a = 0.9
            }, -- green bar
            filled = true,
            left_top = {x1, y1},
            right_bottom = {fg_x2, y2},
            surface = bot.surface,
            draw_on_ground = true,
            only_in_alt_mode = false
        }
    end

    -------------------------------------------------------
    -- Text (e.g. "75/100") just below the bar
    -------------------------------------------------------
    local text_y_off = 0.8
    local text_pos = {
        x = pos.x,
        y = pos.y + text_y_off + y_offset
    }

    local text_value = string.format("%.0f/%.0f", health, max_health)

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

---------------------------------------------------
-- BOT / PLAYER LINES
---------------------------------------------------
function visuals.clear_lines(pdata)
    if pdata.vis_lines then
        for _, obj in pairs(pdata.vis_lines) do
            destroy_render_handle(obj)
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
-- Green box around mapped entities
---------------------------------------------------
function visuals.add_mapped_entity_box(player, pdata, entity)
    if not (entity and entity.valid) then
        return nil
    end

    local box = entity.selection_box or entity.bounding_box
    if not box then
        return nil
    end

    local id = rendering.draw_rectangle {
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

    return id
end

---------------------------------------------------
-- Bright-blue search radius circle around the bot
---------------------------------------------------
function visuals.update_search_radius_circle(player, pdata, bot, radius)
    -- Destroy old circle if it exists (handles both id and object)
    if pdata.vis_search_radius_circle then
        destroy_render_handle(pdata.vis_search_radius_circle)
        pdata.vis_search_radius_circle = nil
    end

    if not (bot and bot.valid) then
        return
    end

    -- Draw a new bright-blue circle, anchored to the bot
    local id = rendering.draw_circle {
        color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }, -- bright blue
        radius = radius,
        width = 4,
        filled = false,
        target = bot, -- anchor so it follows the bot
        surface = bot.surface,
        players = {player},
        draw_on_ground = true
    }

    -- Store the numeric id
    pdata.vis_search_radius_circle = id
end

function visuals.clear_search_radius_circle(pdata)
    if pdata.vis_search_radius_circle then
        destroy_render_handle(pdata.vis_search_radius_circle)
        pdata.vis_search_radius_circle = nil
    end
end

return visuals
