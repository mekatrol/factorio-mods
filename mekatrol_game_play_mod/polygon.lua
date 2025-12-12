----------------------------------------------------------------------
-- polygon.lua
--
-- Convex hull utilities using Graham scan.
--
-- Expected point format:
--   { x = number, y = number }
--
-- Public API:
--   polygon.convex_hull(points) -> hull_points
--
-- Notes:
-- - Collinear points on edges are reduced to extreme endpoints.
-- - Input is not modified.
-- - Output hull is CCW, without repeating the first point at the end.
----------------------------------------------------------------------
local polygon = {}

----------------------------------------------------------------------
-- Basic geometry helpers
----------------------------------------------------------------------

local function cross(o, a, b)
    -- Cross product of OA x OB
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
end

local function dot(ax, ay, bx, by)
    return ax * bx + ay * by
end

local function dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function len2(x, y)
    return x * x + y * y
end

local function points_equal(a, b)
    return a.x == b.x and a.y == b.y
end

local function angle_ccw(prev_dir, from, to)
    -- prev_dir is a vector {x,y} indicating last edge direction
    local vx = to.x - from.x
    local vy = to.y - from.y

    local a1 = math.atan2(prev_dir.y, prev_dir.x)
    local a2 = math.atan2(vy, vx)

    local da = a2 - a1
    while da < 0 do
        da = da + 2 * math.pi
    end
    while da >= 2 * math.pi do
        da = da - 2 * math.pi
    end
    return da
end

local function angle_ccw(prev_dir, from, to)
    -- prev_dir is a vector {x,y} indicating last edge direction
    local vx = to.x - from.x
    local vy = to.y - from.y

    local a1 = math.atan2(prev_dir.y, prev_dir.x)
    local a2 = math.atan2(vy, vx)

    local da = a2 - a1
    while da < 0 do
        da = da + 2 * math.pi
    end
    while da >= 2 * math.pi do
        da = da - 2 * math.pi
    end
    return da
end

local function on_segment(a, b, p)
    return math.min(a.x, b.x) <= p.x and p.x <= math.max(a.x, b.x) and math.min(a.y, b.y) <= p.y and p.y <=
               math.max(a.y, b.y)
end

local function orient(a, b, c)
    local v = cross(a, b, c)
    if v > 0 then
        return 1
    end
    if v < 0 then
        return -1
    end
    return 0
end

local function segments_intersect(a, b, c, d)
    -- Proper + collinear intersections
    local o1 = orient(a, b, c)
    local o2 = orient(a, b, d)
    local o3 = orient(c, d, a)
    local o4 = orient(c, d, b)

    if o1 ~= o2 and o3 ~= o4 then
        return true
    end

    if o1 == 0 and on_segment(a, b, c) then
        return true
    end
    if o2 == 0 and on_segment(a, b, d) then
        return true
    end
    if o3 == 0 and on_segment(c, d, a) then
        return true
    end
    if o4 == 0 and on_segment(c, d, b) then
        return true
    end

    return false
end

local function would_self_intersect(hull, candidate)
    -- Check new segment (last -> candidate) against existing edges,
    -- ignoring adjacent edges sharing endpoints.
    local n = #hull
    if n < 3 then
        return false
    end

    local a = hull[n]
    local b = candidate

    -- compare against edges (hull[i] -> hull[i+1]) for i = 1..n-2
    for i = 1, n - 2 do
        local c = hull[i]
        local d = hull[i + 1]
        if segments_intersect(a, b, c, d) then
            return true
        end
    end

    return false
end

local function all_points_inside_or_on(hull, points)
    -- Ray casting for point-in-polygon (treat boundary as inside).
    local function point_in_poly(poly, p)
        local inside = false
        local n = #poly
        local j = n
        for i = 1, n do
            local a = poly[i]
            local b = poly[j]

            -- boundary check via collinearity + bounding
            if orient(a, b, p) == 0 and on_segment(a, b, p) then
                return true
            end

            local intersect = ((a.y > p.y) ~= (b.y > p.y)) and
                                  (p.x < (b.x - a.x) * (p.y - a.y) / ((b.y - a.y) ~= 0 and (b.y - a.y) or 1e-12) + a.x)
            if intersect then
                inside = not inside
            end
            j = i
        end
        return inside
    end

    for i = 1, #points do
        if not point_in_poly(hull, points[i]) then
            return false
        end
    end
    return true
end

local function dedupe_points(points)
    -- Exact dedupe (works well if you already quantize positions).
    local seen = {}
    local out = {}
    for i = 1, #points do
        local p = points[i]
        local k = tostring(p.x) .. "," .. tostring(p.y)
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = {
                x = p.x,
                y = p.y
            }
        end
    end
    return out
end

