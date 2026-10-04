-- Repair role policy: find damaged friendly entities and approach them with A*.
local config = require("config")
local discovery = require("discovery")
local movement = require("movement")
local pathfinding = require("pathfinding")
local supply = require("supply")
local visuals = require("visuals")
local M = {
    tasks = {"follow", "move_to", "repair"},
    handoff = true,
    scan_phase = "idle"
}

-- Target checks are frequent, so convert the configured ignore array to an
-- O(1) membership set once when the role module is loaded.
local ignored = {}
for _, name in ipairs(config.tasks.repair.ignored_names or {}) do
    ignored[name] = true
end

function M.radius()
    return config.tasks.repair.radius
end

function M.filter(_, anchor)
    return {force = anchor.force}
end

---Accept friendly, damageable entities below the configured health ratio.
function M.valid(entity, _, anchor)
    return anchor and entity.force == anchor.force and not ignored[entity.name] and entity.health and
               entity.max_health and entity.health < entity.max_health * config.tasks.repair.threshold
end

---Spend persistent repair-pack durability on one bounded healing action.
---Unused durability remains on the role record across targets and save/load,
---ensuring each consumed pack contributes exactly the configured health total.
function M.act(rs, anchor, entity)
    if not (entity and entity.valid and entity.health and entity.max_health) then
        return true
    end
    -- `health_needed_this_action` is measured in entity health points and is
    -- capped so one heavily damaged entity cannot consume an entire tick.
    local missing_entity_health = entity.max_health - entity.health
    local health_needed_this_action = math.min(missing_entity_health, config.tasks.repair.health_per_action)
    if health_needed_this_action <= 0 then
        return true
    end
    -- The pool is unused repair-pack durability, also measured in health points.
    -- Saves made before this field existed are equivalent to an empty pool.
    rs.repair_health_pool = rs.repair_health_pool or 0
    if rs.repair_health_pool < health_needed_this_action then
        local durability_deficit = health_needed_this_action - rs.repair_health_pool
        -- Ceiling is required because any positive partial-pack deficit needs a
        -- complete inventory item before its durability can enter the pool.
        local repair_packs_requested = math.ceil(durability_deficit / config.supply.repair_pack_durability)
        local repair_packs_supplied = supply.take(rs, anchor.player, entity, rs.entity or entity, "repair-pack",
            repair_packs_requested)
        if repair_packs_supplied == nil then
            return false
        end
        rs.repair_health_pool = rs.repair_health_pool +
                                    repair_packs_supplied * config.supply.repair_pack_durability
        if repair_packs_supplied == 0 then
            if not rs.out_of_repair_packs_warned then
                anchor.player.print("[MAB] repair bot is out of repair packs")
                rs.out_of_repair_packs_warned = true
            end
            return true
        end
        rs.out_of_repair_packs_warned = nil
    end
    local health_restored = math.min(health_needed_this_action, rs.repair_health_pool)
    entity.health = math.min(entity.max_health, entity.health + health_restored)
    rs.repair_health_pool = rs.repair_health_pool - health_restored
    visuals.health(discovery.identity(entity), entity)
    return entity.health >= entity.max_health * config.tasks.repair.threshold
end

---Retain a partially repaired target for the next bounded scheduler action.
function M.keep_target(entity, rs, anchor)
    return entity.valid and M.valid(entity, rs, anchor)
end

---Self-repair takes priority because an incapacitated bot cannot service others.
function M.before_step(rs, anchor, bot)
    if bot.health and bot.max_health and bot.health < bot.max_health * config.tasks.repair.self_repair_threshold then
        M.act(rs, anchor, bot)
        return "working"
    end
end

---Advance resumable four-neighbour A* and stop within interaction distance.
---Failed routes release their target instead of allowing direct movement through
---walls. Each call performs at most one pathfinding or movement work unit.
function M.navigate(rs, anchor, bot)
    if not rs.path_job then
        rs.path_job = pathfinding.start(anchor.surface, bot.position, rs.target.position,
            config.tasks.repair.radius, config.tasks.repair.interaction_distance)
        return "moving", false
    end
    if not rs.path_job.done then
        pathfinding.step(rs.path_job)
        return "moving", false
    end
    if rs.path_job.failed then
        rs.target, rs.target_visualized = nil, nil
        rs.path_job, rs.best_distance, rs.scan = nil, nil, nil
        return "idle", false
    end
    if rs.path_job.path and rs.path_job.cursor >= 1 then
        if movement.step(bot, rs.path_job.path[rs.path_job.cursor]) then
            rs.path_job.cursor = rs.path_job.cursor - 1
        end
        return "moving", false
    end
    -- Both sides are squared tile distances, avoiding a square root on every
    -- repair work unit while retaining the configured inclusive radius.
    local squared_distance_to_target = movement.distance2(bot.position, rs.target.position)
    local squared_interaction_distance = config.tasks.repair.interaction_distance ^ 2
    if squared_distance_to_target > squared_interaction_distance then
        -- A target may move, and saves from the older tile-distance pathfinder
        -- can contain a completed route whose endpoint is physically too far
        -- away. Replan instead of remaining permanently in the working phase.
        rs.path_job = nil
        return "moving", false
    end
    return "working", true
end

return M
