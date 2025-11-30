----------------------------------------------------------------------
-- HOTKEYS
----------------------------------------------------------------------
data:extend({{
    type = "custom-input",
    name = "mekatrol-mapping-bot-toggle",
    key_sequence = "CONTROL + SHIFT + M",
    consuming = "none"
}, {
    type = "custom-input",
    name = "mekatrol-mapping-bot-clear",
    key_sequence = "CONTROL + SHIFT + N",
    consuming = "none"
}})

----------------------------------------------------------------------
-- ENTITY PROTOTYPE: mekatrol-mapping-bot AS A CONSTRUCTION ROBOT
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
    mapping_bot.localised_name = {"entity-name.mekatrol-mapping-bot"}

    -- Hide it from normal player interaction:
    -- - not-on-map: no minimap dot
    -- - not-blueprintable: cannot be included in blueprints
    -- - not-deconstructable: can’t be marked for deconstruction
    mapping_bot.flags = {"placeable-player", "not-on-map", "not-blueprintable", "not-deconstructable"}

    mapping_bot.speed = base.speed

    -- Make sure it doesn’t do real logistic/construction work on its own.
    mapping_bot.max_payload_size = 0
    mapping_bot.construction_radius = 0
    mapping_bot.logistic_radius = 0
    mapping_bot.energy_per_move = "0J"
    mapping_bot.energy_per_tick = "0J"

    ------------------------------------------------------------------
    -- GRAPHICS: always look like a working construction robot
    --
    -- We override the idle / in_motion sprites to reuse the vanilla
    -- "working" and "shadow_working" animations so the bot is always
    -- shown as repairing.
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
