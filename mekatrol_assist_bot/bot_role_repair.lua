-- Repair role policy: find damaged friendly entities and fly directly to them.
local config = require("config")
local discovery = require("discovery")
local movement = require("movement")
local supply = require("supply")
local visuals = require("visuals")
local M = {
    tasks = {"follow", "move_to", "repair"},
    handoff = true
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

---Chain the first search after a completed repair from the bot's current
---location. If that search is empty, later watch scans return to the normal
---player-centred, formation-following behaviour.
function M.scan_center(rs, anchor, bot)
    if rs.repair_chain_scan then
        rs.repair_chain_scan = nil
        rs.repair_scan_active = true
        return bot.position
    end
    return anchor.position
end

function M.scan_phase(rs)
    return rs.repair_scan_active and "moving" or "idle"
end

function M.normalize(rs)
    if rs.repair_scan_active and rs.scan and rs.scan.done and not rs.target then
        rs.repair_scan_active = nil
    end
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
            -- Do not report the repair as complete: the target is still
            -- damaged, so keep_target would retain it and leave the bot in a
            -- permanent working state.  The shared inventory wait polls the
            -- configured sources and lets the bot follow formation until a
            -- pack becomes available.
            rs.waiting_inventory = "repair-pack"
            return false
        end
        rs.waiting_inventory = nil
        rs.out_of_repair_packs_warned = nil
    end
    local health_restored = math.min(health_needed_this_action, rs.repair_health_pool)
    entity.health = math.min(entity.max_health, entity.health + health_restored)
    rs.repair_health_pool = rs.repair_health_pool - health_restored
    visuals.health(discovery.identity(entity), entity)
    local complete = entity.health >= entity.max_health * config.tasks.repair.threshold
    if complete and entity ~= rs.entity then
        rs.repair_chain_scan = true
    end
    return complete
end

---Retain a partially repaired target for the next bounded scheduler action.
function M.keep_target(entity, rs, anchor)
    return entity.valid and M.valid(entity, rs, anchor)
end

---Self-repair takes priority because an incapacitated bot cannot service others.
function M.before_step(rs, anchor, bot)
    if bot.health and bot.max_health and bot.health < bot.max_health * config.tasks.repair.self_repair_threshold then
        M.act(rs, anchor, bot)
        -- A selected player supply source owns movement just as it does for a
        -- normal repair target; idle would let formation following oppose it.
        return rs.player_supply_name and "moving" or (rs.waiting_inventory and "idle" or "working")
    end
end

---Fly directly toward a target and stop within repair interaction distance.
---Assist bots are airborne, so walls and gates must not influence their route.
function M.navigate(rs, _, bot)
    -- Discard a persisted route from versions which treated repair movement as
    -- ground navigation.
    rs.path_job = nil
    if movement.distance2(bot.position, rs.target.position) > config.tasks.repair.interaction_distance ^ 2 then
        movement.step(bot, rs.target.position)
        return "moving", false
    end
    return "working", true
end

return M
