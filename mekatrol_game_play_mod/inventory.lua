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
    util.print_player_or_game(player, "red", "inv count: %s", inv_count)

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

function inventory.harvest_resource_to_player(player, ent, requested_amount, progress_by_id)
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
        util.print_player_or_game(player, "red", "resource has no mineable product: %s", ent.name)
        return 0
    end

    local want = requested_amount or 1
    if want < 1 then
        want = 1
    end

    local pos = ent.position
    local name = ent.name
    local start_amount = ent.amount
    local id = util.generated_id(ent)

    local inv = player.get_main_inventory()
    if not inv then
        return 0
    end

    -- mining_time is seconds per 1 "resource unit" at mining speed 1.0
    local mining_time = (mineable and mineable.mining_time) or 1.0
    if mining_time <= 0 then
        mining_time = 1.0
    end

    -- Best-effort: derive a "player-like" mining speed multiplier.
    local speed = 1.0

    if player.character and player.character.valid then
        speed = speed * (1.0 + player.character.character_mining_speed_modifier)
    end

    -- Progress store per resource id
    progress_by_id = progress_by_id or {}
    local id = util.generated_id(ent)

    local p = progress_by_id[id]
    if not p then
        p = {
            progress = 0.0,
            last_tick = game.tick
        }
        progress_by_id[id] = p
    end

    local now = game.tick
    local dt_ticks = now - (p.last_tick or now)

    if dt_ticks < 0 then
        dt_ticks = 0
    end

    p.last_tick = now

    -- Convert to seconds (Factorio tick = 1/60s)
    local dt_seconds = dt_ticks / 60.0

    -- Increase progress by (speed * time / mining_time)
    p.progress = (p.progress or 0.0) + (speed * dt_seconds / mining_time)

    -- How many whole units can we mine this tick?
    local mined_units = math.floor(p.progress)

    if mined_units <= 0 then
        return 0
    end

    -- Consume progress for units mined
    p.progress = p.progress - mined_units

    -- Cap by requested and remaining in the resource entity
    mined_units = math.min(mined_units, want, ent.amount)

    -- Insert/spill results (keeps your existing simplistic 1:1 mapping)
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

    -- util.print_player_or_game(player, "yellow",
    --     "ent name: %s, ent id: %s, product name: %s, product amt: %s (%s: %s), mined: %s, inserted: %s, remainder: %s",
    --     name, id, item_name, ent.amount, start_amount, ent.amount - start_amount, mined_units, inserted, remainder)

    if ent.amount <= 0 and ent.valid then
        ent.deplete()

        -- cleanup progress table entry
        progress_by_id[id] = nil
    end

    return mined_units
end

function inventory.mine_to_player(player, ent, mine_amount)
    -- entity must be minable
    if not (ent and ent.valid and ent.minable) then
        return false
    end

    local inv = game.create_inventory(32)

    local ok
    if ent.type == "resource" then
        local amount = mine_amount or 1
        if amount < 1 then
            amount = 1
        end

        -- Only resources have .amount; clamp safely
        if ent.amount and ent.amount > 0 then
            amount = math.min(amount, ent.amount)
        end

        ok = ent.mine {
            inventory = inv,
            count = amount
        }
    else
        -- For non-resources: mine the entity (do NOT touch ent.amount, do NOT pass count)
        ok = ent.mine {
            inventory = inv
        }
    end

    util.print_player_or_game(player, "red", "ent.mine: %s", ok)

    if not ok then
        inv.destroy()
        return false
    end

    local moved_any = inventory.transfer_to_player(player, ent, inv)
    inv.destroy()

    return moved_any
end

function inventory.transfer_container_to_player(player, ent)
    local inv = ent.get_inventory(defines.inventory.chest)
    if not inv then
        util.print_player_or_game(player, "red", "no chest inventory: name=%s type=%s", ent.name, ent.type)
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
