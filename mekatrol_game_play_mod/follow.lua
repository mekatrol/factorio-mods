local follow = {}

local config = require("configuration")
local mapping = require("mapping")

local BOT = config.bot

----------------------------------------------------------------------
-- Follow mode
----------------------------------------------------------------------

function follow.update(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local ppos = player.position
    local bpos = bot.position

    local prev = ps.last_player_position
    local left, right = false, false

    if prev then
        local dx = ppos.x - prev.x
        if dx < -0.1 then
            left = true
        elseif dx > 0.1 then
            right = true
        end
    end

    ps.last_player_position = {
        x = ppos.x,
        y = ppos.y
    }

    local side = BOT.movement.side_offset_distance
    local so = ps.last_player_side_offset_x or -side

    if left and so ~= side then
        so = side
    elseif right and so ~= -side then
        so = -side
    end

    ps.last_player_side_offset_x = so

    local follow = BOT.movement.follow_distance
    local dx = ppos.x - bpos.x
    local dy = ppos.y - bpos.y

    if dx * dx + dy * dy <= follow * follow then
        return
    end

    local target = {
        x = ppos.x + so,
        y = ppos.y - 2
    }

    mapping.move_bot_towards(player, bot, target)
end

return follow