-- Pure deterministic polygon helpers used by survey groups and the check harness.
local M = {}

function M.area(points)
    local sum = 0;
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1];
        sum = sum + a.x * b.y - b.x * a.y
    end
    return math.abs(sum) / 2
end

function M.perimeter(points)
    local sum = 0;
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1];
        local x, y = a.x - b.x, a.y - b.y;
        sum = sum + math.sqrt(x * x + y * y)
    end
    return sum
end

function M.contains(points, p)
    local inside = false;
    local j = #points
    for i = 1, #points do
        local a, b = points[i], points[j];
        if ((a.y > p.y) ~= (b.y > p.y)) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

return M
