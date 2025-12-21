local mapping = {}

local config = require("configuration")
local polygon = require("polygon")
local util = require("util")
local visual = require("visual")

local BOT = config.bot
local NON_STATIC_TYPES = config.non_static_types

----------------------------------------------------------------------
-- Mappable entity helpers
----------------------------------------------------------------------

function mapping.is_static_mappable(entity)
    if not (entity and entity.valid) then
        return false
    end

    -- Ignore types that are considered non-static (moving, temporary, etc.).
    if NON_STATIC_TYPES[entity.type] then
        return false
    end

    return true
end

function mapping.get_entity_key(entity)
    -- Prefer unit_number for stable identity when available.
    if entity.unit_number then
        return entity.unit_number
    end

    -- Fallback: name + position + surface.
    local p = entity.position
    return string.format("%s@%s,%s#%d", entity.name, p.x, p.y, entity.surface.index)
end

function mapping.get_position_key(x, y, q)
    if q == 0.5 then
        return string.format("%.1f,%.1f", x, y)
    end

    return string.format("%.2f,%.2f", x, y)
end

function mapping.quantize(v, step)
    return math.floor(v / step + 0.5) * step
end

function mapping.mark_position_mapped(ps, x, y, q)
    local qx = mapping.quantize(x, q)
    local qy = mapping.quantize(y, q)
    ps.survey_mapped_positions[mapping.get_position_key(qx, qy, q)] = true
end

function mapping.is_position_mapped(ps, x, y, q)
    local qx = mapping.quantize(x, q)
    local qy = mapping.quantize(y, q)
    return ps.survey_mapped_positions[mapping.get_position_key(qx, qy, q)] == true
end

function mapping.ring_seed_for_center(center)
    local x = mapping.quantize(center.x, 1)
    local y = mapping.quantize(center.y, 1)
    local h = (x * 12.9898 + y * 78.233)
    local frac = h - math.floor(h)
    return frac * 2 * math.pi
end

function mapping.frontier_distance_sq(bot_pos, node)
    local dx = node.x - bot_pos.x
    local dy = node.y - bot_pos.y
    return dx * dx + dy * dy
end

function mapping.get_nearest_frontier(ps, bot_pos)
    local frontier = ps.survey_frontier
    if #frontier == 0 then
        return nil
    end

    local best_i = 1
    local best_d2 = mapping.frontier_distance_sq(bot_pos, frontier[1])

    for i = 2, #frontier do
        local d2 = mapping.frontier_distance_sq(bot_pos, frontier[i])
        if d2 < best_d2 then
            best_d2 = d2
            best_i = i
        end
    end

    local node = frontier[best_i]
    table.remove(frontier, best_i)
    table.insert(ps.survey_done, node)
    return node
end

function mapping.add_frontier_node(player, state, ps, bot, x, y)
    state.ensure_survey_sets(ps)

    -- Frontier nodes are quantized to half-tiles.
    local q = 0.5
    x = mapping.quantize(x, q)
    y = mapping.quantize(y, q)

    local key = mapping.get_position_key(x, y, q)
    if ps.survey_seen[key] == true then
        return
    end

    -- Never enqueue already-covered locations.
    if mapping.is_position_mapped(ps, x, y, q) then
        return
    end

    -- Only enqueue frontier nodes that are "interesting":
    -- we require at least one static mappable entity very near the node.
    local surf = bot.surface
    local char = player.character

    local found = surf.find_entities_filtered {
        position = {
            x = x,
            y = y
        },
        radius = 0.49,
        name = ps.survey_entity_type_name
    }

    local discovered_any = false
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and mapping.is_static_mappable(e) then
            discovered_any = true
            break
        end
    end

    if not discovered_any then
        return
    end

    ps.survey_seen[key] = true
    table.insert(ps.survey_frontier, {
        x = x,
        y = y
    })
end

