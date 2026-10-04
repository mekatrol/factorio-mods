local config = require("config")

local basic_category = config.combat.basic_ammo_category
local advanced_category = "bullet"

local function accepts_category(attack_parameters, category)
  if attack_parameters.ammo_category == category then
    return true
  end

  for _, accepted in pairs(attack_parameters.ammo_categories or {}) do
    if accepted == category then
      return true
    end
  end

  return false
end

local function add_category(attack_parameters, category)
  if attack_parameters.ammo_category then
    attack_parameters.ammo_categories = {attack_parameters.ammo_category, category}
    attack_parameters.ammo_category = nil
  else
    attack_parameters.ammo_categories = attack_parameters.ammo_categories or {}
    table.insert(attack_parameters.ammo_categories, category)
  end
end

-- Preserve firearm-magazine support in every bullet weapon, including weapons
-- added by other mods. The long-range turret is the sole deliberate exception.
for _, prototypes in pairs(data.raw) do
  for name, prototype in pairs(prototypes) do
    local attack_parameters = prototype.attack_parameters
    if name ~= config.prototype_name
        and attack_parameters
        and accepts_category(attack_parameters, advanced_category)
        and not accepts_category(attack_parameters, basic_category) then
      add_category(attack_parameters, basic_category)
    end
  end
end

-- Firearm magazines should continue receiving the same research bonuses as
-- other bullet ammunition after moving to their dedicated category.
for _, technology in pairs(data.raw.technology) do
  local extra_effects = {}
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "ammo-damage" and effect.ammo_category == advanced_category then
      local basic_effect = table.deepcopy(effect)
      basic_effect.ammo_category = basic_category
      table.insert(extra_effects, basic_effect)
    end
  end

  for _, effect in pairs(extra_effects) do
    table.insert(technology.effects, effect)
  end
end
