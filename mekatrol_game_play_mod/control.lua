local common_bot = require("common_bot")
local config = require("config")
local entitygroup = require("entitygroup")
local follow = require("follow")
local move_to = require("move_to")
local polygon = require("polygon")
local search = require("search")
local state = require("state")
local survey = require("survey")
local util = require("util")
local visual = require("visual")

local cleaner_bot = require("cleaner_bot")
local constructor_bot = require("constructor_bot")
local mapper_bot = require("mapper_bot")
local repairer_bot = require("repairer_bot")

-- Config aliases.
local BOT_CONF = config.bot
local MODES = config.modes
local BOT_NAMES = config.bot_names

local OVERLAY_UPDATE_TICKS = 10 -- ~1/6 second

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
    if ps.bots then
        for _, name in ipairs(BOT_NAMES) do
            local bot = ps.bots[name]
            if bot and bot.entity and bot.entity.valid then
                has_any = true
                break
            end
        end
    end

    if has_any then
        state.destroy_player_bot(p, visual.clear_all, entitygroup.clear_entity_groups)
    else
        state.create_player_bot(p, entitygroup.clear_entity_groups)
    end
end

local function on_cycle_mapper_bot_mode(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then
        return
    end

    local ps = state.get_player_state(player.index)

    if not ps.bot_enabled then
        return
    end

    local bot = state.get_bot_by_name(player, ps, "mapper")

    -- default to search
    local new_mode = "search"

    -- if not in follow mode then set to follow mode
    if not (bot.task.current_mode == "follow") then
        new_mode = "follow"
    end

    state.set_player_bot_task(player, ps, "mapper", new_mode)
end

----------------------------------------------------------------------
-- Event: Entity died
----------------------------------------------------------------------

local function on_entity_died(event)
    local ent = event.entity
    if not ent or ent.name ~= "mekatrol-game-play-bot" then
        return
    end

    for idx, ps in pairs(storage.mekatrol_game_play_bot or {}) do
        local match = false
        if ps.bots then
            for _, name in ipairs(BOT_NAMES) do
                if ps.bots[name] == ent then
                    match = true
                    break
                end
            end
        end

        if match then
            local pl = game.get_player(idx)
            if pl and pl.valid then
                state.destroy_player_bot(pl, visual.clear_all, entitygroup.clear_entity_groups)
                util.print(pl, "yellow", "destroyed")
            else
                -- Player not valid; still clear state.
                visual.clear_all(ps)
                storage.mekatrol_game_play_bot[idx] = nil
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

    local all = storage.mekatrol_game_play_bot
    local idx = event.player_index
    local ps = all[idx]
    if not ps then
        return
    end

    local p = game.get_player(idx)
    if p and p.valid then
        state.destroy_player_bot(p, true, visual.clear_all, entitygroup.clear_entity_groups)
    else
        -- Player entity is gone; best-effort cleanup of any remaining bots.
        if ps.bots then
            for _, name in ipairs(BOT_NAMES) do
                local ent = ps.bots[name]
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
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_mapper_bot_mode)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

----------------------------------------------------------------------
-- Tick handler
----------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % BOT_CONF.update_interval ~= 0 then
        return
    end

    -- Note: This mod currently drives only player 1 (current single player)
    -- For multiplayer support, iterate game.connected_players instead.
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local ps = state.get_player_state(player.index)
    if not ps then
        return
    end

    visual.draw_player_light(player, ps)

    ps.overlay_next_tick = event.tick + OVERLAY_UPDATE_TICKS
    local overlay_lines = {"[game play mod]:"}

    if ps.bot_enabled and ps.bots then
        local tick = event.tick
        cleaner_bot.update(player, ps, tick)
        constructor_bot.update(player, ps, tick)
        mapper_bot.update(player, ps, tick)
        repairer_bot.update(player, ps, tick)

        local cleaner_current_mode, cleaner_next_mode = common_bot.get_modes(player, ps, "cleaner")
        local cleaner_current_mode_line = string.format("cleaner: %s→%s", cleaner_current_mode or "nil",
            cleaner_next_mode or "nil")
        overlay_lines[#overlay_lines + 1] = cleaner_current_mode_line

        local constructor_current_mode, constructor_next_mode = common_bot.get_modes(player, ps, "constructor")
        local constructor_current_mode_line = string.format("constructor: %s→%s", constructor_current_mode or "nil",
            constructor_next_mode or "nil")
        overlay_lines[#overlay_lines + 1] = constructor_current_mode_line

        local mapper_current_mode, mapper_next_mode = common_bot.get_modes(player, ps, "mapper")
        local mapper_current_mode_line = string.format("mapper: %s→%s", mapper_current_mode or "nil",
            mapper_next_mode or "nil")
        overlay_lines[#overlay_lines + 1] = mapper_current_mode_line

        local repairer_current_mode, repairer_next_mode = common_bot.get_modes(player, ps, "repairer")
        local repairer_current_mode_line = string.format("repairer: %s→%s", repairer_current_mode or "nil",
            repairer_next_mode or "nil")
        overlay_lines[#overlay_lines + 1] = repairer_current_mode_line
    else
        overlay_lines[#overlay_lines + 1] = "bot is currently disabled"
    end

    -------------------------------------------------------------------------------
    -- Render overlay
    -------------------------------------------------------------------------------

    visual.update_overlay(player, ps, overlay_lines)
end)
