local module = {}

local key_for = {
    constructor = "constructor_bot",
    logistics = "logistics_bot",
    mapper = "mapper_bot",
    repairer = "repairer_bot",
    searcher = "searcher_bot",
    entity_group = "entity_group",
    inventory = "inventory",
    visual = "visual"
}

module.modules = {}

function module.init_module(modules)
    module.modules = modules or {}
end

function module.get_module(key)
    local module_key = key_for[key]
    return module_key and module.modules[module_key] or nil
end

return module
