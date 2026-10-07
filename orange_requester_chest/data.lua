local name = "orange-requester-chest"

local entity = table.deepcopy(data.raw["logistic-container"]["requester-chest"])
entity.name = name
entity.icon = "__orange_requester_chest__/graphics/icons/orange-requester-chest.png"
entity.minable.result = name
entity.animation.layers[1].filename =
  "__orange_requester_chest__/graphics/entity/orange-requester-chest.png"

local item = table.deepcopy(data.raw.item["requester-chest"])
item.name = name
item.icon = "__orange_requester_chest__/graphics/icons/orange-requester-chest.png"
item.place_result = name
item.order = "b[storage]-d[orange-requester-chest]"

local recipe = table.deepcopy(data.raw.recipe["requester-chest"])
recipe.name = name
recipe.results = {{type = "item", name = name, amount = 1}}

data:extend({entity, item, recipe})

table.insert(data.raw.technology["logistic-robotics"].effects, {
  type = "unlock-recipe",
  recipe = name
})
