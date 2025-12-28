local inventory = {}

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

return inventory
