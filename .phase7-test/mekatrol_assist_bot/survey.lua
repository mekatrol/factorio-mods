-- Incremental Moore-neighbour resource-boundary trace; each step performs a fixed query count.
local config = require("config")
local M = {}
local dirs = {{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}
local four = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
local function k(x, y)
    return x .. "," .. y
end
local function inside(surface, name, x, y)
    return #surface.find_entities_filtered {
        position = {x + 0.5, y + 0.5},
        radius = 0.7,
        name = name,
        type = "resource",
        limit = 1
    } > 0
end
local function boundary(surface, name, x, y)
    for _, d in ipairs(four) do
        if not inside(surface, name, x + d[1], y + d[2]) then
            return true
        end
    end
    return false
end

function M.start(entity)
    local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
    return {
        surface_index = entity.surface.index,
        name = entity.name,
        x = x,
        y = y,
        phase = "seek",
        points = {},
        seen = {},
        steps = 0,
        area_twice = 0,
        perimeter = 0,
        done = false
    }
end

function M.step(job)
    if job.done then
        return true
    end
    local surface = game.surfaces[job.surface_index];
    if not surface then
        job.done = true
        return true
    end
    job.steps = job.steps + 1;
    if job.steps > config.tasks.surveyor.boundary_max_steps then
        job.done = true;
        job.truncated = true;
        return true
    end
    if job.phase == "seek" then
        if inside(surface, job.name, job.x, job.y - 1) then
            job.y = job.y - 1;
            return false
        end
        job.start_x, job.start_y = job.x, job.y;
        job.phase = "trace";
        job.points[1] = {
            x = job.x + 0.5,
            y = job.y + 0.5
        };
        job.seen[k(job.x, job.y)] = true;
        return false
    end
    local next_x, next_y
    for _, d in ipairs(dirs) do
        local x, y = job.x + d[1], job.y + d[2];
        if inside(surface, job.name, x, y) and boundary(surface, job.name, x, y) then
            local id = k(x, y);
            if (x == job.start_x and y == job.start_y and #job.points >= 3) or not job.seen[id] then
                next_x, next_y = x, y;
                break
            end
        end
    end
    if not next_x then
        job.done = true;
        return true
    end
    local previous = job.points[#job.points];
    local next_point = {
        x = next_x + 0.5,
        y = next_y + 0.5
    };
    local dx, dy = next_point.x - previous.x, next_point.y - previous.y;
    job.perimeter = job.perimeter + math.sqrt(dx * dx + dy * dy);
    job.area_twice = job.area_twice + previous.x * next_point.y - next_point.x * previous.y
    if next_x == job.start_x and next_y == job.start_y then
        job.area = math.abs(job.area_twice) / 2;
        job.done = true;
        return true
    end
    job.x, job.y = next_x, next_y;
    job.seen[k(next_x, next_y)] = true;
    job.points[#job.points + 1] = next_point;
    return false
end

return M
