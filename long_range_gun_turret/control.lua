-- Factorio assigns yellow, red, and uranium magazines to the same prototype
-- ammo category. Enforce the requested red-or-better rule at runtime without
-- changing vanilla ammunition or preventing it from working in other weapons.
local config = require("config")

local function rebuild_turret_list()
  storage.long_range_gun_turrets = {}
  for _, surface in pairs(game.surfaces) do
    for _, turret in pairs(surface.find_entities_filtered {name = config.prototype_name}) do
      table.insert(storage.long_range_gun_turrets, turret)
    end
  end
end

local function track_built_turret(event)
  local turret = event.entity
  if turret and turret.valid and turret.name == config.prototype_name then
    table.insert(storage.long_range_gun_turrets, turret)
  end
end

local function reject_basic_ammo(turret)
  if not (turret and turret.valid) then
    return
  end

  local inventory = turret.get_inventory(defines.inventory.turret_ammo)
  if not inventory then
    return
  end

  local count = inventory.get_item_count(config.combat.forbidden_ammo)
  if count == 0 then
    return
  end

  inventory.remove({name = config.combat.forbidden_ammo, count = count})
  turret.surface.spill_item_stack {
    position = turret.position,
    stack = {name = config.combat.forbidden_ammo, count = count},
    enable_looted = true,
    force = turret.force,
    allow_belts = false
  }
end

-- Build the tracked list from the map when the mod is added or upgraded, then
-- append newly built turrets without repeatedly searching every surface.
script.on_init(rebuild_turret_list)
script.on_configuration_changed(rebuild_turret_list)
script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, track_built_turret)

-- Check tracked turrets once per tick so hand-loading and inserters cannot
-- leave unsupported yellow magazines in them. Invalid ammunition is safely
-- dropped beside the turret rather than destroyed.
script.on_event(defines.events.on_tick, function()
  local turrets = storage.long_range_gun_turrets
  local write_index = 1

  for read_index = 1, #turrets do
    local turret = turrets[read_index]
    if turret.valid then
      reject_basic_ammo(turret)
      turrets[write_index] = turret
      write_index = write_index + 1
    end
  end

  for index = #turrets, write_index, -1 do
    turrets[index] = nil
  end
end)
