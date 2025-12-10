----------------------------------------------------------------------
-- data.lua
-- 
-- This file defines:
--  1) A custom hotkey input ("mekatrol-game-play-bot-toggle") that is
--     used to toggle the game-play bot via control scripts.
--  2) An invisible helper entity ("mekatrol-game-play-bot") that acts
--     as a script-controlled pseudo-robot, implemented as a
--     simple-entity-with-owner. It is non-interactable and is intended
--     solely for use by control logic.
----------------------------------------------------------------------


----------------------------------------------------------------------
-- HOTKEY: toggle game play bot
--
-- This creates a custom input prototype that the control script can
-- subscribe to (script.on_event) and use to toggle the bot on/off.
----------------------------------------------------------------------

data:extend({{
    -- Prototype type for custom keybinds that fire input events.
    type = "custom-input",

    -- Unique internal name for this input. Used in script like:
    --   script.on_event("mekatrol-game-play-bot-toggle", handler)
    name = "mekatrol-game-play-bot-toggle",

    -- Default key combination for triggering this input.
    -- Players can change this in the in-game controls menu.
    -- This particular combo is:
    --   Ctrl + Shift + G
    key_sequence = "CONTROL + SHIFT + G",

    -- How the input interacts with other key handling:
    --
    -- "none" means:
    --   - The custom-input event is raised when the key is pressed.
    --   - The key press is NOT consumed; the game/UI may still treat
    --     the keypress as normal (if any other binding exists).
    --
    -- Other possible values (for reference) are:
    --   - "game-only"   : Consumes input only for the game world.
    --   - "script-only" : Consumes input only for scripts.
    --   - "all"         : Fully consumes the key press everywhere.
    consuming = "none"
}})


----------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-game-play-bot AS A CONSTRUCTION ROBOT-LIKE
--
-- This defines an entity that:
--   - Is of type "simple-entity-with-owner".
--   - Has a sprite similar to a construction robot (icon and picture).
--   - Is invisible to normal gameplay:
--       * Not shown on the map.
--       * Not selectable.
--       * Not blueprintable.
--       * Not deconstructable.
--   - Has no collisions, so it does not block or interact physically.
--   - Is intended to be teleported/controlled exclusively via script,
--     effectively acting as a hidden "bot" under script control.
----------------------------------------------------------------------

-- Grab the base construction-robot prototype to reuse icon and picture.
local base_robot = data.raw["construction-robot"]["construction-robot"]
if not base_robot then
    -- Fail early during data stage if the expected vanilla prototype
    -- is missing (e.g. unusual mod setup or base game removed).
    error("Base construction-robot prototype not found")
end

