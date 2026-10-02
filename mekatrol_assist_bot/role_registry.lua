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

function M.get(name)
    return M.roles[M.aliases[name] or name]
end

function M.has_task(role, task)
    for _, v in ipairs(role.tasks) do
        if v == task then
            return true
        end
    end
    return false
end

return M
