local util = require("util")

----------------------------------------------------------------------
-- HOTKEY: toggle mapping bot
----------------------------------------------------------------------

data:extend({{
    type = "custom-input",
    name = "mekatrol-mapping-bot-toggle",
    key_sequence = "CONTROL + SHIFT + M",
    consuming = "none"
}})

----------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-mapping-bot AS A CONSTRUCTION ROBOT
--
-- We clone the base game's construction robot and modify it:
-- - New name ("mekatrol-mapping-bot") so we can spawn it by script.
-- - Hidden from normal gameplay (no blueprints, no deconstruction).
-- - Always uses the "working" animation so it looks like it's mapping.
----------------------------------------------------------------------

do
    -- Grab the vanilla construction robot prototype.
    local base = data.raw["construction-robot"]["construction-robot"]
    if not base then
        error("Base construction-robot prototype not found")
    end

    -- Deep copy the vanilla robot so we start from a valid definition.
    local mapping_bot = table.deepcopy(base)

    ------------------------------------------------------------------
    -- Basic identity / visibility
    ------------------------------------------------------------------
    mapping_bot.name = "mekatrol-mapping-bot"
    mapping_bot.localised_name = {"entity-name.mekatrol-mapping-bot"} -- optional, add locale if you like

    -- Hide it from normal player interaction:
    -- - not-on-map: no minimap dot
    -- - not-blueprintable: cannot be included in blueprints
    -- - not-deconstructable: can’t be marked for deconstruction
    mapping_bot.flags = {"placeable-player", "not-on-map", "not-blueprintable", "not-deconstructable"}

    -- Make sure it doesn’t do real logistic/construction work on its own.
    mapping_bot.max_payload_size = 0
    mapping_bot.construction_radius = 0
    mapping_bot.logistic_radius = 0
    mapping_bot.energy_per_move = "0J"
    mapping_bot.energy_per_tick = "0J"
    mapping_bot.speed = 0

    -- You can tweak speed if you want; this is the vanilla value:
    -- (Your script is teleporting it, so this mostly affects how it looks
    -- if the game ever tries to move it naturally.)
    mapping_bot.speed = base.speed

    ------------------------------------------------------------------
    -- GRAPHICS: always look like a working construction robot
    --
    -- We override the idle / in_motion sprites to reuse the vanilla
    -- "working" and "shadow_working" animations so the bot is always
    -- shown as mapping [Mapping bot] disabled.
    ------------------------------------------------------------------
    mapping_bot.idle = base.working
    mapping_bot.in_motion = base.working
    mapping_bot.shadow_idle = base.shadow_working
    mapping_bot.shadow_in_motion = base.shadow_working

    ------------------------------------------------------------------
    -- Register the new prototype
    ------------------------------------------------------------------
    data:extend({mapping_bot})
end
