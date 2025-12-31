local entity_group = {}

local module = require("module")
local polygon = require("polygon")
local util = require("util")

function entity_group.clear_entity_groups(ps)
    ps.entity_groups = {}
end

function entity_group.ensure_entity_groups(ps)
    ps.entity_groups = ps.entity_groups or {}
end

local ignore_entities = {
    ["mekatrol-game-play-bot"] = true,
    ["fish"] = true,
    ["unit"] = true
}

function entity_group.is_survey_ignore_target(e)
    if not e or not e.valid then
        return true
    end

    if ignore_entities[e.type] then
        return true
    end

    if ignore_entities[e.name] then
        return true
    end

    return false
end

function entity_group.is_survey_single_target(entity)
    if not entity or not (entity.name or entity.type) then
        return false
    end

    local single_target_names = {
        ["big-sand-rock"] = true,
        ["huge-rock"] = true,
        ["cliff"] = true,
        ["tree"] = true,
        ["simple-entity-with-owner"] = true,
        ["crude-oil"] = true
    }

    if entity.name and single_target_names[entity.name] then
        return true
    end

    local single_target_types = {
        ["container"] = true,
        ["cliff"] = true,
        ["tree"] = true,
        ["simple-entity"] = true,
        ["simple-entity-with-owner"] = true
    }

    if entity.type and single_target_types[entity.type] then
        return true
    end

    return false
end

