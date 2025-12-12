----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Notes:
-- - This file uses a consistent parameter order for context-aware helpers:
--     (player, ps, bot, ...)
-- - Survey frontier insertion is now strict:
--     1) A frontier node is only queued if there is at least one static mappable entity
--        near that node position.
--     2) A frontier node is not queued if that position is already mapped.
--     3) A frontier node is not queued if it was already seen/queued before.
-- - Survey now tracks mapped positions independently of mapped entities:
--     ps.survey_mapped_positions["x,y"] = true
--   This prevents repeatedly re-queuing frontier nodes for already-covered locations.
-- - Comments use consistent casing and are intentionally verbose.
----------------------------------------------------------------------
local config = require("configuration")
local polygon = require("polygon")
local visuals = require("visuals")

-- Config aliases.
local BOT = config.bot
local MODES = config.modes
local NON_STATIC_TYPES = config.non_static_types
local mapped_entities_hull = nil

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

            -- Survey data.
            survey_mapped_entities = {}, -- Map: entity_key -> entity_info.
            survey_mapped_positions = {}, -- Set: "x,y" (quantized) -> true.
            survey_frontier = {}, -- Queue: { {x=, y=}, ... }.
            survey_done = {}, -- positions already surveyed
            survey_seen = {}, -- Set: "x,y" (quantized) -> true.

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

    -- Fallback: name + position + surface, which is good enough for most static entities.
    local p = entity.position
    return string.format("%s@%s,%s#%d", entity.name, p.x, p.y, entity.surface.index)
end

local function get_position_key(x, y, q)
    -- Keep this stable; it is used as a set key.
    -- For q=0.5 we keep 1 decimal place.
    if q == 0.5 then
        return string.format("%.1f,%.1f", x, y)
    end

    -- Fallback formatting for other quantization values.
    return string.format("%.2f,%.2f", x, y)
end

----------------------------------------------------------------------
-- Survey helpers
----------------------------------------------------------------------

local function quantize(v, step)
    return math.floor(v / step + 0.5) * step
end

local function ensure_survey_sets(ps)
    -- Frontier queue and sets may be missing in older saves or after partial state resets.
    ps.survey_frontier = ps.survey_frontier or {}
    ps.survey_done = ps.survey_done or {}
    ps.survey_seen = ps.survey_seen or {}
    ps.survey_mapped_positions = ps.survey_mapped_positions or {}
end

local function mark_position_mapped(ps, x, y, q)
    -- Mark a quantized position as mapped so we do not add frontier nodes for it again.
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
    -- Stable-ish angle seed so rings do not always start at 0 radians.
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
    local done = ps.survey_done
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
    table.remove(frontier, best_i) -- remove from frontier list
    table.insert(done, node) -- add to done list
    return node
end

local function add_frontier_node(player, ps, bot, x, y)
    ensure_survey_sets(ps)

    -- Quantize to half-tiles; adjust q if you want coarser/finer frontiers.
    local q = 0.5
    x = quantize(x, q)
    y = quantize(y, q)

    local key = get_position_key(x, y, q)
    if ps.survey_seen[key] == true then
        -- we have already seen this node
        return
    end

    -- Do not enqueue nodes for locations that have already been mapped.
    if is_position_mapped(ps, x, y, q) then
        return
    end

    -- Only enqueue if there is at least one static mappable entity near this position.
    -- "Contains an entity at that position" is approximated by a very small radius.
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

    -- Mark as seen and enqueue.
    ps.survey_seen[key] = true
    table.insert(ps.survey_frontier, {
        x = x,
        y = y
    })
end

local function add_ring_frontiers(player, ps, bot, center, radius, count, start_angle, radial_offset)
    -- Radial_offset lets you place points slightly outside the scan radius.
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
    -- Add frontier nodes on the scan edge in the direction of a detected entity.
    -- This helps the survey expand outward along interesting directions.
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

    -- Primary edge point in the entity direction.
    local ex = center_pos.x + nx * radius
    local ey = center_pos.y + ny * radius
    add_frontier_node(player, ps, bot, ex, ey)

    -- Also add two slight angular offsets to broaden coverage.
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

    -- Mark the entity position as mapped so we do not re-add frontier nodes for this location.
    -- This uses the same quantization as frontier nodes (half-tile).
    mark_position_mapped(ps, entity.position.x, entity.position.y, 0.5)

    return is_new
