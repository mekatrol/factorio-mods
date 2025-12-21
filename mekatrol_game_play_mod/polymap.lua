local polymap = {}

local config = require("configuration")
local mapping = require("mapping")
local polygon = require("polygon")
local util = require("util")
local visual = require("visual")

local BOT = config.bot

local function get_position_key(x, y, q)
    if q == 0.5 then
        return string.format("%.1f,%.1f", x, y)
    end

    return string.format("%.2f,%.2f", x, y)
end

----------------------------------------------------------------------
-- Incremental concave hull job API
--
-- The job is a plain Lua table so it can be stored in mod persistent state.
-- Each step call advances the algorithm by a bounded number of “micro-steps”.
----------------------------------------------------------------------

local function set_job_phase(player, job, phase)
    job.phase = phase
end

local function start_concave_hull_job(player, points, k, opts)
    opts = opts or {}

    local pts = polygon.dedupe_points(points)
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

        -- validation progress (incremental)
        validate_i = 1,
        validated_ok = true,

        -- final output
        result = nil
    }

    -- phases:
    --   init_attempt -> build -> validate -> done
    -- or fallback_done (convex hull)
    set_job_phase(player, job, "init_attempt")

    if n < 3 then
        set_job_phase(player, job, "done")
        job.result = pts
        return job
    end

    if job.k0 > n then
        job.k0 = n
    end

    job.kk = job.k0

    return job
end

----------------------------------------------------------------------
-- Hull scheduling and incremental processing
----------------------------------------------------------------------

