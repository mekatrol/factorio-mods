local entitygroup = {}

local polygon = require("polygon")
local visual = require("visual")

function entitygroup.clear_entity_groups(ps)
    ps.entity_groups = {}
end

function entitygroup.ensure_entity_groups(ps)
    ps.entity_groups = ps.entity_groups or {}
end

function entitygroup.is_survey_ignore_target(e)
    if not e or not e.valid then
        return true
    end

    local ignore_types = {
        ["container"] = true,
        ["fish"] = true,
        ["unit"] = true
    }

    if ignore_types[e.type] then
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
        ["cliff"] = true,
        ["tree"] = true,
        ["simple-entity-with-owner"] = true
    }

    if single_target_types[entity.type] then
        return true
    end

    return false
end

function entitygroup.is_in_any_entity_group(ps, surface_index, pos)
    local groups = ps.entity_groups

    if not groups then
        return false
    end

    local margin = 1.0 -- tiles (world units)

    for _, g in pairs(groups) do
        if g and g.surface_index == surface_index and g.boundary and #g.boundary >= 3 then
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

function entitygroup.add_boundary(player, ps, boundary, entity_name, surface_index)
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
end

function entitygroup.add_single_tile_entity_group(player, ps, surface_index, entity)
    entitygroup.ensure_entity_groups(ps)

    local pos = entity.position

    -- tile square around the tile center (Factorio positions are in tile units)
    local size = 1
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

    -- add to boundary group
    entitygroup.add_boundary(player, ps, boundary, entity.name, surface_index)
end

return entitygroup
