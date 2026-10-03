-- Technology gates are checked at every activation and research transition.
local config = require("config")
local M = {}

---Return unmet technology names under an `all` or `any` requirement policy.
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

---Validate that every configured prerequisite exists in the loaded prototype set.
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

---Read a force's research state and return prerequisites missing for a role.
function M.missing(force, role)
    local r = config.roles[role];
    local researched = {}
    for _, name in ipairs(r.required_technologies) do
        researched[name] = force.technologies[name] and force.technologies[name].researched or false
    end
    return M.missing_from(researched, r.required_technologies, r.technology_mode)
end

---Return true when the force currently satisfies a role's technology gate.
function M.allowed(force, role)
    return #M.missing(force, role) == 0
end

local upgrade_sources = {
    ["yellow-to-red-belts"] = {"transport-belt", "underground-belt", "splitter"},
    ["red-to-blue-belts"] = {"fast-transport-belt", "fast-underground-belt", "fast-splitter"},
    ["blue-to-green-inserters"] = {"fast-inserter"},
    containers = {"wooden-chest", "iron-chest"}
}

---Checks whether at least one recipe used by an upgrade task is currently available.
---Combined mode is available when any configured mapping can be crafted. Track mode
---is intentionally excluded because it waits for later research while remaining active.
---@return boolean allowed
---@return string[] unavailable_recipe_names
function M.task_allowed(force, role, task)
    if role ~= "upgrade" then
        return true, {}
    end
    local sources = upgrade_sources[task]
    if task == "combined" then
        sources = {}
        for source in pairs(config.tasks.upgrade.mappings) do
            sources[#sources + 1] = source
        end
        table.sort(sources)
    end
    if not sources then
        return true, {}
    end
    local unavailable = {}
    for _, source in ipairs(sources) do
        local target = config.tasks.upgrade.mappings[source]
        local recipe = target and force.recipes[target]
        if target and prototypes.entity[target] and prototypes.item[target] and (not recipe or recipe.enabled) then
            return true, {}
        end
        unavailable[#unavailable + 1] = target or source
    end
    return false, unavailable
end

return M
