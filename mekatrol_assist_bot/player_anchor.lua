-- Resolves a usable player anchor without persisting controller/render objects.
local config = require("config")
local M = {}

function M.get(index)
    local p = game.get_player(index)
    if not p or not p.valid or (not p.connected and not config.debug) then
        return nil
    end
    local c = p.character
    if c and c.valid then
        return {
            player = p,
            surface = c.surface,
            position = c.position,
            force = p.force
        }
    end
    if p.surface then
        return {
            player = p,
            surface = p.surface,
            position = p.position,
            force = p.force
        }
    end
end

return M
