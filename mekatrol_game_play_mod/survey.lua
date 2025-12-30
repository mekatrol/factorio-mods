-- survey.lua
--
-- Purpose:
--   Trace the boundary of a resource/entity “blob” on a Factorio surface by walking tiles and
--   performing a clockwise Moore-neighbourhood boundary trace. The traced boundary is then
--   persisted/rendered via the entity_group module.
--
-- Notes on terminology used in this file:
--   - “tile”: integer grid coordinate (tile_x, tile_y) derived from an entity’s world position.
--   - “inside tile”: a tile that contains at least one entity matching the tracked entity name.
--   - “boundary tile”: an inside tile that has at least one of its 4-neighbours outside.
--   - “Moore neighbourhood”: the 8 neighbours around a tile (NW, N, NE, E, SE, S, SW, W).
--
-- This file is a verbose rewrite of the original logic with descriptive names and comments.
-- Source: :contentReference[oaicite:0]{index=0}
local survey = {}

local config = require("config")
local module = require("module")
local polygon = require("polygon")
local positioning = require("positioning")
local util = require("util")

local BOT_CONFIGURATION = config.bot

local PERIMETER_UNCHANGED_COUNT_THRESHOLD = 10

--------------------------------------------------------------------------------
-- Tile / coordinate helpers
--------------------------------------------------------------------------------

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

--- A boundary tile is an “inside tile” with at least one 4-neighbour “outside tile”.
--- 4-neighbours: north, east, south, west.
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

-- De-duplicate points globally (order-preserving), but always keep:
--   - the first point (start)
--   - the last point (end)
local function dedupe_boundary_preserve_ends(points)
    if not points or #points == 0 then
        return {}
    end
    if #points <= 2 then
        return points
    end

    local out = {points[1]}
    local seen = {}
    seen[tostring(points[1].x) .. "," .. tostring(points[1].y)] = true

    -- middle points: only first occurrence
    for i = 2, #points - 1 do
        local p = points[i]
        local k = tostring(p.x) .. "," .. tostring(p.y)
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = p
        end
    end

    -- always keep the final point even if duplicate
    out[#out + 1] = points[#points]
    return out
end

--------------------------------------------------------------------------------
-- Moore-neighbourhood clockwise boundary tracing over tiles
--
-- Standard approach:
--   start_tile = first boundary tile
--   backtrack_tile = tile immediately “behind” us (initially west of start_tile)
--   At each step:
--     1) Determine the index of backtrack_tile in the neighbour list around current_tile.
--     2) Scan neighbours starting from the next neighbour clockwise.
--     3) Choose the first neighbour that is also a boundary tile as the next current tile.
--     4) Update backtrack_tile to be the neighbour immediately counterclockwise of the chosen neighbour.
--   Stop when we return to start_tile and the next step would be the first step tile (p1).
--------------------------------------------------------------------------------

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

--- Find the 1..8 neighbour index for a tile-to-tile step.
--- @param from_tile_x integer
--- @param from_tile_y integer
--- @param to_tile_x integer
--- @param to_tile_y integer
--- @return integer|nil neighbour_index_1_to_8
local function moore_neighbour_index(from_tile_x, from_tile_y, to_tile_x, to_tile_y)
    local delta_x = to_tile_x - from_tile_x
    local delta_y = to_tile_y - from_tile_y

    for neighbour_index = 1, 8 do
        local neighbour_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[neighbour_index]
        if neighbour_offset.dx == delta_x and neighbour_offset.dy == delta_y then
            return neighbour_index
        end
    end

    return nil
end

--- Compute the next boundary tile using Moore-neighbourhood boundary tracing.
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
    -- Start scanning from the neighbour after the backtrack neighbour, clockwise.
    local backtrack_neighbour_index = moore_neighbour_index(current_tile_x, current_tile_y, backtrack_tile_x,
        backtrack_tile_y) or 8 -- default to W if unknown

    local first_scan_neighbour_index = (backtrack_neighbour_index % 8) + 1

    for scan_step = 0, 7 do
        local neighbour_index = ((first_scan_neighbour_index - 1 + scan_step) % 8) + 1
        local neighbour_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[neighbour_index]

        local candidate_tile_x = current_tile_x + neighbour_offset.dx
        local candidate_tile_y = current_tile_y + neighbour_offset.dy

        if tile_is_boundary_tile(surface, entity_name, candidate_tile_x, candidate_tile_y) then
            -- Backtrack becomes the neighbour immediately before the chosen neighbour (counterclockwise).
            local counterclockwise_neighbour_index = ((neighbour_index - 2) % 8) + 1
            local counterclockwise_offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[counterclockwise_neighbour_index]

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

