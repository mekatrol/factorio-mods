-- Global round-robin budget prevents each enabled role from spending a full budget.
local config = require("config")
local state = require("state")
local anchor = require("player_anchor")
local manager = require("bot_manager")
local controllers = require("controllers")
local discovery = require("discovery")
local scanner = require("entity_scanner")
local supply = require("supply")
local visuals = require("visuals")
local movement = require("movement")
local registry = require("role_registry")
local M = {}

-- Rendering handles are deliberately non-persistent. Rebuild one destroyed-site
-- marker per background work unit after load or configuration change.
local function destroyed_visual_job(root)
    local job = root.destroyed_visual_job
    if not job then
        return false
    end
    -- `next` resumes directly after the previous hash key without allocating a
    -- copied key list. The chosen ordering is unspecified but completeness, not
    -- presentation order, matters for rebuilding markers.
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

---Advance the oldest queued cliff-planner selection by one scan cell.
local function selection_job(root)
    -- Planner selections can cover huge areas, so they use the same one-cell
    -- scanner budget as role searches instead of querying everything at once.
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

---Spend this tick's global work budget across maintenance and role state machines.
---A "work unit" is deliberately coarse: one scan cell, cleanup item, visual
---item, or controller transition. The background cap preserves foreground bot
---responsiveness while the total cap prevents cost scaling without bound.
function M.tick(event)
    local root = state.root();
    -- With no enabled bots there is no per-tick work to do. In particular,
    -- avoid visual maintenance, background scans, role scheduling, formation
    -- following, and discovery pruning until a bot is switched on again.
    if state.enabled_role_count() == 0 then
        return
    end
    -- Rendering survives save/load while the visual ownership index does not.
    -- Reclaim orphaned target lines and labels before any controller can draw
    -- this session's active UI.
    visuals.reclaim_session_lines()
    -- Saves from before cliff selection have no queue. Lazy initialization also
    -- keeps the optional feature safe when its queue has not been created yet.
    root.selection_jobs = root.selection_jobs or {}
    local budget = config.scheduler.work_per_tick;
    local background = 0
    -- A budget larger than the roster used to wrap the round-robin cursor and
    -- run some controllers two or three times in one game tick.  Besides being
    -- unfair at the wrap boundary, that made CPU/rendering cost jump as bots
    -- were enabled.  One visit per pair is sufficient; movement already has a
    -- separate per-tick allowance.
    local foreground_remaining = state.enabled_role_count()
    while budget > 0 do
        local did_background = false
        if background < config.scheduler.background_work_per_tick then
            if visuals.step_clear(root) then
                did_background = true
            elseif discovery.step_clear(root) then
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
            if foreground_remaining == 0 then
                break
            end
            foreground_remaining = foreground_remaining - 1
            -- Round-robin selection gives every player-role pair an equal
            -- opportunity independent of how expensive its current task is.
            local item = state.next_enabled_role();
            if not item then
                return
            end
            local a = anchor.get(item.player_index);
            local rs = item.state
            local paused = manager.is_temporarily_disabled(item.player_index, item.name)
            -- Recreate an enabled bot whose engine entity disappeared, but only
            -- when its player currently has a usable anchor.
            if a and rs.enabled and (not rs.entity or not rs.entity.valid) then
                manager.enable(item.player_index, item.name, true)
            end
            -- Rendering ownership is transient across load. Recreate a paused
            -- label without advancing or otherwise mutating the bot's work.
            if paused and rs.entity and rs.entity.valid then
                local visual_key = rs.visual_key or (item.player_index .. ":" .. item.name)
                visuals.bot_label(visual_key, rs.entity, item.name, "paused", item.player_index)
            end
            if a and rs.enabled and not paused and rs.entity and rs.entity.valid and event.tick %
                config.scheduler.role_intervals[item.name] == 0 then
                local logic = registry.roles[item.name].logic
                local visual_key = rs.visual_key or (item.player_index .. ":" .. item.name)
                -- Cleanup accumulates several ground stacks before delivery;
                -- all other roles immediately return their unused supplies.
                local should_flush = not logic.should_flush_cargo or logic.should_flush_cargo(rs)
                local before_cargo_phase = should_flush and logic.before_cargo and
                                               logic.before_cargo(rs, a, rs.entity)
                local cargo_flushed = not should_flush or
                                          (not before_cargo_phase and supply.flush_cargo(rs, a.player, rs.entity))
                if before_cargo_phase then
                    rs.phase = before_cargo_phase
                    manager.set_visual(item.name, rs, a, rs.phase)
                elseif not cargo_flushed then
                    -- Cargo delivery takes precedence over ordinary role work;
                    -- this prevents collected items from becoming stranded.
                    -- Cargo fields may not exist on roles/saves which have never
                    -- carried anything. Cursor one is the first Lua array item.
                    local cargo_name = rs.cargo_order and rs.cargo_order[rs.cargo_cursor or 1]
                    local destination = cargo_name and rs.cargo_destinations and rs.cargo_destinations[cargo_name]
                    -- Cleanup can keep formation while it searches for a
                    -- matching chest or waits for player inventory space.
                    -- A concrete destination still owns movement explicitly.
                    -- Lua has no ternary operator; `condition and A or B` works
                    -- here because both A and B are non-false strings.
                    rs.phase = logic.cargo_phase and logic.cargo_phase(destination) or "working"
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
                    -- Robots have no `scan` prototype. Scanning uses the moving
                    -- animation, while idle/working/moving map directly.
                    manager.set_visual(item.name, rs, a, rs.phase == "scan" and "moving" or rs.phase)
                end
                if rs.task == "follow" then
                    visuals.clear_role(visual_key)
                -- Idle means formation-following. A role may retain a candidate
                -- target while scanning or waiting, but that inactive target
                -- must not leave a misleading action line on screen.
                elseif rs.phase ~= "idle" and rs.target and rs.target.valid then
                    visuals.target_line(visual_key, rs.entity, rs.target, item.player_index)
                elseif rs.task == "move_to" and rs.destination then
                    visuals.target_line(visual_key, rs.entity, rs.destination, item.player_index)
                else
                    visuals.clear_role(visual_key)
                end
                local secondary_visual_key = "secondary:" .. visual_key
                local secondary_target = logic.secondary_target and logic.secondary_target(rs)
                if rs.task ~= "follow" and rs.phase ~= "idle" and secondary_target then
                    visuals.target_line(secondary_visual_key, rs.entity, secondary_target, item.player_index)
                else
                    visuals.clear_role(secondary_visual_key)
                end
                -- An idle controller is physically following formation even if
                -- its configured task remains repair/search/etc.
                local current_task = manager.activity(rs)
                visuals.bot_label(visual_key, rs.entity, item.name, current_task, item.player_index)
            end
            budget = budget - 1
        end
    end

    if event.tick % config.scheduler.idle_interval == 0 then
        -- Formation following is outside the work loop, but movement.lua still
        -- enforces one physical speed budget per entity and tick.
        for pi in pairs(root.players) do
            manager.follow(pi)
        end
    end
    
    if event.tick % config.scanning.prune_interval == 0 then
        -- Pruning itself is bounded by prune_per_step, spreading stale-record
        -- cleanup over time rather than pausing the simulation.
        discovery.prune(config.scanning.prune_per_step)
    end
end

return M
