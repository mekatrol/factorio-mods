-- Global round-robin budget prevents each enabled role from spending a full budget.
local config = require("config")
local state = require("state")
local anchor = require("player_anchor")
local manager = require("bot_manager")
local controllers = require("controllers")
local discovery = require("discovery")
local scanner = require("entity_scanner")
local migrations = require("migrations")
local supply = require("supply")
local visuals = require("visuals")
local movement = require("movement")
local M = {}

-- Rendering handles are deliberately non-persistent. Rebuild one destroyed-site
-- marker per background work unit after load or configuration change.
local function destroyed_visual_job(root)
    local job = root.destroyed_visual_job
    if not job then
        return false
    end
    local key, site = next(root.destroyed_sites, job.cursor)
    job.cursor = key
    if key == nil then
        root.destroyed_visual_job = nil
        return false
    end
    local surface = game.surfaces[site.surface_index]
    if surface then
        visuals.destroyed_site(key, surface, site.position)
    end
    return true
end

local function selection_job(root)
    local job = root.selection_jobs and root.selection_jobs[1];
    if not job then
        return false
    end
    local done, found = scanner.step(job.scan);
    for _, e in ipairs(found) do
        if e.valid then
            local id = discovery.identity(e);
            root.cliffs[id] = job.mark or nil;
            if job.mark then
                visuals.cliff_marker(id, e)
            else
                visuals.clear_role("cliff:" .. id)
            end
        end
    end
    if done then
        table.remove(root.selection_jobs, 1)
    end
    return true
end

function M.tick(event)
    local root = state.root();
    root.selection_jobs = root.selection_jobs or {}
    local budget = config.scheduler.work_per_tick;
    local background = 0
    while budget > 0 do
        local did_background = false
        if background < config.scheduler.background_work_per_tick then
            if visuals.step_clear(root) then
                did_background = true
            elseif discovery.step_clear(root) then
                did_background = true
            elseif migrations.step() then
                did_background = true
            elseif destroyed_visual_job(root) then
                did_background = true
            elseif selection_job(root) then
                did_background = true
            end
        end
        if did_background then
            background = background + 1;
            budget = budget - 1
        else
            local item = state.next_role();
            if not item then
                return
            end
            local a = anchor.get(item.player_index);
            local rs = item.state
            if a and rs.enabled and (not rs.entity or not rs.entity.valid) then
                manager.enable(item.player_index, item.name, true)
            end
            if a and rs.enabled and rs.entity and rs.entity.valid and event.tick %
                config.scheduler.role_intervals[item.name] == 0 then
                if not supply.flush_cargo(rs, a.player, rs.entity) then
                    local cargo_name = rs.cargo_order and rs.cargo_order[rs.cargo_cursor or 1]
                    local destination = cargo_name and rs.cargo_destinations and rs.cargo_destinations[cargo_name]
                    -- Cleanup can keep formation while it searches for a
                    -- matching chest or waits for player inventory space.
                    -- A concrete destination still owns movement explicitly.
                    rs.phase = item.name == "cleanup" and
                                   (destination == nil or destination == false) and "idle" or "working"
                    manager.set_visual(item.name, rs, a, rs.phase)
                elseif rs.task == "follow" then
                    rs.phase = "idle"
                elseif rs.task == "move_to" then
                    if rs.destination and movement.step(rs.entity, rs.destination) then
                        rs.task = "follow";
                        rs.destination = nil;
                        rs.phase = "idle"
                    else
                        rs.phase = "moving"
                    end
                else
                    rs.phase = controllers.step(item.name, rs, a, rs.entity);
                    manager.set_visual(item.name, rs, a, rs.phase == "scan" and "moving" or rs.phase)
                end
            end
            budget = budget - 1
        end
    end

    if event.tick % config.scheduler.idle_interval == 0 then
        for pi in pairs(root.players) do
            manager.follow(pi)
        end
    end
    
    if event.tick % config.scanning.prune_interval == 0 then
        discovery.prune(config.scanning.prune_per_step)
    end
end

return M
