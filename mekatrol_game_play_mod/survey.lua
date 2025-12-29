local survey = {}

local config = require("config")
local module = require("module")
local polygon = require("polygon")
local positioning = require("positioning")
local util = require("util")

local BOT_CONF = config.bot

----------------------------------------------------------------------
-- Tile helpers
----------------------------------------------------------------------

local function tile_xy_from_pos(pos)
    return math.floor(pos.x), math.floor(pos.y)
end

local function tile_center(tx, ty)
    return {
        x = tx + 0.5,
        y = ty + 0.5
    }
end

local function tile_key(tx, ty)
    return tostring(tx) .. "," .. tostring(ty)
end

-- Checks whether the *tile* at (tx,ty) contains at least one entity with the tracked name.
-- Uses a 0.49 radius around tile center so it stays within the tile.
local function tile_has_name(surface, entity_name, tx, ty)
    if not entity_name then
        return false
    end

    local c = tile_center(tx, ty)
    local found = surface.find_entities_filtered {
        position = c,
        radius = 0.49,
        name = entity_name
    }

    return #found > 0
end

-- A boundary tile is an "inside" tile with at least one 4-neighbor "outside" tile.
local function is_boundary_tile(surface, entity_name, tx, ty)
    if not tile_has_name(surface, entity_name, tx, ty) then
        return false
    end

    -- 4-neighbors
    if not tile_has_name(surface, entity_name, tx, ty - 1) then
        return true
    end -- north
    if not tile_has_name(surface, entity_name, tx + 1, ty) then
        return true
    end -- east
    if not tile_has_name(surface, entity_name, tx, ty + 1) then
        return true
    end -- south
    if not tile_has_name(surface, entity_name, tx - 1, ty) then
        return true
    end -- west

    return false
end

local function find_nearby_resource_tile(surface, name, pos, max_r)
    local cx, cy = tile_xy_from_pos(pos)

    for r = 0, max_r do
        for dx = -r, r do
            for dy = -r, r do
                local tx = cx + dx
                local ty = cy + dy
                if tile_has_name(surface, name, tx, ty) then
                    return tx, ty
                end
            end
        end
    end

    return nil
end

----------------------------------------------------------------------
-- Moore-neighborhood clockwise boundary tracing over tiles
--
-- Standard approach:
--   p0 = start boundary tile
--   b0 = backtrack tile (initially west of p0)
--   At each step: search neighbors of p starting from neighbor after b in clockwise order,
--   pick first boundary tile found as next p, and set new b to the neighbor immediately
--   before that (counterclockwise) in the neighbor list.
-- Stop when we return to p0 and next == p1.
----------------------------------------------------------------------

-- Clockwise neighbor order (Moore neighborhood):
-- 0: NW, 1: N, 2: NE, 3: E, 4: SE, 5: S, 6: SW, 7: W
local N8 = {{
    dx = -1,
    dy = -1
}, -- NW
{
    dx = 0,
    dy = -1
}, -- N
{
    dx = 1,
    dy = -1
}, -- NE
{
    dx = 1,
    dy = 0
}, -- E
{
    dx = 1,
    dy = 1
}, -- SE
{
    dx = 0,
    dy = 1
}, -- S
{
    dx = -1,
    dy = 1
}, -- SW
{
    dx = -1,
    dy = 0
} -- W
}

local function neighbor_index(from_tx, from_ty, to_tx, to_ty)
    local dx = to_tx - from_tx
    local dy = to_ty - from_ty
    for i = 1, 8 do
        local n = N8[i]
        if n.dx == dx and n.dy == dy then
            return i
        end
    end
    return nil
end

local function moore_next(surface, entity_name, p_tx, p_ty, b_tx, b_ty)
    -- start scanning from the neighbor *after* backtrack neighbor, clockwise
    local b_idx = neighbor_index(p_tx, p_ty, b_tx, b_ty) or 8 -- default W
    local start_idx = (b_idx % 8) + 1

    for step = 0, 7 do
        local i = ((start_idx - 1 + step) % 8) + 1
        local n = N8[i]
        local ntx = p_tx + n.dx
        local nty = p_ty + n.dy

        if is_boundary_tile(surface, entity_name, ntx, nty) then
            -- New backtrack is the neighbor just before i (counterclockwise)
            local prev_i = ((i - 2) % 8) + 1
            local pn = N8[prev_i]
            local nb_tx = p_tx + pn.dx
            local nb_ty = p_ty + pn.dy

            return ntx, nty, nb_tx, nb_ty
        end
    end

    return nil
