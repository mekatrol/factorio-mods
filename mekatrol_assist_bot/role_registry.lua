-- Canonical role/task metadata shared by command, manager, and controllers.
local config = require("config")
local M = {
    roles = {}
}

local tasks = {
    builder = {"follow", "move_to", "construct"},
    repair = {"follow", "move_to", "repair"},
    upgrade = {"follow", "yellow-to-red-belts", "red-to-blue-belts", "blue-to-green-inserters", "containers", "combined"},
    track = {"follow", "track"},
    lamp = {"follow", "place"},
    cliff = {"follow", "demolish"},
    logistics = {"follow", "collect", "pickup"},
    cleanup = {"follow", "cleanup"},
    mapper = {"follow", "search"},
    surveyor = {"follow", "search", "survey"}
}

-- Discovery handoffs replace the legacy master controller. Producers publish
-- once; each consumer advances its own persistent queue under scheduler budget.
M.handoffs = {
    repair = {},
    logistics = {types = {"item-entity", "simple-entity", "simple-entity-with-owner", "container", "resource"}},
    surveyor = {types = {"resource"}}
}

---Return whether a discovery record satisfies a role's subscription rule.
function M.accepts_handoff(role, record)
    local rule = M.handoffs[role]
    if not rule then
        return false
    end
    if rule.force and record.force_name ~= rule.force then
        return false
    end
    if rule.types then
        for _, entity_type in ipairs(rule.types) do
            if record.type == entity_type then
                return true
            end
        end
        return false
    end
    return true
end

for _, name in ipairs(config.formation.role_order) do
    M.roles[name] = {
        name = name,
        config = config.roles[name],
        tasks = tasks[name]
    }
end

M.aliases = {
    b = "builder",
    r = "repair",
    u = "upgrade",
    t = "track",
    l = "lamp",
    d = "cliff",
    g = "logistics",
    c = "cleanup",
    m = "mapper",
    s = "surveyor",
    v = "surveyor"
}

---Resolve a canonical role name or configured short/legacy alias.
function M.get(name)
    return M.roles[M.aliases[name] or name]
end

---Return whether a task name is supported by the supplied role metadata.
function M.has_task(role, task)
    for _, v in ipairs(role.tasks) do
        if v == task then
            return true
        end
    end
    return false
end

return M