function mapping.add_ring_frontiers(player, state, ps, bot, center, radius, count, start_angle, radial_offset)
    state.ensure_survey_sets(ps)

    radial_offset = radial_offset or 0
    start_angle = start_angle or 0

    if count <= 0 then
        return
    end

    local step = (2 * math.pi) / count
    local r = radius + radial_offset

    for i = 0, count - 1 do
        local a = start_angle + i * step
        mapping.add_frontier_node(player, state, ps, bot, center.x + math.cos(a) * r, center.y + math.sin(a) * r)
    end
end

function mapping.should_add_frontier(ps, x, y)
    if not ps.hull then
        return true
    end

    return polygon.contains_point(ps.hull, {
        x = x,
        y = y
    })
end

function mapping.add_frontier_on_radius_edge(player, state, ps, bot, center_pos, point_pos, radius)
    state.ensure_survey_sets(ps)

    local dx = point_pos.x - center_pos.x
    local dy = point_pos.y - center_pos.y
    local d2 = dx * dx + dy * dy

    if d2 <= 0 then
        return
    end

    local d = math.sqrt(d2)
    local nx = dx / d
    local ny = dy / d
    local angle = math.atan2(ny, nx)
    local delta = math.rad(15)

    -- Straight ahead
    local ex = center_pos.x + nx * radius
    local ey = center_pos.y + ny * radius

    if mapping.should_add_frontier(ps, ex, ey) then
        mapping.add_frontier_node(player, state, ps, bot, ex, ey)
    end

    -- Slightly left
    ex = center_pos.x + math.cos(angle + delta) * radius
    ey = center_pos.y + math.sin(angle + delta) * radius

    if mapping.should_add_frontier(ps, ex, ey) then
        mapping.add_frontier_node(player, state, ps, bot, ex, ey)
    end

    -- Slightly right
    ex = center_pos.x + math.cos(angle - delta) * radius
    ey = center_pos.y + math.sin(angle - delta) * radius

    if mapping.should_add_frontier(ps, ex, ey) then
        mapping.add_frontier_node(player, state, ps, bot, ex, ey)
    end
end

----------------------------------------------------------------------
-- Mapping upsert
----------------------------------------------------------------------

function mapping.upsert_mapped_entity(player, state, ps, entity, tick)
    local key = mapping.get_entity_key(entity)
    if not key then
        return false
    end

    state.ensure_survey_sets(ps)

    local mapped = ps.survey_mapped_entities
    local info = mapped[key]
    local is_new = false

    if not info then
        is_new = true
        info = {
            name = entity.name,
            surface_index = entity.surface.index,
            position = {
                x = entity.position.x,
                y = entity.position.y
            },
            force_name = entity.force and entity.force.name or nil,
            last_seen_tick = tick,
            discovered_by_player_index = player.index
        }

        mapped[key] = info

        if ps.survey_render_mapped then
            local box_id = visual.draw_mapped_entity_box(player, ps, entity)
            ps.visual.mapped_entities[key] = box_id
        end
    else
        local pos = entity.position
        info.position.x = pos.x
        info.position.y = pos.y
        info.last_seen_tick = tick
    end

    -- Mark location as mapped (coverage) so we don't enqueue frontier nodes repeatedly.
    mapping.mark_position_mapped(ps, entity.position.x, entity.position.y, 0.5)

    return is_new
end

----------------------------------------------------------------------
-- Hull point extraction and fingerprinting
----------------------------------------------------------------------

function mapping.get_mapped_entity_points(ps)
    -- Convert mapped entities into a de-duplicated set of quantized points.
    -- Also compute:
    --   count = number of unique points
    --   hash  = order-independent hash of points
    --
    -- The hash+count combination is used to detect point-set changes cheaply,
    -- without deep-comparing tables.
    local points = {}
    local seen = {}

    local q = 1.0 -- hull quantization
    local hash = 0
    local count = 0

    for _, info in pairs(ps.survey_mapped_entities) do
        local x = mapping.quantize(info.position.x, q)
        local y = mapping.quantize(info.position.y, q)

        local ix = x
        local iy = y

        local key = ix .. "," .. iy
        if not seen[key] then
            seen[key] = true

            points[#points + 1] = {
                x = ix,
                y = iy
            }
            count = count + 1

            local v = ix * 73856093 + iy * 19349663
            hash = util.hash_combine(hash, v)
        end
    end

    return points, count, hash
