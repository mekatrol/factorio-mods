-- Role state machines. Scan/planning phases yield after one cell; action phases handle one target.
local config = require("config")
local scanner = require("entity_scanner")
local discovery = require("discovery")
local movement = require("movement")
local supply = require("supply")
local track = require("track")
local pathfinding = require("pathfinding")
local visuals = require("visuals")
local survey = require("survey")
local polygon = require("polygon")
local state = require("state")
local logistics = require("logistics")
local M = {}

-- Convert the configured ignore list to a set once. Target checks occur often,
-- so O(1) membership is preferable to repeatedly scanning an array.
local ignored_repair = {};
for _, name in ipairs(config.tasks.repair.ignored_names or {}) do
    ignored_repair[name] = true
end

-- Mapping records stationary world features only. Mobile/transient entity
-- types would create stale map records almost immediately after discovery.
local mobile = {
    character = true,
    car = true,
    ["spider-vehicle"] = true,
    locomotive = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
    unit = true,
    corpse = true,
    ["character-corpse"] = true,
    fish = true,
    ["combat-robot"] = true,
    ["construction-robot"] = true,
    ["logistic-robot"] = true,
    projectile = true,
    beam = true,
    ["flying-text"] = true,
    smoke = true,
    fire = true,
    stream = true
}
local upgrades = config.tasks.upgrade.mappings

-- Coarse Factorio query filters reduce the candidate set cheaply. The richer
-- per-role policy which needs state, recipes, or prototypes lives in
-- `valid_target` below.
local filters = {
    builder = {
        type = "entity-ghost",
        force = "player"
    },
    repair = {
        force = "player"
    },
    upgrade = {
        name = {}
    },
    track = {
        type = {"transport-belt", "underground-belt", "splitter"}
    },
    lamp = {
        type = {"electric-pole", "lamp"}
    },
    cliff = {
        type = "cliff"
    },
    logistics = {
        type = {"item-entity", "simple-entity", "simple-entity-with-owner", "container", "resource"}
    },
    cleanup = {
        type = "item-entity"
    },
    mapper = {},
    surveyor = {
        type = "resource"
    }
}

