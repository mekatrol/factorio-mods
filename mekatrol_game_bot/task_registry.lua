local registry = {tasks = {}, aliases = {}, ordered_names = {}}
local constants = require("constants")
local config = require("config")

local function validate(definition)
    -- Fail during control-stage loading rather than much later during a tick;
    -- malformed extension tasks are configuration errors, not runtime states.
    if type(definition) ~= "table" or type(definition.name) ~= "string" then
        error("Upgrade task requires a name")
    end
    if definition.kind ~= constants.LAMP_MODE_KIND and
            (type(definition.mappings) ~= "table" or next(definition.mappings) == nil) then
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
    for source in pairs(definition.mappings or {}) do names[#names + constants.ITEM_TRANSFER_COUNT] = source end
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

function registry.mapping_available(force, definition, source_name)
    -- Every planned replacement must be craftable by the owning force. Mapping
    -- definitions may name a different unlocking recipe, but conventional
    -- Factorio entities use the required item name as their recipe name.
    local mapping = registry.mapping_for(definition, source_name)
    if not mapping then return false end
    if mapping.is_available then return mapping.is_available(force, mapping) end
    local recipe_name = mapping.recipe or mapping.required_item
    local recipe = recipe_name and force and force.recipes[recipe_name] or nil
    -- Items without a recipe are treated as externally obtainable unless a
    -- mapping supplies an explicit availability callback.
    return not recipe or recipe.enabled
end

local function register_all_upgrades()
    -- Build the all-upgrades mode from registered task data. This keeps future
    -- upgrade families automatically available in the composite mode while
    -- excluding non-upgrade modes such as autonomous lamp placement.
    local combined = {
        name = constants.ALL_TASK_NAME,
        label = "All upgrades",
        aliases = {"all", "everything"},
        description = "Perform every suitable registered upgrade",
        all_upgrades = true,
        mappings = {}
    }

    for _, task_name in ipairs(registry.ordered_names) do
        local task = registry.tasks[task_name]
        if task.kind ~= constants.LAMP_MODE_KIND and not task.all_upgrades then
            for source_name, raw_mapping in pairs(task.mappings) do
                -- Copy mapping fields instead of modifying the concrete task.
                -- The owner reference preserves its radius, supply, return and
                -- custom-executor policy when selected through composite mode.
                local mapping = type(raw_mapping) == "string" and {
                    target = raw_mapping,
                    required_item = raw_mapping,
                    recovered_item = source_name
                } or {}
                if type(raw_mapping) == "table" then
                    for key, value in pairs(raw_mapping) do mapping[key] = value end
                end
                mapping.owner_task = task
                combined.mappings[source_name] = mapping
                combined.search_radius = math.max(combined.search_radius or 0,
                    task.search_radius or config.search_radius)
            end
        end
    end

    registry.register(combined)
end

-- Built-in tasks use the same public registration path that future modules can
-- use, preventing two subtly different task formats from developing.
for _, definition in ipairs(require("tasks")) do registry.register(definition) end
register_all_upgrades()

return registry
