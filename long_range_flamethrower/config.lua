-- Centralise the mod's identity so every generated prototype and locale lookup
-- stays aligned when the upgraded turret is renamed.
local config = {
  prototype_name = "long-range-flamethrower-turret",

  -- Identify the vanilla prototypes used as templates so the upgraded turret
  -- retains the standard recipe, behaviour, sounds, connections, and artwork.
  source = {
    turret_type = "fluid-turret",
    turret_name = "flamethrower-turret",
    item_type = "item",
    item_name = "flamethrower-turret",
    recipe_name = "flamethrower-turret",
    unlock_technology = "flamethrower"
  },

  -- Define the requested combat balance explicitly so later vanilla changes do
  -- not alter the doubled range, close-range blind spot, or oil economy.
  combat = {
    maximum_range = 60,
    minimum_range = 25,
    turn_range = 1,
    prepare_range = 65,
    fluid_consumption = 0.2
  },

  -- Use a muted red on the vanilla colour-mask artwork so the variant remains
  -- recognisable without overpowering the turret's metal detail and shading.
  appearance = {
    tint = {r = 0.72, g = 0.38, b = 0.38, a = 1},
    icon = "__base__/graphics/icons/flamethrower-turret.png",
    icon_size = 64
  },

  -- Place the new item immediately after the standard defensive turrets so it
  -- remains easy to find in the same crafting-menu group.
  item_order = "b[turret]-d[long-range-flamethrower-turret]",

  -- Upgrade an existing standard turret with two additional engines so the
  -- long-range version is an improvement step rather than a separate build.
  recipe = {
    energy_required = 20,
    ingredients = {
      {type = "item", name = "flamethrower-turret", amount = 1},
      {type = "item", name = "engine-unit", amount = 2}
    },
    result_count = 1
  }
}

-- Expose one shared configuration table so data-stage files use a single source
-- of truth for all mod-specific choices.
return config
