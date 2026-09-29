local constants = require("constants")

-- A custom input gives every player a discoverable, rebindable way to toggle
-- the bot without requiring console commands.
data:extend({{
    type = "custom-input",
    name = constants.CUSTOM_INPUT_NAME,
    key_sequence = constants.CUSTOM_INPUT_KEY_SEQUENCE,
    consuming = "none"
}})

data:extend({{
    type = "custom-input",
    name = constants.CLEANUP_CUSTOM_INPUT_NAME,
    key_sequence = constants.CLEANUP_CUSTOM_INPUT_KEY_SEQUENCE,
    consuming = "none"
}})

data:extend({{
    type = "custom-input",
    name = constants.LAMP_CUSTOM_INPUT_NAME,
    key_sequence = constants.LAMP_CUSTOM_INPUT_KEY_SEQUENCE,
    consuming = "none"
}})

-- Reusing the base construction robot keeps the helper visually consistent
-- with Factorio and avoids maintaining copied copyrighted sprite assets.
local base_robot = data.raw[constants.BASE_ROBOT_ENTITY_NAME][constants.BASE_ROBOT_ENTITY_NAME]
if not base_robot then
    error("Base construction-robot prototype not found")
end

-- A simple owned entity supplies health, force ownership, and rendering while
-- scripted movement supplies the specialized upgrade behavior.
data:extend({{
    type = "simple-entity-with-owner",
    name = constants.BOT_ENTITY_NAME,
    localised_name = {"entity-name.upgrade-bot"},
    icon = base_robot.icon,
    icon_size = base_robot.icon_size,
    icon_mipmaps = base_robot.icon_mipmaps,
    flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
             "not-selectable-in-game"},
    collision_box = {{-constants.BOT_COLLISION_HALF_SIZE, -constants.BOT_COLLISION_HALF_SIZE},
                     {constants.BOT_COLLISION_HALF_SIZE, constants.BOT_COLLISION_HALF_SIZE}},
    collision_mask = {layers = {}},
    selection_box = nil,
    render_layer = "object",
    max_health = constants.BOT_MAX_HEALTH,
    picture = base_robot.idle or {
        filename = "__base__/graphics/entity/construction-robot/construction-robot.png",
        width = constants.FALLBACK_SPRITE_SIZE,
        height = constants.FALLBACK_SPRITE_SIZE
    }
}})

local logistic_robot = data.raw["logistic-robot"]["logistic-robot"]
if not logistic_robot then error("Base logistic-robot prototype not found") end

data:extend({{
    type = "simple-entity-with-owner",
    name = constants.CLEANUP_BOT_ENTITY_NAME,
    localised_name = {"entity-name.cleanup-bot"},
    icon = logistic_robot.icon,
    icon_size = logistic_robot.icon_size,
    icon_mipmaps = logistic_robot.icon_mipmaps,
    flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
             "not-selectable-in-game"},
    collision_box = {{-constants.BOT_COLLISION_HALF_SIZE, -constants.BOT_COLLISION_HALF_SIZE},
                     {constants.BOT_COLLISION_HALF_SIZE, constants.BOT_COLLISION_HALF_SIZE}},
    collision_mask = {layers = {}},
    selection_box = nil,
    render_layer = "object",
    max_health = constants.BOT_MAX_HEALTH,
    picture = logistic_robot.idle or {
        filename = "__base__/graphics/entity/logistic-robot/logistic-robot.png",
        width = constants.FALLBACK_SPRITE_SIZE,
        height = constants.FALLBACK_SPRITE_SIZE
    }
}})