local repair_bot = {
    ------------------------------------------------------------------
    -- BASIC PROTOTYPE METADATA
    ------------------------------------------------------------------

    -- The prototype type determines what behavior and fields are valid.
    -- "simple-entity-with-owner" is a very lightweight entity type that:
    --   - Belongs to a force (player/enemy/etc.).
    --   - Has health and can be damaged.
    --   - Has no built-in AI or behavior (script must drive it).
    --   - Is commonly used for simple helper entities or dummies.
    type = "simple-entity-with-owner",

    -- Internal name of the entity. Used in scripts and data, e.g.:
    --   surface.create_entity{name = "mekatrol-game-play-bot", ...}
    name = "mekatrol-game-play-bot",

    -- Localised name reference. This points to a locale key, so that
    -- the entity’s display name can be translated:
    --   In locale file:
    --     [entity-name]
    --     mekatrol-game-play-bot=Game Play Bot
    localised_name = {"entity-name.mekatrol-game-play-bot"},

    ------------------------------------------------------------------
    -- ICON SETTINGS
    --
    -- These define how the entity looks in GUIs, debug menus, etc.
    -- Reusing icon settings from the base construction robot for a
    -- consistent visual identity.
    ------------------------------------------------------------------

    icon = base_robot.icon,
    icon_size = base_robot.icon_size,
    icon_mipmaps = base_robot.icon_mipmaps,

    ------------------------------------------------------------------
    -- FLAGS
    --
    -- These flags control various interaction and visibility aspects.
    -- In combination they make this entity:
    --   - Off-grid: can be placed anywhere.
    --   - Invisible on the map.
    --   - Invisible to blueprints.
    --   - Not deconstructable.
    --   - Not selectable in game.
    ------------------------------------------------------------------

    flags = {
        -- "placeable-off-grid":
        --   - Entity can be placed at arbitrary coordinates, ignoring
        --     the regular tile grid alignment.
        --   - It does not obey typical placement rules and can exist
        --     "between" tiles or overlapping other entities (subject to
        --     collision masks).
        "placeable-off-grid",

        -- "not-on-map":
        --   - This entity will not appear on the world map or minimap.
        --   - Even if it has a map color defined, it will not be drawn.
        --   - Useful for invisible helper entities controlled by script.
        "not-on-map",

        -- "not-blueprintable":
        --   - Blueprints will ignore this entity.
        --   - Copy-paste operations and blueprint creation do not
        --     include it.
        --   - Ensures player blueprints do not get cluttered with
        --     hidden helper entities.
        "not-blueprintable",

        -- "not-deconstructable":
        --   - Entity cannot be marked for deconstruction.
        --   - Deconstruction planner and bots will not remove it.
        --   - Prevents players from accidentally deleting the helper
        --     entity from the world.
        "not-deconstructable",

        -- "not-selectable-in-game":
        --   - Entity cannot be selected by the player cursor.
        --   - No selection box, no tooltip, no GUI will open.
        --   - Selection tools and normal clicking will ignore it.
        --   - This is crucial to keep it fully "invisible" to normal
        --     gameplay interaction.
        "not-selectable-in-game"
    },

    ------------------------------------------------------------------
    -- COLLISION AND SELECTION
    ------------------------------------------------------------------

    -- collision_box:
    --   - Defines the physical bounds used for collision detection.
    --   - Here it is set very small. However, the actual collision is
    --     governed by collision_mask below.
    --   - Even if small, the box is still used for certain internal
    --     checks and some script operations.
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},

    -- collision_mask:
    --   - Governs what this entity collides with.
    --   - Using "layers = {}" means it collides with nothing at all:
    --       * It does not block movement of players, units, or trains.
    --       * It does not block placement of other entities.
    --       * It is effectively "ghost-like" in the world.
    --   - This is ideal for a script-only helper that should not affect
    --     gameplay physics or pathfinding.
    collision_mask = {
        layers = {}
    },

    -- selection_box:
    --   - Controls the area that can be selected with the cursor.
    --   - Setting this to nil means there is no defined selection area.
    --   - Combined with "not-selectable-in-game", this guarantees that
    --     the entity is never directly selectable by the player.
    selection_box = nil,

    ------------------------------------------------------------------
    -- RENDERING AND HEALTH
    ------------------------------------------------------------------

    -- render_layer:
    --   - Determines drawing order relative to other world visuals.
    --   - "object" is a typical layer used by regular entities.
    --   - Even though the entity is not selectable or on the map, this
    --     affects how/where it is drawn in-world when visible.
    render_layer = "object",

    -- max_health:
    --   - Total hit points the entity has.
    --   - This entity can, in principle, take damage from script or
    --     certain game events (if ever exposed).
    --   - High enough to avoid accidental destruction, but the exact
    --     value depends on how scripts use it.
    max_health = 500,

    ------------------------------------------------------------------
    -- GRAPHICS (PICTURE)
    ------------------------------------------------------------------

    -- picture:
    --   - This sprite is what gets drawn for the entity in the world.
    --   - For "simple-entity-with-owner", this is a static picture,
    --     not an animation sequence by default.
    --   - Here we reuse the base robot's idle animation definition if
    --     available; otherwise fall back to a simple static sprite.
    picture = base_robot.idle or {
        -- Fallback filename for the construction robot sprite.
        filename = "__base__/graphics/entity/construction-robot/construction-robot.png",

        -- Sprite size in pixels.
        width = 32,
        height = 32,

        -- Positional shift relative to the entity's origin.
        -- {0, 0} means no offset.
        shift = {0, 0}
    }
}

----------------------------------------------------------------------
-- REGISTER PROTOTYPE
--
-- This final data:extend call makes the prototype available to the
-- game. After this, control scripts can create and manipulate the
-- "mekatrol-game-play-bot" entity via surface.create_entity, etc.
----------------------------------------------------------------------

data:extend({repair_bot})
