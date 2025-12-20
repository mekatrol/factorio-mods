local mapping = {}

local config = require("configuration")
local state = require("state")
local utils = require("utils")
local visuals = require("visuals")

local BOT = config.bot
local NON_STATIC_TYPES = config.non_static_types

----------------------------------------------------------------------
-- Movement and position helpers
----------------------------------------------------------------------

function mapping.resolve_target_position(target)
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

function mapping.move_bot_towards(player, bot, target)
    if not (bot and bot.valid) then
        return
    end

    local pos, err = mapping.resolve_target_position(target)
    if not pos then
        utils.print_bot_message(player, "red", "invalid target: %s", err or "?")
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

----------------------------------------------------------------------
-- Survey helpers
----------------------------------------------------------------------

function mapping.quantize(v, step)
    return math.floor(v / step + 0.5) * step
end

function mapping.ensure_survey_sets(ps)
    ps.survey_frontier = ps.survey_frontier or {}
    ps.survey_done = ps.survey_done or {}
    ps.survey_seen = ps.survey_seen or {}
    ps.survey_mapped_positions = ps.survey_mapped_positions or {}
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

function mapping.add_frontier_node(player, ps, bot, x, y)
    mapping.ensure_survey_sets(ps)

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
        radius = 0.49
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

function mapping.add_ring_frontiers(player, ps, bot, center, radius, count, start_angle, radial_offset)
    mapping.ensure_survey_sets(ps)

    radial_offset = radial_offset or 0
    start_angle = start_angle or 0

    if count <= 0 then
        return
    end

    local step = (2 * math.pi) / count
    local r = radius + radial_offset

    for i = 0, count - 1 do
        local a = start_angle + i * step
        mapping.add_frontier_node(player, ps, bot, center.x + math.cos(a) * r, center.y + math.sin(a) * r)
    end
end

function mapping.add_frontier_on_radius_edge(player, ps, bot, center_pos, point_pos, radius)
    mapping.ensure_survey_sets(ps)

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
    mapping.add_frontier_node(player, ps, bot, ex, ey)

    local angle = math.atan2(ny, nx)
    local delta = math.rad(15)

    mapping.add_frontier_node(player, ps, bot, center_pos.x + math.cos(angle + delta) * radius,
        center_pos.y + math.sin(angle + delta) * radius)

    mapping.add_frontier_node(player, ps, bot, center_pos.x + math.cos(angle - delta) * radius,
        center_pos.y + math.sin(angle - delta) * radius)
end

----------------------------------------------------------------------
-- Mapping upsert
----------------------------------------------------------------------

function mapping.upsert_mapped_entity(player, ps, entity, tick)
    local key = mapping.get_entity_key(entity)
    if not key then
        return false
    end

    mapping.ensure_survey_sets(ps)

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
            local box_id = visuals.draw_mapped_entity_box(player, ps, entity)
            ps.visuals.mapped_entities[key] = box_id
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
            hash = utils.hash_combine(hash, v)
        end
    end

    return points, count, hash
end

return mapping
