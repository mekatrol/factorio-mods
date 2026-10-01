-- Mark only immobile enemy structures as valid automatic targets. This runs
-- after every mod has registered prototypes so compatible modded spawners and
-- worm-style enemy turrets are included as well.
local stationary_target_mask = "long-range-cannon-stationary-target"

local function has_flag(prototype, wanted_flag)
  for _, flag in pairs(prototype.flags or {}) do
    if flag == wanted_flag then
      return true
    end
  end
  return false
end

local function add_stationary_target_mask(prototype)
  -- "common" preserves normal targeting by other weapons after replacing the
  -- prototype's implicit default mask with an explicit list.
  prototype.trigger_target_mask = prototype.trigger_target_mask or {"common"}
  for _, mask in pairs(prototype.trigger_target_mask) do
    if mask == stationary_target_mask then
      return
    end
  end
  table.insert(prototype.trigger_target_mask, stationary_target_mask)
end

for _, spawner in pairs(data.raw["unit-spawner"] or {}) do
  add_stationary_target_mask(spawner)
end

for _, turret in pairs(data.raw.turret or {}) do
  if has_flag(turret, "placeable-enemy") then
    add_stationary_target_mask(turret)
  end
end
