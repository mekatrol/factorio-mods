----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Goals of this version:
-- 1) Keep gameplay smooth by avoiding long single-tick work.
-- 2) Compute the concave hull incrementally over many ticks (state machine job),
--    instead of calling polygon.concave_hull(...) synchronously.
-- 3) Remove redundant hull calculations:
--    - Do NOT compute both the synchronous hull and the incremental hull.
--    - Do NOT recompute mapped points/hash every tick while a job is running.
--
-- Source base: your pasted control.lua. :contentReference[oaicite:0]{index=0}
----------------------------------------------------------------------
local config = require("configuration")
local polygon = require("polygon")
local visuals = require("visuals")

-- Config aliases.
local BOT = config.bot
local MODES = config.modes
local NON_STATIC_TYPES = config.non_static_types

----------------------------------------------------------------------
-- Print helpers
----------------------------------------------------------------------

local function print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = "<format error>"
    end

    player.print({"", string.format("[color=%s][Game Play Bot][/color] ", color), msg})
end

-- Simple, fast, order-independent hash combiner.
-- Uses 32-bit wrap semantics implemented via Lua numbers.
local function hash_combine(h, v)
    h = h + v * 0x9e3779b1
    h = h - math.floor(h / 0x100000000) * 0x100000000
    return h
end

----------------------------------------------------------------------
-- Storage and player state
----------------------------------------------------------------------

local function ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

local function get_player_state(player_index)
    ensure_storage_tables()

    local all = storage.game_bot
    local ps = all[player_index]

    if not ps then
        ps = {
            bot_entity = nil,
            bot_enabled = false,

            bot_mode = "follow",
            last_player_position = nil,
            last_player_side_offset_x = -BOT.movement.side_offset_distance,

            bot_target_position = nil,

            ------------------------------------------------------------------
            -- Survey data:
            --
            -- survey_mapped_entities:
            --   Map of stable entity_key -> info snapshot (position, name, etc).
            --
            -- survey_mapped_positions:
            --   Set of quantized "x,y" keys. This is "coverage"; it prevents
            --   repeatedly re-adding frontier nodes for already-surveyed places.
            --
            -- survey_frontier:
            --   Queue/list of frontier nodes (positions the bot should visit).
            --
            -- survey_done:
            --   List of already-visited frontier nodes (for visuals/debug).
            --
            -- survey_seen:
            --   Set of quantized "x,y" keys so we don't enqueue the same node
            --   multiple times.
            ------------------------------------------------------------------
            survey_mapped_entities = {},
            survey_mapped_positions = {},
            survey_frontier = {},
            survey_done = {},
            survey_seen = {},

            ------------------------------------------------------------------
            -- Hull data:
            --
            -- hull:
            --   The last completed hull polygon, if any.
            --
            -- hull_job:
            --   The current incremental job state (serializable table). When
            --   present, we advance it a limited amount each tick.
            --
            -- hull_quantized_count / hull_quantized_hash:
            --   A cheap fingerprint of the point set used for the *last
            --   completed hull*. If the mapped point set changes, these will
            --   no longer match and we schedule a new job.
            --
            -- hull_tick:
            --   When hull was last completed (used to avoid rebuilding too often).
            --
            -- hull_last_eval_tick:
            --   When we last computed (points,count,hash) from mapped entities.
            --   This allows us to avoid recomputing mapped points/hash every tick.
            ------------------------------------------------------------------
            hull = nil,
            hull_job = nil,
            hull_quantized_count = 0,
            hull_quantized_hash = 0,
            hull_tick = 0,
            hull_last_eval_tick = 0,
            hull_point_set = {}, -- set: "x,y" => true for quantized hull input points we've already seen

            visuals = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                mapped_entities = {},
                survey_frontier = {},
                survey_done = {}
            }
        }

        all[player_index] = ps
    else
        -- Defensive initialization for upgrades / older saves.
        ps.survey_frontier = ps.survey_frontier or {}
        ps.survey_done = ps.survey_done or {}
        ps.survey_seen = ps.survey_seen or {}
        ps.survey_mapped_entities = ps.survey_mapped_entities or {}
        ps.survey_mapped_positions = ps.survey_mapped_positions or {}

        ps.hull = ps.hull or nil
        ps.hull_job = ps.hull_job or nil
        ps.hull_quantized_count = ps.hull_quantized_count or 0
        ps.hull_quantized_hash = ps.hull_quantized_hash or 0
        ps.hull_tick = ps.hull_tick or 0
        ps.hull_last_eval_tick = ps.hull_last_eval_tick or 0
        ps.hull_point_set = ps.hull_point_set or {}

        ps.visuals = ps.visuals or {}
        ps.visuals.lines = ps.visuals.lines or nil
        ps.visuals.bot_highlight = ps.visuals.bot_highlight or nil
        ps.visuals.radius_circle = ps.visuals.radius_circle or nil
        ps.visuals.mapped_entities = ps.visuals.mapped_entities or {}
        ps.visuals.survey_frontier = ps.visuals.survey_frontier or {}
        ps.visuals.survey_done = ps.visuals.survey_done or {}
    end

    return ps