end

----------------------------------------------------------------------
-- Hull scheduling and incremental processing
----------------------------------------------------------------------

function mapping.evaluate_hull_need(player, ps, tick)
    -- Only evaluate at a coarse cadence to avoid redundant work.
    if tick % BOT.update_hull_interval ~= 0 then
        return
    end

    local points, qcount, qhash = mapping.get_mapped_entity_points(ps)

    -- If not enough points, reset hull state.
    if qcount < 3 then
        ps.hull_job = nil
        ps.hull = nil
        ps.hull_point_set = {}
        ps.hull_quantized_count = 0
        ps.hull_quantized_hash = 0
        ps.hull_tick = tick
        return
    end

    -- Don't need to start hull if job already running, let it finish
    if ps.hull_job then
        return
    end

    -- Detect point-set change relative to last committed fingerprint.
    local changed = (qcount ~= ps.hull_quantized_count) or (qhash ~= ps.hull_quantized_hash)
    if not changed then
        return
    end

    -- Rebuild only if stale (same as before).
    local stale = (tick - (ps.hull_tick or 0)) > 60 * 2
    if not stale then
        return
    end

    ps.hull_point_set = ps.hull_point_set or {}

    -- Compute "new points since last time" by comparing against hull_point_set.
    local new_points = {}
    for i = 1, #points do
        local p = points[i]
        local key = tostring(p.x) .. "," .. tostring(p.y)
        if not ps.hull_point_set[key] then
            new_points[#new_points + 1] = {
                x = p.x,
                y = p.y
            }
        end
    end

    -- If we have an existing hull, and ALL newly-added points are inside/on it,
    -- then the existing hull is still valid and we can skip recalculation.
    if ps.hull and #ps.hull >= 3 and #new_points > 0 then
        local all_inside = true
        for i = 1, #new_points do
            if not polygon.contains_point(ps.hull, new_points[i]) then
                all_inside = false
                break
            end
        end

        if all_inside then
            -- Commit the new fingerprint without changing the hull.
            for i = 1, #new_points do
                local p = new_points[i]
                local key = tostring(p.x) .. "," .. tostring(p.y)
                ps.hull_point_set[key] = true
            end

            ps.hull_quantized_count = qcount
            ps.hull_quantized_hash = qhash
            -- Keep hull_tick unchanged (hull shape did not change).
            return
        end
    end

    -- Otherwise we need a rebuild. Start (or restart) an incremental job.
    -- Snapshot the full point set for the job.
    ps.hull_job = polygon.start_concave_hull_job(player, points, 8, {
        max_k = 120
    })
    ps.hull_job.qcount = qcount
    ps.hull_job.qhash = qhash
end

function mapping.step_hull_job(player, ps, tick)
    if not ps.hull_job then
        return
    end

    local step_budget = BOT.hull_steps_per_tick or 25
    local done, hull = polygon.step_concave_hull_job(player, ps.hull_job, step_budget)
    
    if not done then
        return
    end

    ps.hull = hull
    ps.hull_quantized_count = ps.hull_job.qcount
    ps.hull_quantized_hash = ps.hull_job.qhash
    ps.hull_tick = tick

    -- Rebuild point-set membership for future delta checks.
    ps.hull_point_set = {}
    local job_points = ps.hull_job.pts
    for i = 1, #job_points do
        local p = job_points[i]
        ps.hull_point_set[tostring(p.x) .. "," .. tostring(p.y)] = true
    end

    ps.hull_job = nil
end

function mapping.update(player, ps, tick)
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
    mapping.evaluate_hull_need(player, ps, tick)
    mapping.step_hull_job(player, ps, tick)

    -- Draw the most recently completed hull (if any).
    local hull = ps.hull
    if hull and #hull >= 2 then
        for i = 1, #hull do
            local a = hull[i]
            local b = hull[i % #hull + 1]

            visual.draw_line(player, ps, a, b, {
                r = 1,
                g = 0,
                b = 0,
                a = 0.8
            })
        end
    end

end

return mapping
