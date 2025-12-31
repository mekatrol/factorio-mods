-- state.lua
--
-- Responsibilities:
--   - Own persistent per-player bot state in `storage.mekatrol_game_play_bot[player_index]`
--   - Provide helpers to create/destroy bot and change bot task
local state = {}

local config = require("config")
local util = require("util")

local constructor_bot = require("constructor_bot")
local logistics_bot = require("logistics_bot")
local repairer_bot = require("repairer_bot")
local searcher_bot = require("searcher_bot")
local surveyor_bot = require("surveyor_bot")

local BOT_CONF = config.bot
local BOT_NAMES = config.bot_names

----------------------------------------------------------------------
-- Storage and player state
----------------------------------------------------------------------

function state.ensure_storage_tables()
    storage.mekatrol_game_play_bot = storage.mekatrol_game_play_bot or {}
end

function state.get_player_state(player_index)
    state.ensure_storage_tables()

    local ps = storage.mekatrol_game_play_bot[player_index]
    local player = game.get_player(player_index)

    if not ps then
        ps = {
            bots = nil,
            bot_enabled = false,

            last_player_position = nil,
            last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance,

            game_phase = "init",

            overlay_next_tick = nil,

            visual = {
                overlay_texts = {}
            }
        }

        storage.mekatrol_game_play_bot[player_index] = ps
        return ps
    end

    ps.game_phase = ps.game_phase or "init"

    ps.bots = ps.bots or {}

    constructor_bot.init_state(player, ps)
    logistics_bot.init_state(player, ps)
    repairer_bot.init_state(player, ps)
    searcher_bot.init_state(player, ps)
    surveyor_bot.init_state(player, ps)

    ps.overlay_next_tick = ps.overlay_next_tick or 0

    ps.visual = ps.visual or {}
    ps.visual.overlay_texts = ps.visual.overlay_texts or {}

    return ps
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

function state.destroy_player_bot(player, visual, clear_entity_groups)
    local ps = state.get_player_state(player.index)

    -- Destroy all bot entities (if present).
    if ps.bots then
        constructor_bot.destroy_state(player, ps, state)
        logistics_bot.destroy_state(player, ps, state)
        repairer_bot.destroy_state(player, ps, state)
        searcher_bot.destroy_state(player, ps, state)
        surveyor_bot.destroy_state(player, ps, state)
    end

    -- Clear ALL render objects / visual.
    visual.clear_entity_groups(ps)
    visual.clear_player_light(ps)
    visual.clear_overlay(ps)

    -- Disable + clear entity references.
    ps.bots = {}
    ps.bot_enabled = false

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance

    -- clear entity groups
    clear_entity_groups(ps)

    -- Reset bookkeeping for render IDs.
    ps.visual = {
        -- Per-bot render objects. Each role has its own set so visuals are independent.
        bots = {},

        -- Overlay text objects are per-player, not per-bot.
        overlay_texts = {}
    }

    util.print(player, "yellow", "deactivated")
end

function state.create_player_bot(player, visual, clear_entity_groups)
    local ps = state.get_player_state(player.index)

    -- If any bot already exists, just enable and keep references.
    if ps.bots then
        for _, name in ipairs(BOT_NAMES) do
            local bot = ps.bots[name]
            if bot and bot.entity and bot.entity.valid then
                ps.bot_enabled = true
                return ps.bots
            end
        end
    end

    ps.bots = ps.bots or {}

    local pos = player.position
    local offsets = {
        ["constructor"] = {
            x = -2,
            y = BOT_CONF.constructor.follow_offset_y
        },
        ["logistics"] = {
            x = -2,
            y = BOT_CONF.logistics.follow_offset_y
        },
        ["repairer"] = {
            x = -2,
            y = BOT_CONF.repairer.follow_offset_y
        },
        ["searcher"] = {
            x = -2,
            y = BOT_CONF.searcher.follow_offset_y
        },
        ["surveyor"] = {
            x = -2,
            y = BOT_CONF.surveyor.follow_offset_y
        }
    }

    local created_any = false

    for _, name in ipairs(BOT_NAMES) do
        local off = offsets[name] or {
            x = -2,
            y = -2
        }
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
            ps.bots[name].entity = ent
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
    clear_entity_groups(ps)

    util.print(player, "green", "created (constructor/logistics/repairer/searcher/surveyor)")
    return ps.bots
end

return state
