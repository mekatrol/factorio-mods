-- Small inventory primitives. Source-area discovery is delegated to the budgeted scanner.
local M = {}
local config = require("config")
local scanner = require("entity_scanner")
local movement = require("movement")

---Remove up to `count` items from the player's main inventory.
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

---Insert as much of a stack as possible into the player's main inventory.
function M.player_give(player, stack)
    local inv = player.get_main_inventory();
    if not inv then
        return 0
    end
    return inv.insert(stack)
end

---Return a stack immediately or retain the uninserted remainder as bot cargo.
---A destination suppresses player insertion because the item should be
---returned to the container that originally supplied it.
function M.give_or_carry(rs, player, stack, destination)
    -- A non-nil destination means the item was borrowed from that container and
    -- must be returned there; bypass the player even if they have room. With no
    -- destination, insert into the player immediately. Lua's `and/or` idiom is
    -- safe here because the chosen zero is truthy in Lua (unlike some languages).
    local inserted = destination and 0 or M.player_give(player, stack);
    local remaining = stack.count - inserted
    if remaining > 0 then
        rs.cargo = rs.cargo or {};
        rs.cargo_order = rs.cargo_order or {};
        rs.cargo_destinations = rs.cargo_destinations or {};
        -- `cargo` is a count map for consolidation, while `cargo_order` provides
        -- deterministic iteration. Append a name only on its first queued unit.
        if not rs.cargo[stack.name] then
            rs.cargo_order[#rs.cargo_order + 1] = stack.name
        end
        rs.cargo[stack.name] = (rs.cargo[stack.name] or 0) + remaining;
        -- Only store a live LuaEntity. Invalid references cannot be dereferenced
        -- later; omitting it safely falls back to delivery to the player.
        if destination and destination.valid then
            rs.cargo_destinations[stack.name] = destination
        end
    end
    return inserted
end

---Append collected material to the role's ordered cargo manifest.
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
        -- Boolean false is an intentional sentinel distinct from nil:
        -- false = search for a suitable existing container;
        -- nil   = no container preference, deliver to the player.
        rs.cargo_destinations[stack.name] = false
    end
end

---Advance delivery of the current cargo type.
---Returns true only when the entire ordered manifest is empty. A false result
---means scanning, travel, insertion, or a later item type still needs work.
function M.flush_cargo(rs, player, bot)
    rs.cargo_order = rs.cargo_order or {};
    rs.cargo_cursor = rs.cargo_cursor or 1;
    local name = rs.cargo_order[rs.cargo_cursor]
    if not name then
        return true
    end
    -- Old saves or partially initialized roles may have an order array without
    -- a cargo table. The temporary empty table makes that mismatch a missing
    -- count, which the cursor repair branch below can skip safely.
    local count = (rs.cargo or {})[name]
    if not count then
        rs.cargo_cursor = rs.cargo_cursor + 1;
        return false
    end
    local destination = rs.cargo_destinations and rs.cargo_destinations[name];
    local inserted
    if destination == false then
        -- Cleanup prefers a nearby friendly container which already stores the
        -- same item, keeping factory organization intact. Search incrementally.
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
                    -- Only relative ordering matters, so squared distance is
                    -- both exact enough and cheaper than Euclidean distance.
                    local d = movement.distance2(e.position, bot.position);
                    if not job.distance or d < job.distance then
                        job.source = e;
                        job.distance = d
                    end
                end
            end
            return false
        end
        -- `job.source` remains nil when no same-item container had capacity.
        -- In that case clearing the destination selects the player fallback.
        destination = job.source;
        rs.cargo_destinations[name] = destination or nil;
        rs.drop_job = nil
    end
    if destination and destination.valid then
        if not movement.step(bot, destination.position) then
            return false
        end
        local inv = M.entity_inventory(destination);
        -- The destination could lose its supported inventory after selection
        -- (for example through replacement by another mod). Treat that as zero
        -- inserted and retain the cargo for a later attempt.
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
    -- Removing a completed key rather than retaining zero keeps `cargo` a map
    -- of real outstanding work and allows a future stack of this name to be
    -- appended to the ordered manifest again.
    rs.cargo[name] = count > 0 and count or nil
    if count == 0 then
        if rs.cargo_destinations then
            rs.cargo_destinations[name] = nil
        end
        rs.cargo_cursor = rs.cargo_cursor + 1
    end
    -- Completion requires both the current type to be empty and no later
    -- ordered type. If insertion was partial, the same cursor resumes next call.
    return count == 0 and rs.cargo_order[rs.cargo_cursor] == nil
end

---Return the first supported inventory exposed by an entity.
---The order expresses which inventory is meaningful for mixed-purpose
---entities; most supported entities expose only one of these IDs.
function M.entity_inventory(e)
    if not e or not e.valid then
        return nil
    end
    -- Query known inventory IDs in preference order. Factorio returns nil when
    -- an ID is unsupported, so this works across chests, wagons, furnaces, and
    -- assembling machines without branching on every entity type.
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
        -- `supplied` is a one-call staging area. A container withdrawal returns
        -- nil first (after travel), then this branch supplies it on the next
        -- controller call, preserving the bounded state-machine contract.
        local used = math.min(count, carried);
        rs.supplied[name] = carried - used;
        return used
    end
    -- An empty policy is an explicit configuration choice meaning bots may not
    -- obtain supplies from either players or containers.
    if #config.supply.source_priority == 0 then
        return 0
    end
    -- Ordering changes behavior: when player is first, any available player
    -- item avoids a container trip. Otherwise containers are exhausted before
    -- the player is tried as a fallback.
    local player_first = config.supply.source_priority[1] == "player";
    local use_containers = false;
    for _, policy in ipairs(config.supply.source_priority) do
        use_containers = use_containers or policy == "containers"
    end
    -- Lua's zero is truthy, so this `and/or` expression reliably yields zero
    -- when the player policy is not first rather than evaluating another branch.
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
        -- Reusing a known source avoids repeating a radius scan for successive
        -- construction/upgrade items, but its live contents are revalidated.
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
                -- Stage the removed amount instead of returning it immediately.
                -- Returning nil tells the controller that this work unit was
                -- spent travelling/withdrawing; the next call consumes it from
                -- `supplied` and performs the actual target action.
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
                -- Select the nearest source by squared Euclidean distance.
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
        -- If player inventory was already checked first, zero is final. If
        -- containers were first, this is the deferred player fallback.
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
