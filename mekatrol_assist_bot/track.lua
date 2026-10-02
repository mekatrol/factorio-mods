-- Incremental connected-belt traversal. One call expands one entity, so large factories yield.
local M = {}

local function key(e)
    return e.unit_number and tostring(e.unit_number) or (e.name .. ":" .. e.position.x .. ":" .. e.position.y)
end

local function allowed(e)
    return e and e.valid and (e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter")
end

function M.start(seed)
    return {
        queue = {seed},
        head = 1,
        seen = {
            [key(seed)] = true
        },
        entities = {},
        done = false,
        force_index = seed.force.index
    }
end

function M.step(job)
    if job.done then
        return true
    end
    local e = job.queue[job.head];
    job.head = job.head + 1
    if not e then
        job.done = true
        return true
    end
    if allowed(e) and e.force.index == job.force_index then
        job.entities[#job.entities + 1] = e
        local neighbours = {};
        local belt = e.belt_neighbours
        if belt then
            for _, v in ipairs(belt.inputs or {}) do
                neighbours[#neighbours + 1] = v
            end
            for _, v in ipairs(belt.outputs or {}) do
                neighbours[#neighbours + 1] = v
            end
        end
        if e.type == "underground-belt" and e.neighbours then
            neighbours[#neighbours + 1] = e.neighbours
        end
        table.sort(neighbours, function(a, b)
            return key(a) < key(b)
        end)
        for _, n in ipairs(neighbours) do
            if allowed(n) then
                local k = key(n);
                if not job.seen[k] then
                    job.seen[k] = true;
                    job.queue[#job.queue + 1] = n
                end
            end
        end
    end
    if job.head > #job.queue then
        job.done = true
    end
    return job.done
end

function M.next(job, predicate)
    job.action_index = job.action_index or 1;
    local e = job.entities[job.action_index];
    if not e then
        return nil, true
    end
    job.action_index = job.action_index + 1
    if e.valid and predicate(e) then
        return e, false
    end
    return nil, false
end

return M
