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

---Travel to the player's live position and stage withdrawn supplies.
---Returns zero when the player has no matching item, and nil while travelling
---or after withdrawing. Staging forces the role to travel back to its target
---before the next call consumes the item and performs the action.
local function inventory_quality(inv, name, accept_any_quality, preferred)
    if preferred and inv.get_item_count {name = name, quality = preferred} > 0 then
        return preferred
    end
    if inv.get_item_count(name) > 0 then
        return "normal"
    end
    if not accept_any_quality or not inv.get_item_quality_counts then
        return nil
    end
    local best, best_level
    for quality, amount in pairs(inv.get_item_quality_counts(name)) do
        local prototype = prototypes.quality and prototypes.quality[quality]
        local level = prototype and prototype.level or math.huge
        if amount > 0 and (not best_level or level < best_level) then
            best, best_level = quality, level
        end
    end
    return best
end

local function take_from_player(rs, player, bot, name, count, accept_any_quality)
    local inv = player.get_main_inventory()
    local quality = inv and inventory_quality(inv, name, accept_any_quality, rs.player_supply_quality)
    if not quality then
        rs.player_supply_name = nil
        rs.player_supply_count = nil
        rs.player_supply_quality = nil
        return 0
    end
    -- Preserve the original batch size while travelling. Inventory-wait polls
    -- request one item merely to test availability and must not shrink an
    -- already-started batch pickup to one item.
    if rs.player_supply_name ~= name then
        rs.player_supply_count = count
    end
    rs.player_supply_name = name
    rs.player_supply_quality = quality
    local requested = rs.player_supply_count or count
    -- Mark the role as supply-waiting before yielding movement.  Controllers
    -- process inventory waits before target navigation, so this prevents the
    -- next work unit from pulling the bot back toward its repair/build target.
    rs.waiting_inventory = name
    if not movement.step(bot, player.position) then
        return nil
    end
    local got = inv.remove {
        name = name,
        count = requested,
        quality = quality
    }
    if got > 0 then
        rs.supplied[name] = (rs.supplied[name] or 0) + got
        rs.supplied_qualities = rs.supplied_qualities or {}
        rs.supplied_qualities[name] = quality
        -- A player pickup has no container return destination. Clear any stale
        -- source metadata left by an older staged batch of the same item.
        rs.supplied_sources[name] = nil
        rs.last_source = nil
        rs.player_supply_count = nil
        rs.player_supply_quality = nil
        return nil
    end
    rs.player_supply_name = nil
    rs.player_supply_count = nil
    rs.player_supply_quality = nil
    return 0
end

---Insert as much of a stack as possible into the player's main inventory.
function M.player_give(player, stack)
    local inv = player.get_main_inventory();
    if not inv then
        return 0
    end
    return inv.insert(stack)
end