--------------------------------------------------------------------------------
-- Survey task: scanning and trace progression
--------------------------------------------------------------------------------

--- Scan for the configured survey entity near the bot. If found, seed tracing state.
--- @return boolean did_find_survey_target
function survey.perform_survey_scan(player, player_state, bot, tick)
    local surface = bot.entity.surface
    local bot_world_position = bot.entity.position

    if not bot.task.survey_entity then
        return false
    end

    local survey_entity_name = bot.task.survey_entity.name

    local entities_found = util.find_entities(player, bot_world_position, BOT_CONFIGURATION.search.detection_radius,
        surface, survey_entity_name, true, true)

    if #entities_found == 0 then
        return false
    end

    -- Record the actual entity instance found (first match) as the target for tracing.
    bot.task.survey_entity = entities_found[1]

    -- Start tracing if not already tracing.
    ensure_survey_trace_state(player_state, bot)
    if not bot.task.survey_trace then
        begin_trace_from_detected_resource(player_state, bot)
    end

    return true
end

--- Switch the bot to its next configured task and clear survey-specific state.
local function switch_bot_to_next_task(player, player_state, visual, bot)
    local bot_module = module.get_module(bot.name)
    local next_task_name = bot.task.next_task or "search"

    if visual and visual.clear_survey_trace then
        visual.clear_survey_trace(player_state, bot.name)
    end

    bot_module.set_bot_task(player, player_state, next_task_name, nil, bot.task.args)

    bot.task.target_position = nil
    bot.task.survey_trace = nil
end

