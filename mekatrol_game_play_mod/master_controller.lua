local master_controller = {}

local module = require("module")

local function init_game(player, ps, tick)
    local surveyor_module = module.get_module("surveyor")
    local bot = ps.bots["surveyor"]

    bot.task.search_item = {
        name = nil,
        find_many = false,
        remove_when_no_more_found = false
    }

    local args = {
        -- set the list of items to search for and in the order we want to search
        ["search_list"] = {{
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
        }}
    }

    bot.task.target_position = nil
    surveyor_module.set_bot_task(player, ps, "search", "survey", args)
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
