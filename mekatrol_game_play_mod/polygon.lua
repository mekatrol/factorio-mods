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

----------------------------------------------------------------------
-- Basic vector/geometry helpers
----------------------------------------------------------------------

local function cross(o, a, b)
    -- Cross product (OA x OB). Sign indicates orientation.
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
end

local function dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function points_equal(a, b)
    return a.x == b.x and a.y == b.y
end

local function on_segment(a, b, p)
    return math.min(a.x, b.x) <= p.x and p.x <= math.max(a.x, b.x) and math.min(a.y, b.y) <= p.y and p.y <=
               math.max(a.y, b.y)
end

local function orient(a, b, c)
    -- Returns:
    --   1  if a->b->c is CCW turn
    --  -1  if CW turn
    --   0  if collinear
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
    -- Proper + collinear intersections.
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
    -- Checks whether adding segment (last hull point -> candidate)
    -- would intersect any existing hull edge excluding adjacent edges.
    local n = #hull
    if n < 3 then
        return false
    end

    local a = hull[n]
    local b = candidate

    -- Check against edges hull[i] -> hull[i+1] for i=1..n-2
    for i = 1, n - 2 do
        local c = hull[i]
        local d = hull[i + 1]
        if segments_intersect(a, b, c, d) then
            return true
        end
    end

    return false
end

local function angle_ccw(prev_dir, from, to)
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

local function point_in_poly(poly, p)
    -- Ray casting. Boundary is treated as inside.
    local inside = false
    local n = #poly
    local j = n

    for i = 1, n do
        local a = poly[i]
        local b = poly[j]

        -- Boundary check.
        if orient(a, b, p) == 0 and on_segment(a, b, p) then
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

local function all_points_inside_or_on(hull, points)
    for i = 1, #points do
        if not point_in_poly(hull, points[i]) then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
-- Point set helpers
----------------------------------------------------------------------

local function copy_points(points)
    local out = {}
    for i = 1, #points do
        local p = points[i]
        out[i] = {
            x = p.x,
            y = p.y
        }
    end
    return out
end

local function dedupe_points(points)
    -- Exact dedupe. Works well if caller already quantizes.
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

local function lowest_point(points)
    -- Lowest Y, then lowest X.
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

local function k_nearest(points, from, k, used)
    -- Returns up to k nearest points to "from" that are not used.
    -- "used" is a boolean array indexed by point index.
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

----------------------------------------------------------------------
-- Incremental concave hull job API
--
-- The job is a plain Lua table so it can be stored in mod persistent state.
-- Each step call advances the algorithm by a bounded number of “micro-steps”.
----------------------------------------------------------------------

function polygon.start_concave_hull_job(points, k, opts)
    opts = opts or {}

    local pts = dedupe_points(points)
    local n = #pts

    local job = {
        -- frozen input for this job attempt
        pts = pts,
        n = n,

        -- k parameters
        k0 = (k and math.max(3, k)) or 3,
        max_k = opts.max_k or math.min(25, n),

        -- attempt state (set by init_attempt)
        kk = nil,
        used = nil,
        start_idx = nil,
        start = nil,
        hull = nil,
        prev_dir = nil,
        current = nil,
        guard = 0,

        -- phases:
        --   init_attempt -> build -> validate -> done
        -- or fallback_done (convex hull)
        phase = "init_attempt",

        -- validation progress (incremental)
        validate_i = 1,
        validated_ok = true,

        -- final output
        result = nil
    }

    if n < 3 then
        job.phase = "done"
        job.result = pts
        return job
    end

    if job.k0 > n then
        job.k0 = n
    end

    job.kk = job.k0
    return job
end

