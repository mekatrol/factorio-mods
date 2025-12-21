----------------------------------------------------------------------
-- polygon.lua
--
-- Geometry utilities:
--   - Convex hull (Graham scan)
--   - Concave hull (k-nearest neighbors heuristic)
--   - Incremental concave hull job (state machine) so long hull builds
--     can be spread over multiple ticks without freezing the game.
--
-- Point format:
--   { x = number, y = number }
--
-- Public API:
--   polygon.convex_hull(points) -> hull_points
--   polygon.concave_hull(points, k, opts) -> hull_points
--   polygon.start_concave_hull_job(points, k, opts) -> job
--   polygon.step_concave_hull_job(job, step_budget) -> done, hull_or_nil
--
-- Notes:
-- - Hull outputs are CCW point lists, WITHOUT repeating the first point at end.
-- - Functions copy input points where needed to avoid mutating caller data.
----------------------------------------------------------------------
local polygon = {}

local util = require("util")

----------------------------------------------------------------------
-- Basic vector/geometry helpers
----------------------------------------------------------------------

function polygon.cross(o, a, b)
    -- Cross product (OA x OB). Sign indicates orientation.
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
end

function polygon.dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

function polygon.points_equal(a, b)
    return a.x == b.x and a.y == b.y
end

function polygon.on_segment(a, b, p)
    return math.min(a.x, b.x) <= p.x and p.x <= math.max(a.x, b.x) and math.min(a.y, b.y) <= p.y and p.y <=
               math.max(a.y, b.y)
end

function polygon.orient(a, b, c)
    -- Returns:
    --   1  if a->b->c is CCW turn
    --  -1  if CW turn
    --   0  if collinear
    local v = polygon.cross(a, b, c)
    if v > 0 then
        return 1
    end
    if v < 0 then
        return -1
    end
    return 0
end

function polygon.segments_intersect(a, b, c, d)
    -- Proper + collinear intersections.
    local o1 = polygon.orient(a, b, c)
    local o2 = polygon.orient(a, b, d)
    local o3 = polygon.orient(c, d, a)
    local o4 = polygon.orient(c, d, b)

    if o1 ~= o2 and o3 ~= o4 then
        return true
    end

    if o1 == 0 and polygon.on_segment(a, b, c) then
        return true
    end
    if o2 == 0 and polygon.on_segment(a, b, d) then
        return true
    end
    if o3 == 0 and polygon.on_segment(c, d, a) then
        return true
    end
    if o4 == 0 and polygon.on_segment(c, d, b) then
        return true
    end

    return false
end

----------------------------------------------------------------------
-- Self-intersection check (endpoint-safe)
----------------------------------------------------------------------

local function shares_endpoint(a, b, c, d)
    return polygon.points_equal(a, c) or polygon.points_equal(a, d) or polygon.points_equal(b, c) or
               polygon.points_equal(b, d)
end

function polygon.would_self_intersect(hull, candidate)
    -- Checks whether adding segment (last hull point -> candidate)
    -- would intersect any existing hull edge excluding adjacent edges.
    local n = #hull
    if n < 3 then
        return false
    end

    local a = hull[n]
    local b = candidate

    for i = 1, n - 2 do
        local c = hull[i]
        local d = hull[i + 1]

        -- ignore shared endpoints so touching is not treated as intersection
        if not shares_endpoint(a, b, c, d) then
            if polygon.segments_intersect(a, b, c, d) then
                return true
            end
        end
    end

    return false
end

function polygon.angle_ccw(prev_dir, from, to)
    -- Returns CCW turn angle [0, 2pi) from prev_dir to vector from->to.
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

----------------------------------------------------------------------
-- Shared polygon membership test (boundary counts as inside)
----------------------------------------------------------------------