end

----------------------------------------------------------------------
-- Trace state
----------------------------------------------------------------------

local function ensure_trace(ps, bot)
    bot.task.survey_trace = bot.task.survey_trace or nil
end

local function start_trace_from_found(ps, bot)
    local tx, ty = tile_xy_from_pos(bot.entity.position)

    bot.task.survey_trace = {
        phase = "north", -- "north" then "edge"
        origin_tx = tx, -- where we first saw it (not strictly required)
        origin_ty = ty,

        -- will be set when north phase ends:
        start_tx = nil,
        start_ty = nil,

        -- moore state:
        p_tx = nil,
        p_ty = nil,
        b_tx = nil,
        b_ty = nil,

        -- closure:
        p1_tx = nil,
        p1_ty = nil,
        started_edge = false,
        boundary = {},

        -- unstick guard
        north_stuck_attempts = 0,
        north_last_tx = tx,
        north_last_ty = ty
    }
end

----------------------------------------------------------------------
-- Survey task
----------------------------------------------------------------------

function survey.perform_survey_scan(player, ps, bot, tick)
    local surf = bot.entity.surface
    local bpos = bot.entity.position

    if not bot.task.survey_entity then
        return false
    end

    local find_name = bot.task.survey_entity.name

    util.print(player, "red", "bot.task.survey_entity: name=%s, type=%s", bot.task.survey_entity.name,
        bot.task.survey_entity.type)

    local found = util.find_entities(player, bpos, BOT_CONF.search.detection_radius, surf, find_name, true, true)

    if #found == 0 then
        return false
    end

    -- If we're not already tracing, start.
    ensure_trace(ps, bot)
    if not bot.task.survey_trace then
        start_trace_from_found(ps, bot)
    end

    return true
end

local function switch_to_next_task(player, ps, state, bot)
    local bot_module = module.get_module(bot.name)

    local next_task = bot.task.next_task or "search"

    bot_module.set_bot_task(player, ps, next_task, nil, bot.task.args)
    bot.task.target_position = nil
    bot.task.survey_trace = nil
end

