local common_bot = {}

local config = require("config")
local util = require("util")

local BOT_CONF = config.bot

-------------------------------------------------------------------------------------------------------
-- This module contains code common to all bots in this mod
-------------------------------------------------------------------------------------------------------

function common_bot.get_modes(player, ps, state, visual, bot_name)
    local bot = state.get_bot_by_name(player, ps, bot_name)

    if not (bot and bot.task) then
        return nil, nil
    end

    return bot.task.current_mode, bot.task.next_mode
end

function common_bot.update(player, ps, state, visual, bot_name, bot, tick)
    -- Clear transient visual each update; they are redrawn below (mapper only).
    visual.clear_lines(ps, bot_name)
    visual.draw_bot_highlight(player, ps, bot_name)

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

    if bot.task.current_mode == "search" then
        radius = BOT_CONF.search.detection_radius
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif bot.task.current_mode == "survey" then
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
        visual.draw_radius_circle(player, ps, bot_name, bot, radius, radius_color)
    else
        visual.clear_radius_circle(ps, bot_name)
    end

    if target_pos then
        visual.draw_lines(player, ps, bot_name, bot, target_pos, line_color)
    end
end

return common_bot
