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

local BOT_TASKS = {
    list = {"follow", "search", "survey", "move_to"},
    index = {}
}

for i, task in ipairs(BOT_TASKS.list) do
    BOT_TASKS.index[task] = i
end

local function full_task_name(task_name)
    if task_name == "f" then
        return "follow"
    elseif task_name == "s" then
        return "search"
    end

    return task_name
end

function mapper_bot.init_state(player, ps)
    common_bot.init_state(player, ps, BOT_NAME)

    local bot = ps.bots[BOT_NAME]

    bot.task.search_spiral = bot.task.search_spiral or nil
    bot.task.survey_entity = bot.task.survey_entity or nil
    bot.task.next_survey_entities = bot.task.next_survey_entities or {}
end

function mapper_bot.destroy_state(player, ps)
    common_bot.destroy_state(player, ps, BOT_NAME)
end

function mapper_bot.set_bot_task(player, ps, new_task, next_task, args)
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

    -- Follow task: no fixed target.
    if new_task == "follow" then
        -- clear the next_task and target position when switching tasks
        bot.task.next_task = nil
        bot.task.target_position = nil
        bot.task.search_spiral = nil
        bot.task.survey_entity = nil
        bot.task.next_survey_entities = {}
        return
    end

    if new_task == "search" then
        bot.task.next_task = "survey"
        return
    end

    if new_task == "survey" then
        bot.task.next_task = "search"
    end

    -- set new next_task
    bot.task.next_task = next_task

    -- set args
    bot.task.args = args or bot.task.args or {}
end

function mapper_bot.toggle_task(player, ps)
    local bot = ps.bots[BOT_NAME]

    -- default to search
    local new_task = "search"

    -- if not in follow task then set to follow task
    if not (bot.task.current_task == "follow") then
        new_task = "follow"
    end

    mapper_bot.set_bot_task(player, ps, new_task, nil, bot.task.args)
end

function mapper_bot.get_queued_task(player, ps)
    return nil, nil
end

function mapper_bot.update(player, ps, state, visual, tick)
    local bot = ps.bots[BOT_NAME]
    local bot_conf = BOT_CONF[BOT_NAME]

    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    -- are we ini init phase?
    if ps.game_phase == "init" and bot.task.current_task ~= "search" then
        mapper_bot.set_bot_task(player, ps, "search", nil, {
            -- set the list of items to search for and in the order we want to search
            ["search_list"] = {"crash-site", "coal", "iron-ore"}
        })

        -- no game phase next
        -- ps.game_phase = nil
    end

    -- perform updates common to all bots
    common_bot.update(player, bot, bot_conf, tick)

    -- Task behavior step
    if bot.task.current_task == "follow" then
        follow.update(player, ps, state, bot, bot_conf.follow_offset_y)
    elseif bot.task.current_task == "move_to" then
        move_to.update(player, ps, bot)
    elseif bot.task.current_task == "search" then
        search.update(player, ps, state, bot)
    elseif bot.task.current_task == "survey" then
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
