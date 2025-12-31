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
        by_id = {},
        by_name = {},
        name_by_id = {},
        count = 0
    }, {
        __index = entity_index
    })
end

function entity_index:add(entity)
    local id = get_id(entity)
    if not id then
        return false
    end

    if self.by_id[id] then
        return false
    end

    local name = entity.name
    self.by_id[id] = entity
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

function entity_index:add_many(player_state, surface_index, entities)
    if not entities or #entities == 0 then
        return 0
    end

    local entity_group = module.get_module("entity_group")

    local added = 0
    for i = 1, #entities do
        local e = entities[i]
        if e and e.valid then
            -- preserve your existing “don’t track if already grouped” rule
            if not entity_group.is_in_any_entity_group(player_state, surface_index, e) then
                if self:add(e) then
                    added = added + 1
                end
            end
        end
    end

    return added
end

-- The equivalent of your current filter_entities():
-- returns all entities of name, and REMOVES them from the future set.
function entity_index:take_by_name(name)
    local bucket = self.by_name[name]
    if not bucket then
        return {}
    end

    local out = {}

    for id in pairs(bucket) do
        local ent = self.by_id[id]

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

-- Optional: cheap cleanup per tick to avoid invalids accumulating.
function entity_index:compact(budget)
    budget = budget or 1000
    local n = 0

    for id, ent in pairs(self.by_id) do
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

return entity_index
