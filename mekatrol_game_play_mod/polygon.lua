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

function polygon.would_self_intersect(poly, candidate)
    -- Checks whether adding segment (last poly point -> candidate)
    -- would intersect any existing poly edge excluding adjacent edges.
    local n = #poly
    if n < 3 then
        return false
    end

    local a = poly[n]
    local b = candidate

    for i = 1, n - 2 do
        local c = poly[i]
        local d = poly[i + 1]

        -- ignore shared endpoints so touching is not treated as intersection
        if not shares_endpoint(a, b, c, d) then
            if polygon.segments_intersect(a, b, c, d) then
                return true
            end
        end
    end

    return false
end

-- True if segment (a->b) intersects any edge of poly, excluding edges adjacent to a or b,
-- and ignoring intersections only when they occur exactly at shared endpoints.
function polygon.segment_intersects_polygon(a, b, poly, exclude_start_idx, exclude_end_idx)
    local n = #poly
    if n < 3 then
        return false
    end

    local function is_shared_endpoint(p, q)
        return polygon.points_equal(p, q)
    end

    for i = 1, n - 1 do
        -- edge poly[i] -> poly[i+1]
        if i ~= exclude_start_idx and i ~= exclude_end_idx then
            local c = poly[i]
            local d = poly[i + 1]

            if polygon.segments_intersect(a, b, c, d) then
                -- If intersection is only at a shared endpoint, allow it; otherwise reject.
                -- This also rejects collinear overlaps because there is no single endpoint intersection.
                local ip = polygon.segment_intersection_point(a, b, c, d)

                if not ip then
                    -- parallel/collinear overlap or unhandled case -> treat as intersection (reject)
                    return true
                end

                local at_ab_endpoint = is_shared_endpoint(ip, a) or is_shared_endpoint(ip, b)
                local at_cd_endpoint = is_shared_endpoint(ip, c) or is_shared_endpoint(ip, d)

                -- Allow only if it's exactly at a shared endpoint
                if not (at_ab_endpoint and at_cd_endpoint) then
                    return true
                end
            end
        end
    end

    return false
end

-- Returns intersection point of segments AB and CD, or nil if none / parallel / collinear.
-- Includes endpoint intersections; you can filter those out if you want.
function polygon.segment_intersection_point(a, b, c, d)
    local r = {
        x = b.x - a.x,
        y = b.y - a.y
    }
    local s = {
        x = d.x - c.x,
        y = d.y - c.y
    }

    local function cross2(u, v)
        return u.x * v.y - u.y * v.x
    end

    local denom = cross2(r, s)
    if denom == 0 then
        -- Parallel or collinear: return nil so caller can treat as overlap/ambiguous.
        return nil
    end

    local cma = {
        x = c.x - a.x,
        y = c.y - a.y
    }
    local t = cross2(cma, s) / denom
    local u = cross2(cma, r) / denom

    if t < 0 or t > 1 or u < 0 or u > 1 then
        return nil
    end

    return {
        x = a.x + t * r.x,
        y = a.y + t * r.y
    }
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

function polygon.all_points_inside_or_on(poly, points)
    for i = 1, #points do
        if not polygon.point_in_poly(poly, points[i]) then
            return false
        end
    end
    return true
end

function polygon.aabb_of(poly)
    local minx, maxx = poly[1].x, poly[1].x
    local miny, maxy = poly[1].y, poly[1].y

    for i = 2, #poly do
        local p = poly[i]
        if p.x < minx then
            minx = p.x
        end
        if p.x > maxx then
            maxx = p.x
        end
        if p.y < miny then
            miny = p.y
        end
        if p.y > maxy then
            maxy = p.y
        end
    end

    return {
        minx = minx,
        miny = miny,
        maxx = maxx,
        maxy = maxy
    }
end

function polygon.aabb_overlap(a, b)
    return not (a.maxx < b.minx or a.minx > b.maxx or a.maxy < b.miny or a.miny > b.maxy)
end

function polygon.polygons_intersect(a, b)
    local abox = polygon.aabb_of(a)
    local bbox = polygon.aabb_of(b)

    -- ealy out if no chance of overlap
    if not polygon.aabb_overlap(abox, bbox) then
        return false
    end

    local na = #a
    local nb = #b

    -- Edge intersections
    for i = 1, na do
        local a1 = a[i]
        local a2 = a[(i % na) + 1]

        for j = 1, nb do
            local b1 = b[j]
            local b2 = b[(j % nb) + 1]

            if polygon.segments_intersect(a1, a2, b1, b2) then
                return true
            end
        end
    end

    -- Containment checks
    if polygon.point_in_poly(a, b[1]) then
        return true
    end
    if polygon.point_in_poly(b, a[1]) then
        return true
    end

    return false
end