end

----------------------------------------------------------------------
-- Movement and position helpers
----------------------------------------------------------------------

local function resolve_target_position(target)
    if type(target) == "table" then
        if target.position then
            return target.position, nil
        elseif target.x and target.y then
            return target, nil
        elseif target[1] and target[2] then
            return {
                x = target[1],
                y = target[2]
            }, nil
        end
    end

    return nil, tostring(target)
end

local function move_bot_towards(player, bot, target)
    if not (bot and bot.valid) then
        return
    end

    local pos, err = resolve_target_position(target)
    if not pos then
        print_bot_message(player, "red", "invalid target: %s", err or "?")
        return
    end

    local step = BOT.movement.step_distance

    local bp = bot.position
    local dx = pos.x - bp.x
    local dy = pos.y - bp.y
    local d2 = dx * dx + dy * dy

    if d2 == 0 then
        return
    end

    local dist = math.sqrt(d2)
    if dist <= step then
        bot.teleport({pos.x, pos.y})
        return
    end

    bot.teleport({
        x = bp.x + dx / dist * step,
        y = bp.y + dy / dist * step
    })
end

----------------------------------------------------------------------
-- Mappable entity helpers
----------------------------------------------------------------------

local function is_static_mappable(entity)
    if not (entity and entity.valid) then
        return false
    end

    -- Ignore types that are considered non-static (moving, temporary, etc.).
    if NON_STATIC_TYPES[entity.type] then
        return false
    end

    return true
end

local function get_entity_key(entity)
    -- Prefer unit_number for stable identity when available.
    if entity.unit_number then
        return entity.unit_number
    end

    -- Fallback: name + position + surface.
    local p = entity.position
    return string.format("%s@%s,%s#%d", entity.name, p.x, p.y, entity.surface.index)
end

local function get_position_key(x, y, q)
    if q == 0.5 then
        return string.format("%.1f,%.1f", x, y)
    end

    return string.format("%.2f,%.2f", x, y)
end

----------------------------------------------------------------------
-- Survey helpers
----------------------------------------------------------------------

local function quantize(v, step)
    return math.floor(v / step + 0.5) * step
end

local function ensure_survey_sets(ps)
    ps.survey_frontier = ps.survey_frontier or {}
    ps.survey_done = ps.survey_done or {}
    ps.survey_seen = ps.survey_seen or {}
    ps.survey_mapped_positions = ps.survey_mapped_positions or {}
end

local function mark_position_mapped(ps, x, y, q)
    local qx = quantize(x, q)
    local qy = quantize(y, q)
    ps.survey_mapped_positions[get_position_key(qx, qy, q)] = true