local function trace_step(player, ps, state, visual, bot)
    local entity_name = nil
    local entity = nil

    if bot.task.survey_entity then
        entity = bot.task.survey_entity
        entity_name = entity.name
    end

    local tr = bot.task.survey_trace
    if not tr then
        return nil
    end

    local surf = bot.entity.surface

    if tr.phase == "north" then
        -- Walk due north until the next tile does NOT contain the resource.
        local tx, ty = tile_xy_from_pos(bot.entity.position)

        local MAX_NORTH_STUCK = 30 -- adjust (30 attempts is usually enough)

        if tx == tr.north_last_tx and ty == tr.north_last_ty then
            tr.north_stuck_attempts = (tr.north_stuck_attempts or 0) + 1
            if tr.north_stuck_attempts >= MAX_NORTH_STUCK then
                -- Abort trace; survey will restart when it finds the resource again
                bot.task.survey_trace = nil
                return nil
            end
        else
            tr.north_last_tx = tx
            tr.north_last_ty = ty
            tr.north_stuck_attempts = 0
        end

        -- If current tile doesn't actually have the resource, snap to origin tile center first.
        if not tile_has_name(surf, entity_name, tx, ty) then
            local found_tx, found_ty = find_nearby_resource_tile(surf, entity_name, bot.entity.position,
                math.ceil(BOT_CONF.survey.radius) + 1)
            if found_tx then
                tr.origin_tx = found_tx
                tr.origin_ty = found_ty
                return tile_center(found_tx, found_ty)
            end

            -- No nearby resource tile; abort trace so scan can restart later
            bot.task.survey_trace = nil
            return nil
        end

        local next_ty = ty - 1 -- due north in Factorio coords
        if tile_has_name(surf, entity_name, tx, next_ty) then
            return tile_center(tx, next_ty)
        end

        -- Next tile north is outside: current tile is our "north edge" start.
        tr.start_tx = tx
        tr.start_ty = ty

        -- Ensure we start on a boundary tile; if not, search nearby for one (tight, local).
        if not is_boundary_tile(surf, entity_name, tr.start_tx, tr.start_ty) then
            local found_boundary = false
            for i = 1, 8 do
                local n = N8[i]
                local ntx = tr.start_tx + n.dx
                local nty = tr.start_ty + n.dy
                if is_boundary_tile(surf, entity_name, ntx, nty) then
                    tr.start_tx = ntx
                    tr.start_ty = nty
                    found_boundary = true
                    break
                end
            end

            if not found_boundary then
                -- Can't find a boundary; abort.
                bot.task.survey_trace = nil
                return nil
            end
        end

        -- Initialize Moore trace:
        tr.phase = "edge"
        tr.p_tx = tr.start_tx
        tr.p_ty = tr.start_ty
        tr.b_tx = tr.p_tx - 1 -- backtrack = west of start
        tr.b_ty = tr.p_ty
        tr.boundary = {tile_center(tr.p_tx, tr.p_ty)}

        tr.started_edge = false
        tr.p1_tx = nil
        tr.p1_ty = nil

        -- First edge move:
        local nx, ny, nbx, nby = moore_next(surf, entity_name, tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty)
        if not nx then
            bot.task.survey_trace = nil
            return nil
        end

        tr.p1_tx = nx
        tr.p1_ty = ny
        tr.started_edge = true

        -- Advance state to first step
        tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty = nx, ny, nbx, nby

        -- Record boundary point for rendering/storage
        tr.boundary[#tr.boundary + 1] = tile_center(tr.p_tx, tr.p_ty)

        return tile_center(tr.p_tx, tr.p_ty)
    end

    if tr.phase == "edge" then
        -- Closed when we are back at start AND the next step would be p1.
        local nx, ny, nbx, nby = moore_next(surf, entity_name, tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty)
        if not nx then
            bot.task.survey_trace = nil
            return nil
        end

        if tr.started_edge and tr.p_tx == tr.start_tx and tr.p_ty == tr.start_ty and nx == tr.p1_tx and ny == tr.p1_ty then
            local entity_group = module.get_module("entity_group")

            -- Completed loop: persist + render group.
            entity_group.ensure_entity_groups(ps)

            local boundary = tr.boundary or {}

            -- add to boundary group
            entity_group.add_boundary(player, ps, visual, boundary, entity, surf.index)

            -- Switch back to survey task to find next entity
            switch_to_next_task(player, ps, state, bot)
            return nil
        end

        tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty = nx, ny, nbx, nby

        -- Record boundary point for rendering/storage
        tr.boundary[#tr.boundary + 1] = tile_center(tr.p_tx, tr.p_ty)

        return tile_center(tr.p_tx, tr.p_ty)
    end

    return nil
end

function survey.update(player, ps, state, visual, bot, tick)
    if not (player and player.valid and bot and bot.entity.valid) then
        return
    end

    local entity_group = module.get_module("entity_group")

    -- If we are tracing, drive movement purely from the trace state machine.
    ensure_trace(ps, bot)

    if bot.task.survey_trace then
        local target_pos = bot.task.target_position
        if not target_pos then
            target_pos = trace_step(player, ps, state, visual, bot)
            bot.task.target_position = target_pos
        end

        if not target_pos then
            return
        end

        positioning.move_entity_towards(player, bot.entity, target_pos)

        local bpos = bot.entity.position

        if not positioning.positions_are_close(target_pos, bpos, BOT_CONF.survey.arrival_threshold) then
            return
        end

        -- Arrived; request next trace target next update.
        bot.task.target_position = nil
        return
    end

    if not bot.task.survey_entity then
        return
    end

    -- For single-tile survey targets (e.g. crude-oil), just add it as self contained polygon
    if entity_group.is_survey_single_target(bot.task.survey_entity) then
        entity_group.add_single_tile_entity_group(player, ps, visual, bot.entity.surface_index, bot.task.survey_entity)

        -- Switch back to survey task to find next entity
        switch_to_next_task(player, ps, state, bot)
    else
        -- Not tracing yet: just scan where we are; when we see the resource, tracing starts.
        survey.perform_survey_scan(player, ps, bot, tick)
    end
end

return survey
