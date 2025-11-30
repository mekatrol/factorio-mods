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
-- ENTITY PROTOTYPE: mekatr ol-repair-bot AS A CONSTRUCTION ROBOT
--
-- We clone the base game's construction robot and modify it:
-- - New name ("mekatrol-repair-bot") so we can spawn it by script.
-- - Hidden from normal gameplay (no blueprints, no deconstruction).
-- - Always uses the "working" animation so it looks like it's repairing.
----------------------------------------------------------------------

do
    -- Grab the vanilla construction robot prototype.
    local base = data.raw["construction-robot"]["construction-robot"]
    if not base then
        error("Base construction-robot prototype not found")
    end

    -- Deep copy the vanilla robot so we start from a valid definition.
    local repair_bot = table.deepcopy(base)

    ------------------------------------------------------------------
    -- Basic identity / visibility
    ------------------------------------------------------------------
    repair_bot.name = "mekatrol-repair-bot"
    repair_bot.localised_name = {"entity-name.mekatrol-repair-bot"} -- optional, add locale if you like

    -- Hide it from normal player interaction:
    -- - not-on-map: no minimap dot
    -- - not-blueprintable: cannot be included in blueprints
    -- - not-deconstructable: can’t be marked for deconstruction
    repair_bot.flags = {"placeable-player", "not-on-map", "not-blueprintable", "not-deconstructable"}

    -- Make sure it doesn’t do real logistic/construction work on its own.
    repair_bot.max_payload_size = 0

    -- You can tweak speed if you want; this is the vanilla value:
    -- (Your script is teleporting it, so this mostly affects how it looks
    -- if the game ever tries to move it naturally.)
    repair_bot.speed = base.speed

    -- override max health
    repair_bot.max_health = 500

    ------------------------------------------------------------------
    -- GRAPHICS: always look like a working construction robot
    --
    -- We override the idle / in_motion sprites to reuse the vanilla
    -- "working" and "shadow_working" animations so the bot is always
    -- shown as repairing.
    ------------------------------------------------------------------
    repair_bot.idle = base.working
    repair_bot.in_motion = base.working
    repair_bot.shadow_idle = base.shadow_working
    repair_bot.shadow_in_motion = base.shadow_working

    ------------------------------------------------------------------
    -- Register the new prototype
    ------------------------------------------------------------------
    data:extend({repair_bot})
end