end

local function is_position_mapped(ps, x, y, q)
    local qx = quantize(x, q)
    local qy = quantize(y, q)
    return ps.survey_mapped_positions[get_position_key(qx, qy, q)] == true
end

local function ring_seed_for_center(center)
    local x = quantize(center.x, 1)
    local y = quantize(center.y, 1)
    local h = (x * 12.9898 + y * 78.233)
    local frac = h - math.floor(h)
    return frac * 2 * math.pi
end

local function frontier_distance_sq(bot_pos, node)
    local dx = node.x - bot_pos.x
    local dy = node.y - bot_pos.y
    return dx * dx + dy * dy
end

local function get_nearest_frontier(ps, bot_pos)
    local frontier = ps.survey_frontier
    if #frontier == 0 then
        return nil
    end

    local best_i = 1
    local best_d2 = frontier_distance_sq(bot_pos, frontier[1])

    for i = 2, #frontier do
        local d2 = frontier_distance_sq(bot_pos, frontier[i])
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

local function add_frontier_node(player, ps, bot, x, y)
    ensure_survey_sets(ps)

    -- Frontier nodes are quantized to half-tiles.
    local q = 0.5
    x = quantize(x, q)
    y = quantize(y, q)

    local key = get_position_key(x, y, q)
    if ps.survey_seen[key] == true then
        return
    end

    -- Never enqueue already-covered locations.
    if is_position_mapped(ps, x, y, q) then
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
        radius = 0.49
    }

    local discovered_any = false
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and is_static_mappable(e) then
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

local function add_ring_frontiers(player, ps, bot, center, radius, count, start_angle, radial_offset)
    ensure_survey_sets(ps)

    radial_offset = radial_offset or 0
    start_angle = start_angle or 0

    if count <= 0 then
        return
    end

    local step = (2 * math.pi) / count
    local r = radius + radial_offset

    for i = 0, count - 1 do
        local a = start_angle + i * step
        add_frontier_node(player, ps, bot, center.x + math.cos(a) * r, center.y + math.sin(a) * r)
    end
end

local function add_frontier_on_radius_edge(player, ps, bot, center_pos, point_pos, radius)
    ensure_survey_sets(ps)

    local dx = point_pos.x - center_pos.x
    local dy = point_pos.y - center_pos.y
    local d2 = dx * dx + dy * dy

    if d2 <= 0 then
        return
    end

    local d = math.sqrt(d2)
    local nx = dx / d
    local ny = dy / d

    local ex = center_pos.x + nx * radius
    local ey = center_pos.y + ny * radius
    add_frontier_node(player, ps, bot, ex, ey)

    local angle = math.atan2(ny, nx)
    local delta = math.rad(15)

    add_frontier_node(player, ps, bot, center_pos.x + math.cos(angle + delta) * radius,
        center_pos.y + math.sin(angle + delta) * radius)

    add_frontier_node(player, ps, bot, center_pos.x + math.cos(angle - delta) * radius,
        center_pos.y + math.sin(angle - delta) * radius)
end

----------------------------------------------------------------------
-- Mapping upsert
----------------------------------------------------------------------

local function upsert_mapped_entity(player, ps, entity, tick)
    local key = get_entity_key(entity)
    if not key then
        return false
    end

    ensure_survey_sets(ps)

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

        local box_id = visuals.draw_mapped_entity_box(player, ps, entity)
        ps.visuals.mapped_entities[key] = box_id
    else
        local pos = entity.position
        info.position.x = pos.x
        info.position.y = pos.y
        info.last_seen_tick = tick
    end

    -- Mark location as mapped (coverage) so we don't enqueue frontier nodes repeatedly.
    mark_position_mapped(ps, entity.position.x, entity.position.y, 0.5)

    return is_new
end

----------------------------------------------------------------------
-- Hull point extraction and fingerprinting
----------------------------------------------------------------------

