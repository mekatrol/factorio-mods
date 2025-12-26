local mapper_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local move_to = require("move_to")
local search = require("search")
local survey = require("survey")

local BOT_CONF = config.bot

function mapper_bot.init_state(player, ps, state)
    return {
        entity = nil,
        task = {
            target_position = nil,
            current_mode = "follow",
            next_mode = nil,
            search_spiral = nil,
            survey_entity = nil
        }
    }
end

function mapper_bot.update(player, ps, state, visual, tick)
    local bot_name = "mapper"
    local bot = state.get_bot_by_name(player, ps, bot_name)
    local conf = BOT_CONF[bot_name]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, ps, state, visual, bot_name, bot, tick)

    -- Mode behavior step
    if bot.task.current_mode == "follow" then
        follow.update(player, ps, state, bot, conf.follow_offset_y)
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

    visual.draw_bot_light(player, ps, bot_name, bot)
end

return mapper_bot
