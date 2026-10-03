-- Pure deterministic polygon helpers used by survey groups and the check harness.
local M = {}

---Compute the unsigned area of a simple polygon with the shoelace formula.
---Each edge contributes `x_i*y_(i+1) - x_(i+1)*y_i`; the signed sum is twice
---the area. The modulo expression joins the final vertex back to vertex one.
function M.area(points)
    local sum = 0;
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1];
        sum = sum + a.x * b.y - b.x * a.y
    end
    return math.abs(sum) / 2
end

---Compute the total Euclidean length of the polygon's closed boundary.
---For every edge, Pythagoras gives `sqrt(dx^2 + dy^2)`. As in `area`, modulo
---closes the final edge without a special case.
function M.perimeter(points)
    local sum = 0;
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1];
        local x, y = a.x - b.x, a.y - b.y;
        sum = sum + math.sqrt(x * x + y * y)
    end
    return sum
end

---Return whether point `p` lies inside the polygon using an even/odd ray cast.
---Imagine a horizontal ray extending rightward from `p`. Every polygon edge
---which crosses that ray toggles inside/outside. The first condition ensures
---the edge straddles p's Y coordinate; the second calculates the edge's X at
---that Y by linear interpolation and checks that the crossing is right of p.
---Horizontal edges never satisfy the first condition, avoiding division by zero.
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
