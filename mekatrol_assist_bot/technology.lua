-- Technology gates are checked at every activation and research transition.
local config = require("config")
local M = {}

function M.missing_from(researched, required, mode)
    local missing = {};
    local any = false
    for _, name in ipairs(required) do
        local has = researched[name] == true;
        any = any or has
        if not has then
            missing[#missing + 1] = name
        end
    end
    if mode == "any" and any then
        return {}
    end
    return missing
end

function M.validate()
    for role, r in pairs(config.roles) do
        for i, name in ipairs(r.required_technologies) do
            if not prototypes.technology[name] then
                error("mekatrol_assist_bot config roles." .. role .. ".required_technologies[" .. i .. "]='" .. name ..
                          "'; expected an installed technology prototype")
            end
        end
    end
end

function M.missing(force, role)
    local r = config.roles[role];
    local researched = {}
    for _, name in ipairs(r.required_technologies) do
        researched[name] = force.technologies[name] and force.technologies[name].researched or false
    end
    return M.missing_from(researched, r.required_technologies, r.technology_mode)
end

function M.allowed(force, role)
    return #M.missing(force, role) == 0
end

return M
