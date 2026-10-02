-- Shared smooth scripted flight. Controllers provide destinations, never teleport directly.
local config = require("config")
local M = {}

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
    local d = math.sqrt(d2);
    local n = math.min(config.movement.step, d)
    entity.teleport {
        x = p.x + dx / d * n,
        y = p.y + dy / d * n
    };
    return d - n <= config.movement.arrival_distance
end

return M
