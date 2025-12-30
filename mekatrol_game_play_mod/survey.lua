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

--- Convert a world position (float) to a tile coordinate (int) by flooring.
--- @param world_position table {x=number, y=number}
--- @return integer tile_x
--- @return integer tile_y
local function tile_coordinates_from_world_position(world_position)
    return math.floor(world_position.x), math.floor(world_position.y)
end

--- Convert tile coordinates into the world position of the tile center.
--- @param tile_x integer
--- @param tile_y integer
--- @return table world_position {x=number, y=number}
local function world_position_at_tile_center(tile_x, tile_y)
    return {
        x = tile_x + 0.5,
        y = tile_y + 0.5
    }
end

--- Generate a stable string key for a tile coordinate.
--- @param tile_x integer
--- @param tile_y integer
--- @return string key
local function tile_key_from_coordinates(tile_x, tile_y)
    return tostring(tile_x) .. "," .. tostring(tile_y)
end

--- Returns whether the tile at (tile_x, tile_y) contains at least one entity with entity_name.
--- Implementation detail:
---   Uses a radius of 0.49 around the tile center to stay within the tile footprint.
--- @param surface LuaSurface
--- @param entity_name string|nil
--- @param tile_x integer
--- @param tile_y integer
--- @return boolean
local function tile_contains_tracked_entity(surface, entity_name, tile_x, tile_y)
    if not entity_name then
        return false
    end

    local tile_center_world_position = world_position_at_tile_center(tile_x, tile_y)
    local entities_found = surface.find_entities_filtered {
        position = tile_center_world_position,
        radius = 0.49,
        name = entity_name
    }

    return #entities_found > 0
end

--- A boundary tile is an “inside tile” with at least one 4-neighbor “outside tile”.
--- 4-neighbors: north, east, south, west.
--- @param surface LuaSurface
--- @param entity_name string|nil
--- @param tile_x integer
--- @param tile_y integer
--- @return boolean
local function tile_is_boundary_tile(surface, entity_name, tile_x, tile_y)
    -- Must be inside first.
    if not tile_contains_tracked_entity(surface, entity_name, tile_x, tile_y) then
        return false
    end

    -- North
    if not tile_contains_tracked_entity(surface, entity_name, tile_x, tile_y - 1) then
        return true
    end
    -- East
    if not tile_contains_tracked_entity(surface, entity_name, tile_x + 1, tile_y) then
        return true
    end
    -- South
    if not tile_contains_tracked_entity(surface, entity_name, tile_x, tile_y + 1) then
        return true
    end
    -- West
    if not tile_contains_tracked_entity(surface, entity_name, tile_x - 1, tile_y) then
        return true
    end

    return false
end

--- Search outward from a given world position for any nearby tile containing the target entity.
--- This is used to “snap back” to a valid inside tile if the bot drifted off the resource area.
--- @param surface LuaSurface
--- @param entity_name string
--- @param world_position table {x=number, y=number}
--- @param maximum_search_radius_tiles integer
--- @return integer|nil found_tile_x
--- @return integer|nil found_tile_y
local function find_nearest_tile_containing_entity(surface, entity_name, world_position, maximum_search_radius_tiles)
    local center_tile_x, center_tile_y = tile_coordinates_from_world_position(world_position)

    for radius_tiles = 0, maximum_search_radius_tiles do
        for delta_x = -radius_tiles, radius_tiles do
            for delta_y = -radius_tiles, radius_tiles do
                local candidate_tile_x = center_tile_x + delta_x
                local candidate_tile_y = center_tile_y + delta_y

                if tile_contains_tracked_entity(surface, entity_name, candidate_tile_x, candidate_tile_y) then
                    return candidate_tile_x, candidate_tile_y
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

