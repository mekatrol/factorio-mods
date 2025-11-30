local pathfinding = {}

---------------------------------------------------
-- TILE HELPERS
---------------------------------------------------
local function round_to_tile_pos(pos)
    return {
        x = math.floor(pos.x + 0.5),
        y = math.floor(pos.y + 0.5)
    }
end

local function tile_key(x, y)
    return x .. "," .. y
end

---------------------------------------------------
-- WALL MAP / BLOCK CHECK
---------------------------------------------------
local function build_wall_map(surface, start_pos, target_pos, max_radius)
    local sp = round_to_tile_pos(start_pos)
    local tp = round_to_tile_pos(target_pos)

    max_radius = max_radius or 128

    local minx = math.min(sp.x, tp.x) - max_radius
    local maxx = math.max(sp.x, tp.x) + max_radius
    local miny = math.min(sp.y, tp.y) - max_radius
    local maxy = math.max(sp.y, tp.y) + max_radius

    local area = {{minx - 1, miny - 1}, {maxx + 1, maxy + 1}}

    local walls = surface.find_entities_filtered {
        area = area,
        type = "wall"
    }

    local wall_map = {}

    for _, w in pairs(walls) do
        if w.valid then
            local wp = round_to_tile_pos(w.position)
            wall_map[wp.x] = wall_map[wp.x] or {}
            wall_map[wp.x][wp.y] = true
        end
    end

    return wall_map, minx, maxx, miny, maxy
end

local function is_tile_blocked(wall_map, minx, maxx, miny, maxy, x, y)
    if x < minx or x > maxx or y < miny or y > maxy then
        return true
    end
    local col = wall_map[x]
    return col and col[y] or false
end

---------------------------------------------------
-- PUBLIC: WALL CHECK FOR ARBITRARY POSITION
---------------------------------------------------
function pathfinding.is_position_blocked_by_wall(surface, pos)
    if not (surface and pos) then
        return false
    end

    local area = {{pos.x - 0.4, pos.y - 0.4}, {pos.x + 0.4, pos.y + 0.4}}

    local walls = surface.find_entities_filtered {
        area = area,
        type = "wall"
    }

    return walls and #walls > 0
end

