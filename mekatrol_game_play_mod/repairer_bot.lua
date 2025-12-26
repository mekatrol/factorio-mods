local repairer_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")

local BOT_CONF = config.bot
local BOT_NAME = "repairer"

function repairer_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)
end

function repairer_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function repairer_bot.update(player, ps, state, visual, tick)
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
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return repairer_bot
