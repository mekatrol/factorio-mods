-- Shared discovery index and subscriptions. Internal tables are never exposed.
local state = require("state")
local config = require("config")
local visuals = require("visuals")
local M = {}
local registry

---Supply the completed role registry after its role modules finish loading.
---This avoids a discovery -> registry -> role -> discovery require cycle while
---keeping every require in Factorio's permitted control.lua parsing phase.
function M.set_registry(value)
    registry = value
end

---Insert or update a record while preserving first-seen order.
function M.store(order, records, id, record)
    local inserted = records[id] == nil
    if inserted then
        order[#order + 1] = id
    end
    records[id] = record
    return inserted
end

---Add an ID to the secondary exact-name index.
local function index_add(d, id, record)
    d.by_name = d.by_name or {}
    local bucket = d.by_name[record.name]
    if not bucket then
        bucket = {}
        d.by_name[record.name] = bucket
    end
    bucket[id] = true
end

---Remove an ID from the name index and discard empty buckets.
local function index_remove(d, id, record)
    local bucket = d.by_name and record and d.by_name[record.name]
    if bucket then
        bucket[id] = nil
        if next(bucket) == nil then
            d.by_name[record.name] = nil
        end
    end
end

---Build a stable identity for a live entity.
---Unit numbers are authoritative when available. Entities without one use
---surface, prototype, and coordinates quantized to 1/256 tile; quantization
---avoids tiny floating-point representation differences changing the key.
function M.identity(e)
    -- Unit numbers are Factorio's unique identity for entities that own one and
    -- remain stable while the entity exists. Decorative/resource-like or
    -- modded entities may have no unit number, so the fallback identifies them
    -- by surface, prototype, and position. Multiplication by 256 converts a
    -- coordinate to 1/256-tile fixed-point before floor removes insignificant
    -- floating-point noise. The `u:`/`p:` prefixes prevent the two key schemes
    -- from ever colliding.
    return e.unit_number and ("u:" .. e.unit_number) or
               ("p:" .. e.surface.index .. ":" .. e.name .. ":" .. math.floor(e.position.x * 256) .. ":" ..
                   math.floor(e.position.y * 256))
end

---Publish a valid entity into the shared map and eligible role handoff queues.
function M.add(e)
    if not e.valid then
        return
    end
    local d = state.root().discovery;
    local id = M.identity(e)
    local record = {
        entity = e,
        name = e.name,
        type = e.type,
        surface_index = e.surface.index,
        position = {
            x = e.position.x,
            y = e.position.y
        },
        force_name = e.force and e.force.name or nil,
        tick = game.tick
    }
    -- `inserted` distinguishes a genuinely new discovery from refreshing the
    -- timestamp/entity reference of an already known identity. Only new IDs
    -- should be appended to consumer queues or emit the mapped event.
    local inserted = M.store(d.order, d.records, id, record)
    index_add(d, id, record)
    if inserted then
        for role in pairs(registry.handoffs) do
            if registry.accepts_handoff(role, record) then
                d.queues[role] = d.queues[role] or {order = {}}
                d.queues[role].order[#d.queues[role].order + 1] = id
            end
        end
    end
    visuals.map_marker(id, e)
end

---Atomically expose an empty discovery database and schedule old data cleanup.
---Detaching the former tables makes clear immediate from callers' perspective;
---the scheduler releases their entries incrementally to avoid a large pause.
function M.clear()
    local root = state.root();
    local d = root.discovery;
    root.discovery_clear = {
        records = d.records,
        order = d.order,
        cursor = 1
    }
    d.records = {};
    d.order = {};
    d.by_name = {};
    d.groups = {};
    d.grouped = {};
    d.queues = {};
    -- Older saves may predate the generation counter, hence zero as the base.
    -- Consumers compare this number to reset cursors after an atomic clear.
    d.generation = (d.generation or 0) + 1;
    visuals.begin_clear(root, "map:")
end

-- Releases one record from a detached map after clear, bounding cleanup cost.
function M.step_clear(root)
    local job = root.discovery_clear
    if not job then
        return false
    end
    local id = job.order[job.cursor]
    if not id then
        root.discovery_clear = nil
        return false
    end
    job.records[id] = nil
    job.order[job.cursor] = nil
    job.cursor = job.cursor + 1
    return true
end

---Inspect a bounded number of records and remove invalid entity references.
function M.prune(limit)
    -- Inspect at most `limit` records. Removal leaves the cursor at the same
    -- numeric index because the following array element shifts into that slot.
    local d = state.root().discovery;
    local n = 0;
    -- The cursor is persistent so repeated bounded calls eventually inspect
    -- the whole array instead of always revisiting its first `limit` entries.
    d.prune_cursor = d.prune_cursor or 1
    while #d.order > 0 and n < limit do
        if d.prune_cursor > #d.order then
            d.prune_cursor = 1
        end
        local id = d.order[d.prune_cursor];
        local r = d.records[id];
        if not r or not r.entity or not r.entity.valid then
            index_remove(d, id, r)
            d.records[id] = nil
            table.remove(d.order, d.prune_cursor)
        else
            d.prune_cursor = d.prune_cursor + 1
        end
        n = n + 1
    end
end

-- Advances at most one shared record. Callers persist their own cursor and may fall back to scanning at end.
function M.next_for(rs, role)
    local d = state.root().discovery;
    local queue = role and d.queues and d.queues[role]
    if queue then
        if rs.handoff_generation ~= (d.generation or 0) then
            rs.handoff_generation = d.generation or 0
            rs.handoff_cursor = 1
        end
        local id = queue.order[rs.handoff_cursor or 1]
        if id then
            rs.handoff_cursor = (rs.handoff_cursor or 1) + 1
            local queued = d.records[id]
            return queued and queued.entity or nil, false
        end
    end
    if rs.discovery_generation ~= (d.generation or 0) then
        rs.discovery_generation = d.generation or 0;
        rs.discovery_cursor = 0
    end
    rs.discovery_cursor = (rs.discovery_cursor or 0) + 1;
    local id = d.order[rs.discovery_cursor]
    if not id then
        return nil, true
    end
    local r = d.records[id];
    return r and r.entity or nil, false
end

return M
