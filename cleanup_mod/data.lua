-- --------------------------------------------------------------------
-- data.lua
--
-- Declares:
--   - A custom input to toggle the cleanup bot.
--   - A prototype "mekatrol-cleanup-bot" cloned from the vanilla
--     logistic robot, with logistics disabled (script-driven only).
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
-- Cloned from the base logistic robot:
--   - Unique name so control.lua can spawn it.
--   - Flags adjusted so it does not participate in normal logistics.
--   - Energy costs set to zero; movement is handled by script.
--   - Logistic/construction radii set to zero so it does no vanilla work.
-- --------------------------------------------------------------------

-- Get the base logistic robot prototype
local base = data.raw["logistic-robot"]["logistic-robot"]
if not base then
    error("Base logistic-robot prototype not found")
end

-- Deep copy to start from a valid robot definition
local cleanup_bot = table.deepcopy(base)

-- --------------------------------------------------------------------
-- Identity / visibility
-- --------------------------------------------------------------------

cleanup_bot.name = "mekatrol-cleanup-bot"
cleanup_bot.localised_name = {"entity-name.mekatrol-cleanup-bot"} -- optional locale key

-- Flags:
--   placeable-player: let script place it.
--   not-on-map: hide from minimap.
--   not-blueprintable / not-deconstructable: avoid normal player tools.
cleanup_bot.flags = {"placeable-player", "not-on-map", "not-blueprintable", "not-deconstructable"}

-- --------------------------------------------------------------------
-- Behavior: disable normal logistic / construction work
-- --------------------------------------------------------------------

-- No logistic or construction radius so it won’t take jobs.
cleanup_bot.logistic_radius = 0
cleanup_bot.construction_radius = 0

-- No useful payload for vanilla logistics.
cleanup_bot.max_payload_size = 0

-- Script drives movement; make in-engine robot “free”.
cleanup_bot.energy_per_move = "0J"
cleanup_bot.energy_per_tick = "0J"

-- If the base has charging / energy source definitions, we keep them but,
-- with zero energy cost, they effectively never run out.

-- --------------------------------------------------------------------
-- Graphics
--
-- For logistic robots, there are typically:
--   - idle
--   - in_motion
--   - shadow_idle
--   - shadow_in_motion
--
-- You can either:
--   - keep the normal logistics look (do nothing), or
--   - force one of the animations as “always on”.
--
-- Below, we simply keep the base animations as-is, so it looks like a
-- normal logistic robot flying around.
-- --------------------------------------------------------------------
-- If you ever want to force an always-working look, uncomment this:
-- cleanup_bot.idle             = base.in_motion
-- cleanup_bot.shadow_idle      = base.shadow_in_motion

-- --------------------------------------------------------------------
-- Register the new prototype
-- --------------------------------------------------------------------

data:extend({cleanup_bot})