local function get_mapped_entity_points(ps)
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
        local x = quantize(info.position.x, q)
        local y = quantize(info.position.y, q)

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
            hash = hash_combine(hash, v)
        end
    end

    return points, count, hash
end

----------------------------------------------------------------------
-- Mode setting
----------------------------------------------------------------------

local function set_player_bot_mode(player, ps, new_mode)
    if not MODES.index[new_mode] then
        new_mode = "follow"
    end

    if ps.bot_mode == new_mode then
        return
    end

    ps.bot_mode = new_mode
    print_bot_message(player, "green", "mode set to %s", new_mode)

    if new_mode == "follow" then
        ps.bot_target_position = nil
        return
    end

    if new_mode == "survey" then
        ensure_survey_sets(ps)

        -- Reset the frontier queue and seen-set for a fresh survey pass.
        -- Do NOT reset mapped positions; those represent accumulated coverage.
        ps.survey_frontier = {}
        ps.survey_seen = {}

        local bot = ps.bot_entity
        local bpos = bot.position
        local start_a = ring_seed_for_center(bpos)
        add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 24, start_a, 0)
    end
end

----------------------------------------------------------------------
-- Follow mode
----------------------------------------------------------------------

local function follow_player(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local ppos = player.position
    local bpos = bot.position

    local prev = ps.last_player_position
    local left, right = false, false

    if prev then
        local dx = ppos.x - prev.x
        if dx < -0.1 then
            left = true
        elseif dx > 0.1 then
            right = true
        end
    end

    ps.last_player_position = {
        x = ppos.x,
        y = ppos.y
    }

    local side = BOT.movement.side_offset_distance
    local so = ps.last_player_side_offset_x or -side

    if left and so ~= side then
        so = side
    elseif right and so ~= -side then
        so = -side
    end

    ps.last_player_side_offset_x = so

    local follow = BOT.movement.follow_distance
    local dx = ppos.x - bpos.x
    local dy = ppos.y - bpos.y

    if dx * dx + dy * dy <= follow * follow then
        return
    end

    local target = {
        x = ppos.x + so,
        y = ppos.y - 2
    }
    move_bot_towards(player, bot, target)
end

----------------------------------------------------------------------
-- Wander mode
----------------------------------------------------------------------

local function pick_new_wander_target(bpos)
    local angle = math.random() * 2 * math.pi
    local step = BOT.wander.step_distance
    local min_d = step * 0.4
    local max_d = step
    local dist = min_d + (max_d - min_d) * math.random()

    return {
        x = bpos.x + math.cos(angle) * dist,
        y = bpos.y + math.sin(angle) * dist
    }
end

local function wander_bot(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target = ps.bot_target_position

    if not target then
        target = pick_new_wander_target(bot.position)
        ps.bot_target_position = target
    end

    move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local step = BOT.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.bot_target_position = nil

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.wander.detection_radius
    }

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char then
            set_player_bot_mode(player, ps, "survey")
            return
        end
    end
end

----------------------------------------------------------------------
-- Survey mode
----------------------------------------------------------------------

local function perform_survey_scan(player, ps, bot, tick)
    local surf = bot.surface
    local bpos = bot.position
    local char = player.character

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.survey.radius
    }

    local discovered_any = false

    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and is_static_mappable(e) then
            add_frontier_on_radius_edge(player, ps, bot, bpos, e.position, BOT.survey.radius)

            if upsert_mapped_entity(player, ps, e, tick) then
                discovered_any = true
            end
        end
    end

    local start_a = ring_seed_for_center(bpos)
    add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 12, start_a, 0)

    if not discovered_any then
        add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 12, start_a + math.pi / 12, 1.0)
    end

    return discovered_any
end

