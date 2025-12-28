local collect = {}

local module = require("module")
local util = require("util")

-- Max different item types the bot can carry at once.
local BOT_MAX_ITEM_COUNT = 100

local function get_total_carried(player, bot)
    local total = 0
    if not bot or not bot.tasks.carried_items then
        return 0
    end
    for _, count in pairs(bot.tasks.carried_items) do
        if count and count > 0 then
            total = total + count
        end
    end
    return total
end

-- How much free capacity (by item count) remains.
local function get_free_capacity(player, bot)
    local carried = get_total_carried(player, bot)
    local free = BOT_MAX_ITEM_COUNT - carried
    if free < 0 then
        free = 0
    end
    return free
end

-- Add a stack of items to the bot's carried-items table.
local function add_to_carried(bot, name, count)
    if count <= 0 then
        return
    end
    bot.tasks = bot.tasks or {}
    bot.tasks.carried_items = bot.tasks.carried_items or {}
    local t = bot.tasks.carried_items
    t[name] = (t[name] or 0) + count
end

local function filter_player_and_bots(player, ps, ents)
    -- Filter player character safely
    local character = nil
    if player and player.valid then
        character = player.character -- may be nil, that's fine
    end

    for i = #ents, 1, -1 do
        local ent = ents[i]

        -- make sure ent is valid
        if not ent or not ent.valid then
            table.remove(ents, i)
            -- do not remove player
        elseif character and ent == character then
            table.remove(ents, i)
            -- do not remove bot
        elseif ent.name == "mekatrol-game-play-bot" then
            table.remove(ents, i)
        end
    end

    return ents
end

local function find_pickup_entities(player, ps, surface, group)
    local ents

    if group.bounding_box then
        ents = surface.find_entities_filtered {
            area = group.bounding_box,
            name = group.name
        }
    else
        ents = surface.find_entities_filtered {
            position = group.center,
            name = group.name,
            radius = 2.0
        }
    end

    return filter_player_and_bots(player, ps, ents)
end

local function pickup(player, ps, bot)
    local inventory = module.get_module("inventory")
    local entity_group = module.get_module("entity_group")
    local bot_module = module.get_module(bot.name)

    local g = bot.task.pickup_group

    if not g then
        bot_module.set_bot_task(player, ps, "collect", nil, bot.task.args)
        return
    end

    local surface = bot.entity.surface

    local ents = find_pickup_entities(player, ps, surface, g)

    local moved_any = false

    for _, ent in pairs(ents) do
        if ent.type == "item-entity" then
            if inventory.insert_stack_into_player(player, ent, ent.stack) then
                moved_any = true
            end
        elseif ent.type == "simple-entity-with-owner" or ent.type == "resource" then
            if inventory.mine_to_player(player, ent) then
                moved_any = true
            end
        else
            if inventory.transfer_container_to_player(player, ent) then
                moved_any = true
            end
        end
    end

    -- group is finished if there are no items
    local remaining = find_pickup_entities(player, ps, surface, g)
    if not remaining or #remaining == 0 then
        entity_group.remove_group(player, ps, g)
        bot.task.pickup_group = nil
        bot_module.set_bot_task(player, ps, "collect", nil, bot.task.args)
        return
    end

    -- If nothing moved this tick but stuff remains, we’re likely blocked by full inventory.
    -- Bail out so we don't spin forever.
    if not moved_any then
        bot.task.pickup_group = nil
        bot_module.set_bot_task(player, ps, "collect", nil, bot.task.args)
    end
end

function collect.try_pickup_item(player, ps, bot, name, count)
    local entity_group = module.get_module("entity_group")
    local bot_module = module.get_module(bot.name)

    -- always collect space ship items as a priority
    local g = entity_group.get_group_entity_name_starts_with(ps, name)

    if g then
        bot.task.target_position = g.center
        bot.task.pickup_group = g
        bot.task.pickup_name = name
        bot.task.pickup_remaining = count
        bot_module.set_bot_task(player, ps, "move_to", "pickup", bot.task.args)
        return true
    end

    bot.task.pickup_name = name
    bot.task.pickup_remaining = count

    return false
end

function collect.update(player, ps, bot)
    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    local entity_group = module.get_module("entity_group")
    local bot_module = module.get_module(bot.name)

    if util.table_size(bot.task.args) > 0 then
        -- get first arg
        local name, count = next(bot.task.args)

        -- remove it from the table
        bot.task.args[name] = nil

        if collect.try_pickup_item(player, ps, bot, name, count) then
            return
        end
    end

    if bot.task.current_task == "pickup" then
        pickup(player, ps, bot)
        return
    end

    if not bot.task.pickup_name then
        return
    end

    -- always collect space ship items as a priority ("crash-site-spaceship")
    local g = entity_group.get_group_entity_name_starts_with(ps, bot.task.pickup_name)

    if g then
        bot.task.target_position = g.center
        bot.task.pickup_group = g
        bot_module.set_bot_task(player, ps, "move_to", "pickup", bot.task.args)
        return
    end
end

return collect
