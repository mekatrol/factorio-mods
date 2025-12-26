local entitygroup = {}

local polygon = require("polygon")
local util = require("util")

function entitygroup.clear_entity_groups(ps)
    ps.entity_groups = {}
end

function entitygroup.ensure_entity_groups(ps)
    ps.entity_groups = ps.entity_groups or {}
end

local ignore_entities = {
    ["mekatrol-game-play-bot"] = true,
    ["fish"] = true,
    ["unit"] = true
}

function entitygroup.is_survey_ignore_target(e)
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

function entitygroup.is_survey_single_target(entity)
    if not entity or not entity.valid then
        return true
    end

    local single_target_names = {
        ["big-sand-rock"] = true,
        ["huge-rock"] = true,
        ["cliff"] = true,
        ["tree"] = true,
        ["simple-entity-with-owner"] = true,
        ["crude-oil"] = true
    }

    if single_target_names[entity.name] then
        return true
    end

    local single_target_types = {
        ["container"] = true,
        ["cliff"] = true,
        ["tree"] = true,
        ["simple-entity"] = true,
        ["simple-entity-with-owner"] = true
    }

    if single_target_types[entity.type] then
        return true
    end

    return false
end

function entitygroup.is_in_any_entity_group(ps, surface_index, entity)
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

function entitygroup.add_boundary(player, ps, visual, boundary, entity_name, surface_index)
    -- must be at least 3 points in boundary
    if #boundary < 3 then
        return
    end

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
        name = entity_name,
        surface_index = surface_index,
        boundary = boundary,
        center = center
    }

    -- Draw polygon + label (clears any prior render for this group_id)
    visual.draw_entity_group(player, ps, group_id, entity_name, boundary, center)

    entitygroup.merge_overlapping_groups(player, ps, visual)
end

function entitygroup.add_single_tile_entity_group(player, ps, visual, surface_index, entity)
    entitygroup.ensure_entity_groups(ps)

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

        entitygroup.add_boundary(player, ps, visual, boundary, entity.name, surface_index)

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

    entitygroup.add_boundary(player, ps, visual, boundary, entity.name, surface_index)
end

function entitygroup.merge_overlapping_groups(player, ps, visual)
    entitygroup.ensure_entity_groups(ps)

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
        visual.draw_entity_group(player, ps, id, g.name, g.boundary, g.center)
    end
end

return entitygroup
