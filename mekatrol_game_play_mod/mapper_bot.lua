local mapper_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local move_to = require("move_to")
local search = require("search")
local survey = require("survey")
local util = require("util")

local BOT_CONF = config.bot
local BOT_NAME = "mapper"
local BOT_MODES = config.modes

function mapper_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)

    ps.bots[BOT_NAME].task.search_spiral = ps.bots[BOT_NAME].task.search_spiral or nil
    ps.bots[BOT_NAME].task.survey_entity = ps.bots[BOT_NAME].task.survey_entity or nil
end

function mapper_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function mapper_bot.set_bot_task(player, ps, new_mode)
    local bot = ps.bots[BOT_NAME]

    -- Validate mode
    if not BOT_MODES.index[new_mode] then
        new_mode = "follow"
    end

    -- set the new current_mode
    bot.task.current_mode = new_mode

    -- Follow mode: no fixed target.
    if new_mode == "follow" then
        -- clear the next_mode and target position when switching modes
        bot.task.next_mode = nil
        bot.task.target_position = nil
        bot.search_spiral = nil
        bot.survey_entity = nil
        bot.next_survey_entities = {}
        return
    end

    if new_mode == "search" then
        bot.task.next_mode = "survey"
        return
    end

    if new_mode == "survey" then
        bot.task.next_mode = "search"
    end
end

function mapper_bot.toggle_mode(player, ps)
    local bot = ps.bots[BOT_NAME]

    -- default to search
    local new_mode = "search"

    -- if not in follow mode then set to follow mode
    if not (bot.task.current_mode == "follow") then
        new_mode = "follow"
    end

    mapper_bot.set_bot_task(player, ps, new_mode)
end

function mapper_bot.update(player, ps, state, visual, tick)
    local bot = ps.bots[BOT_NAME]
    local bot_conf = BOT_CONF[BOT_NAME]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, bot, bot_conf, tick)

    -- Mode behavior step
    if bot.task.current_mode == "follow" then
        follow.update(player, ps, state, bot, bot_conf.follow_offset_y)
    elseif bot.task.current_mode == "move_to" then
        move_to.update(player, ps, bot)
    elseif bot.task.current_mode == "search" then
        search.update(player, ps, state, bot)
    elseif bot.task.current_mode == "survey" then
        survey.update(player, ps, state, visual, bot, tick)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return mapper_bot
