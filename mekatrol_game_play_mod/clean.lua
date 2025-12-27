local clean = {}

local module = require("module")
local util = require("util")

-- Max different item types the bot can carry at once.
local BOT_MAX_ITEM_COUNT = 100

local function get_total_carried(player, bot)
    local total = 0
    if not bot or not bot.tasks.carried_items then
        util.print(player, "yellow", "zero carried")
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

    bot.carried_items = bot.carried_items or {}
    local t = bot.carried_items
    t[name] = (t[name] or 0) + count
end

function clean.update(player, ps, bot)
    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    local surface = bot.entity.surface
    if not surface then
        return false
    end

    local items = surface.find_entities_filtered {
        position = bot.entity.position,
        radius = 1.0,
        type = "item-entity"
    }

    local bot_module = module.get_module(bot.name)

    if not items or #items == 0 then
        -- return to follow and then try cleaning again
        bot_module.set_bot_task(player, ps, "follow", "clean")
        return
    end

    local picked_any = false

    for _, ent in pairs(items) do
        if ent.valid and ent.stack and ent.stack.valid_for_read then
            local free = get_free_capacity(player, ps)
            if free <= 0 then
                -- No more capacity at all; stop picking up.
                break
            end

            local name = ent.stack.name
            local stack_count = ent.stack.count
            local take = math.min(stack_count, free)

            if take > 0 then
                add_to_carried(ps, name, take)

                if take == stack_count then
                    -- Took it all, remove the entity.
                    ent.destroy()
                else
                    -- Partially consume this ground stack.
                    ent.stack.count = stack_count - take
                end

                picked_any = true
            end
        end
    end

    if picked_any then
        local total = get_total_carried(player, bot)
        if total > 0 and (bot.task.current_task == "idle" or pdata.mode == "roam") then
            bot_module.set_bot_task(player, ps, "pickup", "clean")
        end
    end
end

return clean
