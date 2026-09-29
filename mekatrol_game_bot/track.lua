local config = require("config")
local constants = require("constants")
local movement = require("movement")
local registry = require("task_registry")
local track = {}

local function accepted_names(task)
    -- Traversal must cross both source and already-upgraded prototypes. Without
    -- target names, one existing red belt would incorrectly split one physical
    -- production line into two independent jobs.
    local names = {}
    for source_name, raw_mapping in pairs(task.mappings) do
        names[source_name] = true
        local target_name = type(raw_mapping) == "string" and raw_mapping or raw_mapping.target
        if target_name then names[target_name] = true end
    end
    return names
end

local function append_if_connected(queue, queued, entity, names, force)
    -- Engine neighbour tables can contain invalid references after simultaneous
    -- player or script changes, so every edge is validated before traversal.
    if not (entity and entity.valid and entity.force == force and names[entity.name]) then return end
    local identity = entity.unit_number
    if not identity or queued[identity] then return end
    queued[identity] = true
    queue[#queue + constants.ITEM_TRANSFER_COUNT] = entity
end

local function connected_entities(entity)
    local connected = {}
    local neighbours = entity.belt_neighbours

    -- Inputs and outputs are both followed because grouping describes physical
    -- membership, not the direction in which items currently flow.
    for _, input in pairs(neighbours.inputs or {}) do
        connected[#connected + constants.ITEM_TRANSFER_COUNT] = input
    end
    for _, output in pairs(neighbours.outputs or {}) do
        connected[#connected + constants.ITEM_TRANSFER_COUNT] = output
    end

    if entity.type == constants.ENTITY_TYPE.UNDERGROUND_BELT then
        -- Factorio 2.0 exposes the far underground endpoint through `neighbours`;
        -- belt_neighbours intentionally contains only surface input/output edges.
        local underground_peer = entity.neighbours
        if underground_peer then
            connected[#connected + constants.ITEM_TRANSFER_COUNT] = underground_peer
        end
    end
    return connected
end

function track.discover(seed, task)
    -- Tasks that do not opt into belt grouping remain valid extension points:
    -- their work group is simply the selected entity rather than assuming that
    -- every future upgrade prototype exposes belt-specific API properties.
    if task.grouping ~= constants.GROUP_STRATEGY.BELT_NETWORK then
        return {
            entities = {seed},
            anchor_position = {x = seed.position.x, y = seed.position.y},
            surface_index = seed.surface.index,
            force_index = seed.force.index
        }
    end

    -- Breadth-first traversal captures the complete connected belt component,
    -- including splitter branches, before any member is replaced and invalidated.
    local queue = {seed}
    local queued = {[seed.unit_number] = true}
    local entities = {}
    local names = accepted_names(task)
    local cursor = constants.FIRST_INDEX

    while cursor <= #queue do
        local entity = queue[cursor]
        cursor = cursor + constants.ITEM_TRANSFER_COUNT
        if entity and entity.valid then
            entities[#entities + constants.ITEM_TRANSFER_COUNT] = entity
            for _, neighbour in pairs(connected_entities(entity)) do
                append_if_connected(queue, queued, neighbour, names, seed.force)
            end
        end
    end
    return {
        entities = entities,
        anchor_position = {x = seed.position.x, y = seed.position.y},
        surface_index = seed.surface.index,
        force_index = seed.force.index
    }
end

function track.refresh(player, value, task)
    local group = value.track
    if not group then return false end

    -- Prefer the entity now occupying the original seed location. This finds a
    -- newly fast-replaced red belt even though the old yellow LuaEntity is invalid.
    local surface = group.surface_index and game.surfaces[group.surface_index] or nil
    local force = group.force_index and game.forces[group.force_index] or player.force
    local seed = nil
    if surface and group.anchor_position then
        local names = accepted_names(task)
        local candidates = surface.find_entities_filtered {
            position = group.anchor_position,
            radius = config.track_anchor_search_radius,
            force = force
        }
        local best_distance = nil
        for _, candidate in pairs(candidates) do
            if candidate.valid and names[candidate.name] then
                local distance = movement.distance_squared(group.anchor_position, candidate.position)
                if not best_distance or distance < best_distance then
                    seed = candidate
                    best_distance = distance
                end
            end
        end
    end

    -- If the anchor was removed, retain the component containing the closest
    -- surviving member of the previously active track rather than jumping lines.
    if not seed then
        for _, entity in pairs(group.entities or {}) do
            if entity and entity.valid then seed = entity; break end
        end
    end

    if not seed then
        track.clear_visual(value)
        value.track = nil
        return false
    end

    local refreshed = track.discover(seed, task)

    -- A mixed-tier underground pair may temporarily disappear from Factorio's
    -- live belt graph after one endpoint is replaced. Preserve still-valid,
    -- still-upgradeable underground endpoints from the locked group so they do
    -- not lose their outline or escape completion of the current track.
    local included = {}
    for _, entity in pairs(refreshed.entities) do
        if entity and entity.valid and entity.unit_number then included[entity.unit_number] = true end
    end
    for _, entity in pairs(group.entities or {}) do
        if entity and entity.valid and entity.type == constants.ENTITY_TYPE.UNDERGROUND_BELT and
                task.mappings[entity.name] and entity.unit_number and not included[entity.unit_number] then
            refreshed.entities[#refreshed.entities + constants.ITEM_TRANSFER_COUNT] = entity
            included[entity.unit_number] = true
        end
    end

    value.track = refreshed
    track.draw(player, value, task)
    return true
end

function track.remaining_entities(group, task, position, force)
    -- Replacements invalidate their source references. Filtering at use time
    -- naturally removes completed members without mutating the persisted group
    -- while another loop may still be iterating it.
    local remaining = {}
    for _, entity in pairs(group and group.entities or {}) do
        if entity and entity.valid and task.mappings[entity.name] and
                (not force or registry.mapping_available(force, task, entity.name)) then
            remaining[#remaining + constants.ITEM_TRANSFER_COUNT] = entity
        end
    end
    table.sort(remaining, function(a, b)
        return movement.distance_squared(position, a.position) < movement.distance_squared(position, b.position)
    end)
    return remaining
end

local function draw_border(player, entity, color, width)
    return rendering.draw_rectangle {
        color = color,
        width = width,
        filled = false,
        left_top = entity.bounding_box.left_top,
        right_bottom = entity.bounding_box.right_bottom,
        surface = entity.surface,
        draw_on_ground = true,
        players = {player.index}
    }
end

function track.draw(player, value, task)
    track.clear_visual(value)
    value.track_highlights = {}

    -- Two concentric strokes approximate a glow: a wide translucent halo under
    -- a narrow bright edge. Traversal retains already-upgraded entities so they
    -- can connect separated yellow sections, but only source mappings represent
    -- outstanding work and therefore receive an outline.
    for _, entity in pairs(value.track and value.track.entities or {}) do
        if entity and entity.valid and task and task.mappings[entity.name] and
                registry.mapping_available(player.force, task, entity.name) then
            local outer = draw_border(player, entity, config.track_highlight_outer_color,
                constants.TRACK_HIGHLIGHT_OUTER_WIDTH)
            local inner = draw_border(player, entity, config.track_highlight_inner_color,
                constants.TRACK_HIGHLIGHT_INNER_WIDTH)
            value.track_highlights[#value.track_highlights + constants.ITEM_TRANSFER_COUNT] = outer
            value.track_highlights[#value.track_highlights + constants.ITEM_TRANSFER_COUNT] = inner
        end
    end
end

function track.clear_visual(value)
    for _, object in pairs(value.track_highlights or {}) do
        if object and object.valid then object.destroy() end
    end
    value.track_highlights = {}
end

return track
