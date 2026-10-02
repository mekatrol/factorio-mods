-- Shared discovery index and compatibility snapshots. Internal tables are never exposed.
local state = require("state")
local config = require("config")
local visuals = require("visuals")
local M = {}

function M.store(order, records, id, record)
    local inserted = records[id] == nil
    if inserted then
        order[#order + 1] = id
    end
    records[id] = record
    return inserted
end

function M.identity(e)
    return e.unit_number and ("u:" .. e.unit_number) or
               ("p:" .. e.surface.index .. ":" .. e.name .. ":" .. math.floor(e.position.x * 256) .. ":" ..
                   math.floor(e.position.y * 256))
end

function M.add(e)
    if not e.valid then
        return
    end
    local d = state.root().discovery;
    local id = M.identity(e)
    M.store(d.order, d.records, id, {
        entity = e,
        name = e.name,
        type = e.type,
        surface_index = e.surface.index,
        position = {
            x = e.position.x,
            y = e.position.y
        }
    })
    visuals.map_marker(id, e)
    local event = d.events and d.events.mapped;
    if event then
        script.raise_event(event, {
            entity = e,
            id = id
        })
    end
end

function M.clear()
    local root = state.root();
    local d = root.discovery;
    d.records = {};
    d.order = {};
    d.groups = {};
    d.generation = (d.generation or 0) + 1;
    visuals.begin_clear(root, "map:")
    local event = d.events and d.events.cleared;
    if event then
        script.raise_event(event, {})
    end
end

function M.prune(limit)
    local d = state.root().discovery;
    local n = 0;
    d.prune_cursor = d.prune_cursor or 1
    while #d.order > 0 and n < limit do
        if d.prune_cursor > #d.order then
            d.prune_cursor = 1
        end
        local id = d.order[d.prune_cursor];
        local r = d.records[id];
        if not r or not r.entity or not r.entity.valid then
            d.records[id] = nil
        end
        d.prune_cursor = d.prune_cursor + 1;
        n = n + 1
    end
end

function M.snapshot_page(cursor, limit)
    local out = {};
    local d = state.root().discovery;
    local first = math.max(1, tonumber(cursor) or 1);
    local count = math.min(config.compatibility.snapshot_limit,
        math.max(1, tonumber(limit) or config.compatibility.snapshot_limit));
    local last = math.min(#d.order, first + count - 1)
    for i = first, last do
        local id = d.order[i];
        local r = d.records[id];
        if r and r.entity and r.entity.valid then
            out[#out + 1] = {
                id = id,
                name = r.name,
                type = r.type,
                surface_index = r.surface_index,
                position = {
                    x = r.position.x,
                    y = r.position.y
                }
            }
        end
    end
    return {
        records = out,
        next_cursor = last < #d.order and last + 1 or nil
    }
end

function M.snapshot()
    return M.snapshot_page(1, config.compatibility.snapshot_limit).records
end

-- Advances at most one shared record. Callers persist their own cursor and may fall back to scanning at end.
function M.next_for(rs)
    local d = state.root().discovery;
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

function M.ensure_events()
    local d = state.root().discovery;
    d.events = d.events or {
        mapped = script.generate_event_name(),
        cleared = script.generate_event_name()
    }
end

function M.register()
    local mapped = function()
        local e = state.root().discovery.events
        return e and e.mapped
    end
    local cleared = function()
        local e = state.root().discovery.events
        return e and e.cleared
    end
    remote.add_interface("mapping_bot_mod", {
        get_mapped_entities = M.snapshot,
        get_mapped_entities_page = M.snapshot_page,
        get_event = mapped,
        get_clear_event = cleared,
        clear_mapped_entities = M.clear,
        get_entity_mapped_event = mapped,
        get_map_cleared_event = cleared
    })
end

return M
