-- move_to.lua
local move_to = {}

local config = require("config")
local module = require("module")
local positioning = require("positioning")
local util = require("util")

local BOT_CONF = config.bot

function move_to.update(player, ps, bot)
    if not (player and player.valid and ps and bot and bot.entity and bot.entity.valid) then
        return
    end

    local bot_module = module.get_module(bot.name)

    local target_pos = bot.task.target_position

    if not target_pos then
        -- if there is no target position then we switch bot tasks
        local task = bot.task.next_task or bot.task.current_task

        -- We don't want an endless loop if target position is nil and task is "move_to"
        if task == "move_to" then
            util.print(player, "red",
                "Switching bot '%s' from 'move_to' to 'follow' task to stop endless 'move_to' loop...", bot.name)
            task = "follow"
        end

        bot_module.set_bot_task(player, ps, task, nil, bot.task.args)
        return
    end

    positioning.move_entity_towards(player, bot.entity, target_pos)
    local bpos = bot.entity.position

    if positioning.positions_are_close(target_pos, bpos) then
        local new_task = bot.task.next_task or "follow"
        bot_module.set_bot_task(player, ps, new_task, nil, bot.task.args)
    end
end

return move_to
