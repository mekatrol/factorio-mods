local config = require("config")
local cannon_name = "long-range-cannon"

local function chunk_position(position)
  return {
    x = math.floor(position.x / 32),
    y = math.floor(position.y / 32)
  }
end

local function nearest_visible_stationary_enemy(cannon)
    local nearest = nil
    local nearest_distance_squared = math.huge
    
    -- Added "segmented-unit-spawner" for Gleba and "segmented-unit" for Vulcanus bosses
    local candidates = cannon.surface.find_entities_filtered({
        position = cannon.position,
        radius = config.cannon.maximum_range,
        type = {"unit-spawner", "segmented-unit-spawner", "turret", "segmented-unit"},
        force = "enemy"
    })
    
    local min_range_squared = (config.cannon.minimum_range * config.cannon.minimum_range)

    for _, target in pairs(candidates) do
        -- Optimization: Calculate local variable once outside loop or dynamically per check
        if target.valid and cannon.force.is_chunk_visible(target.surface, chunk_position(target.position)) then
            local dx = target.position.x - cannon.position.x
            local dy = target.position.y - cannon.position.y
            local distance_squared = (dx * dx) + (dy * dy)
            
            if distance_squared >= min_range_squared and distance_squared < nearest_distance_squared then
                nearest = target
                nearest_distance_squared = distance_squared
            end
        end
    end
    
    return nearest
end

local function update_cannon(cannon)
  local target = nearest_visible_stationary_enemy(cannon)
  if target then
    cannon.active = true
    cannon.shooting_target = target
  else
    -- A turret target cannot be cleared through the runtime API. Deactivating
    -- it prevents the engine from firing at a target hidden by fog of war.
    cannon.active = false
  end
end

local function update_all_cannons()
  for _, surface in pairs(game.surfaces) do
    for _, cannon in pairs(surface.find_entities_filtered({name = cannon_name})) do
      update_cannon(cannon)
    end
  end
end

local function disable_new_cannon(event)
  local entity = event.created_entity or event.entity or event.destination
  if entity and entity.valid and entity.name == cannon_name then
    entity.active = false
  end
end

script.on_init(update_all_cannons)
script.on_configuration_changed(update_all_cannons)
-- Reassert the selected target every tick so the native turret AI cannot
-- replace the scripted nearest-visible target between updates.
script.on_event(defines.events.on_tick, update_all_cannons)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, disable_new_cannon)
