local bot = require("bot")
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
    -- command grammar. Missing input intentionally means a harmless status read.
    local action, argument = string.match(command_data.parameter or constants.EMPTY_TEXT, constants.COMMAND_PATTERN)
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
end

script.on_init(function() state.ensure(); register_commands() end)
script.on_configuration_changed(function() state.ensure(); register_commands() end)
script.on_load(register_commands)

script.on_event(constants.CUSTOM_INPUT_NAME, function(event)
    local player = player_for(event)
    if player and player.valid then bot.toggle(player) end
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
end)

script.on_event(defines.events.on_tick, function(event)
    -- A shared cadence avoids registering per-player tick handlers and allows
    -- tuning CPU cost from one configuration value.
    if event.tick % config.update_interval ~= constants.EMPTY_COUNT then return end
    for _, player in pairs(game.connected_players) do bot.update(player, event.tick) end
end)
