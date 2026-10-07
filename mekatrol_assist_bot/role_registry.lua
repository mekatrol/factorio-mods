-- Canonical role metadata. Behavior and task declarations are loaded from one
-- conventionally named `bot_role_<role>` module per configured role.
local config = require("config")
local M = {
    roles = {},
    handoffs = {}
}

for _, name in ipairs(config.formation.role_order) do
    local logic = require("bot_role_" .. name)
    M.roles[name] = {
        name = name,
        config = config.roles[name],
        tasks = logic.tasks,
        logic = logic
    }
    -- Discovery producers publish once. Each subscribing role receives an
    -- independent queue and therefore never steals work from another consumer.
    if logic.handoff then
        M.handoffs[name] = {types = logic.handoff_types}
    end
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
    a = "ammo",
    m = "mapper",
    s = "surveyor"
}

---Resolve a canonical role name or configured short alias.
function M.get(name)
    return M.roles[M.aliases[name] or name]
end

---Return whether a task belongs to the supplied role definition.
function M.has_task(role, task)
    for _, value in ipairs(role.tasks) do
        if value == task then
            return true
        end
    end
    return false
end

---Return whether a discovery record satisfies a role's subscription filter.
function M.accepts_handoff(role, record)
    local rule = M.handoffs[role]
    if not rule then
        return false
    end
    if not rule.types then
        return true
    end
    for _, entity_type in ipairs(rule.types) do
        if record.type == entity_type then
            return true
        end
    end
    return false
end

return M
