-- Stable external identifiers. User policy belongs in config.lua.
local M = {
    mod_name = "mekatrol_assist_bot",
    state_key = "mekatrol_assist_bot",
    command = "mab"
}

function M.prototype(role, state)
    return "mekatrol-assist-" .. role .. "-bot-" .. (state or "idle")
end

function M.input(action)
    return "mekatrol-assist-" .. action:gsub("_", "-")
end

return M
