-- Persistent, resumable cell scanner. Exactly one bounded cell query is one work unit.
local config = require("config")
local M = {}

---Convert a circular search's bounding square into inclusive cell indices.
---Dividing world coordinates by cell size maps them to the scanner grid;
---floor is correct for negative coordinates as well as positive ones.
local function cells(center, r)
    local s = config.scanning.cell_size
    return math.floor((center.x - r) / s), math.floor((center.x + r) / s), math.floor((center.y - r) / s),
        math.floor((center.y + r) / s)
end

---Create a serializable scan job for a radius around `center`.
---The job stores indices and filters, not an iterator or surface object, so it
---can safely pause between ticks and survive a save/load cycle.
function M.start(surface, center, radius, filter)
    local x0, x1, y0, y1 = cells(center, radius)
    return {
        surface_index = surface.index,
        center = {
            x = center.x,
            y = center.y
        },
        radius = radius,
        x = x0,
        y = y0,
        x0 = x0,
        x1 = x1,
        y0 = y0,
        y1 = y1,
        filter = filter or {},
        results = {},
        done = false
    }
end

---Create a rectangular scan job, including partial edge cells.
---The midpoint is retained only so the common circular-distance test can be
---reused with an infinite radius; `area` performs the actual rectangle clip.
function M.start_area(surface, area, filter)
    local s = config.scanning.cell_size;
    local x0 = math.floor(area[1][1] / s);
    local x1 = math.floor(area[2][1] / s);
    local y0 = math.floor(area[1][2] / s);
    local y1 = math.floor(area[2][2] / s)
    return {
        surface_index = surface.index,
        center = {
            x = (area[1][1] + area[2][1]) / 2,
            y = (area[1][2] + area[2][2]) / 2
        },
        radius = math.huge,
        x = x0,
        y = y0,
        x0 = x0,
        x1 = x1,
        y0 = y0,
        y1 = y1,
        filter = filter or {},
        results = {},
        done = false,
        area = area
    }
end

---Query one cell (or one adaptively split subcell) and advance the cursor.
---@return boolean done Whether every cell has been processed.
---@return LuaEntity[] found Entities accepted during this single work unit.
function M.step(scan)
    if scan.done then
        return true, {}
    end
    local surface = game.surfaces[scan.surface_index];
    if not surface then
        scan.done = true
        return true, {}
    end
    local s = config.scanning.cell_size;
    scan.subcells = scan.subcells or {};
    local area = table.remove(scan.subcells)
    if not area then
        area = {{scan.x * s, scan.y * s}, {(scan.x + 1) * s, (scan.y + 1) * s}};
        scan.x = scan.x + 1;
        if scan.x > scan.x1 then
            scan.x = scan.x0;
            scan.y = scan.y + 1
        end
    end
    local f = {
        area = area,
        limit = config.scanning.entities_per_cell
    }
    for k, v in pairs(scan.filter) do
        f[k] = v
    end
    local r2 = scan.radius * scan.radius
    local queried = surface.find_entities_filtered(f);
    local width = area[2][1] - area[1][1];
    local height = area[2][2] - area[1][2]
    if #queried >= config.scanning.entities_per_cell and math.max(width, height) > 0.5 then
        -- Hitting Factorio's result limit means the result might be truncated.
        -- Split into four quadrants and query them on later calls. The 0.5-tile
        -- floor guarantees termination in an exceptionally dense location.
        local mx, my = (area[1][1] + area[2][1]) / 2, (area[1][2] + area[2][2]) / 2
        scan.subcells[#scan.subcells + 1] = {{area[1][1], area[1][2]}, {mx, my}};
        scan.subcells[#scan.subcells + 1] = {{mx, area[1][2]}, {area[2][1], my}};
        scan.subcells[#scan.subcells + 1] = {{area[1][1], my}, {mx, area[2][2]}};
        scan.subcells[#scan.subcells + 1] = {{mx, my}, {area[2][1], area[2][2]}}
        return false, {}
    end
    local found = {};
    for _, e in ipairs(queried) do
        local dx = e.position.x - scan.center.x;
        local dy = e.position.y - scan.center.y;
        local inside = not scan.area or
                           (e.position.x >= scan.area[1][1] and e.position.x <= scan.area[2][1] and e.position.y >=
                               scan.area[1][2] and e.position.y <= scan.area[2][2]);
        -- Compare squared Euclidean distance with radius squared. This removes
        -- the enclosing square's corner regions without paying for sqrt.
        if inside and dx * dx + dy * dy <= r2 then
            found[#found + 1] = e
        end
    end
    if scan.y > scan.y1 and #scan.subcells == 0 then
        scan.done = true
    end
    scan.results = found;
    return scan.done, found
end

---Choose the closest valid result accepted by an optional predicate.
---Squared distance preserves ordering, so a square root is unnecessary.
function M.nearest(scan, position, predicate)
    local best, d2
    for _, e in ipairs(scan.results) do
        if e.valid and (not predicate or predicate(e)) then
            local x = e.position.x - position.x;
            local y = e.position.y - position.y;
            local n = x * x + y * y
            if not d2 or n < d2 then
                best, d2 = e, n
            end
        end
    end
    return best
end

return M