function polygon.polygon_area(points)
    if not points or #points < 3 then
        return 0
    end

    local n = #points
    if n >= 2 and polygon.points_equal(points[1], points[n]) then
        n = n - 1
        if n < 3 then
            return 0
        end
    end

    local sum = 0
    for i = 1, n do
        local a = points[i]
        local b = points[(i % n) + 1]
        sum = sum + (a.x * b.y - b.x * a.y)
    end

    return math.abs(sum) * 0.5
end

function polygon.merge_polygons(a, b, opts)
    opts = opts or {}
    local points = {}

    for i = 1, #a do
        points[#points + 1] = a[i]
    end
    for i = 1, #b do
        points[#points + 1] = b[i]
    end

    points = polygon.dedupe_points(points)

    if opts.concave then
        return polygon.concave_hull(points, opts.k or 6, opts)
    end

    return polygon.convex_hull(points)
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
-- Synchronous concave hull algorithm
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

        local poly = {start}
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
                local closing = (#poly >= 3 and polygon.points_equal(cand, start))

                if closing then
                    local a = poly[#poly]
                    local b = start

                    -- Exclude edge 1 (start->poly[2]) and edge (#poly-1) (poly[#poly-1]->poly[#poly])
                    -- because they are adjacent to the closing segment endpoints.
                    local exclude_edge_1 = 1
                    local exclude_edge_last = #poly - 1

                    local intersects = polygon.segment_intersects_polygon(a, b, poly, exclude_edge_1, exclude_edge_last)
                    if not intersects then
                        next = start
                        next_idx = start_idx
                        break
                    end
                else
                    if not polygon.would_self_intersect(poly, cand) then
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
            poly[#poly + 1] = next

            if #poly >= n then
                break
            end
        end

        if #poly >= 3 and polygon.all_points_inside_or_on(poly, pts) then
            return poly
        end
    end

    return polygon.convex_hull(polygon.copy_points(pts))
end

----------------------------------------------------------------------
-- Convex hull algorithm (Graham scan)
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

    local poly = {filtered[1], filtered[2], filtered[3]}
    for i = 4, #filtered do
        while #poly >= 2 do
            local top = poly[#poly]
            local next_to_top = poly[#poly - 1]
            if polygon.cross(next_to_top, top, filtered[i]) > 0 then
                break
            end
            table.remove(poly)
        end
        poly[#poly + 1] = filtered[i]
    end

    return poly
end

function polygon.contains_point(poly, p)
    if not poly or #poly < 3 then
        return false
    end
    return polygon.point_in_poly(poly, p)
end

function polygon.polygon_center(points)
    if not points or #points == 0 then
        return nil
    end

    local minx, maxx = points[1].x, points[1].x
    local miny, maxy = points[1].y, points[1].y

    for i = 2, #points do
        local p = points[i]
        if p.x < minx then
            minx = p.x
        end
        if p.x > maxx then
            maxx = p.x
        end
        if p.y < miny then
            miny = p.y
        end
        if p.y > maxy then
            maxy = p.y
        end
    end

    return {
        x = (minx + maxx) * 0.5,
        y = (miny + maxy) * 0.5
    }
end

-- Squared distance from point p to segment a-b
function polygon.point_segment_dist2(p, a, b)
    local abx = b.x - a.x
    local aby = b.y - a.y
    local apx = p.x - a.x
    local apy = p.y - a.y

    local ab_len2 = abx * abx + aby * aby
    if ab_len2 == 0 then
        -- a==b
        return apx * apx + apy * apy
    end

    local t = (apx * abx + apy * aby) / ab_len2
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end

    local cx = a.x + t * abx
    local cy = a.y + t * aby
    local dx = p.x - cx
    local dy = p.y - cy
    return dx * dx + dy * dy
end

-- True if inside polygon OR within 'margin' (in tiles/world units) of its boundary.
-- Works whether poly is "closed" (last point equals first) or not.
function polygon.contains_point_buffered(poly, p, margin)
    if not poly or #poly < 3 then
        return false
    end

    if polygon.point_in_poly(poly, p) then
        return true
    end

    local m2 = (margin or 0) * (margin or 0)
    if m2 <= 0 then
        return false
    end

    local n = #poly

    -- If the polygon is closed (last == first), ignore the last point for edge iteration
    local last = poly[n]
    local first = poly[1]
    local closed = polygon.points_equal(last, first)

    local edge_n = closed and (n - 1) or n

    for i = 1, edge_n do
        local a = poly[i]
        local b = (i == edge_n) and (closed and poly[1] or poly[1]) or poly[i + 1]
        -- If not closed, last edge wraps to poly[1]
        if not closed and i == edge_n then
            b = poly[1]
        end

        if polygon.point_segment_dist2(p, a, b) <= m2 then
            return true
        end
    end

    return false
end

return polygon
