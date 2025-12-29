local common_bot = {}

local config = require("config")
local module = require("module")
local util = require("util")

local BOT_CONF = config.bot
local BOT_NAMES = config.bot_names

-------------------------------------------------------------------------------------------------------
-- This module contains code common to all bots in this mod
-------------------------------------------------------------------------------------------------------

function common_bot.get_tasks(player, ps, state, visual, bot_name)
    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not (bot and bot.task) then
        return nil, nil
    end

    local other = nil

    if bot_name == "logistics" and bot.task.pickup_name then
        other = string.format(" [%s: %s]", bot.task.pickup_name, bot.task.pickup_remaining)
    elseif bot_name == "mapper" then
        local search_for_list = util.get_value(bot.task.args, "search_list")
        local search_next = "no search"

        if #search_for_list > 0 then
            search_next = search_for_list[1]
        end

        other = string.format(" [%s:%s]", bot.task.search_name or "no search", search_next)
    end

    return bot.task.current_task, bot.task.next_task, other
end

function common_bot.init_state(player, ps, bot_name, init_task)
    if not init_task then
        init_task = "follow"
    end

    ps.bots[bot_name] = ps.bots[bot_name] or {
        name = bot_name,
        entity = nil,
        task = {
            target_position = nil,
            current_task = init_task,
            next_task = nil,
            args = {}
        },
        visual = {
            highlight = nil,
            circle = nil,
            lines = nil,
            light = nil
        }
    }
end

function common_bot.destroy_state(player, ps, bot_name)
    local bot = ps.bots[bot_name]

    if not bot then
        -- probably already destroyed or did not exist
        return
    end

    common_bot.clear_lines(bot)
    common_bot.clear_highlight(bot)
    common_bot.clear_circle(bot)
    common_bot.clear_light(bot)

    if bot and bot.entity and bot.entity.valid then
        bot.entity.destroy()
    end

    ps.bots[bot_name] = nil
end

function common_bot.update(player, bot, bot_conf, tick)
    common_bot.draw_highlight(player, bot, bot_conf)
    common_bot.draw_bot_light(player, bot)

    local radius = nil
    local radius_color = nil

    -- default to targetting player
    local target_pos = player.position

    if not (bot and bot.task) then
        util.print(player, "red", "bot or task not set")
        return
    end

    -- change to target position if defined
    if bot.task.target_position then
        target_pos = bot.task.target_position
    end

    local line_color = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.1
    }

    if bot.task.current_task == "search" then
        radius = BOT_CONF.search.detection_radius
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif bot.task.current_task == "survey" then
        radius = BOT_CONF.survey.radius
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color
    end

    if radius and radius > 0 then
        common_bot.draw_circle(player, bot, radius, radius_color)
    else
        common_bot.clear_circle(bot)
    end

    common_bot.clear_lines(bot)
    if target_pos then
        common_bot.draw_line(player, bot, bot.entity.position, target_pos, line_color)
    end
end

local function issue_task(player, ps, bot_name, new_task, next_task, args)
    local bot_module = module.get_module(bot_name)

    if not bot_module then
        util.print(player, "red", "bot module not found for bot name: %s", bot_name)
        return
    end

    bot_module.set_bot_task(player, ps, new_task, next_task, args)
end

function common_bot.issue_task(player, ps, bot_name, new_task, next_task, args)
    if bot_name == "all" then
        for _, name in ipairs(BOT_NAMES) do
            issue_task(player, ps, name, new_task, next_task, args)
        end
    else
        issue_task(player, ps, bot_name, new_task, next_task, args)
    end
end

function common_bot.clear_light(bot)
    if not bot then
        return
    end

    local obj = bot.light

    if obj and obj.valid then
        obj:destroy()
    end

    bot.light = nil
end

function common_bot.clear_circle(bot)
    if not bot then
        return
    end

    local obj = bot.visual.circle

    if obj and obj.valid then
        obj:destroy()
    end

    bot.visual.circle = nil
end

function common_bot.clear_highlight(bot)
    if not bot then
        return
    end

    local obj = bot.visual.highlight

    if obj and obj.valid then
        obj:destroy()
    end

    bot.visual.highlight = nil
end

function common_bot.clear_lines(bot)
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

function common_bot.draw_bot_light(player, bot)
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
        surface = bot.entity.surface,
        players = {player.index}
    }
end

function common_bot.draw_circle(player, bot, radius, color)
    if not (player and player.valid and bot and bot.entity and bot.entity.valid and radius) then
        return
    end

    bot.visual = bot.visual or {}

    local circle = bot.visual.circle

    -- Factorio 2: rendering.draw_circle returns a LuaRenderObject.
    -- Recreate only if missing or invalid.
    if not (circle and circle.valid) then
        -- Keep this if your clear_circle destroys any other render objects for the bot.
        common_bot.clear_circle(bot)

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
        return
    end

    -- Update existing object (no recreate)
    circle.target = bot.entity
    circle.radius = radius
    if color then
        circle.color = color
    end
    circle.players = {player.index}
end

function common_bot.draw_highlight(player, bot, bot_conf)
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

function common_bot.draw_line(player, bot, a, b, color, width)
    if not (player and player.valid) then
        return nil
    end

    local id = rendering.draw_line {
        surface = bot.entity.surface,
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

    local lines = bot.visual.lines or {}
    lines[#lines + 1] = id
    bot.visual.lines = lines
end

return common_bot
