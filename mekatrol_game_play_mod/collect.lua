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

local function find_pickup_entities(player, ps, surface, group)
    local ents

    if group.bounding_box then
        ents = surface.find_entities_filtered {
            area = group.bounding_box
        }
    else
        ents = surface.find_entities_filtered {
            position = group.center,
            radius = 2.0
        }
    end

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

function collect.update(player, ps, bot)
    if not (bot and bot.entity and bot.entity.valid) then
        return
    end

    local surface = bot.entity.surface
    if not surface then
        return false
    end

    local items = nil

    local inventory = module.get_module("inventory")
    local entity_group = module.get_module("entity_group")
    local bot_module = module.get_module(bot.name)

    if bot.task.current_task == "pick_up" then
        local g = bot.task.pick_up_group

        if not g then
            bot_module.set_bot_task(player, ps, "collect", nil)
            return
        end

        local ents = find_pickup_entities(player, ps, surface, g)
        if not ents or #ents == 0 then
            -- Nothing in the area at all, treat as done
            entity_group.remove_group(player, ps, g)
            bot.task.pick_up_group = nil
            bot_module.set_bot_task(player, ps, "collect", nil)
            return
        end

        local moved_any = false

        for _, ent in pairs(ents) do
            if ent.valid then
                if ent.type == "item-entity" then
                    local stack = ent.stack

                    util.print(player, "yellow", "item-entity: %s (%s)", stack.name, stack.count)

                    if stack and stack.valid_for_read then
                        -- Cache for debugging (safe even if stack becomes invalid later)
                        local name = stack.name
                        local before_count = stack.count

                        util.print(player, "red", "ground (before): %s (%s)", name, before_count)

                        local inv = player.get_main_inventory()
                        if inv then
                            local free = inv.get_insertable_count(name)

                            if free > 0 then
                                local take = math.min(before_count, free)
                                local inserted = inv.insert {
                                    name = name,
                                    count = take
                                }

                                if inserted > 0 then
                                    moved_any = true

                                    if inserted == before_count then
                                        -- ent/stack becomes invalid after destroy; only use cached values
                                        util.print(player, "red", "ground (moved all): %s (%s)", name, inserted)
                                        ent.destroy()
                                    else
                                        local after_count = before_count - inserted
                                        stack.count = after_count -- may still be valid-for-read (non-zero)

                                        util.print(player, "red", "ground (moved): %s moved (%s) left (%s)", name,
                                            inserted, after_count)
                                    end
                                else
                                    util.print(player, "red", "ground (no insert): %s free (%s)", name, free)
                                end
                            else
                                util.print(player, "red", "ground (no space): %s (%s)", name, before_count)
                            end
                        end
                    end
                elseif ent.type == "simple-entity-with-owner" then
                    if ent.valid and ent.minable then
                        local tmp = game.create_inventory(1)

                        local ok = ent.mine {
                            inventory = tmp
                        }

                        if ok then
                            moved_any = true

                            local player_inv = player.get_main_inventory()

                            if player_inv then
                                for i = 1, #tmp do
                                    local s = tmp[i]
                                    if s and s.valid_for_read then
                                        local name = s.name
                                        local count = s.count
                                        local inserted = player_inv.insert {
                                            name = name,
                                            count = count
                                        }

                                        util.print(player, "red", "mined: %s (%s) inserted (%s)", name, count, inserted)

                                        if inserted > 0 then
                                            s.count = s.count - inserted
                                        end

                                        -- If player inventory is full, spill the remainder to ground
                                        if s.valid_for_read and s.count > 0 then
                                            ent.surface.spill_item_stack(ent.position, {
                                                name = name,
                                                count = s.count
                                            }, true, nil, false)
                                            s.clear()
                                        end
                                    end
                                end
                            end
                        else
                            util.print(player, "red", "mine failed: %s (%s)", ent.name, ent.type)
                        end

                        tmp.destroy()
                    else
                        util.print(player, "red", "not minable: %s (%s)", ent.name, ent.type)
                    end

                    ::continue::
                else
                    if inventory.transfer_container_to_player(player, ent) then
                        moved_any = true
                    end
                end
            end
        end

        -- Determine whether the group is finished:
        -- finished if there are no ground items and no non-empty containers left nearby.
        local remaining = find_pickup_entities(player, ps, surface, g)
        local any_left = false

        if remaining and #remaining > 0 then
            for _, ent in pairs(remaining) do
                if ent.valid then
                    if ent.type == "item-entity" then
                        -- any ground item left means not finished
                        any_left = true
                        break
                    elseif ent.type == "simple-entity-with-owner" then
                        if ent.valid and ent.minable then
                            any_left = true
                        end
                    else
                        -- check if it has any chest inventory with something inside
                        local inv = ent.get_inventory(defines.inventory.chest)
                        if inv and not inv.is_empty() then
                            any_left = true
                            break
                        end
                    end
                end
            end
        end

        if not any_left then
            entity_group.remove_group(player, ps, g)
            bot.task.pick_up_group = nil
            bot_module.set_bot_task(player, ps, "collect", nil)
            return
        end

        -- If nothing moved this tick but stuff remains, we’re likely blocked by full inventory.
        -- Bail out so we don't spin forever.
        if not moved_any then
            bot.task.pick_up_group = nil
            bot_module.set_bot_task(player, ps, "collect", nil)
        end

        return
    end

    -- always collect space ship items as a priority
    local g = entity_group.get_group_entity_name_starts_with(ps, "crash-site-spaceship")

    if g then
        bot.task.target_position = g.center
        bot.task.pick_up_group = g
        bot_module.set_bot_task(player, ps, "move_to", "pick_up")
        return
    end

    if not items then
        items = surface.find_entities_filtered {
            position = bot.entity.position,
            radius = 1.0,
            type = "item-entity"
        }
    end

    if not items or #items == 0 then
        -- return to follow and then try collecting again
        -- bot_module.set_bot_task(player, ps, "follow", nil)
        return
    end

    local picked_any = false

    for _, ent in pairs(items) do
        if ent.valid and ent.stack and ent.stack.valid_for_read then
            local free = get_free_capacity(player, bot)
            if free <= 0 then
                -- No more capacity at all; stop picking up.
                break
            end

            local name = ent.stack.name
            local stack_count = ent.stack.count
            local take = math.min(stack_count, free)

            if take > 0 then
                add_to_carried(bot, name, take)

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
        if total > 0 and (bot.task.current_task == "idle") then
            bot_module.set_bot_task(player, ps, "pickup", nil)
        end
    end
end

return collect
