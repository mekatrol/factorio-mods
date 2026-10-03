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
        name = constants.prototype(role, visual or "idle"),
        position = position,
        force = a.force
    };
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
    rs.enabled = true;
    rs.visual_key = index .. ":" .. role
    if not rs.entity or not rs.entity.valid then
        local slots = formation.slots(active_names(ps), ps.direction or 1);
        local slot = slots[role] or {
            x = 0,
            y = 0
        };
        spawn(role, rs, a, {
            x = a.position.x + slot.x,
            y = a.position.y + slot.y
        }, "moving")
    end
    visuals.bot_label(rs.visual_key, rs.entity, role, rs.phase == "idle" and "follow" or rs.task, index)
    if not quiet then
        a.player.print("[MAB] " .. role .. " enabled")
    end
    return true
end

---Disable a role and discard all transient work/entity/render references.
function M.disable(index, role, reason)
    local p = game.get_player(index);
    local rs = state.player(index).roles[role];
    rs.enabled = false;
    rs.scan = nil;
    rs.target = nil;
    rs.target_visualized = nil;
    rs.path_job = nil;
    rs.survey_job = nil;
    rs.track_job = nil;
    rs.track_started = nil;
    visuals.clear_role(index .. ":" .. role)
    visuals.clear_role("label:" .. index .. ":" .. role)
    if rs.entity and rs.entity.valid then
        rs.entity.destroy()
    end
    rs.entity = nil
    if p and reason then
        p.print("[MAB] " .. role .. " disabled: " .. reason)
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
    local slots = formation.slots(active_names(ps), direction)
    for _, role in ipairs(config.formation.role_order) do
        local rs = ps.roles[role];
        local slot = slots[role];
        if slot and rs.phase == "idle" then
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
        for role, rs in pairs(ps.roles) do
            if rs.entity and rs.entity.valid then
                rs.entity.destroy()
            end
            local visual_key = rs.visual_key or (index .. ":" .. role)
            visuals.clear_role(visual_key)
            visuals.clear_role("label:" .. visual_key)
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
