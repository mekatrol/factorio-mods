local bot = require("bot")
local cleanup = require("cleanup_bot")
local config = require("config")
local constants = require("constants")
local registry = require("task_registry")
local state = require("state")

local function player_for(event_or_command)
    -- Commands issued by the server console have no player index. Returning nil
    -- lets every caller use the same safe validity guard.
    return event_or_command.player_index and game.get_player(event_or_command.player_index) or nil
end

local function command(command_data)
    local player = player_for(command_data)
    if not (player and player.valid) then return end
    -- Split once so task aliases remain free to grow without changing the
    -- command grammar. Missing input is handled below according to the alias.
    local action, argument = string.match(command_data.parameter or constants.EMPTY_TEXT, constants.COMMAND_PATTERN)
    -- The short command is the in-game mode switch. Keep the long command's
    -- empty form as a status query for diagnostics and backwards compatibility.
    if not action and command_data.name == constants.SHORT_COMMAND_NAME then
        bot.next_task(player)
        return
    end
    action = action or constants.ACTION.STATUS
    -- Every branch delegates to the bot API so command aliases and hotkeys share
    -- one implementation of lifecycle, validation, and resource behavior.
    if action == constants.ACTION.ON or action == constants.ACTION.START then bot.enable(player)
    elseif action == constants.ACTION.OFF or action == constants.ACTION.STOP then bot.disable(player)
    elseif action == constants.ACTION.TOGGLE then bot.toggle(player)
    elseif action == constants.ACTION.TASK then bot.select_task(player, argument)
    elseif action == constants.ACTION.STATUS then bot.status(player)
    elseif action == constants.ACTION.REFRESH then bot.refresh_track(player)
    elseif action == constants.ACTION.TASKS then
        player.print(constants.TASK_LIST_PREFIX .. table.concat(registry.names(), constants.LIST_DISPLAY_SEPARATOR))
    else player.print(constants.COMMAND_USAGE) end
end

local function register_commands()
    -- Guard registration because this routine runs for both new games and mod
    -- configuration changes, where the command may already exist.
    if not commands.commands[constants.PRIMARY_COMMAND_NAME] then
        commands.add_command(constants.PRIMARY_COMMAND_NAME, constants.COMMAND_DESCRIPTION, command)
    end
    if not commands.commands[constants.SHORT_COMMAND_NAME] then
        commands.add_command(constants.SHORT_COMMAND_NAME, constants.COMMAND_DESCRIPTION, command)
    end
    local function cleanup_command(command_data)
        local player = player_for(command_data)
        if not (player and player.valid) then return end
        local action = string.match(command_data.parameter or constants.EMPTY_TEXT, "^(%S+)") or constants.ACTION.STATUS
        if action == constants.ACTION.ON or action == constants.ACTION.START then cleanup.enable(player)
        elseif action == constants.ACTION.OFF or action == constants.ACTION.STOP then cleanup.disable(player)
        elseif action == constants.ACTION.TOGGLE then cleanup.toggle(player)
        elseif action == constants.ACTION.STATUS then cleanup.status(player)
        else player.print(constants.CLEANUP_COMMAND_USAGE) end
    end
    if not commands.commands[constants.CLEANUP_COMMAND_NAME] then
        commands.add_command(constants.CLEANUP_COMMAND_NAME, constants.CLEANUP_COMMAND_DESCRIPTION, cleanup_command)
    end
    if not commands.commands[constants.CLEANUP_SHORT_COMMAND_NAME] then
        commands.add_command(constants.CLEANUP_SHORT_COMMAND_NAME, constants.CLEANUP_COMMAND_DESCRIPTION, cleanup_command)
    end
end

script.on_init(function() state.ensure(); register_commands() end)
script.on_configuration_changed(function() state.ensure(); register_commands() end)
script.on_load(register_commands)

local function register_custom_input(name, handler)
    -- During mod development, Factorio can load a changed control.lua into a
    -- session whose data stage predates a newly added custom-input prototype.
    -- Register only prototypes present in this session; a full restart runs the
    -- data stage and makes newly introduced inputs available.
    if prototypes.custom_input and prototypes.custom_input[name] then
        script.on_event(name, handler)
    end
end

register_custom_input(constants.CUSTOM_INPUT_NAME, function(event)
    local player = player_for(event)
    if player and player.valid then bot.toggle(player) end
end)

register_custom_input(constants.CLEANUP_CUSTOM_INPUT_NAME, function(event)
    local player = player_for(event)
    if player and player.valid then cleanup.toggle(player) end
end)

local function request_track_refresh(event)
    -- Mutation events can fire before the engine finishes every connection
    -- update. The bot therefore records intent here and rebuilds next tick.
    bot.request_track_refresh(event.entity or event.created_entity or event.destination)
end

-- These events cover player, robot, combat, and script-driven changes without
-- polling the belt graph. Unrelated entities are inexpensive because the bot
-- filters by surface/force before setting a refresh request.
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity,
                 defines.events.script_raised_built, defines.events.script_raised_revive,
                 defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined,
                 defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
                 defines.events.on_entity_died, defines.events.script_raised_destroy,
                 defines.events.on_player_rotated_entity}, request_track_refresh)

script.on_event(defines.events.on_player_removed, function(event)
    -- Player removal is permanent, unlike disconnecting. Destroying references
    -- here prevents orphaned entities and render objects on the surface.
    state.ensure()
    local players = storage[constants.STORAGE_KEY].players
    local value = players[event.player_index]
    if value then state.destroy(value); players[event.player_index] = nil end
    local cleanup_players = storage[constants.STORAGE_KEY].cleanup_players
    local cleanup_value = cleanup_players[event.player_index]
    if cleanup_value then
        state.destroy_cleanup(cleanup_value)
        cleanup_players[event.player_index] = nil
    end
end)

script.on_event(defines.events.on_tick, function(event)
    -- A shared cadence avoids registering per-player tick handlers and allows
    -- tuning CPU cost from one configuration value.
    if event.tick % config.update_interval ~= constants.EMPTY_COUNT then return end
    for _, player in pairs(game.connected_players) do
        bot.update(player, event.tick)
        cleanup.update(player, event.tick)
    end
end)
