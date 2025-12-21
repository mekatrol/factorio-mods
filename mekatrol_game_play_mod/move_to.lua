-- move_to.lua
local move_to = {}

local config = require("configuration")
local positioning = require("positioning")
local state = require("state")

local BOT = config.bot

function move_to.update(player, ps, bot)
    if not (player and player.valid and ps and bot and bot.valid) then
        return
    end

    local target = ps.bot_target_position
    if not target then
        return
    end

    positioning.move_bot_towards(player, bot, target)

    -- Optional: auto-exit when reached (same threshold as wander)
    local bp = bot.position
    local dx = target.x - bp.x
    local dy = target.y - bp.y
    local step = BOT.movement.step_distance
    if dx * dx + dy * dy <= step * step then
        ps.bot_target_position = nil
        state.set_player_bot_mode(player, ps, "survey")
    end
end

return move_to