for name in pairs(upgrades) do
    filters.upgrade.name[#filters.upgrade.name + 1] = name
end
table.sort(filters.upgrade.name)

local radii = {
    builder = "builder",
    repair = "repair",
    upgrade = "upgrade",
    track = "track",
    lamp = "lamp",
    cliff = "cliff",
    logistics = "logistics",
    cleanup = "cleanup",
    mapper = nil,
    surveyor = "surveyor"
}

---Return the mapper's next cell in an outward square spiral.
---
---Directions cycle right, down, left, up. Leg lengths follow
---`1,1,2,2,3,3,...`: after each leg the direction turns 90 degrees, and after
---each pair of legs the length grows by one. This enumerates every grid cell
---around the origin without retaining an unbounded queue of future cells.
local function mapper_area(rs, anchor)
    if rs.mapper_surface ~= anchor.surface.index then
        -- Changing surfaces starts a new spiral centered on the current anchor.
        rs.mapper_surface = anchor.surface.index
        rs.mapper_origin = {x = anchor.position.x, y = anchor.position.y}
        rs.mapper_leg, rs.mapper_leg_progress, rs.mapper_leg_length = 0, 0, 1
        rs.mapper_x, rs.mapper_y, rs.mapper_direction = 0, 0, 1
    end
    local s = config.scanning.cell_size
    local x = math.floor(rs.mapper_origin.x / s) + rs.mapper_x
    local y = math.floor(rs.mapper_origin.y / s) + rs.mapper_y
    local area = {{x * s, y * s}, {(x + 1) * s, (y + 1) * s}}
    -- Direction-indexed unit vectors apply one cell step along the current leg.
    local dx = ({1, 0, -1, 0})[rs.mapper_direction]
    local dy = ({0, 1, 0, -1})[rs.mapper_direction]
    rs.mapper_x, rs.mapper_y = rs.mapper_x + dx, rs.mapper_y + dy
    rs.mapper_leg_progress = rs.mapper_leg_progress + 1
    if rs.mapper_leg_progress >= rs.mapper_leg_length then
        rs.mapper_leg_progress = 0
        rs.mapper_direction = rs.mapper_direction % 4 + 1
        rs.mapper_leg = rs.mapper_leg + 1
        if rs.mapper_leg % 2 == 0 then
            rs.mapper_leg_length = rs.mapper_leg_length + 1
        end
    end
    return area
end

---Initialize one bounded scan appropriate to a role and its current task.
local function begin(role, rs, anchor)
    -- Every finite service role maps to a task radius. Mapper is the exception:
    -- it scans one spiral cell, represented by nil here and handled below.
    local radius = role ~= "mapper" and config.tasks[radii[role]].radius or nil
    if role == "upgrade" then
        -- Specialized upgrade modes may narrow their search. Combined mode has
        -- no override and therefore falls back to the general upgrade radius.
        radius = config.tasks.upgrade.mode_radii[rs.task] or radius
    end
    local f = {};
    for k, v in pairs(filters[role]) do
        f[k] = v
    end
    -- `player` in the static filter is a stage-independent placeholder. Runtime
    -- scanning needs the actual anchor force object, including custom forces.
    if f.force == "player" then
        f.force = anchor.force
    end
    if role == "mapper" then
        rs.scan = scanner.start_area(anchor.surface, mapper_area(rs, anchor), f)
    else
        rs.scan = scanner.start(anchor.surface, anchor.position, radius, f)
    end
    rs.phase = "scan"
end

---Return whether an entity belongs to the player and is below repair threshold.
---Multiplying max health by a ratio makes the policy scale across prototypes
---with very different health totals.
function M.is_repair_target(e, anchor)
    -- The left-to-right guards are significant: some entity types have neither
    -- health nor maximum health, so those fields must exist before arithmetic.
    return anchor and e.force == anchor.force and not ignored_repair[e.name] and e.health and e.max_health and
               e.health < e.max_health * config.tasks.repair.threshold
end

---Apply role-specific eligibility rules after the coarse scanner filter.
---This function is intentionally side-effect free so the same rule can be used
---for freshly scanned, discovered, and connected-belt candidates.
local function valid_target(role, e, rs, anchor)
    if role == "mapper" then
        return not mobile[e.type]
    end
    if role == "cliff" then
        return state.root().cliffs[discovery.identity(e)] == true
    end
    if role == "repair" then
        return M.is_repair_target(e, anchor)
    end
    if role == "upgrade" then
        local target = upgrades[e.name];
        local recipe = anchor and anchor.force.recipes[target];
        if not target or not prototypes.entity[target] or not prototypes.item[target] or (recipe and not recipe.enabled) then
            return false
        end
        -- Pure tests may call target validation without role state. Combined is
        -- the broad, backward-compatible policy in that case.
        local task = rs and rs.task or "combined"
        if task == "yellow-to-red-belts" then
            return e.name == "transport-belt" or e.name == "underground-belt" or e.name == "splitter"
        end
        if task == "red-to-blue-belts" then
            return e.name == "fast-transport-belt" or e.name == "fast-underground-belt" or e.name == "fast-splitter"
        end
        if task == "blue-to-green-inserters" then
            return e.name == "fast-inserter"
        end
        if task == "containers" then
            return e.name == "wooden-chest" or e.name == "iron-chest"
        end
        return true
    end
    if role == "track" then
        local target = upgrades[e.name];
        local recipe = target and anchor and anchor.force.recipes[target];
        return target ~= nil and prototypes.entity[target] ~= nil and prototypes.item[target] ~= nil and
                   (not recipe or recipe.enabled) and
                   (e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter")
    end
    if role == "lamp" then
        return e.type == "electric-pole" and e.electric_network_id ~= nil and e.surface.can_place_entity {
            name = "small-lamp",
            position = {e.position.x + 2, e.position.y},
            force = e.force
        }
    end
    if role == "surveyor" then
        local d = state.root().discovery;
        return not (d.grouped and d.grouped[discovery.identity(e)])
    end
    if role == "logistics" then
        -- Some minable world entities expose no force; others explicitly use
        -- `neutral`. Both mean logistics may collect them without stealing from
        -- another player or an enemy force.
        local neutral = not e.force or e.force.name == "neutral"
        return (e.type == "item-entity" or (e.minable and neutral)) and
                   logistics.matches_pickup(e, rs and rs.pickup_name)
    end
    return true
end

---Fast-replace an entity while preserving direction, force, and last user.
---Underground belts also require their input/output type to preserve topology.
local function replace(e, name)
    if not prototypes.entity[name] then
        return false
    end
    local p = {
        name = name,
        position = e.position,
        direction = e.direction,
        force = e.force,
        player = e.last_user,
        fast_replace = true,
        spill = false,
        raise_built = true
    }
    if e.type == "underground-belt" then
        p.type = e.belt_to_ground_type
    end
    return e.surface.create_entity(p) ~= nil
end

-- Repair durability is a persistent pool: packs are consumed only when the
-- pool cannot cover a bounded repair action, so partial packs survive save/load.
local function repair_entity(rs, anchor, e)
    if not (e and e.valid and e.health and e.max_health) then
        return true
    end
    -- Bound healing per scheduler action so one large entity cannot consume an
    -- arbitrary amount of work or inventory in a single tick.
    local need = math.min(e.max_health - e.health, config.tasks.repair.health_per_action)
    if need <= 0 then
        return true
    end
    -- The pool was added after early save versions, and zero also represents a
    -- new role with no partially used pack.
    rs.repair_health_pool = rs.repair_health_pool or 0
    if rs.repair_health_pool < need then
        -- Convert missing durability to whole packs. Ceiling is required: any
        -- positive fractional deficit still needs one complete inventory item.
        local packs = math.ceil((need - rs.repair_health_pool) / config.supply.repair_pack_durability)
        local got = supply.take(rs, anchor.player, e, rs.entity or e, "repair-pack", packs)
        if got == nil then
            return false
        end
        rs.repair_health_pool = rs.repair_health_pool + got * config.supply.repair_pack_durability
        if got == 0 then
            if not rs.out_of_repair_packs_warned then
                anchor.player.print("[MAB] repair bot is out of repair packs")
                rs.out_of_repair_packs_warned = true
            end
            return true
        end
        rs.out_of_repair_packs_warned = nil
    end
    local repaired = math.min(need, rs.repair_health_pool)
    e.health = math.min(e.max_health, e.health + repaired)
    rs.repair_health_pool = rs.repair_health_pool - repaired
    visuals.health(discovery.identity(e), e)
    return e.health >= e.max_health * config.tasks.repair.threshold
end

---Perform one bounded action on a target.
---Returns false only when a supporting supply job must continue first; true
---means this action can be considered complete for the current target.
local function act(role, rs, anchor, e)
    if not e or not e.valid then
        return true
    end
    if role == "mapper" then
        discovery.add(e);
        return true
    end
    if role == "surveyor" then
        discovery.add(e);
        local d = state.root().discovery;
        local job = rs.survey_job
        -- A surveyed patch is identified by surface, resource prototype, and
        -- trace seed. Including the surface prevents identical map coordinates
        -- on Nauvis and another surface from merging.
        local k = e.surface.index .. ":" .. e.name .. ":" .. job.start_x .. ":" .. job.start_y
        -- Reuse a prior group when another entity resolves to the same patch;
        -- otherwise initialize its membership and bounds from this target.
        local g = d.groups[k] or {
            name = e.name,
            surface_index = e.surface.index,
            entities = {},
            bounds = {
                left = e.position.x,
                right = e.position.x,
                top = e.position.y,
                bottom = e.position.y
            }
        }
        for id in pairs(job.entities or {}) do
            g.entities[id] = true
            d.grouped = d.grouped or {}
            d.grouped[id] = k
        end
        local b = g.bounds;
        b.left = math.min(b.left, e.position.x);
        b.right = math.max(b.right, e.position.x);
        b.top = math.min(b.top, e.position.y);
        b.bottom = math.max(b.bottom, e.position.y)
        -- Three vertices are the minimum polygon. If tracing could not produce
        -- them, use a half-tile-expanded bounding rectangle around resources.
        g.polygon = (job and #job.points >= 3) and job.points or {{
            x = b.left - 0.5,
            y = b.top - 0.5
        }, {
            x = b.right + 0.5,
            y = b.top - 0.5
        }, {
            x = b.right + 0.5,
            y = b.bottom + 0.5
        }, {
            x = b.left - 0.5,
            y = b.bottom + 0.5
        }}
        if job and #job.points >= 3 then
            g.area = job.area or 0;
            g.perimeter = job.perimeter or 0
        else
            -- Resource positions are tile centers, so inclusive width/height
            -- are coordinate span + 1. Rectangle area is w*h and perimeter is
            -- twice the sum of its side lengths.
            local w, h = b.right - b.left + 1, b.bottom - b.top + 1;
            g.area = w * h;
            g.perimeter = 2 * (w + h)
        end
        d.groups[k] = g;
        return true
    end
    if role == "repair" then
        return repair_entity(rs, anchor, e)
    end
    if role == "cleanup" then
        local stack = e.stack;
        if stack and stack.valid_for_read then
            -- Capacity is global across carried item types. Clamp at zero in
            -- case an older save already contains more than the new limit.
            -- `cargo_count` is absent in saves from before bounded cleanup
            -- cargo, so nil means the bot is currently carrying zero items.
            local free = math.max(0, config.supply.cleanup_capacity - (rs.cargo_count or 0));
            local count = math.min(stack.count, free);
            if count > 0 then
                local name, total = stack.name, stack.count;
                if count >= total then
                    e.destroy()
                else
                    stack.count = total - count
                end
                supply.queue_cargo(rs, {
                    name = name,
                    count = count
                }, true)
            end
        end
        return true
    end
    if role == "logistics" and e.type == "item-entity" then
        local stack = e.stack;
        if stack and stack.valid_for_read then
            local total = stack.count;
            local inserted = supply.player_give(anchor.player, {
                name = stack.name,
                count = total,
                quality = stack.quality
            });
            if inserted > 0 then
                if rs.pickup_remaining then
                    rs.pickup_remaining = math.max(0, rs.pickup_remaining - inserted)
                end
                if inserted >= total then
                    e.destroy()
                else
                    stack.count = total - inserted
                end
            end
        end
        return not rs.pickup_remaining or rs.pickup_remaining <= 0 or not e.valid
    end
    if role == "logistics" then
        local player_inv = anchor.player.get_main_inventory();
        if e.type == "resource" then
            if not player_inv or not e.amount or e.amount <= 0 then
                return true
            end
            local products = e.prototype and e.prototype.mineable_properties and e.prototype.mineable_properties.products
            local name = products and products[1] and products[1].name
            if not name then
                return true
            end
            -- One action is bounded by policy, remaining resource quantity,
            -- and the explicit command quantity (when one was requested).
            local amount = math.min(config.tasks.logistics.resource_units_per_action, e.amount,
                rs.pickup_remaining or math.huge)
            local inserted = player_inv.insert {name = name, count = amount}
            if inserted <= 0 then
                return true
            end
            e.amount = e.amount - inserted
            if rs.pickup_remaining then
                rs.pickup_remaining = math.max(0, rs.pickup_remaining - inserted)
            end
            if e.amount <= 0 and e.valid then
                e.deplete()
            end
            -- Depletion invalidates the resource entity. Otherwise a finite
            -- pickup request completes at zero; an ordinary collect task has no
            -- remaining counter and continues until the target is exhausted.
            return not e.valid or (rs.pickup_remaining and rs.pickup_remaining <= 0)
        end
        local contents = supply.entity_inventory(e)
        if contents then
            local job = rs.collect_job;
            if not job or job.entity ~= e then
                job = {
                    entity = e,
                    cursor = 1
                };
                rs.collect_job = job
            end
            -- Inclusive stop index: cursor + N - 1 processes at most N slots.
            local stop = math.min(#contents, job.cursor + config.tasks.logistics.inventory_slots_per_action - 1)
            while job.cursor <= stop do
                local stack = contents[job.cursor];
                if stack.valid_for_read then
                    -- A player without a main inventory (possible in controller
                    -- modes) inserts zero and leaves the source stack untouched.
                    local inserted = player_inv and player_inv.insert {
                        name = stack.name,
                        count = stack.count,
                        quality = stack.quality
                    } or 0;
                    if inserted > 0 then
                        stack.count = stack.count - inserted
                    end
                    if stack.valid_for_read then
                        return false
                    end
                end
                job.cursor = job.cursor + 1;
            end
            if job.cursor <= #contents then
                return false
            end
            rs.collect_job = nil
        end
        if player_inv and e.minable then
            e.mine {
                inventory = player_inv,
                force = true,
                raise_destroyed = true
            }
        end
        return true
    end
    if role == "builder" then
        local name = logistics.placement_item(e);
        if name then
            local got = supply.take(rs, anchor.player, e, rs.entity or e, name, 1);
            if got == nil then
                return false
            end
            if got > 0 then
                local source = rs.last_source;
                rs.last_source = nil;
                -- `revive` consumes the ghost and creates the real entity. It
                -- can still fail after the earlier checks if world state changed.
                local revived = e.revive {
                    raise_revive = true
                };
                if not revived then
                    supply.give_or_carry(rs, anchor.player, {
                        name = name,
                        count = 1
                    }, source)
                end
            end
        end
        return true
    end
    if role == "upgrade" or role == "track" then
        local old = e.name;
        local name = upgrades[old];
        local recipe = name and anchor.force.recipes[name];
        if name and (not recipe or recipe.enabled) then
            local got = supply.take(rs, anchor.player, e, rs.entity or e, name, 1);
            if got == nil then
                return false
            end
            if got > 0 then
                local source = rs.last_source;
                rs.last_source = nil;
                if replace(e, name) then
                    -- Successful fast replacement returns the removed lower-tier
                    -- item to its source/player. Failure returns the unused new
                    -- item instead, so upgrades never silently destroy inventory.
                    supply.give_or_carry(rs, anchor.player, {
                        name = old,
                        count = 1
                    }, source)
                else
                    supply.give_or_carry(rs, anchor.player, {
                        name = name,
                        count = 1
                    }, source)
                end
            end
        end
        return true
    end
    if role == "cliff" then
        local got = supply.take(rs, anchor.player, e, rs.entity or e, "cliff-explosives", 1);
        if got == nil then
            return false
        end
        if got > 0 then
            local source = rs.last_source;
            rs.last_source = nil;
            local id = discovery.identity(e);
            local projectile = e.surface.create_entity {
                name = "cliff-explosives",
                position = rs.entity.position,
                target = e.position,
                speed = config.tasks.cliff.projectile_speed,
                force = anchor.force
            };
            if projectile then
                state.root().cliffs[id] = nil;
                visuals.clear_role("cliff:" .. id)
            else
                supply.give_or_carry(rs, anchor.player, {
                    name = "cliff-explosives",
                    count = 1
                }, source)
            end
        end
        return true
    end
    if role == "lamp" then
        -- Darkness is normalized from 0 (day) to 1 (dark). Returning nil here
        -- is acceptable to `step`: it means no completed action yet and the bot
        -- may reconsider the same pole when lighting conditions change.
        if anchor.surface.darkness < config.tasks.lamp.darkness then
            return
        end
        local pos = {
            x = e.position.x + 2,
            y = e.position.y
        };
        if anchor.surface.can_place_entity {
            name = "small-lamp",
            position = pos,
            force = anchor.force
        } then
            local got = supply.take(rs, anchor.player, e, rs.entity or e, "small-lamp", 1);
            if got == nil then
                return false
            end
            if got > 0 then
                local source = rs.last_source;
                rs.last_source = nil;
                if not anchor.surface.create_entity {
                    name = "small-lamp",
                    position = pos,
                    force = anchor.force,
                    player = anchor.player,
                    raise_built = true
                } then
                    supply.give_or_carry(rs, anchor.player, {
                        name = "small-lamp",
                        count = 1
                    }, source)
                end
            end
        end
    end
    return true
end

---Advance one role state machine by one scheduler work unit.
---
---The common lifecycle is discovery handoff -> bounded scan -> nearest target
---> optional group/path planning -> movement -> one action -> reset. Every
---long-running sub-operation stores a cursor/job in `rs`, allowing the next
---tick (or a reloaded save) to resume exactly where this call stopped.
function M.step(role, rs, anchor, bot)
    -- A repair bot prioritizes itself below the configured safety threshold;
    -- an incapacitated service bot cannot help anything else reliably.
    if role == "repair" and bot.health and bot.max_health and
        bot.health < bot.max_health * config.tasks.repair.self_repair_threshold then
        repair_entity(rs, anchor, bot)
        return "working"
    end
    if rs.target and not rs.target.valid then
        -- LuaEntity references become invalid when another player or mod
        -- removes them. Clear all calculations derived from that entity.
        rs.target = nil
        rs.target_visualized = nil
        rs.path_job = nil
        rs.best_distance = nil
    end
    if role == "logistics" and rs.pickup_remaining and rs.pickup_remaining <= 0 then
        -- Completing a finite pickup request returns logistics to its normal
        -- opportunistic collection mode.
        rs.pickup_name = nil
        rs.pickup_remaining = nil
        rs.task = "collect"
        rs.scan = nil
        rs.target = nil
    end
    if not rs.scan and not rs.target and
        (role == "repair" or role == "logistics" or role == "surveyor" or role == "builder") then
        -- Prefer shared mapper/event discoveries. Each role owns an independent
        -- cursor, so accepting a record never steals it from another consumer.
        local candidate, exhausted = discovery.next_for(rs, role);
        if candidate and candidate.valid and candidate.surface == anchor.surface and
            valid_target(role, candidate, rs, anchor) then
            rs.target = candidate;
            rs.best_distance = movement.distance2(candidate.position, bot.position)
        end
        -- One handoff record is examined per work unit. If it was unsuitable
        -- but more records remain, yield instead of falling through to a full
        -- spatial scan in the same scheduler unit.
        if not rs.target and not exhausted then
            return "idle"
        end
    end
    if not rs.scan and not rs.target then
        begin(role, rs, anchor);
        return "idle"
    end
    if rs.scan and not rs.scan.done then
        local _, found = scanner.step(rs.scan)
        for _, e in ipairs(found) do
            if role == "mapper" then
                if valid_target(role, e, rs, anchor) then
                    discovery.add(e)
                end
            elseif valid_target(role, e, rs, anchor) then
                -- Squared distance is enough for ordering and avoids sqrt for
                -- every candidate returned by the scanner.
                local d = movement.distance2(e.position, bot.position);
                if not rs.best_distance or d < rs.best_distance then
                    rs.target = e;
                    rs.best_distance = d
                end
            end
        end
        -- Scanning is background work; passive service bots should keep their
        -- formation until an actual target has been selected.
        -- Repair and cleanup are passive services and should visually remain in
        -- formation while searching. Other roles display moving to communicate
        -- that an active search task is under way.
        return (role == "repair" or role == "cleanup") and "idle" or "moving"
    end
    if rs.track_job and rs.track_job.done and (not rs.target or not rs.target.valid) then
        local candidate, complete = track.next(rs.track_job, function(e)
            return valid_target(role, e, rs, anchor)
        end);
        rs.target = candidate
        if not candidate and not complete then
            return "moving"
        end
        if complete then
            rs.track_job = nil;
            rs.track_started = nil;
            rs.scan = nil;
            rs.best_distance = nil;
            return "idle"
        end
    end
    if not rs.target then
        rs.scan = nil;
        rs.best_distance = nil;
        rs.phase = "idle";
        return "idle"
    end
    if not rs.target_visualized then
        visuals.target_line(rs.visual_key or role, bot, rs.target, anchor.player.index);
        rs.target_visualized = true
    end
    -- Track always consumes a connected belt graph. Upgrade does so only after
    -- selecting a belt-family target (or while an existing graph job resumes);
    -- inserters and containers remain isolated upgrades.
    local grouped = (role == "track") or (role == "upgrade" and (rs.track_job or (rs.target and rs.target.valid and
                        (rs.target.type == "transport-belt" or rs.target.type == "underground-belt" or rs.target.type ==
                            "splitter"))))
    if grouped then
        -- Belt entities are a graph rather than isolated targets. First finish
        -- the bounded breadth-first traversal, then act on its stable list one
        -- entity per scheduler opportunity.
        if not rs.track_job then
            rs.track_job = track.start(rs.target);
            return "moving"
        end
        if not rs.track_job.done then
            track.step(rs.track_job);
            return "moving"
        end
        if not rs.track_started then
            rs.track_started = true;
            rs.target = nil
        end
        if not rs.target or not rs.target.valid then
            local candidate, complete = track.next(rs.track_job, function(e)
                return valid_target(role, e, rs, anchor)
            end);
            rs.target = candidate;
            if not candidate and not complete then
                return "moving"
            end
            if complete then
                rs.track_job = nil;
                rs.track_started = nil;
                rs.scan = nil;
                rs.best_distance = nil;
                return "idle"
            end
        end
    end
    if role == "repair" then
        if not rs.path_job then
            rs.path_job =
                -- Stop within interaction distance instead of entering the
                -- target's occupied tile. floor converts the world radius into
                -- the pathfinder's integer Manhattan tolerance.
                pathfinding.start(anchor.surface, bot.position, rs.target.position, config.tasks.repair.radius,
                    math.max(1, math.floor(config.tasks.repair.interaction_distance)));
            return "moving"
        end
        if not rs.path_job.done then
            pathfinding.step(rs.path_job);
            return "moving"
        end
        if rs.path_job.failed then
            rs.target = nil
            rs.target_visualized = nil
            rs.path_job = nil
            rs.best_distance = nil
            rs.scan = nil
            return "idle"
        end
        if rs.path_job.path and rs.path_job.cursor >= 1 then
            if movement.step(bot, rs.path_job.path[rs.path_job.cursor]) then
                rs.path_job.cursor = rs.path_job.cursor - 1
            end
            return "moving"
        end
        -- Squared-radius comparison avoids sqrt on every repair work unit.
        if movement.distance2(bot.position, rs.target.position) <= config.tasks.repair.interaction_distance ^ 2 then
            if not act(role, rs, anchor, rs.target) then
                return "working"
            end
            if rs.target.valid and valid_target(role, rs.target, rs, anchor) then
                return "working"
            end
            rs.target = nil;
            rs.target_visualized = nil;
            rs.path_job = nil;
            rs.best_distance = nil;
            rs.scan = nil
            return "working"
        end
    end
    if not movement.step(bot, rs.target.position) then
        return "moving"
    end
    if role == "surveyor" then
        if not rs.survey_job then
            rs.survey_job = survey.start(rs.target);
            return "working"
        end
        if not rs.survey_job.done then
            survey.step(rs.survey_job);
            return "working"
        end
        if not rs.survey_job.collect_scan then
            -- The traced polygon gives an economical bounding box. Expand by
            -- one tile so entities centered on the contour are not clipped.
            local left, right, top, bottom = rs.target.position.x, rs.target.position.x,
                rs.target.position.y, rs.target.position.y
            for _, point in ipairs(rs.survey_job.points) do
                left, right = math.min(left, point.x), math.max(right, point.x)
                top, bottom = math.min(top, point.y), math.max(bottom, point.y)
            end
            rs.survey_job.entities = {}
            rs.survey_job.collect_scan = scanner.start_area(anchor.surface,
                {{left - 1, top - 1}, {right + 1, bottom + 1}}, {name = rs.target.name, type = "resource"})
            return "working"
        end
        if not rs.survey_job.collect_scan.done then
            local _, found = scanner.step(rs.survey_job.collect_scan)
            for _, found_entity in ipairs(found) do
                -- Rectangle scanning finds candidates; the point-in-polygon
                -- test removes resources from neighbouring or enclosed patches.
                if polygon.contains(rs.survey_job.points, found_entity.position) then
                    local id = discovery.identity(found_entity)
                    rs.survey_job.entities[id] = true
                    discovery.add(found_entity)
                end
            end
            return "working"
        end
    end
    if not act(role, rs, anchor, rs.target) then
        return "working"
    end
    if grouped then
        local candidate, complete = track.next(rs.track_job, function(e)
            return valid_target(role, e, rs, anchor)
        end);
        rs.target = candidate;
        rs.target_visualized = nil;
        if rs.target or not complete then
            return "working"
        end
        rs.track_job = nil;
        rs.track_started = nil
    end
    rs.target = nil;
    -- A completed isolated action, survey, or group clears all transient jobs.
    -- The next call may consume another discovery or begin a fresh scan.
    rs.target_visualized = nil;
    rs.path_job = nil;
    rs.survey_job = nil;
    rs.best_distance = nil;
    rs.scan = nil;
    rs.phase = "idle";
    return "working"
end

return M
