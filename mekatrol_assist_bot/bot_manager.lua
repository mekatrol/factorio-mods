-- Bot lifecycle, gates, formation reflow, and visual-state replacement.
local config = require("config")
local constants = require("constants")
local state = require("state")
local anchor = require("player_anchor")
local formation = require("formation")
local movement = require("movement")
local technology = require("technology")
local visuals = require("visuals")
local M = {}

---Describe the visible activity independently of the configured task.
function M.activity(rs)
    if rs.phase ~= "idle" then
        return rs.task
    end
    if rs.waiting_ammo_container then
        return "follow (unload)"
    end
    if rs.waiting_inventory then
        local color = config.tasks.upgrade.item_colors[rs.waiting_inventory]
        local item_label = color and (rs.waiting_inventory .. ": " .. color) or rs.waiting_inventory
        return "follow (" .. item_label .. ")"
    end
    return "follow"
end

---List enabled roles in configured formation order.
local function active_names(ps)
    local out = {};
    for _, name in ipairs(config.formation.role_order) do
        if ps.roles[name].enabled then
            out[#out + 1] = name
        end
    end
    return out
end

---Create the inert visual robot and attach it to its persistent role state.
local function spawn(role, rs, a, position, visual)
    rs.entity = a.surface.create_entity {
        -- Callers may omit a visual during initial creation. Idle is the least
        -- surprising animation and also guarantees a valid prototype suffix.
        name = constants.prototype(role, visual or "idle"),
        position = position,
        -- The mod owns movement and tasks. A player force would make Factorio
        -- treat this visual actor as a logistic-network robot and eventually
        -- raise the empty-roboport-slot alert.
        force = constants.visual_force
    };
    -- Mirror the exact fallback used for the prototype name so logical and
    -- rendered state cannot disagree.
    rs.visual = visual or "idle";
    return rs.entity
end

---Ensure the role has a live visual entity.
function M.set_visual(role, rs, a, visual)
    if rs.entity and rs.entity.valid then
        -- Keep one persistent entity per bot. Destroying and recreating a
        -- flying robot to change animation prototypes leaves both generations
        -- visible during the render interpolation frame, especially when the
        -- bot is repositioned every tick.
        return rs.entity
    end
    -- Recreating a missing bot at the anchor avoids spawning at an obsolete
    -- saved coordinate. Moving is the default because it must rejoin its slot.
    return spawn(role, rs, a, a.position, visual or "moving")
end

---Enable a role after checking its player anchor and technology gate.
function M.enable(index, role, quiet)
    local a = anchor.get(index);
    if not a then
        return false, "player has no usable anchor"
    end
    local missing = technology.missing(a.force, role);
    if #missing > 0 then
        return false, "requires technology: " .. table.concat(missing, ", ")
    end
    local ps = state.player(index);
    local rs = ps.roles[role];
    local was_enabled = rs.enabled
    rs.enabled = true;
    if not was_enabled then
        state.adjust_enabled_role_count(1)
    end
    -- Migrate active bots made by earlier versions. Configuration changes call
    -- this function for every enabled role.
    if rs.entity and rs.entity.valid and rs.entity.force.name ~= constants.visual_force then
        rs.entity.destroy()
        rs.entity = nil
    end
    -- Enabling a bot while temporary disable mode is active makes it visible,
    -- but does not let it begin work until the player resumes the assistants.
    if ps.temporary_disable_active then
        ps.temporary_disabled[role] = true
    end
    rs.visual_key = index .. ":" .. role
    if not rs.entity or not rs.entity.valid then
        local slots = formation.slots(active_names(ps), ps.direction or "right");
        local slot = slots[role] or {
            -- The fallback is defensive: a newly enabled role should normally
            -- be in `active_names`, but origin is safer than indexing nil if a
            -- malformed/partially migrated state disagrees.
            x = 0,
            y = 0
        };
        spawn(role, rs, a, {
            x = a.position.x + slot.x,
            y = a.position.y + slot.y
        }, "moving")
    end
    -- Idle means the controller is not performing its configured task, so show
    -- the user-facing activity "follow" rather than a misleading task label.
    visuals.bot_label(rs.visual_key, rs.entity, role,
        ps.temporary_disable_active and ps.temporary_disabled[role] and "paused" or M.activity(rs), index)
    if not quiet then
        a.player.print("[MAB] " .. role .. " enabled")
    end
    return true
end

---Disable a role and discard all transient work/entity/render references.
function M.disable(index, role, reason)
    local p = game.get_player(index);
    local ps = state.player(index);
    local rs = ps.roles[role];
    local was_enabled = rs.enabled
    rs.enabled = false;
    if was_enabled then
        state.adjust_enabled_role_count(-1)
    end
    -- A normally disabled bot must not be resurrected by a later resume.
    ps.temporary_disabled[role] = nil
    rs.scan = nil;
    rs.target = nil;
    rs.target_visualized = nil;
    rs.path_job = nil;
    rs.survey_job = nil;
    rs.track_job = nil;
    rs.track_started = nil;
    rs.waiting_inventory = nil;
    rs.waiting_accept_any_quality = nil;
    rs.waiting_ammo_container = nil;
    rs.ammo_waiting_turret = nil;
    rs.ammo_container = nil;
    rs.ammo_chain_scan = nil;
    rs.ammo_pickup_scan = nil;
    rs.ammo_fallback_turret = nil;
    rs.ammo_fallback_distance = nil;
    visuals.clear_role(index .. ":" .. role)
    visuals.clear_role("secondary:" .. index .. ":" .. role)
    visuals.clear_role("label:" .. index .. ":" .. role)
    if rs.entity and rs.entity.valid then
        rs.entity.destroy()
    end
    rs.entity = nil
    if p and reason then
        p.print("[MAB] " .. role .. " disabled: " .. reason)
    end
end

---Return whether one enabled role is currently frozen by temporary disable.
function M.is_temporarily_disabled(index, role)
    local ps = state.player(index)
    return ps.temporary_disable_active and ps.temporary_disabled[role] == true
end

---Freeze every currently enabled bot in place without discarding its work.
function M.temporary_disable(index)
    local ps = state.player(index)
    ps.temporary_disable_active = true
    for _, role in ipairs(config.formation.role_order) do
        local rs = ps.roles[role]
        if rs.enabled then
            ps.temporary_disabled[role] = true
            local visual_key = rs.visual_key or (index .. ":" .. role)
            visuals.clear_role(visual_key)
            visuals.clear_role("secondary:" .. visual_key)
            if rs.entity and rs.entity.valid then
                visuals.bot_label(visual_key, rs.entity, role, "paused", index)
            end
        else
            ps.temporary_disabled[role] = nil
        end
    end
end

---Resume only bots still enabled, preserving their controller state and task.
function M.resume(index)
    local ps = state.player(index)
    ps.temporary_disable_active = false
    ps.temporary_disabled = {}
    for _, role in ipairs(config.formation.role_order) do
        local rs = ps.roles[role]
        if rs.enabled and rs.entity and rs.entity.valid then
            local visual_key = rs.visual_key or (index .. ":" .. role)
            visuals.bot_label(visual_key, rs.entity, role, M.activity(rs), index)
        end
    end
end

---Flip one role's enabled state and report gate failures to its player.
function M.toggle(index, role)
    local rs = state.player(index).roles[role];
    if rs.enabled then
        M.disable(index, role, "requested")
        return true
    end
    local ok, why = M.enable(index, role);
    if not ok then
        local p = game.get_player(index);
        if p then
            p.print("[MAB] " .. role .. " locked; " .. why)
        end
    end
    return ok
end

---Disable active roles whose technology prerequisites are no longer true.
function M.enforce_gates()
    for pi, ps in pairs(state.root().players) do
        local a = anchor.get(pi);
        if a then
            for _, role in ipairs(config.formation.role_order) do
                if ps.roles[role].enabled and not technology.allowed(a.force, role) then
                    M.disable(pi, role, "technology requirement no longer met")
                end
            end
        end
    end
end

---Move every idle role toward its formation slot behind the player.
function M.follow(index)
    local a = anchor.get(index);
    if not a then
        return
    end
    local ps = state.player(index);
    local direction = formation.update_direction(ps, a.position);
    local names = active_names(ps)
    local slots = formation.slots(names, direction)
    for _, role in ipairs(names) do
        local rs = ps.roles[role];
        local slot = slots[role];
        if slot and rs.phase == "idle" and not M.is_temporarily_disabled(index, role) then
            local target = {
                x = a.position.x + slot.x,
                y = a.position.y + slot.y
            };
            -- Compare squared values so an idle formation pass needs no sqrt.
            local moving = not rs.entity or not rs.entity.valid or movement.distance2(rs.entity.position, target) >
                               config.movement.arrival_distance ^ 2;
            local e = M.set_visual(role, rs, a, moving and "moving" or "idle");
            movement.step(e, target)
        end
    end
end

---Destroy a departing player's bots and remove their scheduler registration.
function M.remove_player(index)
    local root = state.root();
    local ps = root.players[index];
    if ps then
        local enabled_removed = 0
        for role, rs in pairs(ps.roles) do
            if rs.enabled then
                enabled_removed = enabled_removed + 1
            end
            if rs.entity and rs.entity.valid then
                rs.entity.destroy()
            end
            -- Disabled roles may not have created a visual key yet.
            local visual_key = rs.visual_key or (index .. ":" .. role)
            visuals.clear_role(visual_key)
            visuals.clear_role("secondary:" .. visual_key)
            visuals.clear_role("label:" .. visual_key)
        end
        if enabled_removed > 0 then
            state.adjust_enabled_role_count(-enabled_removed)
        end
        root.players[index] = nil
    end
    local order = root.scheduler.player_order or {};
    for i, v in ipairs(order) do
        if v == index then
            table.remove(order, i);
            break
        end
    end
end
return M
