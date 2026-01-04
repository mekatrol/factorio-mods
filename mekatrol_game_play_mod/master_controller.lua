local master_controller = {}

local entity_index = require("entity_index")
local module = require("module")
local util = require("util")

local function get_bot(ps, bot_name)
    local bot_module = module.get_module(bot_name)
    local bot_state = ps.bots[bot_name]

    return bot_module, bot_state
end

local function init_game(player, ps, tick)
    local logistics_module, logistics_bot = get_bot(ps, "logistics")
    local searcher_module, mapper_bot = get_bot(ps, "mapper")
    local surveyor_module, surveyor_bot = get_bot(ps, "surveyor")

    logistics_bot.collect_list = {
        -- set the list of items to collect
        ["collect_list"] = {{
            name = "crash-site"
        }}
    }
    logistics_bot.task.target_position = nil
    logistics_module.set_bot_task(player, ps, "collect")

    mapper_bot.task.search_list = {{
        name = "crash-site",
        find_many = true,
        remove_when_no_more_found = true
    }, {
        name = "coal",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "iron-ore",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "copper-ore",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "stone",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "tree",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "uranium-ore",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "oil",
        find_many = true,
        remove_when_no_more_found = false
    }, {
        name = "rock",
        find_many = true,
        remove_when_no_more_found = false
    }}
    mapper_bot.task.target_position = nil
    searcher_module.set_bot_task(player, ps, "search")

    surveyor_bot.task.target_position = nil
    surveyor_bot.task.survey_list = nil
    surveyor_module.set_bot_task(player, ps, "follow")
end

local function update_collect_state(player, ps, bot_module, bot_state)
    -- task bot with next group if one available and collector has finished processing any previous group
    if not bot_state.task.collect_group then
        -- get the next list to target
        local entity_group = module.get_module("entity_group")
        local group = entity_group.get_group_entity_name_contains(ps, "crash-site")

        if group then
            bot_state.task.collect_group = group

            -- collect the group
            bot_module.set_bot_task(player, ps, "collect")
        else
            -- nothing left to survey, so return to follow mode
            bot_module.set_bot_task(player, ps, "follow")
        end
    end
end

local function get_discovered_entitities(ps, list)
    local bucket_name, entities

    if list == nil then
        bucket_name, entities = ps.discovered_entities:pop_first()
    end

    for _, name in ipairs(list) do
        bucket_name, entities = ps.discovered_entities:pop_first_contains(name)

        if bucket_name then
            return entities
        end
    end

    -- none found by priority name, so just get next if available
    bucket_name, entities = ps.discovered_entities:pop_first()

    if bucket_name then
        return entities
    end

    return nil
end

local function update_survey_state(player, ps, bot_module, bot_state)
    -- task bot with next list if one available and surveyor finished processing and previous list
    if not (bot_state.task.survey_list or bot_state.task.survey_entity or bot_state.task.target_position) then
        -- get the next list to target (prioritise the specified entity names)
        local entities = get_discovered_entitities(ps, {"crash", "coal", "iron", "copper", "stone", "rock", "tree"})
        bot_state.task.survey_list = entities

        if bot_state.task.survey_list then
            -- survey the list
            bot_module.set_bot_task(player, ps, "survey")
        else
            -- nothing left to survey, so return to follow mode
            bot_module.set_bot_task(player, ps, "follow")
        end
    end
end

function master_controller.update(player, ps, tick)
    local constructor_module, constructor_bot = get_bot(ps, "constructor")
    local logistics_module, logistics_bot = get_bot(ps, "logistics")
    local searcher_module, mapper_bot = get_bot(ps, "mapper")
    local repairer_module, repairer_bot = get_bot(ps, "repairer")
    local surveyor_module, surveyor_bot = get_bot(ps, "surveyor")

    ps.discovered_entities = ps.discovered_entities or entity_index.new()

    if ps.game_phase == "init" then
        ps.game_phase = "init_pending"
        init_game(player, ps, tick)
    end

    update_collect_state(player, ps, logistics_module, logistics_bot)
    update_survey_state(player, ps, surveyor_module, surveyor_bot)

    constructor_module.update(player, ps, tick)
    logistics_module.update(player, ps, tick)
    repairer_module.update(player, ps, tick)
    searcher_module.update(player, ps, tick)
    surveyor_module.update(player, ps, tick)
end

return master_controller
