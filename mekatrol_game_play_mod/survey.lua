local survey = {}

local config = require("configuration")
local mapping = require("mapping")
local positioning = require("positioning")
local state = require("state")

local BOT = config.bot

----------------------------------------------------------------------
-- Survey mode
----------------------------------------------------------------------

function survey.perform_survey_scan(player, ps, bot, tick)
    local surf = bot.surface
    local bpos = bot.position
    local char = player.character

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.survey.radius
    }

    local discovered_any = false

    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and mapping.is_static_mappable(e) then
            mapping.add_frontier_on_radius_edge(player, state, ps, bot, bpos, e.position, BOT.survey.radius)

            if mapping.upsert_mapped_entity(player, state, ps, e, tick) then
                discovered_any = true
            end
        end
    end

    return discovered_any
end

function survey.update(player, ps, bot, tick)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local target = ps.bot_target_position or mapping.get_nearest_frontier(ps, bot.position)

    if not target then
        state.set_player_bot_mode(player, ps, "follow")
        return
    end

    ps.bot_target_position = target
    positioning.move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local d2 = dx * dx + dy * dy

    local thr = BOT.survey.arrival_threshold
    if d2 > (thr * thr) then
        return
    end

    ps.bot_target_position = nil

    local discovered = survey.perform_survey_scan(player, ps, bot, tick)
    if discovered then
        mapping.add_frontier_on_radius_edge(player, state, ps, bot, bpos, target, BOT.survey.radius)
    end
end

return survey
