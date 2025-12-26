local mapper_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local move_to = require("move_to")
local search = require("search")
local survey = require("survey")

local BOT_CONF = config.bot
local BOT_NAME = "mapper"

function mapper_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)

    ps.bots[BOT_NAME].task.search_spiral = ps.bots[BOT_NAME].task.search_spiral or nil
    ps.bots[BOT_NAME].task.survey_entity = ps.bots[BOT_NAME].task.survey_entity or nil
end

function mapper_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function mapper_bot.update(player, ps, state, visual, tick)
    local bot = state.get_bot_by_name(player, ps, BOT_NAME)
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
        move_to.update(player, ps, state, bot)
    elseif bot.task.current_mode == "search" then
        search.update(player, ps, state, bot)
    elseif bot.task.current_mode == "survey" then
        survey.update(player, ps, bot, state, visual, tick)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return mapper_bot
