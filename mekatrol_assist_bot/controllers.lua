-- Generic role state-machine orchestration. Every role-specific decision lives
-- in its bot_role_<role> module and is reached through this uniform interface.
local registry = require("role_registry")
local scanner = require("entity_scanner")
local discovery = require("discovery")
local movement = require("movement")
local track = require("track")
local supply = require("supply")
local visuals = require("visuals")
local M = {}

---Resolve either a fixed role scan phase or a state-dependent phase policy.
local function scan_phase(def, rs)
    if type(def.scan_phase) == "function" then
        return def.scan_phase(rs)
    end
    return def.scan_phase or "idle"
end

---Discard every transient calculation derived from the current target.
local function clear_target(rs)
    rs.target, rs.target_visualized, rs.path_job, rs.best_distance = nil, nil, nil, nil
end

---Return a completed role action to its neutral search state.
local function reset(rs)
    clear_target(rs)
    rs.survey_job, rs.scan, rs.phase = nil, nil, "idle"
end

---Create the role-defined bounded spatial scan.
local function begin(def, rs, anchor, bot)
    local area = def.scan_area and def.scan_area(rs, anchor)
    if area then
        rs.scan = scanner.start_area(anchor.surface, area, def.filter(rs, anchor))
    else
        local center = def.scan_center and def.scan_center(rs, anchor, bot) or anchor.position
        rs.scan = scanner.start(anchor.surface, center, def.radius(rs), def.filter(rs, anchor))
    end
    rs.phase = "scan"
end

local function next_group_target(def, rs, anchor)
    return track.next(rs.track_job, function(entity)
        return def.valid(entity, rs, anchor)
    end)
end

---Advance one role state machine by one scheduler work unit.
---The common lifecycle is discovery handoff, bounded scan, nearest-target
---selection, optional graph/path planning, movement, one action, and reset.
---Long-running role operations store their cursors in `rs`, so a later tick or
---reloaded save resumes at the exact point where this call yielded.
function M.step(role, rs, anchor, bot)
    local def = registry.roles[role].logic
    if def.before_step then
        local phase = def.before_step(rs, anchor, bot)
        if phase then
            return phase
        end
    end
    if rs.target and not rs.target.valid then
        clear_target(rs)
        rs.waiting_inventory = nil
    end
    if def.normalize then
        def.normalize(rs)
    end

    -- Upgrade roles retain their selected target while waiting for stock, but
    -- surrender movement to formation-following until a supply source appears.
    if rs.waiting_inventory and not rs.target then
        rs.waiting_inventory = nil
    end
    if rs.waiting_inventory then
        local ready, phase = supply.wait_for_item(rs, anchor.player, rs.target, bot)
        if not ready then
            return phase
        end
    end

    -- Shared discoveries are considered before starting a new local scan.
    -- Each call examines at most one queue record to preserve the work budget.
    if not rs.scan and not rs.target and def.handoff then
        local candidate, exhausted = discovery.next_for(rs, role)
        if candidate and candidate.valid and candidate.surface == anchor.surface and def.valid(candidate, rs, anchor) then
            rs.target = candidate
            rs.best_distance = movement.distance2(candidate.position, bot.position)
        end
        if not rs.target and not exhausted then
            return "idle"
        end
    end
    if not rs.scan and not rs.target then
        begin(def, rs, anchor, bot)
        -- Let each role decide whether beginning its scan is active work.  In
        -- particular, cleanup follows formation during an empty watch scan but
        -- stays active while carrying cargo or pursuing a selected stack.
        return scan_phase(def, rs)
    end
    if rs.scan and not rs.scan.done then
        local _, found = scanner.step(rs.scan)
        for _, e in ipairs(found) do
            if def.scan_entity then
                def.scan_entity(e, rs, anchor)
            elseif def.valid(e, rs, anchor) then
                local distance = movement.distance2(e.position, bot.position)
                if not rs.best_distance or distance < rs.best_distance then
                    rs.target, rs.best_distance = e, distance
                end
            end
        end
        return scan_phase(def, rs)
    end
    if rs.track_job and rs.track_job.done and (not rs.target or not rs.target.valid) then
        local candidate, complete = next_group_target(def, rs, anchor)
        rs.target = candidate
        if not candidate and not complete then
            return "moving"
        end
        if complete then
            rs.track_job, rs.track_started, rs.scan, rs.best_distance = nil, nil, nil, nil
            return "idle"
        end
    end
    if not rs.target then
        reset(rs)
        return "idle"
    end
    if not rs.target_visualized then
        visuals.target_line(rs.visual_key or role, bot, rs.target, anchor.player.index)
        rs.target_visualized = true
    end
    local grouped = def.grouped and def.grouped(rs)
    if grouped then
        -- Belt-like roles first finish bounded graph discovery, then consume the
        -- stable result one entity per scheduler opportunity.
        if not rs.track_job then
            rs.track_job = track.start(rs.target)
            return "moving"
        end
        if not rs.track_job.done then
            track.step(rs.track_job)
            return "moving"
        end
        if not rs.track_started then
            rs.track_started, rs.target = true, nil
        end
        if not rs.target or not rs.target.valid then
            local candidate, complete = next_group_target(def, rs, anchor)
            rs.target = candidate
            if not candidate and not complete then
                return "moving"
            end
            if complete then
                rs.track_job, rs.track_started, rs.scan, rs.best_distance = nil, nil, nil, nil
                return "idle"
            end
        end
    end
    if def.navigate then
        local phase, ready = def.navigate(rs, anchor, bot)
        if not ready then
            return phase
        end
    elseif not movement.step(bot, rs.target.position) then
        return "moving"
    end
    if def.prepare_action then
        local phase, ready = def.prepare_action(rs, anchor, bot)
        if not ready then
            return phase
        end
    end
    if not def.act(rs, anchor, rs.target) then
        -- An inventory wait with a selected player source owns movement.  It
        -- must not be marked idle because formation following would then pull
        -- the bot away from the player between scheduler opportunities.
        return rs.player_supply_name and "moving" or (rs.waiting_inventory and "idle" or "working")
    end
    if def.keep_target and def.keep_target(rs.target, rs, anchor) then
        return "working"
    end
    if grouped then
        local candidate, complete = next_group_target(def, rs, anchor)
        rs.target, rs.target_visualized = candidate, nil
        if rs.target or not complete then
            return "working"
        end
        rs.track_job, rs.track_started = nil, nil
    end
    reset(rs)
    return "working"
end

return M
