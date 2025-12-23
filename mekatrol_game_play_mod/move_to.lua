-- move_to.lua
local move_to = {}

local config = require("configuration")
local positioning = require("positioning")
local state = require("state")
local util = require("util")

local BOT = config.bot

function move_to.update(player, ps, bot)
    if not (player and player.valid and ps and bot and bot.valid) then
        return
    end

    local target_pos = ps.task.target_position
    if not target_pos then
        -- if there is no target position then we switch bot modes
        local mode = ps.task.next_mode or ps.task.current_mode

        -- We don't want an endless loop if target position is nil and mode is "move_to"
        if mode == "move_to" then
            util.print(player, "red", "Switching from 'move_to' to 'follow' mode to stop endless 'move_to' loop...")
            mode = "follow"
        end

        state.set_player_bot_task(player, ps, mode)
        return
    end

    positioning.move_bot_towards(player, bot, target_pos)

    -- auto-exit when reached (same threshold as search)
    local bp = bot.position
    local dx = target_pos.x - bp.x
    local dy = target_pos.y - bp.y
    local step = BOT.movement.step_distance

    -- reached target, if so move to next mode
    if dx * dx + dy * dy <= step * step then
        local new_mode = ps.task.next_mode or "follow"        
        state.set_player_bot_task(player, ps, new_mode)
    end
end

return move_to
