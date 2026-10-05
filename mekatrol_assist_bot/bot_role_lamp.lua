-- Lamp role policy: illuminate powered poles once the surface is dark enough.
local config = require("config")
local supply = require("supply")
local movement = require("movement")
local M = {
    tasks = {"follow", "place"}
}

---Follow formation while watching for work. Once lamps are aboard, retain
---movement control between placements just like an upgrade bot's work batch.
function M.scan_phase(rs)
    return (rs.supplied and (rs.supplied["small-lamp"] or 0) > 0) and "moving" or "idle"
end

function M.begin_scan(rs)
    rs.lamp_demand = 0
end

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

---Count valid placement sites while retaining the closest one. The count is
---capped at carrying capacity because additional demand cannot affect pickup.
function M.scan_entity(entity, rs, anchor)
    if not M.valid(entity, rs, anchor) then
        return
    end
    rs.lamp_demand = math.min(config.tasks.lamp.items_per_trip, (rs.lamp_demand or 0) + 1)
    local distance = movement.distance2(entity.position, rs.entity.position)
    if not rs.best_distance or distance < rs.best_distance then
        rs.target, rs.best_distance = entity, distance
    end
end

---Do no target work in daylight. Returning idle lets the shared formation
---follower position the bot alongside the other assistants until night.
function M.before_step(_, anchor)
    if anchor.surface.darkness < config.tasks.lamp.darkness then
        return "idle"
    end
end

local function pickup_count(rs)
    return math.max(1, math.min(config.tasks.lamp.items_per_trip, rs.lamp_demand or 1))
end

---Acquire the demand-sized lamp batch before flying to the selected pole.
function M.navigate(rs, anchor, bot)
    local staged = rs.supplied and (rs.supplied["small-lamp"] or 0) or 0
    if staged == 0 then
        local supplied = supply.take(rs, anchor.player, rs.target, bot, "small-lamp", 1, pickup_count(rs))
        if supplied == nil then
            return "moving", false
        end
        if supplied == 0 then
            rs.waiting_inventory = "small-lamp"
            return "idle", false
        end
        -- Leave the handed-off item staged for act(), matching upgrade roles.
        rs.supplied["small-lamp"] = (rs.supplied["small-lamp"] or 0) + supplied
    end
    local ready = movement.step(bot, rs.target.position)
    return ready and "working" or "moving", ready
end

function M.finish(rs, anchor)
    supply.return_staged(rs, anchor.player)
    rs.lamp_demand = nil
end

---Consume and place one lamp. The daylight check is a final safety guard in
---case darkness changes between navigation and the scheduled action.
function M.act(rs, anchor, entity)
    if anchor.surface.darkness < config.tasks.lamp.darkness then
        return false
    end
    -- The fixed two-tile offset keeps the lamp clear of the pole's collision box
    -- and makes repeated scans choose the same deterministic placement tile.
    local lamp_position = {x = entity.position.x + 2, y = entity.position.y}
    if anchor.surface.can_place_entity {name = "small-lamp", position = lamp_position, force = anchor.force} then
        local lamps_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity, "small-lamp", 1,
            pickup_count(rs))
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
        else
            rs.waiting_inventory = "small-lamp"
            return false
        end
    end
    return true
end

return M
