-- Surveyor role policy: trace resource boundaries and publish polygon-backed groups.
local config = require("config")
local discovery = require("discovery")
local polygon = require("polygon")
local scanner = require("entity_scanner")
local state = require("state")
local survey = require("survey")
local M = {
    tasks = {"follow", "search", "survey"},
    handoff = true,
    handoff_types = {"resource"},
    scan_phase = "moving"
}

function M.radius()
    return config.tasks.surveyor.radius
end

function M.filter()
    return {type = "resource"}
end

---Reject resources already assigned to a completed survey group.
function M.valid(entity)
    local index = state.root().discovery
    return not (index.grouped and index.grouped[discovery.identity(entity)])
end

---Advance boundary tracing and collect resources inside the resulting polygon.
---Each phase is persistent and bounded: one trace step or one scanner cell is
---processed per scheduler call, so even huge ore patches cannot stall a tick.
function M.prepare_action(rs, anchor)
    if not rs.survey_job then
        rs.survey_job = survey.start(rs.target)
        return "working", false
    end
    if not rs.survey_job.done then
        survey.step(rs.survey_job)
        return "working", false
    end
    if not rs.survey_job.collect_scan then
        -- These values are world-tile coordinates of the smallest rectangle
        -- enclosing the traced contour. They seed from the target resource so
        -- an empty/degenerate point list still produces a valid scan area.
        local left, right = rs.target.position.x, rs.target.position.x
        local top, bottom = rs.target.position.y, rs.target.position.y
        for _, point in ipairs(rs.survey_job.points) do
            left, right = math.min(left, point.x), math.max(right, point.x)
            top, bottom = math.min(top, point.y), math.max(bottom, point.y)
        end
        rs.survey_job.entities = {}
        rs.survey_job.collect_scan = scanner.start_area(anchor.surface,
            {{left - 1, top - 1}, {right + 1, bottom + 1}}, {name = rs.target.name, type = "resource"})
        return "working", false
    end
    if not rs.survey_job.collect_scan.done then
        local _, found = scanner.step(rs.survey_job.collect_scan)
        for _, entity in ipairs(found) do
            -- The rectangular query is cheap; polygon containment removes
            -- neighbouring patches and resources enclosed by a concave trace.
            if polygon.contains(rs.survey_job.points, entity.position) then
                local id = discovery.identity(entity)
                rs.survey_job.entities[id] = true
                discovery.add(entity)
            end
        end
        return "working", false
    end
    return "working", true
end

---Commit a completed survey to the shared discovery index.
function M.act(rs, _, entity)
    discovery.add(entity)
    local index = state.root().discovery
    local job = rs.survey_job
    -- Surface, prototype, and trace seed distinguish otherwise identical patches.
    local key = entity.surface.index .. ":" .. entity.name .. ":" .. job.start_x .. ":" .. job.start_y
    local group = index.groups[key] or {
        name = entity.name,
        surface_index = entity.surface.index,
        entities = {},
        bounds = {
            left = entity.position.x,
            right = entity.position.x,
            top = entity.position.y,
            bottom = entity.position.y
        }
    }
    for id in pairs(job.entities or {}) do
        group.entities[id] = true
        index.grouped = index.grouped or {}
        index.grouped[id] = key
    end
    local bounds = group.bounds
    bounds.left = math.min(bounds.left, entity.position.x)
    bounds.right = math.max(bounds.right, entity.position.x)
    bounds.top = math.min(bounds.top, entity.position.y)
    bounds.bottom = math.max(bounds.bottom, entity.position.y)

    if #job.points >= 3 then
        group.polygon = job.points
        group.area = job.area or 0
        group.perimeter = job.perimeter or 0
    else
        -- A failed/degenerate trace falls back to a half-tile-expanded bounding
        -- rectangle, preserving useful and deterministic group geometry.
        group.polygon = {{x = bounds.left - 0.5, y = bounds.top - 0.5},
                         {x = bounds.right + 0.5, y = bounds.top - 0.5},
                         {x = bounds.right + 0.5, y = bounds.bottom + 0.5},
                         {x = bounds.left - 0.5, y = bounds.bottom + 0.5}}
        -- Resource coordinates are tile centers, so inclusive dimensions add
        -- one tile to the coordinate span before area/perimeter calculation.
        local width_tiles = bounds.right - bounds.left + 1
        local height_tiles = bounds.bottom - bounds.top + 1
        group.area = width_tiles * height_tiles
        group.perimeter = 2 * (width_tiles + height_tiles)
    end
    index.groups[key] = group
    return true
end

return M
