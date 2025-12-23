----------------------------------------------------------------------
-- data.lua
--
-- This file defines:
--  1) A custom hotkey input ("mekatrol-game-play-bot-toggle") that is
--     used to toggle the game-play bot via control scripts.
--  2) A custom hotkey input ("mekatrol-game-play-bot-next-mode") that
--     cycles the bot's behavior mode.
--  3) An invisible helper entity ("mekatrol-game-play-bot") that acts
--     as a script-controlled pseudo-robot, implemented as a
--     simple-entity-with-owner.
--
-- The helper entity:
--   * Is non-interactable for the player.
--   * Can be attacked by enemies.
--   * Is intended solely for use by control logic.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- HOTKEYS
--
-- 1) "mekatrol-game-play-bot-toggle"
--      - Toggle creation/destruction of the bot.
-- 2) "mekatrol-game-play-bot-next-mode"
--      - Cycle through behavior modes:
--          follow -> search -> follow -> ...
----------------------------------------------------------------------
data:extend({{
    type = "custom-input",
    name = "mekatrol-game-play-bot-toggle",

    -- Default key combination: Ctrl + Shift + G
    key_sequence = "CONTROL + SHIFT + G",

    -- "none" so the key press is not consumed by script only.
    consuming = "none"
}, {
    -- Second hotkey: cycle bot modes.
    --
    -- This hotkey is used to change the bot's behavior mode
    -- without destroying/recreating the entity:
    --   * follow
    --   * search
    --
    -- The control script will interpret this as "advance to the
    -- next mode in the list".
    type = "custom-input",
    name = "mekatrol-game-play-bot-next-mode",

    -- Default key combination: Ctrl + Shift + H
    key_sequence = "CONTROL + SHIFT + H",

    consuming = "none"
}, {
    -- Fourth hotkey: change hull algorithm.
    --
    -- This hotkey is used to change the change hull algorithm
    type = "custom-input",
    name = "mekatrol-game-play-bot-render-hull-algorithm",

    -- Default key combination: Ctrl + Shift + L
    key_sequence = "CONTROL + SHIFT + L",

    consuming = "none"
}})

----------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-game-play-bot AS AN ATTACKABLE HELPER
--
-- This version is tuned so that biters/spitters can:
--   - Path to it.
--   - Attack it.
--   - Deal real damage (reducing max_health).
--
-- The main requirements:
--   1) Non-empty collision_mask so it exists in the collision world
--      and enemies can consider it for pathing/attacks.
--   2) An entity type that can be damaged ("simple-entity-with-owner").
--   3) Belongs to a force that enemies are configured to attack
--      ("player" is enough; the script chooses the force when
--      creating the entity).
----------------------------------------------------------------------

local base_robot = data.raw["construction-robot"]["construction-robot"]
if not base_robot then
    error("Base construction-robot prototype not found")
end

local repair_bot = {
    ------------------------------------------------------------------
    -- BASIC PROTOTYPE METADATA
    ------------------------------------------------------------------
    type = "simple-entity-with-owner",
    name = "mekatrol-game-play-bot",

    -- Localised name reference.
    localised_name = {"entity-name.mekatrol-game-play-bot"},

    ------------------------------------------------------------------
    -- ICON SETTINGS
    ------------------------------------------------------------------
    icon = base_robot.icon,
    icon_size = base_robot.icon_size,
    icon_mipmaps = base_robot.icon_mipmaps,

    ------------------------------------------------------------------
    -- FLAGS
    ------------------------------------------------------------------
    flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game"},

    ------------------------------------------------------------------
    -- COLLISION AND SELECTION
    ------------------------------------------------------------------
    collision_box = {{-0.2, -0.2}, {0.2, 0.2}},
    collision_mask = {
        layers = {}
    },
    selection_box = nil,

    ------------------------------------------------------------------
    -- RENDERING AND HEALTH
    ------------------------------------------------------------------
    render_layer = "object",
    max_health = 500,

    ------------------------------------------------------------------
    -- SPRITE / PICTURE
    ------------------------------------------------------------------
    picture = base_robot.idle or {
        filename = "__base__/graphics/entity/construction-robot/construction-robot.png",
        width = 32,
        height = 32,
        shift = {0, 0}
    }
}

----------------------------------------------------------------------
-- REGISTER PROTOTYPE
----------------------------------------------------------------------

data:extend({repair_bot})