---Queue a stack for physical delivery by the bot.
---A destination suppresses player insertion because the item should be
---returned to the container that originally supplied it.
function M.give_or_carry(rs, player, stack, destination)
    local remaining = stack.count
    if remaining > 0 then
        rs.cargo = rs.cargo or {};
        rs.cargo_order = rs.cargo_order or {};
        rs.cargo_destinations = rs.cargo_destinations or {};
        rs.cargo_stacks = rs.cargo_stacks or {}
        rs.cargo_count = rs.cargo_count or 0
        local quality = stack.quality or "normal"
        local key = quality == "normal" and stack.name or (stack.name .. "\31" .. quality)
        -- `cargo` is a count map for consolidation, while `cargo_order` provides
        -- deterministic iteration. Append a name only on its first queued unit.
        if not rs.cargo[key] then
            rs.cargo_order[#rs.cargo_order + 1] = key
        end
        rs.cargo[key] = (rs.cargo[key] or 0) + remaining;
        rs.cargo_stacks[key] = {name = stack.name, quality = quality}
        rs.cargo_count = rs.cargo_count + remaining
        -- Only store a live LuaEntity. Invalid references cannot be dereferenced
        -- later; omitting it safely falls back to delivery to the player.
        if destination and destination.valid then
            rs.cargo_destinations[key] = destination
        end
    end
    return 0
end

---Move every unused staged supply item into normal return cargo. Roles call
---this after exhausting their targets so prefetched stock is never stranded.
function M.return_staged(rs, player)
    for name, count in pairs(rs.supplied or {}) do
        if count > 0 then
            local destination = rs.supplied_sources and rs.supplied_sources[name]
            M.give_or_carry(rs, player, {
                name = name,
                count = count,
                quality = rs.supplied_qualities and rs.supplied_qualities[name]
            }, destination)
        end
        rs.supplied[name] = nil
        if rs.supplied_sources then
            rs.supplied_sources[name] = nil
        end
        if rs.supplied_qualities then
            rs.supplied_qualities[name] = nil
        end
    end
end

---Append collected material to the role's ordered cargo manifest.
function M.queue_cargo(rs, stack, prefer_existing_container)
    rs.cargo = rs.cargo or {};
    rs.cargo_order = rs.cargo_order or {};
    rs.cargo_destinations = rs.cargo_destinations or {};
    rs.cargo_stacks = rs.cargo_stacks or {}
    rs.cargo_lowest_inventory = rs.cargo_lowest_inventory or {}
    rs.cargo_count = rs.cargo_count or 0
    local quality = stack.quality or "normal"
    local key = quality == "normal" and stack.name or (stack.name .. "\31" .. quality)
    if not rs.cargo[key] then
        rs.cargo_order[#rs.cargo_order + 1] = key
    end
    rs.cargo[key] = (rs.cargo[key] or 0) + stack.count;
    rs.cargo_stacks[key] = {name = stack.name, quality = quality}
    rs.cargo_count = rs.cargo_count + stack.count
    if prefer_existing_container then
        -- Boolean false is an intentional sentinel distinct from nil:
        -- false = search for a suitable existing container;
        -- nil   = no container preference, deliver to the player.
        rs.cargo_destinations[key] = false
    end
end

---Advance delivery of the current cargo type.
---Returns true only when the entire ordered manifest is empty. A false result
---means scanning, travel, insertion, or a later item type still needs work.
function M.flush_cargo(rs, player, bot)
    rs.cargo_order = rs.cargo_order or {};
    rs.cargo_cursor = rs.cargo_cursor or 1;
    local key = rs.cargo_order[rs.cargo_cursor]
    if not key then
        return true
    end
    local stack = rs.cargo_stacks and rs.cargo_stacks[key] or {name = key, quality = "normal"}
    local name, quality = stack.name, stack.quality
    -- Old saves or partially initialized roles may have an order array without
    -- a cargo table. The temporary empty table makes that mismatch a missing
    -- count, which the cursor repair branch below can skip safely.
    local count = (rs.cargo or {})[key]
    if not count then
        rs.cargo_cursor = rs.cargo_cursor + 1;
        return false
    end
    local destination = rs.cargo_destinations and rs.cargo_destinations[key];
    local prefer_lowest_inventory = rs.cargo_lowest_inventory and rs.cargo_lowest_inventory[key]
    local inserted
    if destination == false then
        if prefer_lowest_inventory then
            rs.waiting_ammo_container = true
        end
        -- Cleanup prefers a nearby friendly container which already stores the
        -- same item, keeping factory organization intact. Search incrementally.
        local job = rs.drop_job
        if not job or job.name ~= name or job.quality ~= quality then
            job = {
                name = name,
                quality = quality,
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
                if inv and inv.get_item_count {name = name, quality = quality} > 0 and inv.can_insert {
                    name = name,
                    count = 1,
                    quality = quality
                } then
                    -- Only relative ordering matters, so squared distance is
                    -- both exact enough and cheaper than Euclidean distance.
                    local d = movement.distance2(e.position, bot.position);
                    local load = prefer_lowest_inventory and inv.get_item_count() or nil
                    if not job.source or (prefer_lowest_inventory and
                        (load < job.load or (load == job.load and d < job.distance))) or
                        (not prefer_lowest_inventory and d < job.distance) then
                        job.source = e;
                        job.load = load
                        job.distance = d
                    end
                end
            end
            return false
        end
        -- Cleanup falls back to the player when no same-item container has
        -- capacity. Ammo remains onboard instead: formation following moves
        -- the next bounded scan to a new area, matching its pre-pickup wait.
        destination = job.source;
        if prefer_lowest_inventory and not destination then
            rs.drop_job = nil
            return false
        end
        rs.cargo_destinations[key] = destination or nil;
        if prefer_lowest_inventory then
            rs.waiting_ammo_container = nil
        end
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
            count = count,
            quality = quality
        } or 0
    else
        -- Never modify player inventory remotely. Fly to the player's live
        -- position before returning recovered or unused items.
        if not movement.step(bot, player.position) then
            return false
        end
        inserted = M.player_give(player, {
            name = name,
            count = count,
            quality = quality
        })
    end
    count = count - inserted;
    rs.cargo_count = math.max(0, (rs.cargo_count or 0) - inserted);
    -- Removing a completed key rather than retaining zero keeps `cargo` a map
    -- of real outstanding work and allows a future stack of this name to be
    -- appended to the ordered manifest again.
    rs.cargo[key] = count > 0 and count or nil
    if count == 0 then
        if rs.cargo_destinations then
            rs.cargo_destinations[key] = nil
        end
        if rs.cargo_stacks then rs.cargo_stacks[key] = nil end
        if rs.cargo_lowest_inventory then rs.cargo_lowest_inventory[key] = nil end
        if prefer_lowest_inventory then rs.waiting_ammo_container = nil end
        rs.cargo_cursor = rs.cargo_cursor + 1
    elseif destination and prefer_lowest_inventory then
        -- Ammo delivery may fill a matching container before the carried stack
        -- is empty. Keep the remainder and find the next least-loaded matching
        -- container instead of retrying the now-full destination forever.
        rs.cargo_destinations[key] = false
        rs.waiting_ammo_container = true
        rs.drop_job = nil
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
function M.take(rs, player, target, bot, name, count, withdraw_count, accept_any_quality)
    rs.supplied = rs.supplied or {};
    rs.supplied_sources = rs.supplied_sources or {}
    local requested = withdraw_count or count
    local carried = rs.supplied[name] or 0
    if carried > 0 then
        -- `supplied` is a one-call staging area. A container withdrawal returns
        -- nil first (after travel), then this branch supplies it on the next
        -- controller call, preserving the bounded state-machine contract.
        local used = math.min(count, carried);
        rs.supplied[name] = carried - used;
        rs.last_source = rs.supplied_sources[name]
        rs.last_quality = rs.supplied_qualities and rs.supplied_qualities[name] or "normal"
        if rs.supplied[name] == 0 then
            rs.supplied_sources[name] = nil
            if rs.supplied_qualities then rs.supplied_qualities[name] = nil end
        end
        -- A player withdrawal keeps this marker through staging so target
        -- navigation cannot resume between pickup and this handoff.
        if rs.player_supply_name == name then
            rs.player_supply_name = nil
        end
        return used
    end
    -- A player fallback selected after a completed container scan must resume
    -- that trip directly. Restarting the scan on every tick would prevent a
    -- distant bot from ever reaching the player.
    if rs.player_supply_name == name then
        return take_from_player(rs, player, bot, name, requested, accept_any_quality)
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
    local got = 0
    if player_first then
        got = take_from_player(rs, player, bot, name, requested, accept_any_quality)
        if got == nil then
            return nil
        end
    end
    if not use_containers then
        return player_first and got or take_from_player(rs, player, bot, name, requested, accept_any_quality)
    end
    rs.source_cache = rs.source_cache or {};
    local cached = rs.source_cache[name]
    if cached and cached.valid then
        -- Reusing a known source avoids repeating a radius scan for successive
        -- construction/upgrade items, but its live contents are revalidated.
        local inv = M.entity_inventory(cached);
        local quality = inv and inventory_quality(inv, name, accept_any_quality,
            rs.supplied_qualities and rs.supplied_qualities[name])
        if quality then
            if not movement.step(bot, cached.position) then
                return nil
            end
            got = inv.remove {
                name = name,
                count = requested,
                quality = quality
            };
            if got > 0 then
                -- Stage the removed amount instead of returning it immediately.
                -- Returning nil tells the controller that this work unit was
                -- spent travelling/withdrawing; the next call consumes it from
                -- `supplied` and performs the actual target action.
                rs.supplied[name] = got;
                rs.supplied_qualities = rs.supplied_qualities or {}
                rs.supplied_qualities[name] = quality
                rs.supplied_sources[name] = cached;
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
            local quality = inv and inventory_quality(inv, name, accept_any_quality)
            if quality then
                -- Select the nearest source by squared Euclidean distance.
                local d = movement.distance2(e.position, bot.position);
                if not job.distance or d < job.distance then
                    job.source = e;
                    job.quality = quality;
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
        return player_first and 0 or take_from_player(rs, player, bot, name, requested, accept_any_quality)
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
        count = requested,
        quality = job.quality or "normal"
    };
    rs.supply_job = nil
    if got > 0 then
        rs.supplied[name] = got;
        rs.supplied_qualities = rs.supplied_qualities or {}
        rs.supplied_qualities[name] = job.quality or "normal"
        rs.supplied_sources[name] = job.source;
        rs.last_source = job.source;
        rs.source_cache[name] = job.source;
        return nil
    end
    return 0
end

---Poll for an item after a role has exhausted every configured supply source.
---The bot remains formation-idle while searches find nothing.  Once a player
---or container inventory has stock, stage the item for the original action and
---allow normal target movement to resume.
function M.wait_for_item(rs, player, target, bot)
    local name = rs.waiting_inventory
    if not name then
        return true, "moving"
    end
    local got = M.take(rs, player, target, bot, name, 1, nil, rs.waiting_accept_any_quality)
    local taken_source = rs.last_source
    local taken_quality = rs.last_quality
    local staged = rs.supplied and (rs.supplied[name] or 0) or 0
    if got and got > 0 then
        rs.supplied = rs.supplied or {}
        rs.supplied_sources = rs.supplied_sources or {}
        rs.supplied[name] = staged + got
        rs.supplied_sources[name] = taken_source
        rs.supplied_qualities = rs.supplied_qualities or {}
        rs.supplied_qualities[name] = taken_quality or "normal"
        rs.waiting_inventory = nil
        rs.waiting_accept_any_quality = nil
        return true, "moving"
    end
    if staged > 0 then
        rs.waiting_inventory = nil
        rs.waiting_accept_any_quality = nil
        return true, "moving"
    end
    -- `take` owns movement after finding either a real container source or
    -- matching stock in the player's inventory. Empty scans leave formation
    -- movement free.
    local cached = rs.source_cache and rs.source_cache[name]
    local job = rs.supply_job
    local source = (cached and cached.valid and cached) or
                       (job and job.scan and job.scan.done and job.source and job.source.valid and job.source)
    return false, (rs.player_supply_name == name or source) and "moving" or "idle"
end

return M
