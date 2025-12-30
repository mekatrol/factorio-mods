local common_bot = require("common_bot")
local config = require("config")
local entity_group = require("entity_group")
local follow = require("follow")
local inventory = require("inventory")
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
        entity_group = entity_group,
        visual = visual,
        inventory = inventory
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

local function full_bot_name(bot_name)

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

    return bot_name
end

local function set_bot_state(player, bot_name, new_task, args)
    local ps = state.get_player_state(player.index)

    if not ps.bot_enabled then
        util.print(player, "red", "bot not enabled")
        return
    end

    common_bot.issue_task(player, ps, bot_name, new_task, nil, args)
end

local function command(cmd)
    local player = game.get_player(cmd.player_index)
    if not (player and player.valid) then
        return
    end

    local p = cmd.parameter or ""

    -- Allow: "<bot> <task> [args...]"
    local bot_name, task, args = string.match(p, "^(%S+)%s+(%S+)%s*(.*)$")

    if not bot_name then
        util.print(player, "yellow", "Usage: /b <c|l|m|r> <task> [args]")
        return
    end

    -- Normalize short task names, if you use them
    bot_name = full_bot_name(bot_name)

    local kv_args = {}
    if args then
        kv_args = util.parse_kv_list(args)
    end

    -- Default behavior: /b <name> <task> <args>
    set_bot_state(player, bot_name, task, kv_args)
end

local function register_commands()
    -- a generic command: /bot <name> <task>
    if not commands.commands["bot"] then
        commands.add_command("bot", "Usage: /bot <constructor|logistics|mapper|repairer> <task>", command)
    end

    -- a generic command: /b <name> <task>
    if not commands.commands["b"] then
        commands.add_command("b", "Usage: /b <c|l|m|r> <task>", command)
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

script.on_load(function(_)
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

local function get_tasks(player, ps, bot_name)
    local current_task, next_task, other = common_bot.get_tasks(player, ps, state, visual, bot_name)
    local line = string.format("%s: %s→%s%s", bot_name, current_task or "nil", next_task or "nil", other or "")
    return line
end

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

    local overlay_lines = {"[game play mod]:", string.format("game phase: %s", ps.game_phase or "none")}

    if ps.bot_enabled and ps.bots then
        local bot = ps.bots["mapper"]
        overlay_lines[#overlay_lines + 1] = string.format("q: %s, f: %s", #bot.task.queued_survey_entities,
            #bot.task.future_survey_entities)

        local tick = event.tick
        constructor_bot.update(player, ps, state, visual, tick)
        logistics_bot.update(player, ps, state, visual, tick)
        mapper_bot.update(player, ps, state, visual, tick)
        repairer_bot.update(player, ps, state, visual, tick)

        overlay_lines[#overlay_lines + 1] = get_tasks(player, ps, "constructor")
        overlay_lines[#overlay_lines + 1] = get_tasks(player, ps, "logistics")
        overlay_lines[#overlay_lines + 1] = get_tasks(player, ps, "mapper")
        overlay_lines[#overlay_lines + 1] = get_tasks(player, ps, "repairer")
    else
        overlay_lines[#overlay_lines + 1] = "bot is currently disabled"
    end

    local lines = inventory.get_list(player)

    for _, line in ipairs(lines) do
        overlay_lines[#overlay_lines + 1] = line
    end

    -------------------------------------------------------------------------------
    -- Render overlay
    -------------------------------------------------------------------------------

    visual.update_overlay(player, ps, overlay_lines)
end)
