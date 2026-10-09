-- Load every mod-specific choice from one file so balancing, appearance, and
-- template selection can be changed without editing prototype-building logic.
local config = require("config")

-- Give firearm magazines their own compatibility category. Ordinary bullet
-- weapons are extended to accept it in data-final-fixes.lua, while this turret
-- deliberately keeps the original "bullet" category used by piercing and
-- uranium magazines. Inserters can therefore reject yellow magazines before
-- picking them up instead of a runtime script having to eject them afterward.
data:extend({
  {
    type = "ammo-category",
    name = config.combat.basic_ammo_category
  }
})
data.raw.ammo["firearm-magazine"].ammo_category = config.combat.basic_ammo_category

-- Recolour only vanilla runtime-colour masks so the turret reads as red while
-- preserving the original metal detail, lighting, animation, and shadows.
local function tint_runtime_layers(value)
  if type(value) ~= "table" then
    return
  end

  if value.apply_runtime_tint then
    value.apply_runtime_tint = false
    value.tint = config.appearance.tint
  end

  for _, child in pairs(value) do
    if type(child) == "table" then
      tint_runtime_layers(child)
    end
  end
end

-- Build from the vanilla turret so all behaviour remains standard except for
-- the deliberately configured range, damage, identity, and red appearance.
local turret = table.deepcopy(data.raw[config.source.turret_type][config.source.turret_name])
turret.name = config.prototype_name
turret.localised_name = {"entity-name." .. config.prototype_name}
turret.localised_description = {"entity-description." .. config.prototype_name}
turret.minable.result = config.prototype_name
turret.next_upgrade = nil
turret.attack_parameters.range = config.combat.maximum_range
turret.attack_parameters.damage_modifier = config.combat.damage_modifier
turret.prepare_range = config.combat.prepare_range
turret.call_for_help_radius = config.combat.maximum_range
tint_runtime_layers(turret)

-- Reuse and tint the vanilla icon so inventories distinguish this turret while
-- the mod remains small and tracks the installed base-game art style.
turret.icon = nil
turret.icons = {
  {
    icon = config.appearance.icon,
    icon_size = config.appearance.icon_size,
    tint = config.appearance.tint
  }
}

-- Build from the vanilla item so inventory behaviour stays familiar while it
-- places the new turret and carries the configured red identity.
local item = table.deepcopy(data.raw[config.source.item_type][config.source.item_name])
item.name = config.prototype_name
item.localised_name = {"item-name." .. config.prototype_name}
item.localised_description = {"item-description." .. config.prototype_name}
item.place_result = config.prototype_name
item.order = config.item_order
item.icon = nil
item.icons = table.deepcopy(turret.icons)

-- Build from the vanilla recipe to retain its crafting category and interface
-- behaviour, then apply the independently adjustable requirements from config.
local recipe = table.deepcopy(data.raw.recipe[config.source.recipe_name])
recipe.name = config.prototype_name
recipe.localised_name = {"recipe-name." .. config.prototype_name}
recipe.energy_required = config.recipe.energy_required
recipe.ingredients = table.deepcopy(config.recipe.ingredients)
recipe.results = {{type = config.source.item_type, name = config.prototype_name, amount = config.recipe.result_count}}

-- Register the matched entity, placeable item, and recipe as one complete
-- feature so no partial prototype can appear in the game.
data:extend({turret, item, recipe})

-- Military 2 unlocks piercing magazines, so unlocking the turret here ensures
-- its minimum permitted ammunition is available at the same time.
table.insert(data.raw.technology[config.source.unlock_technology].effects, {
  type = "unlock-recipe",
  recipe = config.prototype_name
})
