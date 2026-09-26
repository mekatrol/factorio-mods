local config = require("config")
local constants = require("constants")
local movement = {}

function movement.distance_squared(a, b)
    -- Squared distance preserves ordering and threshold comparisons without
    -- paying for a square root during every target and container scan.
    local dx, dy = b.x - a.x, b.y - a.y
    return dx * dx + dy * dy
end

function movement.towards(entity, target)
    -- Entities can disappear between ticks, particularly when another mod or
    -- player mines them. Treat that normal race as no work instead of an error.
    if not (entity and entity.valid and target) then return end

    -- Work from the live entity position each tick so movement remains correct
    -- after teleports or other scripts reposition the visual bot.
    local pos = entity.position
    local dx, dy = target.x - pos.x, target.y - pos.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance == constants.EMPTY_COUNT then return end

    -- Capping the step avoids overshooting a nearby destination while retaining
    -- a consistent travel speed for distant destinations.
    local step = math.min(config.movement_step, distance)
    entity.teleport({x = pos.x + dx / distance * step, y = pos.y + dy / distance * step})
end

return movement
