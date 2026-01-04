-- entity_index.lua
local entity_index = {}

local module = require("module")
local util = require("util")

-- Same idea as util.generated_id() but avoid collisions when unit_number exists.
local function get_id(entity)
    if not (entity and entity.valid) then
        return nil
    end

    if entity.unit_number then
        return tostring(entity.surface.index) .. ":" .. tostring(entity.unit_number)
    end

    return util.generated_id(entity) -- tile-based fallback (your existing util)
end

function entity_index.new()
    return setmetatable({
        by_id = {}, -- id -> { tick=number, entity=LuaEntity }
        by_name = {}, -- name -> { [id]=true, ... }
        name_by_id = {}, -- id -> name
        count = 0
    }, {
        __index = entity_index
    })
end

function entity_index:add(entity, tick)
    local id = get_id(entity)
    if not id then
        return false
    end

    if self.by_id[id] then
        return false
    end

    local name = entity.name
    self.by_id[id] = {
        tick = tick,
        entity = entity
    }
    self.name_by_id[id] = name

    local bucket = self.by_name[name]
    if not bucket then
        bucket = {}
        self.by_name[name] = bucket
    end
    bucket[id] = true

    self.count = self.count + 1
    return true
end

function entity_index:add_many(ps, surface_index, entities, tick)
    if not entities or #entities == 0 then
        return 0
    end

    local entity_group = module.get_module("entity_group")

    local added = 0
    for i = 1, #entities do
        local e = entities[i]
        if e and e.valid then
            -- don’t add if already in entity group
            if not entity_group.is_in_any_entity_group(ps, surface_index, e) then
                if self:add(e, tick) then
                    added = added + 1
                end
            end
        end
    end

    return added
end

