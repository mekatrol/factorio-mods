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

local BOT_CONF = config.bot
local MODES = config.modes

local BOT_NAMES = {"mapper", "repairer", "constructor", "cleaner"}

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
            bot_entities = {},
            bot_enabled = false,

            last_player_position = nil,
            last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance,

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

    ps.bot_entities = ps.bot_entities or {}

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
    -- Validate mode
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

    if new_mode == "search" then
        ps.task.next_mode = "survey"
        return
    end

    if new_mode == "survey" then
        ps.task.next_mode = "search"
    end
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

function state.destroy_player_bot(player, silent)
    local ps = state.get_player_state(player.index)

    -- Destroy all bot entities (if present).
    if ps.bot_entities then
        for _, name in ipairs(BOT_NAMES) do
            local ent = ps.bot_entities[name]
            if ent and ent.valid then
                ent.destroy()
            end
            ps.bot_entities[name] = nil
        end
    end

    -- Clear ALL render objects / visual.
    visual.clear_all(ps)
    -- Disable + clear entity references.
    ps.bot_entities = {}
    ps.bot_enabled = false

    -- Init to follow mode
    state.set_player_bot_task(player, ps, "follow")

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance

    -- clear entity groups
    entitygroup.clear_entity_groups(ps)

    -- Clear survey entity
    ps.survey_entity = nil

    -- Reset bookkeeping for render IDs.
    ps.visual = {
        -- Per-bot render objects. Each role has its own set so visuals are independent.
        bots = {},
    
        -- Overlay text objects are per-player, not per-bot.
        overlay_texts = {},
    }

    if not silent then
        util.print(player, "yellow", "deactivated")
    end
end

function state.create_player_bot(player)
    local ps = state.get_player_state(player.index)

    -- If any bot already exists, just enable and keep references.
    if ps.bot_entities then
        for _, name in ipairs(BOT_NAMES) do
            local ent = ps.bot_entities[name]
            if ent and ent.valid then
                ps.bot_enabled = true
                return ps.bot_entities
            end
        end
    end

    ps.bot_entities = ps.bot_entities or {}

    local pos = player.position
    local offsets = {
        mapper = {x = -2, y = -2},
        repairer = {x = -2, y = 2},
        constructor = {x = 2, y = -2},
        cleaner = {x = 2, y = 2}
    }

    local created_any = false

    for _, name in ipairs(BOT_NAMES) do
        local off = offsets[name] or {x = -2, y = -2}
        local ent = player.surface.create_entity {
            name = "mekatrol-game-play-bot",
            position = {pos.x + off.x, pos.y + off.y},
            force = player.force,
            raise_built = true
        }

        if not ent then
            util.print(player, "red", "create failed (%s)", name)
        else
            -- Store by role name (the "name" the mod uses internally).
            ps.bot_entities[name] = ent
            ent.destructible = true

            -- Some entity types support backer_name; set it when available.
            if ent.backer_name ~= nil then
                ent.backer_name = name
            end

            created_any = true
        end
    end

    if not created_any then
        util.print(player, "red", "create failed")
        return nil
    end
    ps.bot_enabled = true

    -- clear entity groups
    entitygroup.clear_entity_groups(ps)

    util.print(player, "green", "created (mapper/repairer/constructor/cleaner)")
    return ps.bot_entities
end

return state