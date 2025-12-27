local common_bot = require("common_bot")
local config = require("config")
local entity_group = require("entity_group")
local follow = require("follow")
local module = require("module")
local move_to = require("move_to")
local polygon = require("polygon")
local search = require("search")
local state = require("state")
local survey = require("survey")
local util = require("util")
local visual = require("visual")

local constructor_bot = require("constructor_bot")
local logistics_bot = require("logistics_bot")
local mapper_bot = require("mapper_bot")
local repairer_bot = require("repairer_bot")

-- Config aliases.
local BOT_CONF = config.bot
local BOT_NAMES = config.bot_names

local OVERLAY_UPDATE_TICKS = 10 -- ~1/6 second

local function init_modules()
    module.init_module({
        logistics_bot = logistics_bot,
        constructor_bot = constructor_bot,
        mapper_bot = mapper_bot,
        repairer_bot = repairer_bot,
        entity_group = entity_group
    })
end

----------------------------------------------------------------------
-- Hotkey handlers
----------------------------------------------------------------------

local function on_toggle_bot(event)
    -- make sure modules for DI are loaded
    init_modules()

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
        state.destroy_player_bot(p, visual, entity_group.clear_entity_groups)
    else
        state.create_player_bot(p, visual, entity_group.clear_entity_groups)
    end
end

local function set_bot_state(player, bot_name, new_task)
    local ps = state.get_player_state(player.index)

    -- convert short hand bot name to long bot name
    if bot_name == "a" then
        bot_name = "all"
    elseif bot_name == "c" then
        bot_name = "constructor"
    elseif bot_name == "l" then
        bot_name = "logistics"
    elseif bot_name == "m" then
        bot_name = "mapper"
    elseif bot_name == "r" then
        bot_name = "repairer"
    end

    if not ps.bot_enabled then
        util.print(player, "red", "bot not enabled")
        return
    end

    common_bot.issue_task(player, ps, bot_name, new_task)
end

local function register_commands()
    -- a generic command: /bot <name> <task>
    if not commands.commands["bot"] then
        commands.add_command("bot", "Usage: /bot <constructor|logistics|mapper|repairer> <task>", function(cmd)
            local player = game.get_player(cmd.player_index)
            if not (player and player.valid) then
                return
            end

            local p = cmd.parameter or ""
            local bot_name, task = string.match(p, "^(%S+)%s+(%S+)$")
            if not bot_name then
                util.print(player, "yellow", "Usage: /bot <name> <task>")
                return
            end

            set_bot_state(player, bot_name, task)
        end)
    end
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
            local player = game.get_player(idx)
            if player and player.valid then
                state.destroy_player_bot(player, visual, entity_group.clear_entity_groups)
                util.print(player, "yellow", "destroyed")
            else
                -- Player not valid; still clear state.
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
        state.destroy_player_bot(p, visual, entity_group.clear_entity_groups)
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
    init_modules()
    register_commands()
end)

script.on_configuration_changed(function(_)
    state.ensure_storage_tables()
    init_modules()
    register_commands()
end)

----------------------------------------------------------------------
-- Event registration
----------------------------------------------------------------------

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)

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
        constructor_bot.update(player, ps, state, visual, tick)
        logistics_bot.update(player, ps, state, visual, tick)
        mapper_bot.update(player, ps, state, visual, tick)
        repairer_bot.update(player, ps, state, visual, tick)

        local constructor_current_task, constructor_next_task =
            common_bot.get_tasks(player, ps, state, visual, "constructor")
        local constructor_current_task_line = string.format("constructor: %s→%s", constructor_current_task or "nil",
            constructor_next_task or "nil")
        overlay_lines[#overlay_lines + 1] = constructor_current_task_line

        local logistics_current_task, logistics_next_task = common_bot.get_tasks(player, ps, state, visual, "logistics")
        local logistics_current_task_line = string.format("logistics: %s→%s", logistics_current_task or "nil",
            logistics_next_task or "nil")
        overlay_lines[#overlay_lines + 1] = logistics_current_task_line

        local mapper_current_task, mapper_next_task = common_bot.get_tasks(player, ps, state, visual, "mapper")
        local mapper_current_task_line = string.format("mapper: %s→%s", mapper_current_task or "nil",
            mapper_next_task or "nil")
        overlay_lines[#overlay_lines + 1] = mapper_current_task_line

        local repairer_current_task, repairer_next_task = common_bot.get_tasks(player, ps, state, visual, "repairer")
        local repairer_current_task_line = string.format("repairer: %s→%s", repairer_current_task or "nil",
            repairer_next_task or "nil")
        overlay_lines[#overlay_lines + 1] = repairer_current_task_line
    else
        overlay_lines[#overlay_lines + 1] = "bot is currently disabled"
    end

    -------------------------------------------------------------------------------
    -- Render overlay
    -------------------------------------------------------------------------------

    visual.update_overlay(player, ps, overlay_lines)
end)
