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

function positioning.positions_squared_distance(pos1, pos2)
    -- Compute the difference in X coordinates between the two positions.
    -- A positive value means pos2 is to the right of pos1,
    -- a negative value means pos2 is to the left of pos1.
    local dx = pos2.x - pos1.x

    -- Compute the difference in Y coordinates between the two positions.
    -- A positive value means pos2 is above pos1,
    -- a negative value means pos2 is below pos1.
    local dy = pos2.y - pos1.y

    -- Compute the squared distance between the two positions.
    -- This uses dx² + dy², which avoids an expensive square-root operation
    -- while still allowing correct distance comparisons.
    local d2 = dx * dx + dy * dy

    return d2
end

function positioning.positions_are_close(pos1, pos2, max_distance)
    -- Maximum distance that is considered "close enough" for two positions
    -- to be treated as equal. If not specified then it comes from the bot movement configuration.
    local step = max_distance or BOT_CONF.movement.step_distance

    -- Compute the difference in X coordinates between the two positions.
    -- A positive value means pos2 is to the right of pos1,
    -- a negative value means pos2 is to the left of pos1.
    local dx = pos2.x - pos1.x

    -- Compute the difference in Y coordinates between the two positions.
    -- A positive value means pos2 is above pos1,
    -- a negative value means pos2 is below pos1.
    local dy = pos2.y - pos1.y

    -- Compute the squared distance between the two positions.
    -- This uses dx² + dy², which avoids an expensive square-root operation
    -- while still allowing correct distance comparisons.
    local d2 = dx * dx + dy * dy

    -- Check whether the squared distance between the positions is less than
    -- or equal to the squared step distance.
    -- If it is, the positions are close enough to be considered equal.
    if d2 <= step * step then
        return true
    end

    -- If the distance exceeds the allowed step distance,
    -- the positions are not considered equal.
    return false
end

function positioning.move_entity_towards(player, entity, target)
    if not (entity and entity.valid) then
        return
    end

    local pos, err = positioning.resolve_target_position(target)
    if not pos then
        util.print_player_or_game(player, "red", "invalid target: %s", err or "?")
        return
    end

    local step = BOT_CONF.movement.step_distance

    local epos = entity.position
    local dx = pos.x - epos.x
    local dy = pos.y - epos.y
    local d2 = dx * dx + dy * dy

    if d2 == 0 then
        return
    end

    local dist = math.sqrt(d2)
    if dist <= step then
        entity.teleport({pos.x, pos.y})
        return
    end

    entity.teleport({
        x = epos.x + dx / dist * step,
        y = epos.y + dy / dist * step
    })
end

return positioning