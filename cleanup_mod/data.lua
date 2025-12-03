-- --------------------------------------------------------------------
-- data.lua
--
-- Declares:
--   - A custom input to toggle the cleanup bot.
--   - A prototype "mekatrol-cleanup-bot" as a simple-entity-with-owner
--     using the vanilla logistic robot graphics, but fully script-driven.
-- --------------------------------------------------------------------
local util = require("util")

-- --------------------------------------------------------------------
-- CUSTOM INPUT: toggle cleanup bot on/off
-- --------------------------------------------------------------------

data:extend({{
    type = "custom-input",
    name = "mekatrol-toggle-cleanup-bot",
    key_sequence = "CONTROL + SHIFT + C",
    consuming = "none"
}})

-- --------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-cleanup-bot
--
-- We no longer use type "logistic-robot". Instead, we use
-- "simple-entity-with-owner" so the game does not run any robot AI on it
-- and does not override our teleport-based movement.
-- --------------------------------------------------------------------

local base_robot = data.raw["logistic-robot"]["logistic-robot"]
if not base_robot then
    error("Base logistic-robot prototype not found")
end

local cleanup_bot = {
    type = "simple-entity-with-owner",
    name = "mekatrol-cleanup-bot",
    localised_name = {"entity-name.mekatrol-cleanup-bot"},

    -- Reuse icon from vanilla robot
    icon = base_robot.icon,
    icon_size = base_robot.icon_size,
    icon_mipmaps = base_robot.icon_mipmaps,

    flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game"},

    -- Small (or nil) collision box. We do NOT set collision_mask;
    -- the default is fine and teleport will still work.
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = nil,

    render_layer = "object",
    max_health = 100,

    -- Use the vanilla logistic robot's idle animation as our picture.
    picture = base_robot.idle or {
        filename = "__base__/graphics/entity/logistic-robot/logistic-robot.png",
        width = 32,
        height = 32,
        shift = {0, 0}
    }
}

data:extend({cleanup_bot})