function polygon.point_in_poly(poly, p)
    -- Ray casting. Boundary is treated as inside.
    local inside = false
    local n = #poly
    local j = n

    for i = 1, n do
        local a = poly[i]
        local b = poly[j]

        -- Boundary check.
        if polygon.orient(a, b, p) == 0 and polygon.on_segment(a, b, p) then
            return true
        end

        local denom = (b.y - a.y)
        if denom == 0 then
            denom = 1e-12
        end

        local intersect = ((a.y > p.y) ~= (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / denom + a.x)

        if intersect then
            inside = not inside
        end
        
        j = i
    end

    return inside
end

function polygon.all_points_inside_or_on(hull, points)
    for i = 1, #points do
        if not polygon.point_in_poly(hull, points[i]) then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
-- Point set helpers
----------------------------------------------------------------------

function polygon.copy_points(points)
    local out = {}
    for i = 1, #points do
        out[i] = {
            x = points[i].x,
            y = points[i].y
        }
    end
    return out
end

function polygon.dedupe_points(points)
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

function polygon.lowest_point(points)
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
-- k-nearest helpers
----------------------------------------------------------------------

function polygon.k_nearest(points, from, k, used)
    local arr = {}

    for i = 1, #points do
        local p = points[i]
        if not used[i] and not polygon.points_equal(p, from) then
            arr[#arr + 1] = {
                idx = i,
                d2 = polygon.dist2(from, p)
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
    for i = 1, math.min(k, #arr) do
        out[#out + 1] = points[arr[i].idx]
    end
    return out
end

function polygon.k_nearest_indexed(pts, current, k, used)
    local cands = {}
    for i = 1, #pts do
        if not used[i] then
            local p = pts[i]
            -- FIX: exclude current point to avoid zero-length edges
            if not polygon.points_equal(p, current) then
                cands[#cands + 1] = {
                    idx = i,
                    p = p,
                    d2 = polygon.dist2(current, p)
                }
            end
        end
    end

    table.sort(cands, function(a, b)
        if a.d2 == b.d2 then
            return a.idx < b.idx
        end
        return a.d2 < b.d2
    end)

    if #cands > k then
        for i = #cands, k + 1, -1 do
            cands[i] = nil
        end
    end

    return cands
end

----------------------------------------------------------------------
-- Synchronous concave hull
----------------------------------------------------------------------

function polygon.concave_hull(points, k, opts)
    opts = opts or {}

    local pts = polygon.dedupe_points(points)
    local n = #pts
    if n < 3 then
        return pts
    end

    local max_k = opts.max_k or math.min(25, n)
    k = math.max(3, math.min(k or 3, n))

    for kk = k, max_k do
        local used = {}
        local start_idx = polygon.lowest_point(pts)
        local start = pts[start_idx]
        used[start_idx] = true

        local hull = {start}
        local prev_dir = {
            x = -1,
            y = 0
        }
        local current = start

        local guard = 0
        while guard < 10000 do
            guard = guard + 1

            local candidates = polygon.k_nearest_indexed(pts, current, kk, used)
            if #candidates == 0 then
                break
            end

            table.sort(candidates, function(a, b)
                local aa = polygon.angle_ccw(prev_dir, current, a.p)
                local ab = polygon.angle_ccw(prev_dir, current, b.p)
                if aa == ab then
                    return polygon.dist2(current, a.p) < polygon.dist2(current, b.p)
                end
                return aa < ab
            end)

            local next, next_idx = nil, nil

            for i = 1, #candidates do
                local cand = candidates[i].p
                local cand_idx = candidates[i].idx
                local closing = (#hull >= 3 and polygon.points_equal(cand, start))

                if closing then
                    local intersects = false
                    local a = hull[#hull]
                    local b = start

                    -- FIX: skip edges adjacent to start and end
                    for e = 2, #hull - 2 do
                        if polygon.segments_intersect(a, b, hull[e], hull[e + 1]) then
                            intersects = true
                            break
                        end
                    end

                    if not intersects then
                        next = start
                        next_idx = start_idx
                        break
                    end
                else
                    if not polygon.would_self_intersect(hull, cand) then
                        next = cand
                        next_idx = cand_idx
                        break
                    end
                end
            end

            if not next or polygon.points_equal(next, start) then
                break
            end

            used[next_idx] = true

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

        if #hull >= 3 and polygon.all_points_inside_or_on(hull, pts) then
            return hull
        end
    end

    return polygon.convex_hull(polygon.copy_points(pts))
end

----------------------------------------------------------------------
-- Convex hull (Graham scan)
----------------------------------------------------------------------

function polygon.convex_hull(points)
    local n = #points
    if n < 3 then
        return polygon.copy_points(points)
    end

    local pts = polygon.copy_points(points)

    local pivot_idx = polygon.lowest_point(pts)
    pts[1], pts[pivot_idx] = pts[pivot_idx], pts[1]
    local pivot = pts[1]

    table.sort(pts, function(a, b)
        if a == pivot then
            return true
        end
        if b == pivot then
            return false
        end
        local c = polygon.cross(pivot, a, b)
        if c == 0 then
            return polygon.dist2(pivot, a) < polygon.dist2(pivot, b)
        end
        return c > 0
    end)

    local filtered = {pts[1]}
    for i = 2, n do
        while #filtered >= 2 do
            local last = filtered[#filtered]
            local prev = filtered[#filtered - 1]
            if polygon.cross(prev, last, pts[i]) ~= 0 then
                break
            end
            if polygon.dist2(prev, pts[i]) > polygon.dist2(prev, last) then
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

    local hull = {filtered[1], filtered[2], filtered[3]}
    for i = 4, #filtered do
        while #hull >= 2 do
            local top = hull[#hull]
            local next_to_top = hull[#hull - 1]
            if polygon.cross(next_to_top, top, filtered[i]) > 0 then
                break
            end
            table.remove(hull)
        end
        hull[#hull + 1] = filtered[i]
    end

    return hull
end

function polygon.contains_point(poly, p)
    if not poly or #poly < 3 then
        return false
    end
    return polygon.point_in_poly(poly, p)
end

return polygon
