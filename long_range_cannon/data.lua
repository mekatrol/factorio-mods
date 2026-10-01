local config = require("config")

local cannon_name = "long-range-cannon"
local round_name = "long-range-cannon-round"
local ammo_category = "long-range-cannon-shell"
local stationary_target_mask = "long-range-cannon-stationary-target"

local cannon = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
cannon.name = cannon_name
cannon.localised_name = {"entity-name." .. cannon_name}
cannon.localised_description = {"entity-description." .. cannon_name}
cannon.icon = "__long_range_cannon__/graphics/icons/long-range-cannon.png"
cannon.icon_size = 64
cannon.icons = nil
cannon.minable = {mining_time = 1, result = cannon_name}
cannon.max_health = config.cannon.maximum_health
cannon.collision_box = {{-1.4, -1.4}, {1.4, 1.4}}
cannon.selection_box = {{-1.5, -1.5}, {1.5, 1.5}}
cannon.drawing_box_vertical_extension = 1.5
cannon.inventory_size = config.cannon.inventory_size
cannon.automated_ammo_count = config.cannon.automated_ammo_count
cannon.next_upgrade = nil
cannon.rotation_speed = config.cannon.rotation_speed
cannon.preparing_speed = 0.04
cannon.folding_speed = 0.04
cannon.call_for_help_radius = config.cannon.maximum_range
cannon.attack_target_mask = {stationary_target_mask}
cannon.attack_parameters = {
  type = "projectile",
  ammo_category = ammo_category,
  cooldown = config.cannon.cooldown_ticks,
  projectile_creation_distance = 3.2,
  range = config.cannon.maximum_range,
  min_range = config.cannon.minimum_range,
  sound = {
    {filename = "__base__/sound/fight/artillery-shoots-1.ogg", volume = 0.9},
    {filename = "__base__/sound/fight/artillery-shoots-2.ogg", volume = 0.9}
  }
}

local turret_animation = {
  layers = {
    {
      filename = "__long_range_cannon__/graphics/entity/long-range-cannon-sheet.png",
      priority = "high",
      width = 256,
      height = 256,
      direction_count = 64,
      line_length = 8,
      frame_count = 1,
      -- Every frame in the current sheet is centred in its 256 px cell.
      shift = {0, 0},
      scale = 0.5
    }
  }
}

cannon.base_picture = {
  layers = {
    {
      filename = "__long_range_cannon__/graphics/entity/long-range-cannon-base.png",
      priority = "high",
      width = 256,
      height = 256,
      shift = {0, 0},
      scale = 0.5
    }
  }
}
cannon.folded_animation = table.deepcopy(turret_animation)
cannon.preparing_animation = table.deepcopy(turret_animation)
cannon.prepared_animation = table.deepcopy(turret_animation)
cannon.attacking_animation = table.deepcopy(turret_animation)
cannon.folding_animation = table.deepcopy(turret_animation)

local cannon_item = {
  type = "item",
  name = cannon_name,
  icon = "__long_range_cannon__/graphics/icons/long-range-cannon.png",
  icon_size = 64,
  subgroup = "defensive-structure",
  order = "b[turret]-d[long-range-cannon]",
  place_result = cannon_name,
  stack_size = 10,
  weight = 200000
}

local cannon_recipe = {
  type = "recipe",
  name = cannon_name,
  enabled = false,
  energy_required = config.recipes.cannon_crafting_time,
  ingredients = table.deepcopy(config.recipes.cannon),
  results = {{type = "item", name = cannon_name, amount = 1}}
}

local round = {
  type = "ammo",
  name = round_name,
  icon = "__long_range_cannon__/graphics/icons/long-range-cannon-round.png",
  icon_size = 64,
  ammo_category = ammo_category,
  ammo_type = {
    category = ammo_category,
    target_type = "entity",
    action = {
      type = "direct",
      action_delivery = {
        type = "projectile",
        projectile = "long-range-cannon-projectile",
        starting_speed = config.round.projectile_starting_speed,
        direction_deviation = 0,
        range_deviation = 0,
        max_range = config.cannon.maximum_range,
        min_range = config.cannon.minimum_range
      }
    }
  },
  magazine_size = 1,
  subgroup = "ammo",
  order = "d[rocket-launcher]-c[long-range-cannon-round]",
  stack_size = config.round.stack_size,
  weight = 10000
}

local round_recipe = {
  type = "recipe",
  name = round_name,
  enabled = false,
  energy_required = config.recipes.round_crafting_time,
  ingredients = table.deepcopy(config.recipes.rounds),
  results = {{type = "item", name = round_name, amount = config.recipes.round_batch_size}}
}

local projectile = table.deepcopy(data.raw.projectile["cannon-projectile"])
projectile.name = "long-range-cannon-projectile"
-- This is a ballistic shell, not a tank round. An empty collision box and hit
-- mask let it pass over the shooter's own factory and all intervening objects;
-- its action is executed only when it reaches the selected target.
projectile.collision_box = {{0, 0}, {0, 0}}
projectile.hit_collision_mask = {layers = {}}
projectile.piercing_damage = 0
projectile.force_condition = "not-same"
-- The base tank shell may use straight-line flight. This turret fires at a
-- specific entity, so retain that entity as a homing target until impact and
-- apply the action at the entity's centre rather than a collision-box edge.
projectile.direction_only = false
projectile.hit_at_collision_position = false
projectile.acceleration = config.round.projectile_acceleration
projectile.max_speed = config.round.projectile_maximum_speed
projectile.action = {
  type = "direct",
  force = "enemy",
  action_delivery = {
    type = "instant",
    target_effects = {
      {type = "create-entity", entity_name = "big-explosion"},
      {type = "damage", damage = {amount = config.round.direct_physical_damage, type = "physical"}},
      {
        type = "nested-result",
        action = {
          type = "area",
          radius = config.round.blast_radius,
          force = "enemy",
          action_delivery = {
            type = "instant",
            target_effects = {{type = "damage", damage = {amount = config.round.blast_damage, type = "explosion"}}}
          }
        }
      }
    }
  }
}

data:extend({
  {type = "trigger-target-type", name = stationary_target_mask},
  {type = "ammo-category", name = ammo_category},
  cannon,
  cannon_item,
  cannon_recipe,
  round,
  round_recipe,
  projectile
})

table.insert(data.raw.technology[config.unlock_technology].effects, {type = "unlock-recipe", recipe = cannon_name})
table.insert(data.raw.technology[config.unlock_technology].effects, {type = "unlock-recipe", recipe = round_name})
