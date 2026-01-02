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
    local searcher_module, searcher_bot = get_bot(ps, "searcher")
    local surveyor_module, surveyor_bot = get_bot(ps, "surveyor")

    logistics_bot.collect_list = {
        -- set the list of items to collect
        ["collect_list"] = {{
            name = "crash-site"
        }}
    }
    logistics_bot.task.target_position = nil
    logistics_module.set_bot_task(player, ps, "collect")

    searcher_bot.task.search_list = {{
        name = "crash-site",
        find_many = true,
        remove_when_no_more_found = true
    }}
    searcher_bot.task.target_position = nil
    searcher_module.set_bot_task(player, ps, "search")

    surveyor_bot.task.target_position = nil
    surveyor_bot.task.survey_list = nil
    surveyor_module.set_bot_task(player, ps, "follow")
end

local function update_survey_state(player, ps, surveyor_module, surveyor_bot)
    -- task surveyor with next list if one available and surveyor finished processing current list
    if not surveyor_bot.task.survey_list and not surveyor_bot.task.target_position then
        -- get the next list to target
        surveyor_bot.task.survey_list = ps.discovered_entities:pop_first()

        if surveyor_bot.task.survey_list then
            -- survey the list
            surveyor_module.set_bot_task(player, ps, "survey")
        else
            -- nothing left to survey, so return to follow mode
            surveyor_module.set_bot_task(player, ps, "follow")
        end
    end
end

function master_controller.update(player, ps, tick)
    local constructor_module = module.get_module("constructor")
    local logistics_module = module.get_module("logistics")
    local repairer_module = module.get_module("repairer")
    local searcher_module = module.get_module("searcher")
    local surveyor_module, surveyor_bot = get_bot(ps, "surveyor")

    ps.discovered_entities = ps.discovered_entities or entity_index.new()

    if ps.game_phase == "init" then
        ps.game_phase = "init_pending"
        init_game(player, ps, tick)
    end

    update_survey_state(player, ps, surveyor_module, surveyor_bot)

    constructor_module.update(player, ps, tick)
    logistics_module.update(player, ps, tick)
    repairer_module.update(player, ps, tick)
    searcher_module.update(player, ps, tick)
    surveyor_module.update(player, ps, tick)
end

return master_controller
