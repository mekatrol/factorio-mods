local repairer_bot = {}

local common_bot = require("common_bot")
local config = require("config")
local follow = require("follow")
local module = require("module")
local move_to = require("move_to")
local util = require("util")

local BOT_CONF = config.bot
local BOT_NAME = "repairer"

local BOT_TASKS = {
    list = {"follow", "repair", "move_to"},
    index = {}
}

for i, task in ipairs(BOT_TASKS.list) do
    BOT_TASKS.index[task] = i
end

local function full_task_name(task_name)
    if task_name == "f" then
        return "follow"
    elseif task_name == "r" then
        return "repair"
    end

    return task_name
end

function repairer_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)
end

function repairer_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function repairer_bot.set_bot_task(player, ps, new_task, next_task, args)
    local bot = ps.bots[BOT_NAME]

    new_task = full_task_name(new_task)
    next_task = full_task_name(next_task)

    -- Validate task
    if not BOT_TASKS.index[new_task] then
        util.print(player, "red", "task '%s' not found for bot name: '%s'", new_task, bot.name)
        return
    end

    -- set the new current_task
    bot.task.current_task = new_task

    -- set new next_task
    bot.task.next_task = next_task

    if bot.task.current_task == "follow" then
        bot.task.target_position = nil
    end

    -- set args
    bot.task.args = args or bot.task.args or {}
end

function repairer_bot.get_queued_task(player, ps)
    return nil, nil
end

function repairer_bot.update(player, ps, tick)
    local bot = ps.bots[BOT_NAME]
    local bot_conf = BOT_CONF[BOT_NAME]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- perform updates common to all bots
    common_bot.update(player, bot, bot_conf, tick)

    -- Task behavior step
    if bot.task.current_task == "follow" then
        follow.update(player, ps, bot, bot_conf.follow_offset_y)
    elseif bot.task.current_task == "move_to" then
        move_to.update(player, ps, bot)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    local visual = module.get_module("visual")
    visual.draw_bot_light(player, ps, BOT_NAME, bot)
end

return repairer_bot
