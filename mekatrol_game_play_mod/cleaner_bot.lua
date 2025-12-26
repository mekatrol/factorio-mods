local cleaner_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local state = require("state")
local visual = require("visual")

local BOT_CONF = config.bot

function cleaner_bot.update(player, ps, tick)
    local bot_name = "cleaner"
    local bot = state.get_bot_by_name(player, ps, bot_name)
    local conf = BOT_CONF[bot_name]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, ps, bot_name, bot, tick)

    -- Mode behavior step
    if bot.task.current_mode == "follow" then
        follow.update(player, ps, bot, conf.follow_offset_y)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, bot_name, bot)
end

return cleaner_bot
