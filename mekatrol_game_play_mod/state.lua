-- state.lua
--
-- Responsibilities:
--   - Own persistent per-player bot state in `storage.game_bot[player_index]`
--   - Provide helpers to create/destroy bot and change bot mode
--
-- Important: Avoid circular requires.
--   Do NOT `require("mapping")` at top-level if mapping.lua requires state.lua.
--   Instead, require mapping lazily inside the function that needs it.
local state = {}

local config = require("configuration")
local mapping = require("mapping")
local util = require("util")
local visual = require("visual")

local BOT = config.bot
local MODES = config.modes

----------------------------------------------------------------------
-- Storage and player state
----------------------------------------------------------------------

function state.ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

local function ensure_visuals_table(ps)
    ps.visual = ps.visual or {}
    ps.visual.bot_highlight = ps.visual.bot_highlight or nil
    ps.visual.lines = ps.visual.lines or nil
    ps.visual.radius_circle = ps.visual.radius_circle or nil
    ps.visual.mapped_entities = ps.visual.mapped_entities or {}
    ps.visual.survey_frontier = ps.visual.survey_frontier or {}
    ps.visual.survey_done = ps.visual.survey_done or {}
end

function state.get_player_state(player_index)
    state.ensure_storage_tables()

    local ps = storage.game_bot[player_index]
    if not ps then
        ps = {
            bot_entity = nil,
            bot_enabled = false,

            bot_mode = "follow",
            last_player_position = nil,
            last_player_side_offset_x = -BOT.movement.side_offset_distance,

            bot_target_position = nil,

            -- Render toggles (defaults ON)
            survey_render_mapped = true,
            survey_render_points = true,

            -- Survey data
            survey_mapped_entities = {},
            survey_mapped_positions = {},
            survey_frontier = {},
            survey_done = {},
            survey_seen = {},

            -- Hull data
            hull = nil,
            hull_job = nil,
            hull_quantized_count = 0,
            hull_quantized_hash = 0,
            hull_tick = 0,
            hull_last_eval_tick = 0,
            hull_point_set = {}, -- set: "x,y" => true

            visual = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                mapped_entities = {},
                survey_frontier = {},
                survey_done = {}
            }
        }

        storage.game_bot[player_index] = ps
        return ps
    end

    -- Defensive initialization for upgrades / older saves.
    -- IMPORTANT: use `== nil` for booleans so default "true" is preserved.
    if ps.survey_render_mapped == nil then
        ps.survey_render_mapped = true
    end
    if ps.survey_render_points == nil then
        ps.survey_render_points = true
    end

    ps.survey_mapped_entities = ps.survey_mapped_entities or {}
    ps.survey_mapped_positions = ps.survey_mapped_positions or {}
    ps.survey_frontier = ps.survey_frontier or {}
    ps.survey_done = ps.survey_done or {}
    ps.survey_seen = ps.survey_seen or {}

    ps.hull = ps.hull or nil
    ps.hull_job = ps.hull_job or nil
    ps.hull_quantized_count = ps.hull_quantized_count or 0
    ps.hull_quantized_hash = ps.hull_quantized_hash or 0
    ps.hull_tick = ps.hull_tick or 0
    ps.hull_last_eval_tick = ps.hull_last_eval_tick or 0
    ps.hull_point_set = ps.hull_point_set or {}

    ensure_visuals_table(ps)

    return ps
end

----------------------------------------------------------------------
-- Mode setting
----------------------------------------------------------------------

function state.set_player_bot_mode(player, ps, new_mode)
    -- Validate mode name.
    if not MODES.index[new_mode] then
        new_mode = "follow"
    end

    if ps.bot_mode == new_mode then
        return
    end

    ps.bot_mode = new_mode
    util.print_bot_message(player, "green", "mode set to %s", new_mode)

    -- Follow mode: no fixed target.
    if new_mode == "follow" then
        ps.bot_target_position = nil
        return
    end

    -- Survey mode: create a new frontier ring around the bot.
    if new_mode == "survey" then
        mapping.ensure_survey_sets(ps)

        -- Start a fresh frontier queue for this pass.
        ps.survey_frontier = {}
        ps.survey_seen = {}

        local bot = ps.bot_entity
        if bot and bot.valid then
            local bpos = bot.position
            local start_a = mapping.ring_seed_for_center(bpos)
            mapping.add_ring_frontiers(player, ps, bot, bpos, BOT.survey.radius, 24, start_a, 0)
        end
    end
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

function state.destroy_player_bot(player, silent)
    local ps = state.get_player_state(player.index)

    -- Destroy the bot entity (if present).
    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_entity.destroy()
    end

    -- Clear ALL render objects / visual.
    visual.clear_all(ps)

    -- Disable + clear entity reference.
    ps.bot_entity = nil
    ps.bot_enabled = false

    -- Return to follow mode.
    ps.bot_mode = "follow"
    ps.bot_target_position = nil

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT.movement.side_offset_distance

    -- Clear ALL survey / mapping sets.
    ps.survey_mapped_entities = {}
    ps.survey_mapped_positions = {}
    ps.survey_frontier = {}
    ps.survey_done = {}
    ps.survey_seen = {}

    -- Clear ALL hull state.
    ps.hull = nil
    ps.hull_job = nil
    ps.hull_point_set = {}
    ps.hull_quantized_count = 0
    ps.hull_quantized_hash = 0
    ps.hull_tick = 0
    ps.hull_last_eval_tick = 0

    -- Keep render toggles as defaults ON (or change if you prefer persisting user preference).
    ps.survey_render_mapped = true
    ps.survey_render_points = true

    -- Reset bookkeeping for render IDs.
    ps.visual = {
        bot_highlight = nil,
        lines = nil,
        radius_circle = nil,
        mapped_entities = {},
        survey_frontier = {},
        survey_done = {}
    }

    if not silent then
        util.print_bot_message(player, "yellow", "deactivated")
    end
end

function state.create_player_bot(player)
    local ps = state.get_player_state(player.index)

    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_enabled = true
        return ps.bot_entity
    end

    local pos = player.position
    local ent = player.surface.create_entity {
        name = "mekatrol-game-play-bot",
        position = {pos.x - 2, pos.y - 2},
        force = player.force,
        raise_built = true
    }

    if not ent then
        util.print_bot_message(player, "red", "create failed")
        return nil
    end

    ps.bot_entity = ent
    ps.bot_enabled = true
    ent.destructible = true

    util.print_bot_message(player, "green", "created")
    return ent
end

return state
