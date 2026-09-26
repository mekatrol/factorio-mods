-- Upgrade jobs are data, not bot logic. Add future jobs here, or call
-- task_registry.register() from another control-stage module.
local constants = require("constants")

return {{
    -- Prototype and item identifiers below are declarative task data. They are
    -- intentionally colocated here—not hidden in procedural bot logic—so a new
    -- upgrade family can be added without changing the scheduler.
    name = constants.DEFAULT_TASK_NAME,
    aliases = {"belts", "yellow-red", "default"},
    description = "Upgrade yellow transport belts, underground belts and splitters to red",
    mappings = {
        -- Each mapping declares both sides of the material exchange so the
        -- scheduler never infers inventory items from prototype naming rules.
        ["transport-belt"] = {
            target = "fast-transport-belt",
            required_item = "fast-transport-belt",
            recovered_item = "transport-belt"
        },
        ["underground-belt"] = {
            target = "fast-underground-belt",
            required_item = "fast-underground-belt",
            recovered_item = "underground-belt",
            -- Object-specific preservation belongs to the task definition,
            -- leaving the executor independent of belt semantics.
            create_parameters = function(entity)
                -- Fast replacement needs the endpoint role explicitly; without
                -- it an output underground belt could be recreated as an input.
                return {type = entity.belt_to_ground_type}
            end
        },
        ["splitter"] = {
            target = "fast-splitter",
            required_item = "fast-splitter",
            recovered_item = "splitter"
        }
    }
}}
