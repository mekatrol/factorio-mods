-- Incremental connected-belt traversal. One call expands one entity, so large factories yield.
local M = {}

---Return an identity stable for the duration of this traversal.
local function key(e)
    -- Belt-like entities normally have a globally unique unit number, so use
    -- its string form as the compact identity. The fallback covers unusual or
    -- modded valid entities without a unit number by combining prototype and
    -- exact position. This key is only scoped to one connected-belt job; unlike
    -- discovery identities it does not need a surface prefix or quantization.
    return e.unit_number and tostring(e.unit_number) or (e.name .. ":" .. e.position.x .. ":" .. e.position.y)
end

---Restrict the graph to the three entity types that form belt networks.
local function allowed(e)
    -- Test existence and validity before reading `type`: queued LuaEntity
    -- references can become invalid if a player mines a belt mid-traversal.
    return e and e.valid and (e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter")
end

---Create a breadth-first traversal rooted at `seed`.
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

---Expand one queued belt and enqueue its as-yet unseen neighbours.
---The monotonically increasing head avoids O(n) `table.remove(..., 1)` calls.
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
        -- Normal belts and splitters expose directed inputs/outputs through
        -- `belt_neighbours`. Either side may be absent at the end of a line.
        local belt = e.belt_neighbours
        if belt then
            -- `or {}` converts a missing input/output list into an empty
            -- iterable list, avoiding a branch for endpoints.
            for _, v in ipairs(belt.inputs or {}) do
                neighbours[#neighbours + 1] = v
            end
            for _, v in ipairs(belt.outputs or {}) do
                neighbours[#neighbours + 1] = v
            end
        end
        -- The paired underground endpoint is not always present in ordinary
        -- input/output lists, so add Factorio's explicit tunnel neighbour too.
        if e.type == "underground-belt" and e.neighbours then
            neighbours[#neighbours + 1] = e.neighbours
        end
        table.sort(neighbours, function(a, b)
            -- Factorio does not promise neighbour iteration order. Sorting
            -- makes traversal and subsequent upgrade actions reproducible.
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

---Consume one discovered entity and return it only if it still matches.
---The second result distinguishes exhaustion from a skipped/invalid entry.
function M.next(job, predicate)
    -- Traversal and action consumption are separate phases. Old/new jobs have
    -- no action cursor until consumption starts, making index one the default.
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
