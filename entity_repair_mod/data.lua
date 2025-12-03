local util = require("util")

----------------------------------------------------------------------
-- HOTKEY: toggle repair bot
----------------------------------------------------------------------

data:extend({{
    type = "custom-input",
    name = "mekatrol-toggle-repair-bot",
    key_sequence = "CONTROL + SHIFT + W",
    consuming = "none"
}})

----------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-repair-bot AS A CONSTRUCTION ROBOT
--
-- We clone the base game's construction robot and modify it:
-- - New name ("mekatrol-repair-bot") so we can spawn it by script.
-- - Hidden from normal gameplay (no blueprints, no deconstruction).
-- - Always uses the "working" animation so it looks like it's repairing.
----------------------------------------------------------------------

local base_robot = data.raw["construction-robot"]["construction-robot"]
if not base_robot then
    error("Base construction-robot prototype not found")
end

local repair_bot = {
    type = "simple-entity-with-owner",
    name = "mekatrol-repair-bot",
    localised_name = {"entity-name.mekatrol-repair-bot"},

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
    max_health = 500,

    -- Use the vanilla logistic robot's idle animation as our picture.
    picture = base_robot.idle or {
        filename = "__base__/graphics/entity/construction-robot/construction-robot.png",
        width = 32,
        height = 32,
        shift = {0, 0}
    }
}

data:extend({repair_bot})
