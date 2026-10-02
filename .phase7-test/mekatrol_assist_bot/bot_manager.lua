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

local function active_names(ps)
    local out = {};
    for _, name in ipairs(config.formation.role_order) do
        if ps.roles[name].enabled then
            out[#out + 1] = name
        end
    end
    return out
end

local function spawn(role, rs, a, position, visual)
    rs.entity = a.surface.create_entity {
        name = constants.prototype(role, visual or "idle"),
        position = position,
        force = a.force
    };
    rs.visual = visual or "idle";
    return rs.entity
end

function M.set_visual(role, rs, a, visual)
    if rs.visual == visual and rs.entity and rs.entity.valid then
        return rs.entity
    end
    local p = rs.entity and rs.entity.valid and rs.entity.position or a.position
    if rs.entity and rs.entity.valid then
        rs.entity.destroy()
    end
    return spawn(role, rs, a, p, visual)
end

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
        }, "idle")
    end
    if not quiet then
        a.player.print("[MAB] " .. role .. " enabled")
    end
    return true
end

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
    if rs.entity and rs.entity.valid then
        rs.entity.destroy()
    end
    rs.entity = nil
    if p and reason then
        p.print("[MAB] " .. role .. " disabled: " .. reason)
    end
end

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
            local moving = not rs.entity or not rs.entity.valid or movement.distance2(rs.entity.position, target) >
                               config.movement.arrival_distance ^ 2;
            local e = M.set_visual(role, rs, a, moving and "moving" or "idle");
            movement.step(e, target)
        end
    end
end

function M.remove_player(index)
    local root = state.root();
    local ps = root.players[index];
    if ps then
        for _, rs in pairs(ps.roles) do
            if rs.entity and rs.entity.valid then
                rs.entity.destroy()
            end
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