---------------------------------------------------
-- A* PATHFINDING
---------------------------------------------------
local function find_path_astar(surface, start_pos, target_pos, max_radius)
    local sp = round_to_tile_pos(start_pos)
    local tp = round_to_tile_pos(target_pos)

    if sp.x == tp.x and sp.y == tp.y then
        return {{
            x = target_pos.x,
            y = target_pos.y
        }}
    end

    local wall_map, minx, maxx, miny, maxy = build_wall_map(surface, start_pos, target_pos, max_radius or 128)

    if is_tile_blocked(wall_map, minx, maxx, miny, maxy, sp.x, sp.y) then
        return nil
    end

    local open = {}
    local open_lookup = {}
    local closed = {}
    local came_from = {}

    local function heuristic(x, y)
        local dx = math.abs(x - tp.x)
        local dy = math.abs(y - tp.y)
        return math.max(dx, dy)
    end

    local function push_open(node)
        open[#open + 1] = node
        open_lookup[node.key] = node
    end

    local function pop_best()
        local best_index = nil
        local best_f = nil

        for i, n in ipairs(open) do
            if not best_f or n.f < best_f then
                best_f = n.f
                best_index = i
            end
        end

        if not best_index then
            return nil
        end

        local n = open[best_index]
        table.remove(open, best_index)
        open_lookup[n.key] = nil
        return n
    end

    local function reconstruct_path(came_from_tbl, end_node, final_pos)
        local rev = {}
        local node = end_node

        while node do
            if node.parent_key == nil then
                break
            end

            rev[#rev + 1] = {
                x = node.x + 0.5,
                y = node.y + 0.5
            }
            node = came_from_tbl[node.parent_key]
        end

        local path = {}
        for i = #rev, 1, -1 do
            path[#path + 1] = rev[i]
        end

        if final_pos and #path > 0 then
            path[#path] = {
                x = final_pos.x,
                y = final_pos.y
            }
        end

        return path
    end

    local start_key = tile_key(sp.x, sp.y)
    local start_h = heuristic(sp.x, sp.y)
    local start_node = {
        x = sp.x,
        y = sp.y,
        g = 0,
        h = start_h,
        f = start_h,
        key = start_key,
        parent_key = nil
    }

    push_open(start_node)
    came_from[start_key] = start_node

    local best_node = start_node
    local best_h = start_h

    local NEIGHBORS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

    while true do
        local current = pop_best()
        if not current then
            if best_node and best_node ~= start_node then
                return reconstruct_path(came_from, best_node, nil)
            else
                return nil
            end
        end

        if current.x == tp.x and current.y == tp.y then
            return reconstruct_path(came_from, current, target_pos)
        end

        closed[current.key] = true

        for _, d in ipairs(NEIGHBORS) do
            local nx = current.x + d[1]
            local ny = current.y + d[2]
            local nkey = tile_key(nx, ny)

            if not (d[1] ~= 0 and d[2] ~= 0 and
                (is_tile_blocked(wall_map, minx, maxx, miny, maxy, current.x + d[1], current.y) or
                    is_tile_blocked(wall_map, minx, maxx, miny, maxy, current.x, current.y + d[2]))) then

                if not closed[nkey] and not is_tile_blocked(wall_map, minx, maxx, miny, maxy, nx, ny) then
                    local move_cost = (d[1] ~= 0 and d[2] ~= 0) and 1.41421356237 or 1
                    local tentative_g = current.g + move_cost
                    local existing = open_lookup[nkey]

                    if not existing or tentative_g < existing.g then
                        local h = heuristic(nx, ny)
                        local node = existing or {
                            x = nx,
                            y = ny,
                            key = nkey
                        }
                        node.g = tentative_g
                        node.h = h
                        node.f = tentative_g + h
                        node.parent_key = current.key

                        came_from[nkey] = node

                        if h < best_h then
                            best_h = h
                            best_node = node
                        end

                        if not existing then
                            push_open(node)
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------
-- PATH VISUALS + STATE RESET
---------------------------------------------------
function pathfinding.clear_bot_path_visuals(pdata)
    if not pdata.vis_bot_path then
        return
    end

    for _, obj in pairs(pdata.vis_bot_path) do
        if obj and obj.valid then
            obj:destroy()
        end
    end

    pdata.vis_bot_path = nil
end

function pathfinding.reset_bot_path(pdata)
    if not pdata then
        return
    end

    pdata.bot_path = nil
    pdata.bot_path_index = 1
    pdata.bot_path_target = nil

    pathfinding.clear_bot_path_visuals(pdata)

    if pdata.vis_current_waypoint and pdata.vis_current_waypoint.valid then
        pdata.vis_current_waypoint:destroy()
    end
    pdata.vis_current_waypoint = nil
end

local function ensure_bot_path(bot, target_pos, pdata)
    if not (bot and bot.valid and target_pos and pdata) then
        return
    end

    local tp = {
        x = target_pos.x,
        y = target_pos.y
    }

    if pdata.bot_path_target then
        local dx = pdata.bot_path_target.x - tp.x
        local dy = pdata.bot_path_target.y - tp.y
        local d2 = dx * dx + dy * dy

        if d2 < 0.25 and pdata.bot_path and #pdata.bot_path > 0 then
            return
        end
    end

    local surface = bot.surface
    local path = find_path_astar(surface, bot.position, tp, 32)

    pathfinding.clear_bot_path_visuals(pdata)
    pdata.vis_bot_path = {}

    local target_circle = rendering.draw_circle {
        color = {
            r = 1,
            g = 0,
            b = 1,
            a = 1
        },
        radius = 0.5,
        filled = true,
        target = tp,
        surface = surface,
        only_in_alt_mode = false
    }
    table.insert(pdata.vis_bot_path, target_circle)

    local line = rendering.draw_line {
        color = {
            r = 1,
            g = 1,
            b = 1,
            a = 0.5
        },
        width = 1,
        from = bot.position,
        to = tp,
        surface = surface,
        only_in_alt_mode = false
    }
    table.insert(pdata.vis_bot_path, line)

    if path and #path > 0 then
        pdata.bot_path = path
        pdata.bot_path_index = 1
        pdata.bot_path_target = tp

        local prev = nil
        for _, wp in ipairs(path) do
            local circle = rendering.draw_circle {
                color = {
                    r = 1,
                    g = 1,
                    b = 0,
                    a = 1
                },
                radius = 0.2,
                filled = true,
                target = wp,
                surface = surface,
                only_in_alt_mode = false
            }
            table.insert(pdata.vis_bot_path, circle)

            if prev then
                local l = rendering.draw_line {
                    color = {
                        r = 1,
                        g = 1,
                        b = 0,
                        a = 0.5
                    },
                    width = 1,
                    from = prev,
                    to = wp,
                    surface = surface,
                    only_in_alt_mode = false
                }
                table.insert(pdata.vis_bot_path, l)
            end

            prev = wp
        end
    else
        pdata.bot_path = nil
        pdata.bot_path_index = 1
        pdata.bot_path_target = nil
    end
end

---------------------------------------------------
-- MOVEMENT ALONG PATH
---------------------------------------------------
local function step_bot_towards(bot, tp, step_distance)
    if not (bot and bot.valid and tp) then
        return
    end

    local bp = bot.position
    local dx = tp.x - bp.x
    local dy = tp.y - bp.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq == 0 then
        return
    end

    local dist = math.sqrt(dist_sq)
    local step = step_distance or 0.8

    if dist <= step then
        bot.teleport {
            x = tp.x,
            y = tp.y
        }
        return
    end

    local scale = step / dist

    bot.teleport {
        x = bp.x + dx * scale,
        y = bp.y + dy * scale
    }
end

local function dist_sq(ax, ay, bx, by)
    local ddx = bx - ax
    local ddy = by - ay
    return ddx * ddx + ddy * ddy
end

function pathfinding.move_bot_to_a_star(bot, target, pdata, step_distance)
    if not (bot and bot.valid and target and pdata) then
        return
    end

    local tp

    if type(target) == "table" and target.position ~= nil then
        tp = target.position
    elseif type(target) == "table" and target.x ~= nil and target.y ~= nil then
        tp = target
    elseif type(target) == "table" and target[1] ~= nil and target[2] ~= nil then
        tp = {
            x = target[1],
            y = target[2]
        }
    else
        return
    end

    ensure_bot_path(bot, tp, pdata)

    local path = pdata.bot_path
    if not path or #path == 0 then
        return
    end

    local idx = pdata.bot_path_index or 1
    if idx < 1 then
        idx = 1
    elseif idx > #path then
        idx = #path
    end

    local bp = bot.position
    local waypoint = path[idx]

    local dx = waypoint.x - bp.x
    local dy = waypoint.y - bp.y
    local d2 = dx * dx + dy * dy

    if d2 < 0.04 then
        idx = idx + 1
        if idx > #path then
            pathfinding.reset_bot_path(pdata)
            return
        end
        waypoint = path[idx]
        bp = bot.position
    end

    local final_target = pdata.bot_path_target or tp
    local bot_to_target_sq = dist_sq(bp.x, bp.y, final_target.x, final_target.y)

    while idx <= #path do
        waypoint = path[idx]
        local wp_to_target_sq = dist_sq(waypoint.x, waypoint.y, final_target.x, final_target.y)

        if wp_to_target_sq <= bot_to_target_sq + 0.0001 then
            break
        end

        idx = idx + 1
    end

    if idx > #path then
        pathfinding.reset_bot_path(pdata)
        return
    end

    waypoint = path[idx]
    pdata.bot_path_index = idx

    if pdata.vis_current_waypoint and pdata.vis_current_waypoint.valid then
        pdata.vis_current_waypoint.target = waypoint
    else
        pdata.vis_current_waypoint = rendering.draw_circle {
            color = {
                r = 1,
                g = 1,
                b = 0,
                a = 1
            },
            radius = 0.6,
            filled = false,
            target = waypoint,
            surface = bot.surface,
            only_in_alt_mode = false
        }
    end

    step_bot_towards(bot, waypoint, step_distance)
end

function pathfinding.follow_player_a_star(bot, player, pdata, follow_distance, step_distance)
    if not (bot and bot.valid and player and player.valid) then
        return
    end

    local bp = bot.position
    local pp = player.position

    local target_pos = {
        x = pp.x - 2.0,
        y = pp.y - 2.0
    }

    local dx = target_pos.x - bp.x
    local dy = target_pos.y - bp.y
    local d2 = dx * dx + dy * dy

    local desired_sq = (follow_distance or 1.0) * (follow_distance or 1.0)

    if d2 > desired_sq then
        pathfinding.move_bot_to_a_star(bot, target_pos, pdata, step_distance)
    end
end

return pathfinding
