local registry = {tasks = {}, aliases = {}, ordered_names = {}}
local constants = require("constants")

local function validate(definition)
    -- Fail during control-stage loading rather than much later during a tick;
    -- malformed extension tasks are configuration errors, not runtime states.
    if type(definition) ~= "table" or type(definition.name) ~= "string" then
        error("Upgrade task requires a name")
    end
    if type(definition.mappings) ~= "table" or next(definition.mappings) == nil then
        error("Upgrade task '" .. definition.name .. "' requires mappings")
    end
end

function registry.register(definition)
    validate(definition)

    -- Canonical names and aliases resolve to one definition so command parsing
    -- never needs task-specific conditionals.
    if not registry.tasks[definition.name] then
        registry.ordered_names[#registry.ordered_names + constants.ITEM_TRANSFER_COUNT] = definition.name
    end
    registry.tasks[definition.name] = definition
    registry.aliases[definition.name] = definition.name
    for _, alias in ipairs(definition.aliases or {}) do
        registry.aliases[alias] = definition.name
    end
end

function registry.next(current_name)
    for index, name in ipairs(registry.ordered_names) do
        if name == current_name then
            return registry.tasks[registry.ordered_names[index % #registry.ordered_names + constants.ITEM_TRANSFER_COUNT]]
        end
    end
    return registry.tasks[registry.ordered_names[constants.FIRST_INDEX]]
end

function registry.get(name)
    -- Resolve the public spelling first, allowing callers to treat canonical
    -- names and short aliases identically.
    local canonical = registry.aliases[name]
    return canonical and registry.tasks[canonical] or nil
end

function registry.names()
    -- Sorted output makes the task-list command deterministic across saves.
    local names = {}
    for name in pairs(registry.tasks) do names[#names + constants.ITEM_TRANSFER_COUNT] = name end
    table.sort(names)
    return names
end

function registry.source_names(definition)
    -- Factorio accepts an array of names in an entity filter. Deriving it from
    -- mappings keeps entity knowledge entirely inside task configuration.
    local names = {}
    for source in pairs(definition.mappings) do names[#names + constants.ITEM_TRANSFER_COUNT] = source end
    return names
end

function registry.mapping_for(definition, source_name)
    local mapping = definition.mappings[source_name]
    if type(mapping) == "string" then
        -- A string is convenient shorthand for the common one-item exchange:
        -- consume the target prototype's item and recover the source item.
        return {target = mapping, required_item = mapping, recovered_item = source_name}
    end
    return mapping
end

-- Built-in tasks use the same public registration path that future modules can
-- use, preventing two subtly different task formats from developing.
for _, definition in ipairs(require("tasks")) do registry.register(definition) end

return registry
