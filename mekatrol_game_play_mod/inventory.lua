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

local function insert_stack_into_player(player, stack)
    if not (stack and stack.valid_for_read) then
        return 0
    end

    local inv = player.get_main_inventory()

    if not inv then
        return 0
    end

    return inv.insert {
        name = stack.name,
        count = stack.count
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

function inventory.transfer_container_to_player(player, ent)
    local inv = ent.get_inventory(defines.inventory.chest)

    if not inv then
        util.print(player, "red", "no chest inventory: name=%s type=%s", ent.name, ent.type)
        return false
    end

    local moved_any = false

    for i = 1, #inv do
        local s = inv[i]
        if s and s.valid_for_read then
            local name = s.name
            local before_count = s.count

            util.print(player, "red", "inventory (before): %s (%s)", name, before_count)

            local inserted = insert_stack_into_player(player, s)
            if inserted > 0 then
                local after_count = before_count - inserted

                -- Update the chest stack first (this can make s invalid_for_read if it becomes 0)
                s.count = after_count

                -- Print using cached values (never touch s.* here)
                util.print(player, "red", "inventory (after): %s (%s) moved (%s)", name, after_count, inserted)

                moved_any = true
            end
        end
    end

    -- Optional: destroy if empty
    if moved_any and inv.is_empty() and ent.valid then
        ent.destroy()
    end

    return moved_any
end

return inventory