local function survey_bot(player, ps, bot, tick)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local target = ps.bot_target_position or get_nearest_frontier(ps, bot.position)

    if not target then
        set_player_bot_mode(player, ps, "follow")
        return
    end

    ps.bot_target_position = target
    move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local d2 = dx * dx + dy * dy

    local thr = BOT.survey.arrival_threshold
    if d2 > (thr * thr) then
        return
    end

    ps.bot_target_position = nil

    local discovered = perform_survey_scan(player, ps, bot, tick)
    if discovered then
        add_frontier_on_radius_edge(player, ps, bot, bpos, target, BOT.survey.radius)
    end
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local ps = get_player_state(player.index)

    -- Destroy the bot entity (if present).
    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_entity.destroy()
    end

    -- Clear ALL render objects / visuals.
    visuals.clear_all(ps)

    -- Disable + clear entity reference.
    ps.bot_entity = nil
    ps.bot_enabled = false

    ------------------------------------------------------------------
    -- Reset behavior state back to "follow".
    ------------------------------------------------------------------
    ps.bot_mode = "follow"
    ps.bot_target_position = nil

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT.movement.side_offset_distance

    ------------------------------------------------------------------
    -- Clear ALL survey / mapping point sets.
    ------------------------------------------------------------------
    ps.survey_mapped_entities = {}
    ps.survey_mapped_positions = {}
    ps.survey_frontier = {}
    ps.survey_done = {}
    ps.survey_seen = {}

    ------------------------------------------------------------------
    -- Clear ALL hull state (including incremental job + fingerprints).
    ------------------------------------------------------------------
    ps.hull = nil
    ps.hull_job = nil
    ps.hull_point_set = {}
    ps.hull_quantized_count = 0
    ps.hull_quantized_hash = 0
    ps.hull_tick = 0
    ps.hull_last_eval_tick = 0

    ------------------------------------------------------------------
    -- Clear any stored visual ids (so visuals code doesn't try to reuse them).
    -- visuals.clear_all(ps) should already destroy render ids; this just resets
    -- your bookkeeping tables to empty.
    ------------------------------------------------------------------
    ps.visuals = {
        bot_highlight = nil,
        lines = nil,
        radius_circle = nil,
        mapped_entities = {},
        survey_frontier = {},
        survey_done = {}
    }

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

local function create_player_bot(player)
    local ps = get_player_state(player.index)

    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_enabled = true
        return ps.bot_entity
    end

    local pos = player.position
    local ent = player.surface.create_entity {
        name = "mekatrol-game-play-bot",
        position = {pos.x - 2, pos.y - 2},
        force = player.force,
        raise_built = true
    }

    if not ent then
        print_bot_message(player, "red", "create failed")
        return nil
    end

    ps.bot_entity = ent
    ps.bot_enabled = true
    ent.destructible = true

    print_bot_message(player, "green", "created")
    return ent
end

----------------------------------------------------------------------
-- Hull scheduling and incremental processing
----------------------------------------------------------------------

local function evaluate_hull_need(ps, tick)
    -- Only evaluate at a coarse cadence to avoid redundant work.
    if tick % BOT.update_hull_interval ~= 0 then
        return
    end

    local points, qcount, qhash = get_mapped_entity_points(ps)

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
    ps.hull_job = polygon.start_concave_hull_job(points, 8, {
        max_k = 12
    })
    ps.hull_job.qcount = qcount
    ps.hull_job.qhash = qhash
end

local function step_hull_job(ps, tick)
    if not ps.hull_job then
        return
    end

    local step_budget = BOT.hull_steps_per_tick or 25
    local done, hull = polygon.step_concave_hull_job(ps.hull_job, step_budget)
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

----------------------------------------------------------------------
-- Visuals and behavior dispatch
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, tick)
    local bot = ps.bot_entity
    if not (bot and bot.valid) then
        return
    end

    -- Clear transient visuals each update; they are redrawn below.
    visuals.clear_lines(ps)
    visuals.draw_bot_highlight(player, ps)

    local radius = nil
    local radius_color = nil

    local target = ps.bot_target_position or player.position

    local line_color = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.1
    }

    if ps.bot_mode == "wander" then
        radius = BOT.wander.detection_radius
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif ps.bot_mode == "survey" then
        radius = BOT.survey.radius
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color
    end

    if radius and radius > 0 then
        visuals.draw_radius_circle(player, ps, bot, radius, radius_color)
    else
        visuals.clear_radius_circle(ps)
    end

    if target then
        visuals.draw_lines(player, ps, bot, target, line_color)
    end

    -- Mode behavior step.
    if ps.bot_mode == "follow" then
        follow_player(player, ps, bot)
    elseif ps.bot_mode == "wander" then
        wander_bot(player, ps, bot)
    elseif ps.bot_mode == "survey" then
        survey_bot(player, ps, bot, tick)
    end

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
    evaluate_hull_need(ps, tick)
    step_hull_job(ps, tick)

    -- Draw the most recently completed hull (if any).
    local hull = ps.hull
    if hull and #hull >= 2 then
        for i = 1, #hull do
            local a = hull[i]
            local b = hull[i % #hull + 1]

            visuals.draw_line(player, ps, a, b, {
                r = 1,
                g = 0,
                b = 0,
                a = 0.8
            })
        end
    end

    visuals.draw_survey_frontier(player, ps, bot)
    visuals.draw_survey_done(player, ps, bot)
end

----------------------------------------------------------------------
-- Hotkey handlers
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = get_player_state(p.index)
    if ps.bot_entity and ps.bot_entity.valid then
        destroy_player_bot(p, false)
    else
        create_player_bot(p)
    end
end

local function on_cycle_bot_mode(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = get_player_state(p.index)
    local cur = ps.bot_mode or "follow"
    local idx = MODES.index[cur] or 1

    idx = idx + 1
    if idx > #MODES.list then
        idx = 1
    end

    set_player_bot_mode(p, ps, MODES.list[idx])
end

----------------------------------------------------------------------
-- Event: Entity died
----------------------------------------------------------------------

local function on_entity_died(event)
    local ent = event.entity
    if not ent or ent.name ~= "mekatrol-game-play-bot" then
        return
    end

    for idx, ps in pairs(storage.game_bot or {}) do
        if ps.bot_entity == ent then
            local pl = game.get_player(idx)
            if pl and pl.valid then
                destroy_player_bot(pl, true)
                print_bot_message(pl, "yellow", "destroyed")
            else
                -- Player not valid; still clear state.
                visuals.clear_all(ps)
                storage.game_bot[idx] = nil
            end
            return
        end
    end
end

----------------------------------------------------------------------
-- Event: Player removed
----------------------------------------------------------------------

local function on_player_removed(event)
    ensure_storage_tables()

    local all = storage.game_bot
    local idx = event.player_index
    local ps = all[idx]
    if not ps then
        return
    end

    local p = game.get_player(idx)
    if p and p.valid then
        destroy_player_bot(p, true)
    else
        if ps.bot_entity and ps.bot_entity.valid then
            ps.bot_entity.destroy()
        end
    end

    all[idx] = nil
end

----------------------------------------------------------------------
-- Init and config
----------------------------------------------------------------------

script.on_init(function()
    ensure_storage_tables()
end)

script.on_configuration_changed(function(_)
    ensure_storage_tables()
end)

----------------------------------------------------------------------
-- Event registration
----------------------------------------------------------------------

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_bot_mode)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

----------------------------------------------------------------------
-- Tick handler
----------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % BOT.update_interval ~= 0 then
        return
    end

    -- Note: This mod currently drives only player 1 (as in your original).
    -- If you want multiplayer support, iterate game.connected_players instead.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local ps = get_player_state(player.index)
    if not ps then
        return
    end

    if ps.bot_enabled and ps.bot_entity and ps.bot_entity.valid then
        update_bot_for_player(player, ps, event.tick)
    end
end)
