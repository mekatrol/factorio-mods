local constructor_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")

local BOT_CONF = config.bot

function constructor_bot.init_state(player, ps, state)
    return {
        entity = nil,
        task = {
            target_position = nil,
            current_mode = "follow",
            next_mode = nil
        }
    }
end

function constructor_bot.update(player, ps, state, visual, tick)
    local bot_name = "constructor"
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
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, bot_name, bot)
end

return constructor_bot
