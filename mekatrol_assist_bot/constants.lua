-- Stable external identifiers. User policy belongs in config.lua.
local M = {
    mod_name = "mekatrol_assist_bot",
    state_key = "mekatrol_assist_bot",
    command = "mab"
}

---Construct the data-stage prototype name for a role and animation state.
function M.prototype(role, state)
    -- `state` is optional for callers interested in the default/idle prototype.
    -- Keeping all naming here prevents data-stage and runtime strings diverging.
    return "mekatrol-assist-" .. role .. "-bot-" .. (state or "idle")
end

---Construct a custom-input name, translating Lua-style underscores to hyphens.
function M.input(action)
    -- Config/task identifiers use underscores as Lua keys, while Factorio
    -- prototype naming convention in this mod uses hyphens.
    return "mekatrol-assist-" .. action:gsub("_", "-")
end

return M
