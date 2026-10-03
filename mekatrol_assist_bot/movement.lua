-- Shared smooth scripted flight. Controllers provide destinations, never teleport directly.
local config = require("config")
local M = {}

-- A role can receive more than one scheduler work unit in the same game tick.
-- Keep movement calls composable without letting that extra work multiply the
-- bot's physical speed.
local movement_tick = -1
local distance_moved = {}

local function remaining_distance(entity)
    local tick = game.tick
    if tick ~= movement_tick then
        movement_tick = tick
        distance_moved = {}
    end
    local key = entity.unit_number or entity
    local moved = distance_moved[key] or 0
    return math.max(0, config.movement.step - moved), key, moved
end

function M.distance2(a, b)
    local x = a.x - b.x;
    local y = a.y - b.y;
    return x * x + y * y
end

function M.step(entity, target)
    if not entity or not entity.valid then
        return true
    end
    local p = entity.position;
    local dx = target.x - p.x;
    local dy = target.y - p.y;
    local d2 = dx * dx + dy * dy
    if d2 <= config.movement.arrival_distance ^ 2 then
        return true
    end
    local remaining, key, moved = remaining_distance(entity)
    if remaining == 0 then
        return false
    end
    local d = math.sqrt(d2);
    local n = math.min(remaining, d)
    local before = entity.position
    entity.teleport {
        x = p.x + dx / d * n,
        y = p.y + dy / d * n
    };
    local after = entity.position
    distance_moved[key] = moved + math.sqrt(M.distance2(before, after))
    return d - n <= config.movement.arrival_distance
end

return M
