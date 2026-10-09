local config = require("config")

local turret_name = config.prototype_name
local range = config.combat.maximum_range
local range_squared = range * range
local rows = config.targeting.sector_rows
local columns = config.targeting.sector_columns
local sector_count = rows * columns

local function ensure_state()
  storage.long_range_targeting = storage.long_range_targeting or {
    turrets = {},
    cursor = 0
  }
  return storage.long_range_targeting
end

local function register(turret)
  if not (turret and turret.valid and turret.name == turret_name) then
    return
  end

  -- Keep idle turrets inactive so the native AI cannot perform a full-radius
  -- acquisition between the scheduled sector scans.
  turret.active = false
  turret.ignore_unprioritised_targets = true
  turret.set_priority_target(1, nil)

  local state = ensure_state()
  state.turrets[#state.turrets + 1] = {
    entity = turret,
    sector = (turret.unit_number or #state.turrets) % sector_count
  }
end

local function rebuild()
  storage.long_range_targeting = {turrets = {}, cursor = 0}
  for _, surface in pairs(game.surfaces) do
    for _, turret in pairs(surface.find_entities_filtered({name = turret_name})) do
      register(turret)
    end
  end
end

local function is_enemy(turret, candidate)
  local candidate_force = candidate.force
  return candidate_force ~= turret.force
      and not turret.force.get_friend(candidate_force)
      and not turret.force.get_cease_fire(candidate_force)
end

local function has_ammunition(turret)
  local inventory = turret.get_inventory(defines.inventory.turret_ammo)
  return inventory and not inventory.is_empty()
end

local function scan_sector(record)
  local turret = record.entity
  if not (turret and turret.valid) then
    return nil
  end

  if record.target then
    return false
  end

  turret.active = false
  turret.ignore_unprioritised_targets = true
  if not has_ammunition(turret) then
    return false
  end

  local sector = record.sector
  record.sector = (sector + 1) % sector_count

  local column = sector % columns
  local row = math.floor(sector / columns)
  local width = range * 2 / columns
  local height = range * 2 / rows
  local left = turret.position.x - range + column * width
  local top = turret.position.y - range + row * height
  local area = {{left, top}, {left + width, top + height}}

  local closest
  local closest_distance = range_squared + 1
  local candidates = turret.surface.find_entities_filtered({
    area = area,
    is_military_target = true
  })

  for _, candidate in pairs(candidates) do
    if candidate.valid and is_enemy(turret, candidate) then
      local dx = candidate.position.x - turret.position.x
      local dy = candidate.position.y - turret.position.y
      local distance = dx * dx + dy * dy
      if distance <= range_squared and distance < closest_distance then
        closest = candidate
        closest_distance = distance
      end
    end
  end

  if closest then
    -- The priority entry permits this exact target type while the explicit
    -- shooting target selects the individual entity. Idle turrets remain
    -- inactive, so the engine never performs an automatic range search.
    turret.set_priority_target(1, closest)
    turret.shooting_target = closest
    turret.active = true
    record.target = closest
  end
  return true
end

local function maintain_targets(records)
  for _, record in pairs(records) do
    local turret = record.entity
    local target = record.target
    if turret and turret.valid and target then
      local in_range = false
      if target.valid and is_enemy(turret, target) then
        local dx = target.position.x - turret.position.x
        local dy = target.position.y - turret.position.y
        in_range = dx * dx + dy * dy <= range_squared
      end

      if not in_range then
        -- shooting_target cannot be cleared through the API. Deactivating the
        -- turret prevents the stale target or native AI from causing work;
        -- the next sector hit will replace it with a fresh entity.
        turret.active = false
        turret.set_priority_target(1, nil)
        record.target = nil
      end
    end
  end
end

local function update()
  local state = ensure_state()
  local records = state.turrets
  local remaining = config.targeting.scans_per_tick
  local checked = 0

  maintain_targets(records)

  while remaining > 0 and checked < #records do
    if state.cursor >= #records then
      state.cursor = 0
    end
    state.cursor = state.cursor + 1
    checked = checked + 1

    local record = records[state.cursor]
    local scanned = scan_sector(record)
    if scanned == nil then
      table.remove(records, state.cursor)
      state.cursor = state.cursor - 1
    elseif scanned then
      remaining = remaining - 1
    end
  end
end

script.on_init(rebuild)
script.on_configuration_changed(rebuild)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, function(event)
  register(event.entity)
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  register(event.destination)
end)

script.on_event(defines.events.on_tick, update)