local function k_nearest(points, from, k, used)
    local arr = {}
    for i = 1, #points do
        local p = points[i]
        if not used[i] and not points_equal(p, from) then
            arr[#arr + 1] = {
                idx = i,
                d2 = dist2(from, p)
            }
        end
    end

    table.sort(arr, function(a, b)
        if a.d2 == b.d2 then
            return a.idx < b.idx
        end
        return a.d2 < b.d2
    end)

    local out = {}
    local lim = math.min(k, #arr)
    for i = 1, lim do
        out[#out + 1] = points[arr[i].idx]
    end
    return out
end

local function lowest_point(points)
    local idx = 1
    for i = 2, #points do
        local p = points[i]
        local q = points[idx]
        if p.y < q.y or (p.y == q.y and p.x < q.x) then
            idx = i
        end
    end
    return idx
end

----------------------------------------------------------------------
-- Concave hull (k-nearest neighbors)
--
-- polygon.concave_hull(points, k, opts) -> hull_points
--
-- points: array of {x=, y=}
-- k: integer >= 3 (higher = smoother/more convex; lower = more concave)
-- opts (optional):
--   opts.max_k = cap for k escalation (default: min(25, #points))
--
-- Returns:
--   hull as CCW point list, no repeated first point at end.
--   If it cannot form a valid concave hull, it falls back to convex_hull(points).
----------------------------------------------------------------------
function polygon.concave_hull(points, k, opts)
    opts = opts or {}
    local pts = dedupe_points(points)
    local n = #pts

    if n < 3 then
        return pts
    end

    local max_k = opts.max_k or math.min(25, n)
    if k == nil then
        k = 3
    end
    if k < 3 then
        k = 3
    end
    if k > n then
        k = n
    end

    -- Attempt with increasing k if needed
    for kk = k, max_k do
        local used = {}
        local start_idx = lowest_point(pts)
        local start = pts[start_idx]
        used[start_idx] = true

        local hull = {start}

        -- Initial direction: pointing to the left (west) so first turn is “upwards”
        local prev_dir = {
            x = -1,
            y = 0
        }
        local current = start

        local guard = 0
        while guard < 10000 do
            guard = guard + 1

            local candidates = k_nearest(pts, current, kk, used)
            if #candidates == 0 then
                break
            end

            -- Sort candidates by smallest CCW turn from prev_dir; tiebreak by distance
            table.sort(candidates, function(a, b)
                local aa = angle_ccw(prev_dir, current, a)
                local ab = angle_ccw(prev_dir, current, b)
                if aa == ab then
                    return dist2(current, a) < dist2(current, b)
                end
                return aa < ab
            end)

            local next = nil
            for i = 1, #candidates do
                local cand = candidates[i]

                -- Allow closing back to start only if hull is long enough
                local closing = (#hull >= 3 and points_equal(cand, start))

                if closing then
                    -- Check closing segment against hull edges
                    local intersects = false
                    local a = hull[#hull]
                    local b = start
                    for e = 1, #hull - 2 do
                        local c = hull[e]
                        local d = hull[e + 1]
                        if segments_intersect(a, b, c, d) then
                            intersects = true
                            break
                        end
                    end
                    if not intersects then
                        next = start
                        break
                    end
                else
                    if not would_self_intersect(hull, cand) then
                        next = cand
                        break
                    end
                end
            end

            if not next then
                break
            end

            if points_equal(next, start) then
                -- closed
                break
            end

            -- Mark used
            for i = 1, n do
                if pts[i] == next then
                    used[i] = true
                    break
                end
            end

            -- advance
            prev_dir = {
                x = next.x - current.x,
                y = next.y - current.y
            }
            current = next
            hull[#hull + 1] = next

            if #hull >= n then
                break
            end
        end

        if #hull >= 3 then
            -- Validate hull contains all points (or at least doesn't exclude them)
            if all_points_inside_or_on(hull, pts) then
                return hull
            end
        end
    end

    -- Fallback
    return polygon.convex_hull(points)
end

----------------------------------------------------------------------
-- Graham scan
----------------------------------------------------------------------

function polygon.convex_hull(points)
    local n = #points
    if n < 3 then
        -- Degenerate cases: return copy
        local out = {}
        for i = 1, n do
            out[i] = {
                x = points[i].x,
                y = points[i].y
            }
        end
        return out
    end

    -- Copy points so we do not mutate caller data
    local pts = {}
    for i = 1, n do
        pts[i] = {
            x = points[i].x,
            y = points[i].y
        }
    end

    -- 1. Find pivot (lowest Y, then lowest X)
    local pivot_idx = lowest_point(pts)
    pts[1], pts[pivot_idx] = pts[pivot_idx], pts[1]
    local pivot = pts[1]

    -- 2. Sort by polar angle around pivot
    table.sort(pts, function(a, b)
        if a == pivot then
            return true
        end
        if b == pivot then
            return false
        end

        local c = cross(pivot, a, b)
        if c == 0 then
            -- Collinear: closer one first
            return dist2(pivot, a) < dist2(pivot, b)
        end
        return c > 0
    end)

    -- 3. Remove intermediate collinear points
    local filtered = {pts[1]}
    for i = 2, n do
        while #filtered >= 2 do
            local last = filtered[#filtered]
            local prev = filtered[#filtered - 1]
            if cross(prev, last, pts[i]) ~= 0 then
                break
            end
            -- Keep the farthest point
            if dist2(prev, pts[i]) > dist2(prev, last) then
                filtered[#filtered] = pts[i]
            end
            goto continue
        end
        filtered[#filtered + 1] = pts[i]
        ::continue::
    end

    if #filtered < 3 then
        return filtered
    end

    -- 4. Build hull stack
    local hull = {filtered[1], filtered[2], filtered[3]}

    for i = 4, #filtered do
        while #hull >= 2 do
            local top = hull[#hull]
            local next_to_top = hull[#hull - 1]
            if cross(next_to_top, top, filtered[i]) > 0 then
                break
            end
            table.remove(hull)
        end
        hull[#hull + 1] = filtered[i]
    end

    return hull
end

return polygon