function entity_group.get_group_entity_name_starts_with(ps, entity_name)
    local groups = ps.entity_groups

    if not groups then
        return false
    end

    for _, g in pairs(groups) do
        -- test group name starts with
        if g and string.sub(g.name, 1, #entity_name) == entity_name and g.boundary and #g.boundary >= 3 then
            return g
        end
    end

    return nil
end

function entity_group.is_in_any_entity_group(ps, surface_index, entity)
    local groups = ps.entity_groups

    if not groups then
        return false
    end

    local pos = entity.position

    local margin = 1.0 -- tiles (world units)

    for _, g in pairs(groups) do
        if g and g.name == entity.name and g.surface_index == surface_index and g.boundary and #g.boundary >= 3 then
            -- Treat points within 1 tile outside the boundary as "inside"
            if polygon.contains_point_buffered then
                if polygon.contains_point_buffered(g.boundary, pos, margin) then
                    return true
                end
            else
                -- Fallback if you haven't added contains_point_buffered yet
                if polygon.point_in_poly(g.boundary, pos) then
                    return true
                end
            end
        end
    end

    return false
end

function entity_group.remove_group(player, ps, group_or_id)
    entity_group.ensure_entity_groups(ps)

    local groups = ps.entity_groups
    if not groups then
        return false
    end

    -- Resolve id
    local id = nil

    if type(group_or_id) == "string" then
        id = group_or_id
    elseif type(group_or_id) == "table" then
        -- If caller already knows the id, allow it
        if group_or_id.id then
            id = group_or_id.id
        else
            -- Reconstruct the id format used in add_boundary()
            local gname = group_or_id.name
            local c = group_or_id.center
            if gname and c and c.x and c.y then
                id = tostring(gname) .. "@" .. tostring(c.x) .. "," .. tostring(c.y)
            end
        end
    end

    if not id then
        return false
    end

    if not groups[id] then
        -- Fallback: find matching group by name+center if floats differ slightly
        if type(group_or_id) == "table" and group_or_id.name and group_or_id.center then
            local gx, gy = group_or_id.center.x, group_or_id.center.y
            for k, g in pairs(groups) do
                if g and g.name == group_or_id.name and g.center then
                    if g.center.x == gx and g.center.y == gy then
                        id = k
                        break
                    end
                end
            end
        end
    end

    if not groups[id] then
        return false
    end

    local visual = module.get_module("visual")
    visual.clear_entity_group(ps, id)
    groups[id] = nil
    return true
end

function entity_group.add_boundary(player, ps, visual, boundary, entity, surface_index)
    -- must be at least 3 points in boundary
    if #boundary < 3 then
        return
    end

    local entity_name = entity.name
    local entity_type = entity.type

    -- make sure boundary end point equals start point
    local first = boundary[1]
    local last = boundary[#boundary]
    if first.x ~= last.x or first.y ~= last.y then
        boundary[#boundary + 1] = {
            x = first.x,
            y = first.y
        }
    end

    -- get center of polygon as position key in group_id
    local center = polygon.polygon_center(boundary)

    -- Use a stable id for this boundary
    local group_id = tostring(entity_name) .. "@" .. tostring(center.x) .. "," .. tostring(center.y)

    ps.entity_groups[group_id] = {
        id = group_id,
        name = entity_name,
        type = entity_type,
        surface_index = surface_index,
        boundary = boundary,
        center = center
    }

    -- Draw polygon + labels (clears any prior render for this group_id)
    visual.draw_entity_group(player, ps, group_id, entity_name, entity_type, boundary, center)

    -- entity_group.merge_overlapping_groups(player, ps, visual)
end

function entity_group.add_single_tile_entity_group(player, ps, visual, surface_index, entity)
    entity_group.ensure_entity_groups(ps)

    if not (entity and entity.valid) then
        return
    end

    local pos = entity.position

    -- Prefer selection_box (matches what players consider the entity's "size"),
    -- fall back to collision_box if needed.
    local box = entity.selection_box or entity.collision_box

    if not box then
        -- last-resort fallback: 1x1 tile-ish
        local size = 0.5
        local boundary = {{
            x = pos.x - size,
            y = pos.y - size
        }, {
            x = pos.x + size,
            y = pos.y - size
        }, {
            x = pos.x + size,
            y = pos.y + size
        }, {
            x = pos.x - size,
            y = pos.y + size
        }}

        entity_group.add_boundary(player, ps, visual, boundary, entity, surface_index)

        return
    end

    -- selection_box/collision_box are relative to the entity origin.
    -- convert to world coords by adding entity.position.
    local left_top = box.left_top
    local right_bottom = box.right_bottom

    local width = (right_bottom.x - left_top.x) / 2
    local height = (right_bottom.y - left_top.y) / 2

    local boundary = {{
        x = pos.x - width,
        y = pos.y - height
    }, {
        x = pos.x + width,
        y = pos.y - height
    }, {
        x = pos.x + width,
        y = pos.y + height
    }, {
        x = pos.x - width,
        y = pos.y + height
    }}

    entity_group.add_boundary(player, ps, visual, boundary, entity, surface_index)
end

function entity_group.merge_overlapping_groups(player, ps, visual)
    entity_group.ensure_entity_groups(ps)

    local groups = ps.entity_groups
    local keys = {}

    for k in pairs(groups) do
        keys[#keys + 1] = k
    end

    local removed = {}

    for i = 1, #keys do
        local gi = groups[keys[i]]
        if gi and not removed[keys[i]] then
            for j = i + 1, #keys do
                local gj = groups[keys[j]]

                if gj and not removed[keys[j]] and gi.name == gj.name and gi.surface_index == gj.surface_index and
                    polygon.polygons_intersect(gi.boundary, gj.boundary) then
                    -- Merge boundaries
                    gi.boundary = polygon.merge_polygons(gi.boundary, gj.boundary, {
                        concave = false
                    })

                    gi.center = polygon.polygon_center(gi.boundary)

                    removed[keys[j]] = true
                end
            end
        end
    end

    -- Remove merged groups
    for k in pairs(removed) do
        visual.clear_entity_group(ps, k)
        groups[k] = nil
    end

    -- Redraw merged groups
    for id, g in pairs(groups) do
        visual.draw_entity_group(player, ps, id, g.name, g.type, g.boundary, g.center)
    end
end

return entity_group
