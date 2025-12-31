local master_controller = {}

local module = require("module")

local function init_game(player, ps, tick)
    local logistics_module = module.get_module("logistics")
    local logistics_bot = ps.bots["surveyor"]
    local searcher_module = module.get_module("searcher")
    local searcher_bot = ps.bots["searcher"]

    searcher_bot.task.search_item = {
        name = nil,
        find_many = false,
        remove_when_no_more_found = false
    }

    searcher_bot.task.target_position = nil
    searcher_bot.task.search_list = {{
        name = "crash-site",
        find_many = true,
        remove_when_no_more_found = true
    }}
    searcher_module.set_bot_task(player, ps, "search")

    local logistics_args = {
        -- set the list of items to collect
        ["collect_list"] = {{
            name = "crash-site"
        }}
    }

    logistics_bot.task.target_position = nil
    logistics_module.set_bot_task(player, ps, "collect", nil, searcher_args)
end

function master_controller.update(player, ps, tick)
    local constructor_module = module.get_module("constructor")
    local logistics_module = module.get_module("logistics")
    local repairer_module = module.get_module("repairer")
    local searcher_module = module.get_module("searcher")
    local surveyor_module = module.get_module("surveyor")

    if ps.game_phase == "init" then
        ps.game_phase = "init_pending"
        init_game(player, ps, tick)
    end

    constructor_module.update(player, ps, tick)
    logistics_module.update(player, ps, tick)
    repairer_module.update(player, ps, tick)
    searcher_module.update(player, ps, tick)
    surveyor_module.update(player, ps, tick)
end

return master_controller
