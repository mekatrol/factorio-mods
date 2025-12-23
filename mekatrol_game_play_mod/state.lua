-- state.lua
--
-- Responsibilities:
--   - Own persistent per-player bot state in `storage.game_bot[player_index]`
--   - Provide helpers to create/destroy bot and change bot mode
local state = {}

local config = require("configuration")
local entitygroup = require("entitygroup")
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
    ps.visual.overlay_texts = ps.visual.overlay_texts or {}
end

function state.get_player_state(player_index)
    state.ensure_storage_tables()

    local ps = storage.game_bot[player_index]
    if not ps then
        ps = {
            bot_entity = nil,
            bot_enabled = false,

            last_player_position = nil,
            last_player_side_offset_x = -BOT.movement.side_offset_distance,

            task = {
                target_position = nil,
                current_mode = "follow",
                next_mode = nil
            },

            search_spiral = nil,

            survey_entity = nil,

            overlay_next_tick = nil,

            visual = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                overlay_texts = {}
            }
        }

        storage.game_bot[player_index] = ps
        return ps
    end

    ps.task = ps.task or {}

    ps.task.current_mode = ps.task.current_mode or "follow"
    ps.task.next_mode = ps.task.next_mode or nil
    ps.task.target_position = ps.task.target_position or nil

    ps.search_spiral = ps.search_spiral or nil

    ps.survey_entity = ps.survey_entity or nil

    ps.overlay_next_tick = ps.overlay_next_tick or 0

    ensure_visuals_table(ps)

    return ps
end

----------------------------------------------------------------------
-- Mode setting
----------------------------------------------------------------------

function state.set_player_bot_task(player, ps, new_mode)
    -- Validate mode name.
    if not MODES.index[new_mode] then
        new_mode = "follow"
    end

    -- set the new current_mode
    ps.task.current_mode = new_mode

    -- Follow mode: no fixed target.
    if new_mode == "follow" then
        -- clear the next_mode and target position when switching modes
        ps.task.next_mode = nil
        ps.task.target_position = nil

        ps.search_spiral = nil
        ps.survey_entity = nil
        ps.next_survey_entities = {}
        return
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

    -- Init to follow mode
    state.set_player_bot_task(player, ps, "follow")

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT.movement.side_offset_distance

    -- clear entity groups
    entitygroup.clear_entity_groups(ps)

    -- Clear survey entity
    ps.survey_entity = nil

    -- Reset bookkeeping for render IDs.
    ps.visual = {
        bot_highlight = nil,
        lines = nil,
        radius_circle = nil
    }

    if not silent then
        util.print(player, "yellow", "deactivated")
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
        util.print(player, "red", "create failed")
        return nil
    end

    ps.bot_entity = ent
    ps.bot_enabled = true
    ent.destructible = true

    -- clear entity groups
    entitygroup.clear_entity_groups(ps)

    util.print(player, "green", "created")
    return ent
end

return state
