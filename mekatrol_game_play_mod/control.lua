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

local OVERLAY_UPDATE_TICKS = 10 -- ~1/6 second

local BOT_NAMES = {"mapper", "repairer", "constructor", "cleaner"}

----------------------------------------------------------------------
-- Visuals and behavior dispatch
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, bot_name, bot, tick, draw_visuals)
    if not (bot and bot.valid) then
        return
    end

    -- Clear transient visual each update; they are redrawn below (mapper only).
    if draw_visuals then
        visual.clear_lines(ps, bot_name)
        visual.draw_bot_highlight(player, ps)
    end

    local radius = nil
    local radius_color = nil

    -- default to targetting player
    local target_pos = player.position

    -- change to target position if defined
    if ps.task.target_position then
        target_pos = ps.task.target_position
    end

    local line_color = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.1
    }

    if ps.task.current_mode == "search" then
        radius = BOT.search.detection_radius
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif ps.task.current_mode == "survey" then
        radius = BOT.survey.radius
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color
    end

    if draw_visuals then
        if radius and radius > 0 then
            visual.draw_radius_circle(player, ps, bot_name, bot, radius, radius_color)
        else
            visual.clear_radius_circle(ps, bot_name)
        end

        if target_pos then
            visual.draw_lines(player, ps, bot_name, bot, target_pos, line_color)
        end
    end

    -- Mode behavior step
    if bot_name == "mapper" then
        if ps.task.current_mode == "follow" then
            follow.update(player, ps, bot)
        elseif ps.task.current_mode == "search" then
            search.update(player, ps, bot)
        elseif ps.task.current_mode == "survey" then
            survey.update(player, ps, bot, tick)
        elseif ps.task.current_mode == "move_to" then
            move_to.update(player, ps, bot)
        end
    end

    -- Throttle overlay updates
    local next_tick = ps.overlay_next_tick or 0

    if tick < next_tick then
        return
    end

    ps.overlay_next_tick = tick + OVERLAY_UPDATE_TICKS

    local bot_current_mode_name = ps.task.current_mode or "nil"
    local bot_next_mode_name = ps.task.next_mode or "nil"
    local bot_mode_name_line = string.format("bot mode %s→%s", bot_current_mode_name, bot_next_mode_name)

    local survey_entity = ps.survey_entity or {
        name = "nil",
        type = "nil"
    }
    local survey_entity_name_line = string.format("survey entity→%s [%s]", survey_entity.name, survey_entity.type)

    local lines = {"State:", bot_mode_name_line, survey_entity_name_line}
    if draw_visuals then
        visual.update_overlay(player, ps, lines)
        visual.draw_bot_light(player, ps, bot_name, bot)
    end
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
    local has_any = false
    if ps.bot_entities then
        for _, name in ipairs(BOT_NAMES) do
            local ent = ps.bot_entities[name]
            if ent and ent.valid then
                has_any = true
                break
            end
        end
    end

    if has_any then
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
    if not (ps.task.current_mode == "follow") then
        new_mode = "follow"
    end

    state.set_player_bot_task(p, ps, new_mode)
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
        local match = false
        if ps.bot_entities then
            for _, name in ipairs(BOT_NAMES) do
                if ps.bot_entities[name] == ent then
                    match = true
                    break
                end
            end
        end

        if match then
            local pl = game.get_player(idx)
            if pl and pl.valid then
                state.destroy_player_bot(pl, true)
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
        state.destroy_player_bot(p, true)
    else
        -- Player entity is gone; best-effort cleanup of any remaining bots.
        if ps.bot_entities then
            for _, name in ipairs(BOT_NAMES) do
                local ent = ps.bot_entities[name]
                if ent and ent.valid then
                    ent.destroy()
                end
            end
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

    visual.draw_player_light(player, ps)

    if ps.bot_enabled and ps.bot_entities then
        -- Drive all bots; visuals are independent per bot (role).
        for _, name in ipairs(BOT_NAMES) do
            local bot = (ps.bot_entities and ps.bot_entities[name]) or nil
            local draw_visuals = true
            update_bot_for_player(player, ps, name, bot, event.tick, draw_visuals)
        end
    end
end)
