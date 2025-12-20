local wander = {}

local config = require("configuration")
local mapping = require("mapping")
local state = require("state")

local BOT = config.bot

----------------------------------------------------------------------
-- Wander mode
----------------------------------------------------------------------

function wander.pick_new_wander_target(bpos)
    local angle = math.random() * 2 * math.pi
    local step = BOT.wander.step_distance
    local min_d = step * 0.4
    local max_d = step
    local dist = min_d + (max_d - min_d) * math.random()

    return {
        x = bpos.x + math.cos(angle) * dist,
        y = bpos.y + math.sin(angle) * dist
    }
end

function wander.update(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target = ps.bot_target_position

    if not target then
        target = wander.pick_new_wander_target(bot.position)
        ps.bot_target_position = target
    end

    mapping.move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local step = BOT.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.bot_target_position = nil

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.wander.detection_radius
    }

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char then
            state.set_player_bot_mode(player, ps, "survey")
            return
        end
    end
end

return wander
