-- Long-Range Cannon balance and recipe settings.
-- Changes take effect after restarting Factorio.
return {
  cannon = {
    maximum_range = 112, -- Approximate radius of a normal radar's 7x7-chunk live coverage.
    minimum_range = 12,
    cooldown_ticks = 180, -- 60 ticks = 1 second at normal game speed.
    rotation_speed = 0.0015,
    maximum_health = 1400,
    inventory_size = 5,
    automated_ammo_count = 5
  },

  round = {
    direct_physical_damage = 500,
    blast_damage = 250,
    blast_radius = 3,
    projectile_starting_speed = 1.2,
    projectile_acceleration = 0.004,
    projectile_maximum_speed = 2,
    stack_size = 100
  },

  recipes = {
    cannon_crafting_time = 12,
    cannon = {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "engine-unit", amount = 5},
      {type = "item", name = "electronic-circuit", amount = 5},
      {type = "item", name = "advanced-circuit", amount = 3}
    },
    round_crafting_time = 10,
    round_batch_size = 10,
    rounds = {
      {type = "item", name = "steel-plate", amount = 20},
      {type = "item", name = "solid-fuel", amount = 1}
    }
  },

  unlock_technology = "military-3"
}