function polygon.step_concave_hull_job(job, step_budget)
    if not job or job.phase == "done" or job.phase == "fallback_done" then
        return true, job and job.result or nil
    end

    local steps_left = step_budget or 10
    if steps_left < 1 then
        steps_left = 1
    end

    while steps_left > 0 do
        steps_left = steps_left - 1

        if job.phase == "init_attempt" then
            -- If k has escalated too far, fall back to convex hull.
            if job.kk > job.max_k then
                job.result = polygon.convex_hull(copy_points(job.pts))
                job.phase = "fallback_done"
                return true, job.result
            end

            -- Reset attempt state.
            job.used = {}
            job.start_idx = lowest_point(job.pts)
            job.start = job.pts[job.start_idx]
            job.used[job.start_idx] = true

            job.hull = {job.start}
            job.prev_dir = {
                x = -1,
                y = 0
            } -- initial “west” direction
            job.current = job.start
            job.guard = 0

            job.phase = "build"

        elseif job.phase == "build" then
            -- Guard against infinite loops.
            job.guard = job.guard + 1
            if job.guard >= 10000 then
                -- Treat as failed attempt; increase k and restart.
                job.kk = job.kk + 1
                job.phase = "init_attempt"
            else
                local candidates = k_nearest(job.pts, job.current, job.kk, job.used)
                if #candidates == 0 then
                    job.kk = job.kk + 1
                    job.phase = "init_attempt"
                else
                    -- Pick candidate with smallest CCW turn; break ties by distance.
                    table.sort(candidates, function(a, b)
                        local aa = angle_ccw(job.prev_dir, job.current, a)
                        local ab = angle_ccw(job.prev_dir, job.current, b)
                        if aa == ab then
                            return dist2(job.current, a) < dist2(job.current, b)
                        end
                        return aa < ab
                    end)

                    local next = nil

                    for i = 1, #candidates do
                        local cand = candidates[i]

                        -- Allow closing to start only when hull is long enough.
                        local closing = (#job.hull >= 3 and points_equal(cand, job.start))

                        if closing then
                            -- Closing segment must not intersect existing hull edges.
                            local intersects = false
                            local a = job.hull[#job.hull]
                            local b = job.start
                            for e = 1, #job.hull - 2 do
                                local c = job.hull[e]
                                local d = job.hull[e + 1]
                                if segments_intersect(a, b, c, d) then
                                    intersects = true
                                    break
                                end
                            end
                            if not intersects then
                                next = job.start
                                break
                            end
                        else
                            -- Standard candidate must not self-intersect.
                            if not would_self_intersect(job.hull, cand) then
                                next = cand
                                break
                            end
                        end
                    end

                    if not next then
                        -- No candidate can extend hull without intersection: failed attempt.
                        job.kk = job.kk + 1
                        job.phase = "init_attempt"
                    elseif points_equal(next, job.start) then
                        -- Closed polygon; validate point containment.
                        job.phase = "validate"
                        job.validate_i = 1
                        job.validated_ok = true
                    else
                        -- Mark used by index (points in job.pts are stable).
                        for i = 1, job.n do
                            if job.pts[i] == next then
                                job.used[i] = true
                                break
                            end
                        end

                        -- Advance.
                        job.prev_dir = {
                            x = next.x - job.current.x,
                            y = next.y - job.current.y
                        }
                        job.current = next
                        job.hull[#job.hull + 1] = next

                        -- If we’ve used all points, stop and validate.
                        if #job.hull >= job.n then
                            job.phase = "validate"
                            job.validate_i = 1
                            job.validated_ok = true
                        end
                    end
                end
            end

        elseif job.phase == "validate" then
            -- Validate incrementally: one point per micro-step.
            if #job.hull < 3 then
                job.kk = job.kk + 1
                job.phase = "init_attempt"
            else
                if job.validate_i > job.n then
                    if job.validated_ok then
                        job.result = job.hull
                        job.phase = "done"
                        return true, job.result
                    end

                    -- Failed validation; increase k and retry.
                    job.kk = job.kk + 1
                    job.phase = "init_attempt"
                else
                    local p = job.pts[job.validate_i]
                    if not point_in_poly(job.hull, p) then
                        job.validated_ok = false
                    end
                    job.validate_i = job.validate_i + 1
                end
            end
        end
    end

    return false, nil
end

----------------------------------------------------------------------
-- Synchronous concave hull
-- (Optional: keep for offline use, tests, or if you still call it elsewhere.)
----------------------------------------------------------------------

function polygon.concave_hull(points, k, opts)
    opts = opts or {}

    local pts = dedupe_points(points)
    local n = #pts
    if n < 3 then
        return pts
    end

    local max_k = opts.max_k or math.min(25, n)

    k = k or 3
    if k < 3 then
        k = 3
    end
    if k > n then
        k = n
    end

    for kk = k, max_k do
        local used = {}
        local start_idx = lowest_point(pts)
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

            local candidates = k_nearest(pts, current, kk, used)
            if #candidates == 0 then
                break
            end

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
                local closing = (#hull >= 3 and points_equal(cand, start))

                if closing then
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
                break -- closed
            end

            for i = 1, n do
                if pts[i] == next then
                    used[i] = true
                    break
                end
            end

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

        if #hull >= 3 and all_points_inside_or_on(hull, pts) then
            return hull
        end
    end

    -- Fallback: convex hull of the same point set we attempted.
    return polygon.convex_hull(copy_points(pts))
end

----------------------------------------------------------------------
-- Convex hull (Graham scan)
----------------------------------------------------------------------

function polygon.convex_hull(points)
    local n = #points
    if n < 3 then
        return copy_points(points)
    end

    local pts = copy_points(points)

    -- 1) pivot: lowest Y, then lowest X
    local pivot_idx = lowest_point(pts)
    pts[1], pts[pivot_idx] = pts[pivot_idx], pts[1]
    local pivot = pts[1]

    -- 2) sort by polar angle around pivot
    table.sort(pts, function(a, b)
        if a == pivot then
            return true
        end
        if b == pivot then
            return false
        end

        local c = cross(pivot, a, b)
        if c == 0 then
            return dist2(pivot, a) < dist2(pivot, b)
        end
        return c > 0
    end)

    -- 3) remove intermediate collinear points (keep extremes)
    local filtered = {pts[1]}
    for i = 2, n do
        while #filtered >= 2 do
            local last = filtered[#filtered]
            local prev = filtered[#filtered - 1]
            if cross(prev, last, pts[i]) ~= 0 then
                break
            end

            -- Keep the farthest collinear point from prev.
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

    -- 4) build hull stack
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

-- Public: true if point is inside OR on the boundary of the polygon.
-- poly: { {x=,y=}, ... } (not necessarily closed)
-- p: {x=,y=}
function polygon.contains_point(poly, p)
    -- If your hull can be nil or degenerate:
    if not poly or #poly < 3 then
        return false
    end
    return point_in_poly(poly, p)
end

return polygon