--- Perform one step of the trace state machine.
--- Returns the next world position the bot should move toward, or nil when idle/finished/aborted.
--- @return table|nil next_target_world_position
local function advance_trace_one_step(player, player_state, visual, bot)
    local target_entity = bot.task.survey_entity
    local tracked_entity_name = target_entity and target_entity.name or nil

    local trace_state = bot.task.survey_trace
    if not trace_state then
        return nil
    end

    local surface = bot.entity.surface

    --------------------------------------------------------------------
    -- Phase 1: walk north until the next tile north is outside
    --------------------------------------------------------------------
    if trace_state.phase == "north" then
        local current_tile_x, current_tile_y = tile_coordinates_from_world_position(bot.entity.position)

        -- Detect “stuck” (not changing tiles) to avoid infinite loops.
        local MAXIMUM_NORTH_PHASE_STUCK_ATTEMPTS = 30
        if current_tile_x == trace_state.north_phase_last_tile_x and current_tile_y ==
            trace_state.north_phase_last_tile_y then
            trace_state.north_phase_stuck_attempts = (trace_state.north_phase_stuck_attempts or 0) + 1
            if trace_state.north_phase_stuck_attempts >= MAXIMUM_NORTH_PHASE_STUCK_ATTEMPTS then
                -- Abort trace; survey will restart when it finds the resource again
                bot.task.survey_trace = nil
                return nil
            end
        else
            trace_state.north_phase_last_tile_x = current_tile_x
            trace_state.north_phase_last_tile_y = current_tile_y
            trace_state.north_phase_stuck_attempts = 0
        end

        -- If we are not currently on a resource tile, snap to a nearby resource tile first.
        if not tile_contains_tracked_entity(surface, tracked_entity_name, current_tile_x, current_tile_y) then
            local maximum_snap_radius_tiles = math.ceil(BOT_CONFIGURATION.survey.radius) + 1
            local found_tile_x, found_tile_y = find_nearest_tile_containing_entity(surface, tracked_entity_name,
                bot.entity.position, maximum_snap_radius_tiles)

            if found_tile_x then
                trace_state.origin_tile_x = found_tile_x
                trace_state.origin_tile_y = found_tile_y
                return world_position_at_tile_center(found_tile_x, found_tile_y)
            end

            -- No nearby resource tile exists; abort trace so scanning can restart later.
            bot.task.survey_trace = nil
            return nil
        end

        -- Move due north (Factorio coordinates: decreasing y).
        local north_neighbour_tile_y = current_tile_y - 1
        if tile_contains_tracked_entity(surface, tracked_entity_name, current_tile_x, north_neighbour_tile_y) then
            return world_position_at_tile_center(current_tile_x, north_neighbour_tile_y)
        end

        -- The tile north is outside: current tile is the “north edge” candidate boundary start.
        trace_state.start_boundary_tile_x = current_tile_x
        trace_state.start_boundary_tile_y = current_tile_y

        -- Ensure we actually start on a boundary tile; if not, search the immediate 8 neighbours.
        if not tile_is_boundary_tile(surface, tracked_entity_name, trace_state.start_boundary_tile_x,
            trace_state.start_boundary_tile_y) then
            local found_boundary_tile = false

            for neighbour_index = 1, 8 do
                local offset = MOORE_NEIGHBOR_OFFSETS_CLOCKWISE[neighbour_index]
                local neighbour_tile_x = trace_state.start_boundary_tile_x + offset.dx
                local neighbour_tile_y = trace_state.start_boundary_tile_y + offset.dy

                if tile_is_boundary_tile(surface, tracked_entity_name, neighbour_tile_x, neighbour_tile_y) then
                    trace_state.start_boundary_tile_x = neighbour_tile_x
                    trace_state.start_boundary_tile_y = neighbour_tile_y
                    found_boundary_tile = true
                    break
                end
            end

            if not found_boundary_tile then
                -- Can't find a boundary; abort.
                bot.task.survey_trace = nil
                return nil
            end
        end

        ----------------------------------------------------------------
        -- Initialize Moore boundary trace state and perform first step.
        ----------------------------------------------------------------
        trace_state.phase = "edge"

        trace_state.current_tile_x = trace_state.start_boundary_tile_x
        trace_state.current_tile_y = trace_state.start_boundary_tile_y

        -- Standard initialization: backtrack is west of the start tile.
        trace_state.backtrack_tile_x = trace_state.current_tile_x - 1
        trace_state.backtrack_tile_y = trace_state.current_tile_y

        trace_state.boundary_points_world_positions = {world_position_at_tile_center(trace_state.current_tile_x,
            trace_state.current_tile_y)}

        trace_state.area = 0
        trace_state.perimeter = 0
        trace_state.permiter_unchanged_count = 0

        if visual and visual.clear_survey_trace then
            visual.clear_survey_trace(player_state, bot.name)
        end

        if visual and visual.append_survey_trace then
            visual.append_survey_trace(player, player_state, bot.name, trace_state.boundary_points_world_positions)
        end

        trace_state.has_started_edge_trace = false
        trace_state.first_edge_step_tile_x = nil
        trace_state.first_edge_step_tile_y = nil

        local next_tile_x, next_tile_y, next_backtrack_x, next_backtrack_y =
            moore_trace_next_boundary_tile(surface, tracked_entity_name, trace_state.current_tile_x,
                trace_state.current_tile_y, trace_state.backtrack_tile_x, trace_state.backtrack_tile_y)

        if not next_tile_x then
            bot.task.survey_trace = nil
            return nil
        end

        trace_state.first_edge_step_tile_x = next_tile_x
        trace_state.first_edge_step_tile_y = next_tile_y
        trace_state.has_started_edge_trace = true

        -- Advance to the first edge step.
        trace_state.current_tile_x = next_tile_x
        trace_state.current_tile_y = next_tile_y
        trace_state.backtrack_tile_x = next_backtrack_x
        trace_state.backtrack_tile_y = next_backtrack_y

        -- Record boundary point for rendering/storage
        trace_state.boundary_points_world_positions[#trace_state.boundary_points_world_positions + 1] =
            world_position_at_tile_center(trace_state.current_tile_x, trace_state.current_tile_y)

        return world_position_at_tile_center(trace_state.current_tile_x, trace_state.current_tile_y)
    end

    --------------------------------------------------------------------
    -- Phase 2: Moore boundary trace until closure
    --------------------------------------------------------------------
    if trace_state.phase == "edge" then
        local next_tile_x, next_tile_y, next_backtrack_x, next_backtrack_y =
            moore_trace_next_boundary_tile(surface, tracked_entity_name, trace_state.current_tile_x,
                trace_state.current_tile_y, trace_state.backtrack_tile_x, trace_state.backtrack_tile_y)

        if not next_tile_x then
            bot.task.survey_trace = nil
            return nil
        end

        -- Closure condition:
        --   We are back at the start tile AND the next step would be the first edge step tile.
        local is_at_start_tile = trace_state.current_tile_x == trace_state.start_boundary_tile_x and
                                     trace_state.current_tile_y == trace_state.start_boundary_tile_y

        local next_step_is_first_edge_step = next_tile_x == trace_state.first_edge_step_tile_x and next_tile_y ==
                                                 trace_state.first_edge_step_tile_y

        if trace_state.has_started_edge_trace and is_at_start_tile and next_step_is_first_edge_step then
            local entity_group = module.get_module("entity_group")

            -- Completed loop: persist + render the boundary group.
            entity_group.ensure_entity_groups(player_state)

            local boundary_world_positions = dedupe_boundary_preserve_ends(
                trace_state.boundary_points_world_positions or {})

            if visual and visual.clear_survey_trace then
                visual.clear_survey_trace(player_state, bot.name)
            end

            -- add to boundary group
            entity_group.add_boundary(player, player_state, visual, boundary_world_positions, target_entity,
                surface.index)

            -- Move on to the next task (typically to search for the next entity).
            switch_bot_to_next_task(player, player_state, visual, bot)
            return nil
        end

        -- Advance the Moore trace state.
        trace_state.current_tile_x = next_tile_x
        trace_state.current_tile_y = next_tile_y
        trace_state.backtrack_tile_x = next_backtrack_x
        trace_state.backtrack_tile_y = next_backtrack_y

        -- Record boundary point for rendering/storage
        trace_state.boundary_points_world_positions[#trace_state.boundary_points_world_positions + 1] =
            world_position_at_tile_center(trace_state.current_tile_x, trace_state.current_tile_y)

        local area = 0
        local perimeter = 0
        local boundary = trace_state.boundary_points_world_positions

        if boundary and #boundary >= 3 then
            area, perimeter = polygon.polygon_area_perimeter(boundary)

            if math.abs(perimeter - trace_state.perimeter) < 0.001 then
                trace_state.permiter_unchanged_count = trace_state.permiter_unchanged_count + 1

                -- has the perimeter remain unchanged for the threshold count?
                if trace_state.permiter_unchanged_count >= PERIMETER_UNCHANGED_COUNT_THRESHOLD then
                    local entity_group = module.get_module("entity_group")
                    entity_group.ensure_entity_groups(player_state)

                    local boundary_world_positions = dedupe_boundary_preserve_ends(
                        trace_state.boundary_points_world_positions or {})

                    if visual and visual.clear_survey_trace then
                        visual.clear_survey_trace(player_state, bot.name)
                    end

                    entity_group.add_boundary(player, player_state, visual, boundary_world_positions, target_entity,
                        surface.index)

                    switch_bot_to_next_task(player, player_state, visual, bot)
                    return nil
                end
            else
                -- if permiter changes then reset count
                trace_state.permiter_unchanged_count = 0
            end

            trace_state.area = area
            trace_state.perimeter = perimeter
        end

        if visual and visual.append_survey_trace then
            visual.append_survey_trace(player, player_state, bot.name, trace_state.boundary_points_world_positions)
        end

        return world_position_at_tile_center(trace_state.current_tile_x, trace_state.current_tile_y)
    end

    return nil
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

function survey.update(player, player_state, visual, bot, tick)
    if not (player and player.valid and bot and bot.entity.valid) then
        return
    end

    local entity_group = module.get_module("entity_group")

    -- If we are tracing, drive movement purely from the trace state machine.
    ensure_survey_trace_state(player_state, bot)

    if bot.task.survey_trace then
        local current_target_world_position = bot.task.target_position

        if not current_target_world_position then
            current_target_world_position = advance_trace_one_step(player, player_state, visual, bot)
            bot.task.target_position = current_target_world_position
        end

        if not current_target_world_position then
            return
        end

        positioning.move_entity_towards(player, bot.entity, current_target_world_position)

        local bot_world_position = bot.entity.position
        local has_arrived_at_target = positioning.positions_are_close(current_target_world_position, bot_world_position,
            BOT_CONFIGURATION.survey.arrival_threshold)

        if not has_arrived_at_target then
            return
        end

        -- Arrived; request the next trace target on the next update tick.
        bot.task.target_position = nil
        return
    end

    -- Not tracing: ensure we have a survey target entity configured.
    if not bot.task.survey_entity then
        return
    end

    -- For single-tile survey targets (e.g. crude-oil), add as a self-contained polygon/group.
    if entity_group.is_survey_single_target(bot.task.survey_entity) then
        entity_group.add_single_tile_entity_group(player, player_state, visual, bot.entity.surface_index,
            bot.task.survey_entity)

        switch_bot_to_next_task(player, player_state, visual, bot)
        bot.task.survey_found_entity = true
        return
    end

    -- For multi-tile targets: scan for the resource; tracing begins once it is seen.
    local did_find_target = survey.perform_survey_scan(player, player_state, bot, tick)
    if not did_find_target then
        switch_bot_to_next_task(player, player_state, visual, bot)
        bot.task.survey_found_entity = false
        return
    end

    bot.task.survey_found_entity = true
end

return survey
