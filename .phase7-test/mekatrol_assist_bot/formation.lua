-- Pure deterministic formation layout plus per-player direction tracking.
local config = require("config")
local M = {}

function M.slots(active, direction)
    direction = direction == -1 and -1 or 1
    local result = {};
    local per = config.formation.max_slots_per_column
    for i, name in ipairs(active) do
        local column = math.floor((i - 1) / per);
        local first = column * per + 1;
        local count = math.min(per, #active - first + 1);
        local row = i - first + 1
        result[name] = {
            x = -direction * (config.formation.side_distance + column * config.formation.column_spacing),
            y = (row - (count + 1) / 2) * config.formation.slot_spacing
        }
    end
    return result
end

---Return true when every role has a distinct slot.
function M.has_unique_slots(slots)
    local occupied = {}
    for _, slot in pairs(slots) do
        local key = string.format("%.9f:%.9f", slot.x, slot.y)
        if occupied[key] then
            return false
        end
        occupied[key] = true
    end
    return true
end

function M.update_direction(ps, pos)
    if ps.last_position then
        local dx = pos.x - ps.last_position.x
        if math.abs(dx) >= config.formation.direction_threshold then
            ps.direction = dx > 0 and 1 or -1
        end
    end
    ps.last_position = {
        x = pos.x,
        y = pos.y
    };
    return ps.direction
end

return M
