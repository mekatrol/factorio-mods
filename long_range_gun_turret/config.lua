-- Centralise the mod's identity so every prototype, runtime check, and locale
-- lookup stays aligned when the upgraded turret is renamed.
local config = {
  prototype_name = "long-range-gun-turret",

  -- Identify the vanilla prototypes used as templates so the upgraded turret
  -- retains the standard behaviour, sounds, circuit connection, and artwork.
  source = {
    turret_type = "ammo-turret",
    turret_name = "gun-turret",
    item_type = "item",
    item_name = "gun-turret",
    recipe_name = "gun-turret",
    unlock_technology = "military-2"
  },

  -- Match the long-range flamethrower's 60-tile reach and double the gun
  -- turret's damage. The modifier stacks with ammunition and research bonuses.
  combat = {
    maximum_range = 60,
    damage_modifier = 2,
    basic_ammo_category = "basic-bullet"
  },

  -- Native turrets look for targets continuously. Long-range turrets instead
  -- acquire targets incrementally: the surrounding square is split into this
  -- many rows and columns and only one cell is queried per scheduler step.
  targeting = {
    sector_rows = 4,
    sector_columns = 4,
    scans_per_tick = 1
  },

  -- Use a muted red on the vanilla colour-mask artwork so the variant remains
  -- recognisable without overpowering the turret's metal detail and shading.
  appearance = {
    tint = {r = 0.72, g = 0.38, b = 0.38, a = 1},
    icon = "__base__/graphics/icons/gun-turret.png",
    icon_size = 64
  },

  -- Place the new item beside the standard defensive turrets in the crafting
  -- menu, immediately after the vanilla gun turret.
  item_order = "b[turret]-b[long-range-gun-turret]",

  -- Upgrade an existing gun turret with an engine.
  recipe = {
    energy_required = 20,
    ingredients = {
      {type = "item", name = "gun-turret", amount = 1},
      {type = "item", name = "engine-unit", amount = 1}
    },
    result_count = 1
  }
}

-- Expose one shared configuration table so data and runtime stages use a
-- single source of truth for all mod-specific choices.
return config
