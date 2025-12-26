-- move_to.lua
local move_to = {}

local config = require("config")
local positioning = require("positioning")
local util = require("util")

local BOT_CONF = config.bot

function move_to.update(player, ps, state, bot)
    if not (player and player.valid and ps and bot and bot.entity and bot.entity.valid) then
        return
    end

    local target_pos = bot.task.target_position

    if not target_pos then
        -- if there is no target position then we switch bot modes
        local mode = bot.task.next_mode or bot.task.current_mode

        -- We don't want an endless loop if target position is nil and mode is "move_to"
        if mode == "move_to" then
            util.print(player, "red", "Switching from 'move_to' to 'follow' mode to stop endless 'move_to' loop...")
            mode = "follow"
        end

        state.set_bot_task(player, ps, bot, mode)
        return
    end

    positioning.move_entity_towards(player, bot.entity, target_pos)

    -- auto-exit when reached (same threshold as search)
    local bp = bot.entity.position
    local dx = target_pos.x - bp.x
    local dy = target_pos.y - bp.y
    local step = BOT_CONF.movement.step_distance

    -- reached target, if so move to next mode
    if dx * dx + dy * dy <= step * step then
        local new_mode = bot.task.next_mode or "follow"
        state.set_bot_task(player, ps, bot, new_mode)
    end
end

return move_to
