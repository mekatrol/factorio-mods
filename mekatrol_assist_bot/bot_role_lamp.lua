-- Lamp role policy: illuminate powered poles once the surface is dark enough.
local config = require("config")
local supply = require("supply")
local M = {
    tasks = {"follow", "place"},
    scan_phase = "moving"
}

function M.radius()
    return config.tasks.lamp.radius
end

function M.filter()
    return {type = {"electric-pole", "lamp"}}
end

---Accept only powered poles with a free lamp position two tiles to the right.
function M.valid(entity)
    return entity.type == "electric-pole" and entity.electric_network_id ~= nil and
               entity.surface.can_place_entity {
            name = "small-lamp",
            position = {entity.position.x + 2, entity.position.y},
            force = entity.force
        }
end

---Consume and place one lamp, retaining the target during daylight.
function M.act(rs, anchor, entity)
    if anchor.surface.darkness < config.tasks.lamp.darkness then
        return false
    end
    -- The fixed two-tile offset keeps the lamp clear of the pole's collision box
    -- and makes repeated scans choose the same deterministic placement tile.
    local lamp_position = {x = entity.position.x + 2, y = entity.position.y}
    if anchor.surface.can_place_entity {name = "small-lamp", position = lamp_position, force = anchor.force} then
        local lamps_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity, "small-lamp", 1)
        if lamps_supplied == nil then
            return false
        end
        if lamps_supplied > 0 then
            local supply_source = rs.last_source
            rs.last_source = nil
            if not anchor.surface.create_entity {
                name = "small-lamp",
                position = lamp_position,
                force = anchor.force,
                player = anchor.player,
                raise_built = true
            } then
                supply.give_or_carry(rs, anchor.player, {name = "small-lamp", count = 1}, supply_source)
            end
        end
    end
    return true
end

return M
