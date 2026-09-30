local target_line = {}

local COLOR = {r = 0.7, g = 1, b = 0.15, a = 0.35}

function target_line.clear(value)
    if value.target_line and value.target_line.valid then value.target_line.destroy() end
    value.target_line = nil
end

function target_line.draw(player, value, destination)
    if not (destination and value.entity and value.entity.valid) then return end
    if value.target_line and value.target_line.valid then
        value.target_line.color = COLOR
        value.target_line.width = 1
        value.target_line.from = value.entity
        value.target_line.to = destination
        value.target_line.players = {player.index}
        return
    end
    value.target_line = rendering.draw_line {
        color = COLOR, width = 1, from = value.entity, to = destination,
        surface = value.entity.surface, draw_on_ground = true,
        only_in_alt_mode = false, players = {player.index}
    }
end

return target_line
