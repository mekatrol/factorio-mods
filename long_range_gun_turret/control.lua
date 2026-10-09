local config = require("config")

local turret_name = config.prototype_name

-- Versions 1.1.1 and earlier disabled the entity while a script searched for
-- targets. Restore those saved entities so Factorio's native turret targeting
-- can acquire and fire at enemies across the full prototype range.
local function activate(turret)
  if turret and turret.valid and turret.name == turret_name then
    turret.active = true
    turret.ignore_unprioritised_targets = false
    turret.set_priority_target(1, nil)
  end
end

local function activate_all()
  for _, surface in pairs(game.surfaces) do
    for _, turret in pairs(surface.find_entities_filtered({name = turret_name})) do
      activate(turret)
    end
  end
end

script.on_init(activate_all)
script.on_configuration_changed(activate_all)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, function(event)
  activate(event.entity)
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  activate(event.destination)
end)
