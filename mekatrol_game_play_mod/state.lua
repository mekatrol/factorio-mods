-- state.lua
--
-- Responsibilities:
--   - Own persistent per-player bot state in `storage.mekatrol_game_play_bot[player_index]`
--   - Provide helpers to create/destroy bot and change bot mode
local state = {}

local config = require("config")
local util = require("util")

local cleaner_bot = require("cleaner_bot")
local constructor_bot = require("constructor_bot")
local mapper_bot = require("mapper_bot")
local repairer_bot = require("repairer_bot")

local BOT_CONF = config.bot
local MODES = config.modes

local BOT_NAMES = {"mapper", "repairer", "constructor", "cleaner"}

----------------------------------------------------------------------
-- Storage and player state
----------------------------------------------------------------------

function state.ensure_storage_tables()
    storage.mekatrol_game_play_bot = storage.mekatrol_game_play_bot or {}
end

function state.ensure_bot_visual(ps, bot_name)
    ps.visual[bot_name] = ps.visual[bot_name] or {}

    ps.visual[bot_name].highlight = ps.visual[bot_name].highlight or nil
    ps.visual[bot_name].radius_circle = ps.visual[bot_name].radius_circle or nil
end

function state.ensure_visuals(ps)
    ps.visual = ps.visual or {}
    ps.visual.lines = ps.visual.lines or nil
    ps.visual.overlay_texts = ps.visual.overlay_texts or {}

    state.ensure_bot_visual(ps, "cleaner")
    state.ensure_bot_visual(ps, "constructor")
    state.ensure_bot_visual(ps, "mapper")
    state.ensure_bot_visual(ps, "repairer")
end

----------------------------------------------------------------------
-- Returns a valid bot entity by role name for the given player.
--
-- @param ps        Player state table (from get_player_state)
-- @param bot_name  string ("mapper", "repairer", "constructor", "cleaner")
-- @return LuaEntity|nil
----------------------------------------------------------------------
function state.get_bot_by_name(player, ps, bot_name)
    if not ps then
        return nil
    end

    local bots = ps.bots
    if not bots then
        return nil
    end

    local bot = bots[bot_name]

    if bot and bot.entity and bot.entity.valid then
        return bot
    end

    return nil
end

function state.get_player_state(player_index)
    state.ensure_storage_tables()

    local ps = storage.mekatrol_game_play_bot[player_index]
    local player = game.get_player(player_index)

    if not ps then
        ps = {
            bots = {
                ["mapper"] = mapper_bot.init_state(player, ps, state, visual),
                ["repairer"] = {
                    entity = nil,
                    task = {
                        target_position = nil,
                        current_mode = "follow",
                        next_mode = nil
                    }
                },
                ["constructor"] = {
                    entity = nil,
                    task = {
                        target_position = nil,
                        current_mode = "follow",
                        next_mode = nil
                    }
                },
                ["cleaner"] = {
                    entity = nil,
                    task = {
                        target_position = nil,
                        current_mode = "follow",
                        next_mode = nil
                    }
                }
            },

            bot_enabled = false,

            last_player_position = nil,
            last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance,

            overlay_next_tick = nil,

            visual = {
                ["mapper"] = {
                    bot_highlight = nil,
                    radius_circle = nil
                },
                ["repairer"] = {
                    bot_highlight = nil,
                    radius_circle = nil
                },
                ["constructor"] = {
                    bot_highlight = nil,
                    radius_circle = nil
                },
                ["cleaner"] = {
                    bot_highlight = nil,
                    radius_circle = nil
                },

                lines = nil,
                overlay_texts = {}
            }
        }

        storage.mekatrol_game_play_bot[player_index] = ps
        return ps
    end

    ps.bots = ps.bots or {}

    ps.task = ps.task or {}

    ps.task.current_mode = ps.task.current_mode or "follow"
    ps.task.next_mode = ps.task.next_mode or nil
    ps.task.target_position = ps.task.target_position or nil

    ps.search_spiral = ps.search_spiral or nil

    ps.survey_entity = ps.survey_entity or nil

    ps.overlay_next_tick = ps.overlay_next_tick or 0

    state.ensure_visuals(ps)

    return ps
end

----------------------------------------------------------------------
-- Mode setting
----------------------------------------------------------------------

function state.set_player_mapper_bot_task(player, ps, bot, new_mode)
    bot.search_spiral = nil
    bot.survey_entity = nil
    bot.next_survey_entities = {}
end

function state.set_player_bot_task(player, ps, bot_name, new_mode)
    -- Validate mode
    if not MODES.index[new_mode] then
        new_mode = "follow"
    end

    -- get bot
    local bot = state.get_bot_by_name(player, ps, bot_name)

    -- set the new current_mode
    bot.task.current_mode = new_mode

    -- Follow mode: no fixed target.
    if new_mode == "follow" then
        -- clear the next_mode and target position when switching modes
        bot.task.next_mode = nil
        bot.task.target_position = nil

        if bot_name == "mapper" then
            state.set_player_mapper_bot_task(player, ps, bot, new_mode)
        end
        return
    end

    if new_mode == "search" then
        bot.task.next_mode = "survey"
        return
    end

    if new_mode == "survey" then
        bot.task.next_mode = "search"
    end
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

function state.destroy_player_bot(player, visual, clear_entity_groups)
    local ps = state.get_player_state(player.index)

    -- Destroy all bot entities (if present).
    if ps.bots then
        for _, name in ipairs(BOT_NAMES) do
            local bot = ps.bots[name]
            if bot and bot.entity and bot.entity.valid then
                bot.entity.destroy()
            end
            ps.bots[name] = nil
        end
    end

    -- Clear ALL render objects / visual.
    visual.clear_all(ps)

    -- Disable + clear entity references.
    ps.bots = {}
    ps.bot_enabled = false

    -- Init to follow mode
    state.set_player_bot_task(player, ps, "follow")

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT_CONF.movement.side_offset_distance

    -- clear entity groups
    clear_entity_groups(ps)

    -- Clear survey entity
    ps.survey_entity = nil

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
        ["mapper"] = {
            x = -2,
            y = BOT_CONF.mapper.follow_offset_y
        },
        ["repairer"] = {
            x = -2,
            y = BOT_CONF.repairer.follow_offset_y
        },
        ["constructor"] = {
            x = -2,
            y = BOT_CONF.constructor.follow_offset_y
        },
        ["cleaner"] = {
            x = -2,
            y = BOT_CONF.cleaner.follow_offset_y
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

    util.print(player, "green", "created (mapper/repairer/constructor/cleaner)")
    return ps.bots
end

return state
