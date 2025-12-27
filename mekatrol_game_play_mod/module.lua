local module = {}

local util = require("util")

local key_for = {
    cleaner = "cleaner_bot",
    constructor = "constructor_bot",
    mapper = "mapper_bot",
    repairer = "repairer_bot"
}

module.modules = {}

local function print_modules()
    util.print(game, "red", "modules:")
    for key, value in pairs(module.modules) do
        util.print(game, "red", "  %s = %s", key, tostring(value))
    end
end

function module.init_module(modules)
    module.modules = modules or {}
end

function module.get_module(key)
    local module_key = key_for[key]
    return module_key and module.modules[module_key] or nil
end

return module
