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
    ps.bots[BOT_NAME] = ps.bots[BOT_NAME] or {
        entity = nil,
        task = {
            target_position = nil,
            current_mode = "follow",
            next_mode = nil,
            search_spiral = nil,
            survey_entity = nil
        },
        visual = {
            highlight = nil,
            radius_circle = nil,
            lines = nil,
            light = nil
        }
    }
end

function mapper_bot.update(player, ps, state, visual, tick)
    local bot = state.get_bot_by_name(player, ps, BOT_NAME)
    local conf = BOT_CONF[BOT_NAME]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, ps, state, visual, BOT_NAME, bot, tick)

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

    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return mapper_bot