-- returns all entities of name, and REMOVES them from the set.
function entity_index:take_by_name(name)
    local bucket = self.by_name[name]
    if not bucket then
        return {}
    end

    local out = {}

    for id in pairs(bucket) do
        local wrap = self.by_id[id]
        local ent = wrap and wrap.entity or nil

        -- remove from indexes regardless (either consumed or invalid)
        self.by_id[id] = nil
        self.name_by_id[id] = nil
        bucket[id] = nil
        self.count = self.count - 1

        if ent and ent.valid then
            out[#out + 1] = ent
        end
    end

    self.by_name[name] = nil
    return out
end

function entity_index:take_by_name_contains(name)
    if not name then
        return {}
    end

    local out = {}

    -- Collect matching bucket names first (don’t mutate while iterating pairs)
    local matching_names = {}

    for bucket_name in pairs(self.by_name) do
        if string.find(bucket_name, name, 1, true) ~= nil then
            matching_names[#matching_names + 1] = bucket_name
        end
    end

    if #matching_names == 0 then
        return {}
    end

    -- Drain all matching buckets
    for i = 1, #matching_names do
        local bucket_name = matching_names[i]
        local bucket = self.by_name[bucket_name]

        if bucket then
            for id in pairs(bucket) do
                local wrap = self.by_id[id]
                local ent = wrap and wrap.entity or nil

                -- remove from indexes regardless (either consumed or invalid)
                self.by_id[id] = nil
                self.name_by_id[id] = nil
                bucket[id] = nil
                self.count = self.count - 1

                if ent and ent.valid then
                    out[#out + 1] = ent
                end
            end

            self.by_name[bucket_name] = nil
        end
    end

    return out
end

function entity_index:take_by_name_contains_with_limit(name, limit)
    if not name or limit <= 0 then
        return {}
    end

    local out = {}
    local taken = 0

    -- iterate bucket names that contain substr
    for bucket_name, bucket in pairs(self.by_name) do
        if string.find(bucket_name, name, 1, true) then
            for id in pairs(bucket) do
                local wrap = self.by_id[id]
                local ent = wrap and wrap.entity or nil

                -- remove one
                self.by_id[id] = nil
                self.name_by_id[id] = nil
                bucket[id] = nil
                self.count = self.count - 1

                if ent and ent.valid then
                    out[#out + 1] = ent
                end

                taken = taken + 1
                if taken >= limit then
                    return out
                end
            end

            if next(bucket) == nil then
                self.by_name[bucket_name] = nil
            end
        end
    end

    return out
end

-- Cheap cleanup per tick to avoid invalids accumulating.
function entity_index:compact(budget)
    budget = budget or 1000
    local n = 0

    for id, wrap in pairs(self.by_id) do
        local ent = wrap and wrap.entity or nil
        if not (ent and ent.valid) then
            local name = self.name_by_id[id]
            self.by_id[id] = nil
            self.name_by_id[id] = nil
            local bucket = name and self.by_name[name]
            if bucket then
                bucket[id] = nil
                if next(bucket) == nil then
                    self.by_name[name] = nil
                end
            end
            self.count = self.count - 1
        end

        n = n + 1
        if n >= budget then
            break
        end
    end
end

function entity_index:get_name_counts()
    local result = {}

    for name, bucket in pairs(self.by_name) do
        local c = 0
        for _ in pairs(bucket) do
            c = c + 1
        end

        -- only include non-empty buckets (should always be true)
        if c > 0 then
            result[name] = c
        end
    end

    return result
end

-- Pops (drains) the first available name bucket and returns the entities from it.
-- Returns nil if no buckets left.
-- Note: "first" is arbitrary (pairs() order).
function entity_index:pop_first()
    for name in pairs(self.by_name) do
        -- take_by_name() already removes the bucket and updates indexes/count
        return self:take_by_name(name)
    end

    return nil
end

-- Returns name, entities; or nil if none.
function entity_index:pop_first_with_name()
    for name in pairs(self.by_name) do
        return name, self:take_by_name(name)
    end

    return nil
end

-- Returns all valid entities across all buckets WITHOUT removing them.
function entity_index:get_all()
    local out = {}

    for _, wrap in pairs(self.by_id) do
        local ent = wrap and wrap.entity or nil
        if ent and ent.valid then
            out[#out + 1] = ent
        end
    end

    return out
end

-- Get the wrapper for a specific entity id.
function entity_index:get_wrapper_by_id(id)
    return self.by_id[id]
end

-- Removes all entities added before (tick < min_tick).
-- Returns the number of removed entries.
function entity_index:clear_older_than(min_tick)
    if not min_tick then
        return 0
    end

    local removed = 0

    for id, wrap in pairs(self.by_id) do
        if wrap.tick < min_tick then
            local name = self.name_by_id[id]

            -- remove from by_id / name_by_id
            self.by_id[id] = nil
            self.name_by_id[id] = nil

            -- remove from name bucket
            local bucket = name and self.by_name[name]
            if bucket then
                bucket[id] = nil
                if next(bucket) == nil then
                    self.by_name[name] = nil
                end
            end

            self.count = self.count - 1
            removed = removed + 1
        end
    end

    return removed
end

-- Removes a single entity from the index.
-- Returns true if it was present and removed, false otherwise.
function entity_index:remove(entity)
    local id = get_id(entity)

    util.print_red("remove name: %s, id: %s, unit number: %s", entity.name, id, entity.unit_number)

    if not id then
        return false
    end

    return self:remove_by_id(id)
end

-- Removes a single entity by id.
-- Returns true if it was present and removed, false otherwise.
function entity_index:remove_by_id(id)
    local wrap = self.by_id[id]

    if not wrap then
        return false
    end

    local name = self.name_by_id[id]

    -- remove from by_id / name_by_id
    self.by_id[id] = nil
    self.name_by_id[id] = nil

    -- remove from name bucket
    local bucket = name and self.by_name[name]
    if bucket then
        bucket[id] = nil
        if next(bucket) == nil then
            self.by_name[name] = nil
        end
    end

    self.count = self.count - 1
    return true
end

return entity_index
