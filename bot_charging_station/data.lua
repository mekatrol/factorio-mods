local name = "bot-charging-station"

local station = table.deepcopy(data.raw.roboport.roboport)
station.name = name
station.icon = "__bot_charging_station__/graphics/icons/bot-charging-station.png"
station.icon_size = 1024
station.minable = {mining_time = 0.2, result = name}
station.max_health = 300
station.corpse = "small-remnants"
station.logistics_radius = 0
station.construction_radius = 0
station.logistics_connection_distance = 0
station.robot_slots_count = 0
station.material_slots_count = 0
station.charging_energy = "1MW"
station.recharge_minimum = "5MJ"
station.energy_source = {
  type = "electric",
  usage_priority = "secondary-input",
  input_flow_limit = "10MW",
  buffer_capacity = "20MJ"
}
station.energy_usage = "50kW"
station.charging_offsets = {
  {-1.05, -1.05}, {-0.35, -1.05}, {0.35, -1.05}, {1.05, -1.05},
  {-1.05,  0.00}, {1.05,  0.00},
  {-1.05,  1.05}, {-0.35,  1.05}, {0.35,  1.05}, {1.05,  1.05}
}
station.base = {
  layers = {
    {
      filename = "__bot_charging_station__/graphics/entity/bot-charging-station.png",
      width = 1024,
      height = 1024,
      scale = 0.095,
      shift = {0, -0.1}
    }
  }
}
station.base_animation = nil
station.door_animation_up = nil
station.door_animation_down = nil
station.recharging_animation = nil
station.spawn_and_station_height = 0.45
station.draw_logistic_radius_visualization = false
station.draw_construction_radius_visualization = false
station.circuit_connector = nil
station.circuit_wire_max_distance = nil

local item = {
  type = "item",
  name = name,
  icon = "__bot_charging_station__/graphics/icons/bot-charging-station.png",
  icon_size = 1024,
  subgroup = "logistic-network",
  order = "c[signal]-b[bot-charging-station]",
  place_result = name,
  stack_size = 50
}

local recipe = {
  type = "recipe",
  name = name,
  enabled = false,
  energy_required = 2,
  ingredients = {
    {type = "item", name = "iron-plate", amount = 5},
    {type = "item", name = "copper-plate", amount = 10},
    {type = "item", name = "small-electric-pole", amount = 2}
  },
  results = {{type = "item", name = name, amount = 1}}
}

data:extend({station, item, recipe})

table.insert(data.raw.technology.robotics.effects, {
  type = "unlock-recipe",
  recipe = name
})
