-- This registry is intentionally smaller than the general upgrade registry:
-- order is meaningful and aliases/manual selection are deliberately omitted.
local registry = {tasks = {}, ordered_names = {}}

for _, task in ipairs(require("track_tasks")) do
    -- Preserve declaration order as the only legal progression order.
    registry.tasks[task.name] = task
    registry.ordered_names[#registry.ordered_names + 1] = task.name
end

-- Resolve the stage stored in each player's persistent track-bot state.
function registry.get(name) return registry.tasks[name] end
function registry.source_names(task)
    -- Surface filters consume a dense array rather than the mapping set.
    local names = {}
    for name in pairs(task.mappings) do names[#names + 1] = name end
    return names
end
-- Keep mapping lookup compatible with the shared upgrade engine API.
function registry.mapping_for(task, name) return task and task.mappings[name] or nil end
function registry.mapping_available(force, task, name)
    -- Optional green prototypes and research state are checked before planning.
    local mapping = registry.mapping_for(task, name)
    if not mapping or not prototypes.entity[mapping.target] or not prototypes.item[mapping.required_item] then return false end
    local recipe = force and force.recipes[mapping.required_item] or nil
    -- Unlike generic extension tasks, every track tier is research-gated; an
    -- absent or disabled recipe must never be interpreted as obtainable.
    return recipe ~= nil and recipe.enabled
end
function registry.next(name)
    -- There is no wraparound: green is terminal and remains the active stage.
    for index, current in ipairs(registry.ordered_names) do
        if current == name then return registry.tasks[registry.ordered_names[index + 1]] end
    end
    return nil
end
-- Expose ordered names for diagnostics without manufacturing a second order.
function registry.names() return registry.ordered_names end
return registry
