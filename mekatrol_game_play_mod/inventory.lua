local inventory = {}

local util = require("util")

local function insert_into_player(player, name, count)
    local inv = inventory.get_player_main_inventory(player)

    if not inv then
        return 0
    end

    return inv.insert {
        name = name,
        count = count
    }
end

function inventory.get_list(player)
    local lines = {}

    if not (player and player.valid) then
        return lines
    end

    local inv = player.get_main_inventory()
    if not inv then
        return lines
    end

    local contents = inv.get_contents()
    if not contents or #contents == 0 then
        return lines
    end

    for _, entry in ipairs(contents) do
        -- entry.name = item prototype name
        -- entry.count = total count
        lines[#lines + 1] = entry.name .. ": " .. entry.count
    end

    return lines
end

function inventory.get_player_main_inventory(player)
    if not (player and player.valid) then
        return nil
    end

    local inv = player.get_main_inventory()

    if inv and inv.valid then
        return inv
    end

    return nil
end

function inventory.insert_stack_into_player(player, ent, stack)
    if not (stack and stack.valid_for_read) then
        return 0
    end

    local inv = player.get_main_inventory()
    if not inv then
        return 0
    end

    local name = stack.name
    local count = stack.count

    local inserted = inv.insert {
        name = name,
        count = count
    }
    local remainder = count - inserted

    -- Remove what we inserted from the source stack (may invalidate it if it hits 0)
    if inserted > 0 and stack.valid_for_read then
        stack.count = remainder
    end

    -- If player inventory is full, spill the remainder to ground
    if remainder > 0 and ent and ent.valid then
        ent.surface.spill_item_stack {
            position = ent.position,
            stack = {
                name = name,
                count = remainder
            },
            enable_looted = true
        }

        -- Clear the source stack if it still exists
        if stack.valid_for_read then
            stack.clear()
        end
    end

    return inserted
end

function inventory.transfer_to_player(player, ent, inv)
    local moved_any = false

    local inv_count = util.table_size(inv)
    util.print(player, "red", "inv count: %s", inv_count)

    for i = 1, #inv do
        local stack = inv[i]
        if stack and stack.valid_for_read then
            local inserted = inventory.insert_stack_into_player(player, ent, stack)

            if inserted > 0 then
                moved_any = true
            end
        end
    end

    return moved_any
end

function inventory.harvest_resource_to_player(player, ent, requested_amount)
    if not (player and player.valid) then
        return 0
    end

    if not (ent and ent.valid) then
        return 0
    end

    if ent.type ~= "resource" then
        return 0
    end

    if not ent.amount or ent.amount <= 0 then
        return 0
    end

    local mineable = ent.prototype and ent.prototype.mineable_properties
    local products = mineable and mineable.products
    local first = products and products[1]
    local item_name = first and first.name
    
    if not item_name then
        util.print(player, "red", "resource has no mineable product: %s", ent.name)
        return 0
    end

    local want = requested_amount or 1
    if want < 1 then
        want = 1
    end

    local mined_units = math.min(want, ent.amount)

    local inv = player.get_main_inventory()
    if not inv then
        return 0
    end

    local inserted = inv.insert {
        name = item_name,
        count = mined_units
    }
    
    local remainder = mined_units - inserted

    if remainder > 0 then
        ent.surface.spill_item_stack {
            position = ent.position,
            stack = {
                name = item_name,
                count = remainder
            },
            enable_looted = true
        }
    end

    -- reduce the resource amount by what we actually produced (inserted + spilled)
    ent.amount = ent.amount - mined_units
    if ent.amount <= 0 and ent.valid then
        ent.deplete()
    end

    return mined_units
end

function inventory.mine_to_player(player, ent, mine_amount)
    -- entity must be minable
    if not (ent and ent.valid and ent.minable) then
        return false
    end

    -- Create a temporary script inventory
    local inv = game.create_inventory(32)

    -- Mine at least 1 unit (or more, if you want)
    local amount = math.min(mine_amount or 1, ent.amount or 1)

    -- Mine into script inventory (does NOT require player proximity)
    local ok = ent.mine {
        inventory = inv,
        count = amount
    }

    util.print(player, "red", "ent.mine: %s", ok)

    if not ok then
        inv.destroy()
        return false
    end

    -- transfer to player
    local moved_any = inventory.transfer_to_player(player, ent, inv)

    -- destroy the created inventory
    inv.destroy()

    return moved_any
end

function inventory.transfer_container_to_player(player, ent)
    local inv = ent.get_inventory(defines.inventory.chest)
    if not inv then
        util.print(player, "red", "no chest inventory: name=%s type=%s", ent.name, ent.type)
        return false
    end

    -- transfer to player
    local moved_any = inventory.transfer_to_player(player, ent, inv)

    -- Only containers should be destroyed when emptied
    if moved_any and inv.is_empty() and ent.valid then
        ent.destroy()
    end

    return moved_any
end

return inventory
