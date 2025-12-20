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
local mapping = require("mapping")
local polygon = require("polygon")
local state = require("state")
local utils = require("utils")
local visuals = require("visuals")

-- Config aliases.
local BOT = config.bot
local MODES = config.modes

----------------------------------------------------------------------
-- Follow mode
----------------------------------------------------------------------

local function follow_player(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local ppos = player.position
    local bpos = bot.position

    local prev = ps.last_player_position
    local left, right = false, false

    if prev then
        local dx = ppos.x - prev.x
        if dx < -0.1 then
            left = true
        elseif dx > 0.1 then
            right = true
        end
    end

    ps.last_player_position = {
        x = ppos.x,
        y = ppos.y
    }

    local side = BOT.movement.side_offset_distance
    local so = ps.last_player_side_offset_x or -side

    if left and so ~= side then
        so = side
    elseif right and so ~= -side then
        so = -side
    end

    ps.last_player_side_offset_x = so

    local follow = BOT.movement.follow_distance
    local dx = ppos.x - bpos.x
    local dy = ppos.y - bpos.y

    if dx * dx + dy * dy <= follow * follow then
        return
    end

    local target = {
        x = ppos.x + so,
        y = ppos.y - 2
    }

    mapping.move_bot_towards(player, bot, target)
end

----------------------------------------------------------------------
-- Wander mode
----------------------------------------------------------------------

local function pick_new_wander_target(bpos)
    local angle = math.random() * 2 * math.pi
    local step = BOT.wander.step_distance
    local min_d = step * 0.4
    local max_d = step
    local dist = min_d + (max_d - min_d) * math.random()

    return {
        x = bpos.x + math.cos(angle) * dist,
        y = bpos.y + math.sin(angle) * dist
    }
end

local function wander_bot(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target = ps.bot_target_position

    if not target then
        target = pick_new_wander_target(bot.position)
        ps.bot_target_position = target
    end

    mapping.move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local step = BOT.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.bot_target_position = nil

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.wander.detection_radius
    }

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char then
            state.set_player_bot_mode(player, ps, "survey")
            return
        end
    end
end

----------------------------------------------------------------------
-- Survey mode
----------------------------------------------------------------------

local function perform_survey_scan(player, ps, bot, tick)
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
            mapping.add_frontier_on_radius_edge(player, ps, bot, bpos, e.position, BOT.survey.radius)

            if mapping.upsert_mapped_entity(player, ps, e, tick) then
                discovered_any = true
            end
        end
    end

    local start_a = mapping.ring_seed_for_center(bpos)
    mapping.add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 12, start_a, 0)

    if not discovered_any then
        mapping.add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 12, start_a + math.pi / 12, 1.0)
    end

    return discovered_any
end

local function survey_bot(player, ps, bot, tick)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local target = ps.bot_target_position or mapping.get_nearest_frontier(ps, bot.position)

    if not target then
        state.set_player_bot_mode(player, ps, "follow")
        return
    end

    ps.bot_target_position = target
    mapping.move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local d2 = dx * dx + dy * dy

    local thr = BOT.survey.arrival_threshold
    if d2 > (thr * thr) then
        return
    end

    ps.bot_target_position = nil

    local discovered = perform_survey_scan(player, ps, bot, tick)
    if discovered then
        mapping.add_frontier_on_radius_edge(player, ps, bot, bpos, target, BOT.survey.radius)
    end
end

----------------------------------------------------------------------
-- Visuals and behavior dispatch
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, tick)
    local bot = ps.bot_entity
    if not (bot and bot.valid) then
        return
    end

    -- Clear transient visuals each update; they are redrawn below.
    visuals.clear_lines(ps)
    visuals.draw_bot_highlight(player, ps)

    local radius = nil
    local radius_color = nil

    local target = ps.bot_target_position or player.position

    local line_color = {
        r = 0.3,
        g = 0.3,
        b = 0.3,
        a = 0.1
    }

    if ps.bot_mode == "wander" then
        radius = BOT.wander.detection_radius
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
        visuals.draw_radius_circle(player, ps, bot, radius, radius_color)
    else
        visuals.clear_radius_circle(ps)
    end

    if target then
        visuals.draw_lines(player, ps, bot, target, line_color)
    end

    -- Mode behavior step.
    if ps.bot_mode == "follow" then
        follow_player(player, ps, bot)
    elseif ps.bot_mode == "wander" then
        wander_bot(player, ps, bot)
    elseif ps.bot_mode == "survey" then
        survey_bot(player, ps, bot, tick)
    end

    ------------------------------------------------------------------
    -- Hull processing (non-blocking)
    --
    -- 1) Every update_hull_interval ticks, compute the fingerprint of the mapped
    --    points and decide whether we need to start/restart the hull job.
    -- 2) Every tick, advance the current job by a limited step budget.
    --
    -- IMPORTANT: We intentionally do NOT compute mapped points/hash every tick.
    -- That avoids redundant hull-related work and keeps the script fast.
    ------------------------------------------------------------------
    mapping.evaluate_hull_need(ps, tick)
    mapping.step_hull_job(ps, tick)

    -- Draw the most recently completed hull (if any).
    local hull = ps.hull
    if hull and #hull >= 2 then
        for i = 1, #hull do
            local a = hull[i]
            local b = hull[i % #hull + 1]

            visuals.draw_line(player, ps, a, b, {
                r = 1,
                g = 0,
                b = 0,
                a = 0.8
            })
        end
    end

    if ps.survey_render_points then
        visuals.draw_survey_frontier(player, ps, bot)
        visuals.draw_survey_done(player, ps, bot)
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
    local cur = ps.bot_mode or "follow"
    local idx = MODES.index[cur] or 1

    idx = idx + 1
    if idx > #MODES.list then
        idx = 1
    end

    state.set_player_bot_mode(p, ps, MODES.list[idx])
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
        visuals.clear_survey_frontier(ps)
        visuals.clear_survey_done(ps)
        visuals.clear_mapped_entities(ps)
    end

    utils.print_bot_message(p, "green", "survey render: %s", ps.survey_render_mapped)
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
                utils.print_bot_message(pl, "yellow", "destroyed")
            else
                -- Player not valid; still clear state.
                visuals.clear_all(ps)
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
