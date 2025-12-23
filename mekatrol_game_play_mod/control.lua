----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Goals of this version:
-- 1) Keep gameplay smooth by avoiding long single-tick work.
-- 2) Compute the concave hull incrementally over many ticks (state machine job),
--    instead of calling polygon.concave_hull(...) synchronously.
-- 3) Remove redundant hull calculations:
--    - Do NOT compute both the synchronous hull and the incremental hull.
--    - Do NOT recompute mapped points/hash every tick while a job is running.
--
-- Source base: your pasted control.lua. :contentReference[oaicite:0]{index=0}
----------------------------------------------------------------------
local config = require("configuration")
local follow = require("follow")
local move_to = require("move_to")
local polygon = require("polygon")
local search = require("search")
local state = require("state")
local survey = require("survey")
local util = require("util")
local visual = require("visual")

-- Config aliases.
local BOT = config.bot
local MODES = config.modes
local HULL_ALGORITHMS = config.hull_algorithms

local OVERLAY_UPDATE_TICKS = 10 -- ~1/6 second

----------------------------------------------------------------------
-- Visuals and behavior dispatch
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, tick)
    local bot = ps.bot_entity
    if not (bot and bot.valid) then
        return
    end

    -- Clear transient visual each update; they are redrawn below.
    visual.clear_lines(ps)
    visual.draw_bot_highlight(player, ps)

    local radius = nil
    local radius_color = nil

    -- default to targetting player
    local target_pos = player.position

    -- change to target position if defined
    if ps.target.position then
        target_pos = ps.target.position
    end

    local line_color = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.1
    }

    if ps.bot_mode == "search" then
        radius = BOT.search.detection_radius
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif ps.bot_mode == "survey" then
        radius = BOT.survey.radius
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color
    end

    if radius and radius > 0 then
        visual.draw_radius_circle(player, ps, bot, radius, radius_color)
    else
        visual.clear_radius_circle(ps)
    end

    if target_pos then
        visual.draw_lines(player, ps, bot, target_pos, line_color)
    end

    -- Mode behavior step.
    if ps.bot_mode == "follow" then
        follow.update(player, ps, bot)
    elseif ps.bot_mode == "search" then
        search.update(player, ps, bot)
    elseif ps.bot_mode == "survey" then
        survey.update(player, ps, bot, tick)
    elseif ps.bot_mode == "move_to" then
        move_to.update(player, ps, bot)
    end

    if ps.survey_render_points then
        visual.draw_survey_frontier(player, ps, bot)
        visual.draw_survey_done(player, ps, bot)
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    ps.overlay_next_tick = tick + OVERLAY_UPDATE_TICKS

    local bot_mode_name = ps.bot_mode or "nil"
    local bot_mode_name_line = string.format("bot mode→%s", bot_mode_name)

        local survey_entity = ps.survey_entity or {
        name = "nil",
        type = "nil"
    }
    local survey_entity_name_line = string.format("survey entity→%s [%s]", survey_entity.name, survey_entity.type)

    local hull_algorithm_name = ps.hull_algorithm
    local hull_algorithm_name_line = string.format("hull algorithm→%s", hull_algorithm_name)

    local lines = {"State:", bot_mode_name_line, survey_entity_name_line, hull_algorithm_name_line}
    visual.update_overlay(player, ps, lines)

    visual.draw_bot_light(player, ps, bot)
end

----------------------------------------------------------------------
-- Hotkey handlers
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = state.get_player_state(p.index)
    if ps.bot_entity and ps.bot_entity.valid then
        state.destroy_player_bot(p, false)
    else
        state.create_player_bot(p)
    end
end

local function on_cycle_bot_mode(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = state.get_player_state(p.index)

    -- default to search
    local new_mode = "search"

    -- if not in follow mode then set to follow mode
    if not (ps.bot_mode == "follow") then
        new_mode = "follow"
    end

    state.set_player_bot_mode(p, ps, new_mode)
end

local function on_toggle_render_survey_mode(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = state.get_player_state(p.index)
    ps.survey_render_mapped = not ps.survey_render_mapped
    ps.survey_render_points = ps.survey_render_mapped -- just follows mapped state

    if not ps.survey_render_mapped then
        visual.clear_survey_frontier(ps)
        visual.clear_survey_done(ps)
        visual.clear_mapped_entities(ps)
    end

    util.print(p, "green", "survey render: %s", ps.survey_render_mapped)
end

local function on_cycle_hull_algorithm(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = state.get_player_state(p.index)
    local cur = ps.hull_algorithm or "concave"
    local idx = HULL_ALGORITHMS.index[cur] or 1

    idx = idx + 1
    if idx > #HULL_ALGORITHMS.list then
        idx = 1
    end

    ps.hull_algorithm = HULL_ALGORITHMS.list[idx]
end

----------------------------------------------------------------------
-- Event: Entity died
----------------------------------------------------------------------

local function on_entity_died(event)
    local ent = event.entity
    if not ent or ent.name ~= "mekatrol-game-play-bot" then
        return
    end

    for idx, ps in pairs(storage.game_bot or {}) do
        if ps.bot_entity == ent then
            local pl = game.get_player(idx)
            if pl and pl.valid then
                destroy_player_bot(pl, true)
                util.print(pl, "yellow", "destroyed")
            else
                -- Player not valid; still clear state.
                visual.clear_all(ps)
                storage.game_bot[idx] = nil
            end
            return
        end
    end
end

----------------------------------------------------------------------
-- Event: Player removed
----------------------------------------------------------------------

local function on_player_removed(event)
    state.ensure_storage_tables()

    local all = storage.game_bot
    local idx = event.player_index
    local ps = all[idx]
    if not ps then
        return
    end

    local p = game.get_player(idx)
    if p and p.valid then
        destroy_player_bot(p, true)
    else
        if ps.bot_entity and ps.bot_entity.valid then
            ps.bot_entity.destroy()
        end
    end

    all[idx] = nil
end

----------------------------------------------------------------------
-- Init and config
----------------------------------------------------------------------

script.on_init(function()
    state.ensure_storage_tables()
end)

script.on_configuration_changed(function(_)
    state.ensure_storage_tables()
end)

----------------------------------------------------------------------
-- Event registration
----------------------------------------------------------------------

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_bot_mode)
script.on_event("mekatrol-game-play-bot-render-survey-mode", on_toggle_render_survey_mode)
script.on_event("mekatrol-game-play-bot-render-hull-algorithm", on_cycle_hull_algorithm)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

----------------------------------------------------------------------
-- Tick handler
----------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % BOT.update_interval ~= 0 then
        return
    end

    -- Note: This mod currently drives only player 1 (as in your original).
    -- If you want multiplayer support, iterate game.connected_players instead.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local ps = state.get_player_state(player.index)
    if not ps then
        return
    end

    if ps.bot_enabled and ps.bot_entity and ps.bot_entity.valid then
        update_bot_for_player(player, ps, event.tick)
    end
end)