-- Clockwise Moore-neighbourhood order:
--   1: NW, 2: N, 3: NE, 4: E, 5: SE, 6: S, 7: SW, 8: W
local MOORE_NEIGHBOR_OFFSETS_CLOCKWISE = {{
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

--- Find the 1..8 neighbor index for a tile-to-tile step.
--- @param from_tile_x integer
--- @param from_tile_y integer
--- @param to_tile_x integer
--- @param to_tile_y integer
--- @return integer|nil neighbor_index_1_to_8
local function moore_neighbor_index(from_tile_x, from_tile_y, to_tile_x, to_tile_y)
    local delta_x = to_tile_x - from_tile_x
    local delta_y = to_tile_y - from_tile_y

    for neighbor_index = 1, 8 do
        local neighbor_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[neighbor_index]
        if neighbor_offset.dx == delta_x and neighbor_offset.dy == delta_y then
            return neighbor_index
        end
    end

    return nil
end

--- Compute the next boundary tile using Moore-neighborhood boundary tracing.
--- @param surface LuaSurface
--- @param entity_name string|nil
--- @param current_tile_x integer
--- @param current_tile_y integer
--- @param backtrack_tile_x integer
--- @param backtrack_tile_y integer
--- @return integer|nil next_tile_x
--- @return integer|nil next_tile_y
--- @return integer|nil next_backtrack_tile_x
--- @return integer|nil next_backtrack_tile_y
local function moore_trace_next_boundary_tile(surface, entity_name, current_tile_x, current_tile_y, backtrack_tile_x,
    backtrack_tile_y)
    -- Start scanning from the neighbor after the backtrack neighbor, clockwise.
    local backtrack_neighbor_index = moore_neighbor_index(current_tile_x, current_tile_y, backtrack_tile_x,
        backtrack_tile_y) or 8 -- default to W if unknown

    local first_scan_neighbor_index = (backtrack_neighbor_index % 8) + 1

    for scan_step = 0, 7 do
        local neighbor_index = ((first_scan_neighbor_index - 1 + scan_step) % 8) + 1
        local neighbor_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[neighbor_index]

        local candidate_tile_x = current_tile_x + neighbor_offset.dx
        local candidate_tile_y = current_tile_y + neighbor_offset.dy

        if tile_is_boundary_tile(surface, entity_name, candidate_tile_x, candidate_tile_y) then
            -- Backtrack becomes the neighbor immediately before the chosen neighbor (counterclockwise).
            local counterclockwise_neighbor_index = ((neighbor_index - 2) % 8) + 1
            local counterclockwise_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[counterclockwise_neighbor_index]

            local next_backtrack_x = current_tile_x + counterclockwise_offset.dx
            local next_backtrack_y = current_tile_y + counterclockwise_offset.dy

            return candidate_tile_x, candidate_tile_y, next_backtrack_x, next_backtrack_y
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Trace state initialization
--------------------------------------------------------------------------------

--- Ensure the trace field exists (or remains nil) on the bot task state.
--- @param player_state table
--- @param bot table
local function ensure_survey_trace_state(player_state, bot)
    bot.task.survey_trace = bot.task.survey_trace or nil
end

--- Initialize a new trace state when a survey target is found.
--- Phases:
---   - "north": walk due north until the tile north is outside the resource
---   - "edge":  perform Moore boundary tracing until closure is detected
--- @param player_state table
--- @param bot table
local function begin_trace_from_detected_resource(player_state, bot)
    local starting_tile_x, starting_tile_y = tile_coordinates_from_world_position(bot.entity.position)

    bot.task.survey_trace = {
        phase = "north",

        -- Initial sighting tile; used to recover if we’re momentarily off-resource.
        origin_tile_x = starting_tile_x,
        origin_tile_y = starting_tile_y,

        -- Boundary start tile (set when north phase ends)
        start_boundary_tile_x = nil,
        start_boundary_tile_y = nil,

        -- Current tile (p) and backtrack tile (b) for Moore tracing
        current_tile_x = nil,
        current_tile_y = nil,
        backtrack_tile_x = nil,
        backtrack_tile_y = nil,

        -- Closure detection:
        --   first_edge_step_tile == p1 in the standard algorithm
        first_edge_step_tile_x = nil,
        first_edge_step_tile_y = nil,
        has_started_edge_trace = false,

        -- Collected boundary points (world positions of tile centers)
        boundary_points_world_positions = {},

        -- Unstick guard for the north-walk phase
        north_phase_stuck_attempts = 0,
        north_phase_last_tile_x = starting_tile_x,
        north_phase_last_tile_y = starting_tile_y
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

    local found = util.find_entities(player, bpos, BOT_CONF.search.detection_radius, surf, find_name, true, true)

    if #found == 0 then
        return false
    end

    -- set survey entity to first found type
    bot.task.survey_entity = found[1]

    -- If we're not already tracing, start.
    ensure_survey_trace_state(ps, bot)
    if not bot.task.survey_trace then
        begin_trace_from_detected_resource(ps, bot)
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
        local tile_x, tile_y = tile_coordinates_from_world_position(bot.entity.position)

        local MAX_NORTH_STUCK = 30 -- adjust (30 attempts is usually enough)

        if tile_x == tr.north_last_tx and tile_y == tr.north_last_ty then
            tr.north_stuck_attempts = (tr.north_stuck_attempts or 0) + 1
            if tr.north_stuck_attempts >= MAX_NORTH_STUCK then
                -- Abort trace; survey will restart when it finds the resource again
                bot.task.survey_trace = nil
                return nil
            end
        else
            tr.north_last_tx = tile_x
            tr.north_last_ty = tile_y
            tr.north_stuck_attempts = 0
        end

        -- If current tile doesn't actually have the resource, snap to origin tile center first.
        if not tile_contains_tracked_entity(surf, entity_name, tile_x, tile_y) then
            local found_tx, found_ty = find_nearest_tile_containing_entity(surf, entity_name, bot.entity.position,
                math.ceil(BOT_CONF.survey.radius) + 1)
            if found_tx then
                tr.origin_tx = found_tx
                tr.origin_ty = found_ty
                return world_position_at_tile_center(found_tx, found_ty)
            end

            -- No nearby resource tile; abort trace so scan can restart later
            bot.task.survey_trace = nil
            return nil
        end

        local next_ty = tile_y - 1 -- due north in Factorio coords
        if tile_contains_tracked_entity(surf, entity_name, tile_x, next_ty) then
            return world_position_at_tile_center(tile_x, next_ty)
        end

        -- Next tile north is outside: current tile is our "north edge" start.
        tr.start_tx = tile_x
        tr.start_ty = tile_y

        -- Ensure we start on a boundary tile; if not, search nearby for one (tight, local).
        if not tile_is_boundary_tile(surf, entity_name, tr.start_tx, tr.start_ty) then
            local found_boundary = false
            for i = 1, 8 do
                local n = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[i]
                local ntx = tr.start_tx + n.dx
                local nty = tr.start_ty + n.dy
                if tile_is_boundary_tile(surf, entity_name, ntx, nty) then
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
        tr.boundary = {world_position_at_tile_center(tr.p_tx, tr.p_ty)}

        tr.started_edge = false
        tr.p1_tx = nil
        tr.p1_ty = nil

        -- First edge move:
        local nx, ny, nbx, nby = moore_trace_next_boundary_tile(surf, entity_name, tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty)
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
        tr.boundary[#tr.boundary + 1] = world_position_at_tile_center(tr.p_tx, tr.p_ty)

        return world_position_at_tile_center(tr.p_tx, tr.p_ty)
    end

    if tr.phase == "edge" then
        -- Closed when we are back at start AND the next step would be p1.
        local nx, ny, nbx, nby = moore_trace_next_boundary_tile(surf, entity_name, tr.p_tx, tr.p_ty, tr.b_tx, tr.b_ty)
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
        tr.boundary[#tr.boundary + 1] = world_position_at_tile_center(tr.p_tx, tr.p_ty)

        return world_position_at_tile_center(tr.p_tx, tr.p_ty)
    end

    return nil
end

function survey.update(player, ps, state, visual, bot, tick)
    if not (player and player.valid and bot and bot.entity.valid) then
        return
    end

    local entity_group = module.get_module("entity_group")

    -- If we are tracing, drive movement purely from the trace state machine.
    ensure_survey_trace_state(ps, bot)

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

        -- Switch to next task
        switch_to_next_task(player, ps, state, bot)

        bot.task.survey_found_entity = true
    else
        -- Not tracing yet: just scan where we are; when we see the resource, tracing starts.
        if not survey.perform_survey_scan(player, ps, bot, tick) then
            -- Switch to next task
            switch_to_next_task(player, ps, state, bot)

            bot.task.survey_found_entity = false
        else
            bot.task.survey_found_entity = true
        end
    end
end

return survey
