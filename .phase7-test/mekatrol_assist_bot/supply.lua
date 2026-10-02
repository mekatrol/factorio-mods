-- Small inventory primitives. Source-area discovery is delegated to the budgeted scanner.
local M = {}
local config = require("config")
local scanner = require("entity_scanner")
local movement = require("movement")

function M.player_take(player, name, count)
    local inv = player.get_main_inventory();
    if not inv then
        return 0
    end
    return inv.remove {
        name = name,
        count = count
    }
end

function M.player_give(player, stack)
    local inv = player.get_main_inventory();
    if not inv then
        return 0
    end
    return inv.insert(stack)
end

function M.give_or_carry(rs, player, stack, destination)
    local inserted = destination and 0 or M.player_give(player, stack);
    local remaining = stack.count - inserted
    if remaining > 0 then
        rs.cargo = rs.cargo or {};
        rs.cargo_order = rs.cargo_order or {};
        rs.cargo_destinations = rs.cargo_destinations or {};
        if not rs.cargo[stack.name] then
            rs.cargo_order[#rs.cargo_order + 1] = stack.name
        end
        rs.cargo[stack.name] = (rs.cargo[stack.name] or 0) + remaining;
        if destination and destination.valid then
            rs.cargo_destinations[stack.name] = destination
        end
    end
    return inserted
end

function M.queue_cargo(rs, stack, prefer_existing_container)
    rs.cargo = rs.cargo or {};
    rs.cargo_order = rs.cargo_order or {};
    rs.cargo_destinations = rs.cargo_destinations or {};
    rs.cargo_count = rs.cargo_count or 0
    if not rs.cargo[stack.name] then
        rs.cargo_order[#rs.cargo_order + 1] = stack.name
    end
    rs.cargo[stack.name] = (rs.cargo[stack.name] or 0) + stack.count;
    rs.cargo_count = rs.cargo_count + stack.count
    if prefer_existing_container then
        rs.cargo_destinations[stack.name] = false
    end
end

function M.flush_cargo(rs, player, bot)
    rs.cargo_order = rs.cargo_order or {};
    rs.cargo_cursor = rs.cargo_cursor or 1;
    local name = rs.cargo_order[rs.cargo_cursor]
    if not name then
        return true
    end
    local count = (rs.cargo or {})[name]
    if not count then
        rs.cargo_cursor = rs.cargo_cursor + 1;
        return false
    end
    local destination = rs.cargo_destinations and rs.cargo_destinations[name];
    local inserted
    if destination == false then
        local job = rs.drop_job
        if not job or job.name ~= name then
            job = {
                name = name,
                scan = scanner.start(bot.surface, bot.position, config.supply.radius, {
                    type = {"container", "logistic-container"},
                    force = player.force
                })
            };
            rs.drop_job = job
        end
        if not job.scan.done then
            local _, found = scanner.step(job.scan);
            for _, e in ipairs(found) do
                local inv = M.entity_inventory(e);
                if inv and inv.get_item_count(name) > 0 and inv.can_insert {
                    name = name,
                    count = 1
                } then
                    local d = movement.distance2(e.position, bot.position);
                    if not job.distance or d < job.distance then
                        job.source = e;
                        job.distance = d
                    end
                end
            end
            return false
        end
        destination = job.source;
        rs.cargo_destinations[name] = destination or nil;
        rs.drop_job = nil
    end
    if destination and destination.valid then
        if not movement.step(bot, destination.position) then
            return false
        end
        local inv = M.entity_inventory(destination);
        inserted = inv and inv.insert {
            name = name,
            count = count
        } or 0
    else
        inserted = M.player_give(player, {
            name = name,
            count = count
        })
    end
    count = count - inserted;
    rs.cargo_count = math.max(0, (rs.cargo_count or 0) - inserted);
    rs.cargo[name] = count > 0 and count or nil
    if count == 0 then
        if rs.cargo_destinations then
            rs.cargo_destinations[name] = nil
        end
        rs.cargo_cursor = rs.cargo_cursor + 1
    end
    return count == 0 and rs.cargo_order[rs.cargo_cursor] == nil
end

function M.entity_inventory(e)
    if not e or not e.valid then
        return nil
    end
    for _, id in ipairs {defines.inventory.chest, defines.inventory.cargo_wagon, defines.inventory.furnace_source,
                         defines.inventory.assembling_machine_input} do
        if e.get_inventory and e.get_inventory(id) then
            return e.get_inventory(id)
        end
    end
end

-- Returns nil while the bounded container search is incomplete, otherwise the amount obtained.
function M.take(rs, player, target, bot, name, count)
    rs.supplied = rs.supplied or {};
    local carried = rs.supplied[name] or 0
    if carried > 0 then
        local used = math.min(count, carried);
        rs.supplied[name] = carried - used;
        return used
    end
    if #config.supply.source_priority == 0 then
        return 0
    end
    local player_first = config.supply.source_priority[1] == "player";
    local use_containers = false;
    for _, policy in ipairs(config.supply.source_priority) do
        use_containers = use_containers or policy == "containers"
    end
    local got = player_first and M.player_take(player, name, count) or 0;
    if got > 0 then
        return got
    end
    if not use_containers then
        return M.player_take(player, name, count)
    end
    rs.source_cache = rs.source_cache or {};
    local cached = rs.source_cache[name]
    if cached and cached.valid then
        local inv = M.entity_inventory(cached);
        if inv and inv.get_item_count(name) > 0 then
            if not movement.step(bot, cached.position) then
                return nil
            end
            got = inv.remove {
                name = name,
                count = count
            };
            if got > 0 then
                rs.supplied[name] = got;
                rs.last_source = cached;
                return nil
            end
        end
    end
    rs.source_cache[name] = nil
    local job = rs.supply_job
    if not job or job.name ~= name then
        job = {
            name = name,
            scan = scanner.start(target.surface, target.position, config.supply.radius, {
                type = {"container", "logistic-container"},
                force = player.force
            })
        };
        rs.supply_job = job
    end
    if not job.scan.done then
        local _, found = scanner.step(job.scan)
        for _, e in ipairs(found) do
            local inv = M.entity_inventory(e);
            if inv and inv.get_item_count(name) > 0 then
                local d = movement.distance2(e.position, bot.position);
                if not job.distance or d < job.distance then
                    job.source = e;
                    job.distance = d
                end
            end
        end
        return nil
    end
    if not (job.source and job.source.valid) then
        rs.supply_job = nil;
        return player_first and 0 or M.player_take(player, name, count)
    end
    if not movement.step(bot, job.source.position) then
        return nil
    end
    local inv = M.entity_inventory(job.source);
    if not inv then
        rs.supply_job = nil;
        return 0
    end
    got = inv.remove {
        name = name,
        count = count
    };
    rs.supply_job = nil
    if got > 0 then
        rs.supplied[name] = got;
        rs.last_source = job.source;
        rs.source_cache[name] = job.source;
        return nil
    end
    return 0
end

return M
