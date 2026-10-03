-- Shared smooth scripted flight. Controllers provide destinations, never teleport directly.
local config = require("config")
local M = {}

-- A role can receive more than one scheduler work unit in the same game tick.
-- Keep movement calls composable without letting that extra work multiply the
-- bot's physical speed.
local movement_tick = -1
local distance_moved = {}

---Return the distance this entity may still travel during the current tick.
---
---`config.movement.step` is a per-tick speed limit, but the scheduler can call
---a controller several times in one tick.  We therefore account for actual
---movement by entity rather than assuming one call equals one movement step.
---The cache is deliberately transient: LuaEntity references are unsuitable
---for persistent state, and the values have no meaning after the tick ends.
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

---Return the square of the Euclidean distance between two positions.
---
---For points `(x1,y1)` and `(x2,y2)`, this computes
---`(x1-x2)^2 + (y1-y2)^2`.  Comparing squared distances avoids a square root
---when the caller only needs to know which point is nearer or inside a radius.
function M.distance2(a, b)
    local x = a.x - b.x;
    local y = a.y - b.y;
    return x * x + y * y
end

---Move a valid scripted bot toward `target`, subject to its per-tick budget.
---@return boolean arrived True when the bot is already within the configured
---arrival radius, or this movement reaches that radius.
function M.step(entity, target)
    -- A missing bot has nothing left to move. Treating this as complete lets
    -- callers abandon stale work instead of waiting forever on an invalid entity.
    if not entity or not entity.valid then
        return true
    end
    local p = entity.position;
    local dx = target.x - p.x;
    local dy = target.y - p.y;
    -- Pythagoras without the square root: d^2 = dx^2 + dy^2.
    local d2 = dx * dx + dy * dy
    if d2 <= config.movement.arrival_distance ^ 2 then
        return true
    end
    local remaining, key, moved = remaining_distance(entity)
    if remaining == 0 then
        return false
    end
    local d = math.sqrt(d2);
    -- Never overshoot: travel either the remaining tick allowance or exactly
    -- the distance to the target, whichever is smaller.
    local n = math.min(remaining, d)
    local before = entity.position
    entity.teleport {
        -- `(dx/d, dy/d)` is the unit vector toward the target. Multiplying it
        -- by n produces a displacement of exactly n world units.
        x = p.x + dx / d * n,
        y = p.y + dy / d * n
    };
    local after = entity.position
    -- Factorio can adjust a teleport destination. Charge the measured
    -- displacement, not the requested displacement, against this tick.
    distance_moved[key] = moved + math.sqrt(M.distance2(before, after))
    return d - n <= config.movement.arrival_distance
end

return M
