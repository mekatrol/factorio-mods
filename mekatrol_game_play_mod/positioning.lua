local positioning = {}

local config = require("config")
local util = require("util")

local BOT_CONF = config.bot

----------------------------------------------------------------------
-- Movement and position helpers
----------------------------------------------------------------------

function positioning.resolve_target_position(target)
    if type(target) == "table" then
        if target.position then
            return target.position, nil
        elseif target.x and target.y then
            return target, nil
        elseif target[1] and target[2] then
            return {
                x = target[1],
                y = target[2]
            }, nil
        end
    end

    return nil, tostring(target)
end

function positioning.move_bot_towards(player, bot, target)
    if not (bot and bot.valid) then
        return
    end

    local pos, err = positioning.resolve_target_position(target)
    if not pos then
        util.print(player, "red", "invalid target: %s", err or "?")
        return
    end

    local step = BOT_CONF.movement.step_distance

    local bp = bot.position
    local dx = pos.x - bp.x
    local dy = pos.y - bp.y
    local d2 = dx * dx + dy * dy

    if d2 == 0 then
        return
    end

    local dist = math.sqrt(d2)
    if dist <= step then
        bot.teleport({pos.x, pos.y})
        return
    end

    bot.teleport({
        x = bp.x + dx / dist * step,
        y = bp.y + dy / dist * step
    })
end

return positioning