local function evaluate_hull_need(player, ps, points)
    -- Make sure is an array (table)
    ps.map_visited_poly = ps.map_visited_poly or {}

    -- Get number of points already in the poly
    local poly_point_count = #ps.map_visited_poly

    -- If not enough points, reset hull job and return
    if (poly_point_count + #points) < 3 then
        ps.map_visited_hull_job = nil
        return
    end

    -- Don't need to start hull if job already running, let it finish
    if ps.map_visited_hull_job then
        return
    end

    -- Only process points not already in polygon
    local old_point_count = #ps.map_visited_poly
    for i = 1, #points do
        -- Get next new points since last time
        local p = points[i]

        -- quantize the point
        p = {
            x = mapping.quantize(p.x, 0.5),
            y = mapping.quantize(p.y, 0.5)
        }

        -- Is it in polygon?
        if not polygon.contains_point(ps.map_visited_poly, p) then
            ps.map_visited_poly[#ps.map_visited_poly + 1] = {
                x = p.x,
                y = p.y
            }
        end
    end

    -- clear any queued positions as they are not in the polygon
    ps.map_visited_queued_positions = {}

    if old_point_count == #ps.map_visited_poly then
        -- there are no new points outside the polygon
        return
    end

    -- start a new job to find concave hull
    ps.map_visited_hull_job = start_concave_hull_job(player, ps.map_visited_poly, 8, {
        max_k = 60
    })
end

local function step_hull_job_inner(player, job, step_budget)
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
                local pts = polygon.copy_points(job.pts)
                job.result = polygon.convex_hull(pts)
                set_job_phase(player, job, "fallback_done")
                return true, job.result
            end

            -- Reset attempt state.
            job.used = {}
            job.start_idx = polygon.lowest_point(job.pts)
            job.start = job.pts[job.start_idx]
            job.used[job.start_idx] = true

            job.hull = {job.start}
            job.prev_dir = {
                x = -1,
                y = 0
            } -- initial “west” direction
            job.current = job.start
            job.guard = 0

            set_job_phase(player, job, "build")

        elseif job.phase == "build" then
            -- Guard against infinite loops.
            job.guard = job.guard + 1
            if job.guard >= 10000 then
                -- Treat as failed attempt; increase k and restart.
                job.kk = job.kk + 1
                set_job_phase(player, job, "init_attempt")
            else
                local candidates = polygon.k_nearest(job.pts, job.current, job.kk, job.used)
                if #candidates == 0 then
                    job.kk = job.kk + 1
                    set_job_phase(player, job, "init_attempt")
                else
                    -- Pick candidate with smallest CCW turn; break ties by distance.
                    table.sort(candidates, function(a, b)
                        local aa = polygon.angle_ccw(job.prev_dir, job.current, a)
                        local ab = polygon.angle_ccw(job.prev_dir, job.current, b)
                        if aa == ab then
                            return polygon.dist2(job.current, a) < polygon.dist2(job.current, b)
                        end
                        return aa < ab
                    end)

                    local next = nil

                    for i = 1, #candidates do
                        local cand = candidates[i]

                        -- Allow closing to start only when hull is long enough.
                        local closing = (#job.hull >= 3 and polygon.points_equal(cand, job.start))

                        if closing then
                            local a = job.hull[#job.hull]
                            local b = job.start

                            local exclude_edge_1 = 1
                            local exclude_edge_last = #job.hull - 1

                            local intersects = polygon.segment_intersects_hull(a, b, job.hull, exclude_edge_1,
                                exclude_edge_last)
                            if not intersects then
                                next = job.start
                                break
                            end
                        else
                            if not polygon.would_self_intersect(job.hull, cand) then
                                next = cand
                                break
                            end
                        end
                    end

                    if not next then
                        -- No candidate can extend hull without intersection: failed attempt.
                        job.kk = job.kk + 1
                        set_job_phase(player, job, "init_attempt")
                    elseif polygon.points_equal(next, job.start) then
                        -- Closed polygon; validate point containment.
                        set_job_phase(player, job, "validate")
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
                            set_job_phase(player, job, "validate")
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
                set_job_phase(player, job, "init_attempt")
            else
                if job.validate_i > job.n then
                    if job.validated_ok then
                        job.result = job.hull
                        set_job_phase(player, job, "done")
                        return true, job.result
                    end

                    -- Failed validation; increase k and retry.
                    job.kk = job.kk + 1
                    set_job_phase(player, job, "init_attempt")
                else
                    local p = job.pts[job.validate_i]
                    if not polygon.point_in_poly(job.hull, p) then
                        job.validated_ok = false
                    end
                    job.validate_i = job.validate_i + 1
                end
            end
        end
    end

    return false, nil
end

local function step_hull_job(player, ps, tick)
    local job = ps.map_visited_hull_job

    if not job then
        return
    end

    local done = false
    local hull = nil

    if ps.hull_algorithm == "convex" then

        hull = polygon.convex_hull(job.pts)
        set_job_phase(player, job, "done")
        done = true
    elseif ps.hull_algorithm == "concave" then
        hull = polygon.concave_hull(job.pts, 8, {
            max_k = 60
        })
        set_job_phase(player, job, "done")
        done = true
    else -- do background task concave
        local step_budget = BOT.hull_steps_per_tick or 25
        done, hull = step_hull_job_inner(player, job, step_budget)
    end

    if not done then
        return
    end

    ps.map_visited_poly = hull
    ps.map_visited_hull_job = nil
end

function polymap.update(player, ps, tick)
    ------------------------------------------------------------------
    -- Hull processing (non-blocking)
    --
    -- 1) Every update_hull_interval ticks, compute the fingerprint of the mapped
    --    points and decide whether we need to start/restart the hull job.
    -- 2) Every tick, advance the current job by a limited step budget.
    --
    -- IMPORTANT: We intentionally do NOT compute mapped points/hash every tick.
    -- That avoids redundant hull-related work and keeps the script fast.
    ------------------------------------------------------------------
    local bot_pos = ps.bot_entity.position

    -- Add the centers of the 8 neighboring tiles around the bot's current tile
    local tx = math.floor(bot_pos.x)
    local ty = math.floor(bot_pos.y)

    for dx = -2, 2 do
        for dy = -2, 2 do
            if not (dx == 0 and dy == 0) then
                ps.map_visited_queued_positions[#ps.map_visited_queued_positions + 1] = {
                    x = mapping.quantize(tx + dx, 0.5),
                    y = mapping.quantize(ty + dy, 0.5)
                }
            end
        end
    end

    evaluate_hull_need(player, ps, ps.map_visited_queued_positions)
    step_hull_job(player, ps, tick)

    -- Draw the most recently completed hull (if any).
    local hull = ps.map_visited_poly
    if hull and #hull >= 2 then
        for i = 1, #hull do
            local a = hull[i]
            local b = hull[i % #hull + 1]

            visual.draw_line(player, ps, a, b, {
                r = 0.6,
                g = 0,
                b = 0.6,
                a = 0.8
            })
        end
    end

end

return polymap
