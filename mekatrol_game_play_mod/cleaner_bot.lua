local cleaner_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local util = require("util")

local BOT_CONF = config.bot
local BOT_NAME = "cleaner"

local BOT_TASKS = {
    list = {"follow", "clean", "move_to"},
    index = {}
}

for i, task in ipairs(BOT_TASKS.list) do
    BOT_TASKS.index[task] = i
end

function cleaner_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)
end

function cleaner_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function cleaner_bot.set_bot_task(player, ps, new_task)
    local bot = ps.bots[BOT_NAME]

    -- Validate task
    if not BOT_TASKS.index[new_task] then
        util.print(player, "red", "task '%s' not found for bot name: '%s'", bot.name)
        return
    end

    -- set the new current_task
    bot.task.current_task = new_task
end

function cleaner_bot.update(player, ps, state, visual, tick)
    local bot = ps.bots[BOT_NAME]
    local bot_conf = BOT_CONF[BOT_NAME]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, bot, bot_conf, tick)

    -- Task behavior step
    if bot.task.current_task == "follow" then
        follow.update(player, ps, state, bot, bot_conf.follow_offset_y)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return cleaner_bot