end

local function get_mapped_entity_points(ps)
    local points = {}

    for _, info in pairs(ps.survey_mapped_entities) do
        points[#points + 1] = {
            x = info.position.x,
            y = info.position.y
        }
    end

    return points
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
        -- Do not reset mapped positions here; they represent accumulated coverage.
        ps.survey_frontier = {}
        ps.survey_seen = {}

        -- add frontier ring from current position
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

    -- Detect movement direction.
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

    -- Update side offset.
    local side = BOT.movement.side_offset_distance
    local so = ps.last_player_side_offset_x or -side
    if left and so ~= side then
        so = side
    elseif right and so ~= -side then
        so = -side
    end
    ps.last_player_side_offset_x = so

    -- Check follow distance.
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
        -- Not yet reached target position.
        return
    end

    -- Target reached, pick a new target next iteration.
    ps.bot_target_position = nil

    -- Detect nearby entities and switch to survey if something is found.
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
            -- Push exploration outward where we detected something.
            add_frontier_on_radius_edge(player, ps, bot, bpos, e.position, BOT.survey.radius)

            -- Record entity mapping.
            if upsert_mapped_entity(player, ps, e, tick) then
                discovered_any = true
            end
        end
    end

    -- Expand around the scan radius edge (subject to add_frontier_node rules).
    local start_a = ring_seed_for_center(bpos)
    add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 12, start_a, 0)

    -- If nothing was discovered, optionally push outward slightly to keep expanding coverage.
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

    -- If bot was not targetting and there are no more frontiers then terminate survey mode
    if not target then
        -- No more frontier nodes, return to follow mode.
        set_player_bot_mode(player, ps, "follow")
        return
    end

    -- Target the frontier position and move toward it.
    ps.bot_target_position = target
    move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local d2 = dx * dx + dy * dy

    local thr = BOT.survey.arrival_threshold

    if d2 > (thr * thr) then
        -- Still not at target so return
        return
    end

    -- Bot arrived at survey location
    ps.bot_target_position = nil

    local discovered = perform_survey_scan(player, ps, bot, tick)
    if discovered then
        -- Push exploration outward where we detected something
        add_frontier_on_radius_edge(player, ps, bot, bpos, target, BOT.survey.radius)
    end
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local ps = get_player_state(player.index)

    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_entity.destroy()
    end

    visuals.clear_all(ps)

    ps.bot_entity = nil
    ps.bot_enabled = false

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
-- Visuals and behavior dispatch
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, tick)
    local bot = ps.bot_entity
    if not (bot and bot.valid) then
        return
    end

    visuals.clear_lines(ps)
    visuals.draw_bot_highlight(player, ps)

    local radius = nil
    local radius_color = nil

    -- Target is either a mode-specific target or the player position.
    local target = ps.bot_target_position or player.position

    -- Default line color (muted gray).
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

    if ps.bot_mode == "follow" then
        follow_player(player, ps, bot)
    elseif ps.bot_mode == "wander" then
        wander_bot(player, ps, bot)
    elseif ps.bot_mode == "survey" then
        survey_bot(player, ps, bot, tick)
    end

    if tick % BOT.update_hull_interval ~= 0 then
        local points = get_mapped_entity_points(ps)

        if #points >= 3 then
            local hull = polygon.convex_hull(points)

            -- Tune k:
            --   k = 3..6  : more concave (fits tighter, can be noisier)
            --   k = 8..15 : smoother (approaches convex hull)
            -- local hull = polygon.concave_hull(points, 6)

            mapped_entities_hull = hull
        end
    end

    if mapped_entities_hull then
        -- mapped_entities_hull is an ordered CCW polygon
        -- { {x,y}, {x,y}, ... }
        for i = 1, #mapped_entities_hull do
            local a = mapped_entities_hull[i]
            local b = mapped_entities_hull[i % #mapped_entities_hull + 1]

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

    ensure_storage_tables()

    for idx, ps in pairs(storage.game_bot) do
        if ps.bot_entity == ent then
            ps.bot_entity = nil
            ps.bot_enabled = false
            visuals.clear_all(ps)

            local pl = game.get_player(idx)
            if pl and pl.valid then
                print_bot_message(pl, "yellow", "destroyed")
            end
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
