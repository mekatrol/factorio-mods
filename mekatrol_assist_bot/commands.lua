-- Canonical /mab command parser and dispatcher.
local config = require("config")
local registry = require("role_registry")
local state = require("state")
local manager = require("bot_manager")
local technology = require("technology")
local M = {}

---Split command text on whitespace into a compact argument array.
local function words(s)
    local out = {}
    -- Factorio passes nil when a command has no parameter. Empty text makes the
    -- same iterator simply yield no words, which is the parser's help case.
    for w in (s or ""):gmatch("%S+") do
        out[#out + 1] = w
    end
    return out
end

---Parse canonical `/mab ROLE ACTION` input.
function M.parse(text)
    local arguments = words(text)
    -- The registry expects a string; empty input intentionally resolves to nil.
    local role = registry.get(arguments[1] or "")
    return {
        arguments = arguments,
        role = role,
        -- A registry match is canonicalized; `all` is a command pseudo-role;
        -- anything else stays nil so execute can report an unknown role.
        role_name = role and role.name or (arguments[1] == "all" and "all" or nil),
        -- Omitting the action is deliberately equivalent to a hotkey toggle.
        action = arguments[2] or "toggle"
    }
end

---Print an unlocalized diagnostic prefixed with the mod's short name.
local function say(pi, text)
    local p = game.get_player(pi);
    if p then
        p.print("[MAB] " .. text)
    end
end

---Print a locale-backed message with variadic substitution parameters.
local function say_localized(pi, key, ...)
    local p = game.get_player(pi)
    if not p then
        return
    end
    local message = {"", "[MAB] ", {key, ...}}
    p.print(message)
end

---Report enabled state, task, and current controller phase for a role or all roles.
local function status(pi, name)
    local ps = state.player(pi);
    -- A concrete name becomes a one-element work list. Missing/all reuses the
    -- canonical roster, preserving the same stable order as formation display.
    local names = name and name ~= "all" and {name} or config.formation.role_order
    local player = game.get_player(pi);
    for _, r in ipairs(names) do
        local x = ps.roles[r];
        local missing = technology.missing(player.force, r);
        local enabled_state = not x.enabled and "off" or
                                  (ps.temporary_disable_active and ps.temporary_disabled[r] and "paused" or "on")
        say(pi, r .. ": " .. enabled_state .. ", task=" .. x.task .. ", phase=" .. x.phase ..
            (#missing > 0 and ", missing=" .. table.concat(missing, ",") or ""))
    end
end

---Apply enable, disable, or toggle uniformly to one role or the complete roster.
local function operate(pi, name, action)
    local names = name == "all" and config.formation.role_order or {name}
    for _, r in ipairs(names) do
        if action == "on" then
            local ok, why = manager.enable(pi, r, true);
            if not ok then
                say(pi, r .. " locked; " .. why)
            end
        elseif action == "off" then
            manager.disable(pi, r, "requested")
        elseif action == "toggle" then
            manager.toggle(pi, r)
        end
    end
end

---Control the player-wide, save-persistent temporary disable mode.
local function temporary_disable(pi, action)
    local ps = state.player(pi)
    if action == "status" then
        local count = 0
        for _ in pairs(ps.temporary_disabled) do count = count + 1 end
        say(pi, ps.temporary_disable_active and ("bots paused (" .. count .. ")") or "bots not paused")
        return
    end
    if action == "toggle" then
        action = ps.temporary_disable_active and "off" or "on"
    end
    if action == "on" then
        manager.temporary_disable(pi)
        say(pi, "bots temporarily disabled")
    elseif action == "off" then
        manager.resume(pi)
        say(pi, "bots resumed")
    else
        say(pi, "unknown pause action '" .. action .. "'; use on, off, toggle, or status")
    end
end

---Validate and execute one parsed command without throwing on user mistakes.
function M.execute(pi, text)
    if not pi then
        game.print("[MAB] command must be run by a player")
        return
    end
    local parsed = M.parse(text);
    local a = parsed.arguments;
    if #a == 0 or a[1] == "help" then
        local requested = a[2] and registry.get(a[2]);
        if requested then
            say_localized(pi, "mab.help-role", requested.name, table.concat(requested.tasks, ", "),
                requested.logic.help_suffix or "")
        else
            say_localized(pi, "mab.help")
        end
        return
    end
    if a[1] == "status" then
        status(pi, registry.get(a[2] or "") and registry.get(a[2]).name or a[2]);
        return
    end
    if a[1] == "pause" or a[1] == "temporary-disable" then
        temporary_disable(pi, a[2] or "toggle")
        return
    end
    local role = parsed.role;
    if a[1] ~= "all" and not role then
        say(pi, "unknown role '" .. a[1] .. "'")
        return
    end
    local name = parsed.role_name;
    local action = parsed.action
    if action == "status" then
        status(pi, name);
        return
    end
    if role.logic.command and role.logic.command(action, {player=game.get_player(pi),say=function(message) say(pi,message) end}) then
        return
    end
    if action == "tasks" then
        say(pi, name .. " tasks: " .. table.concat(role.tasks, ", "));
        return
    end
    if action == "refresh" then
        local rs = state.player(pi).roles[name];
        rs.scan = nil;
        rs.target = nil;
        rs.path_job = nil;
        rs.survey_job = nil;
        rs.track_job = nil;
        rs.track_started = nil;
        rs.waiting_inventory = nil;
        rs.waiting_accept_any_quality = nil;
        rs.waiting_ammo_container = nil;
        rs.ammo_waiting_turret = nil;
        rs.ammo_container = nil;
        say(pi, name .. " refreshed");
        return
    end
    if action == "task" then
        local task = a[3];
        if not task or not registry.has_task(role, task) then
            say(pi, "invalid task; use /mab " .. name .. " tasks")
            return
        end
        local player = game.get_player(pi)
        local missing = technology.missing(player.force, name)
        if #missing > 0 then
            say_localized(pi, "mab.locked-technologies", name, table.concat(missing, ", "))
            return
        end
        local available, recipes = technology.task_allowed(player.force, name, task)
        if not available then
            say_localized(pi, "mab.locked-recipes", name, task, table.concat(recipes, ", "))
            return
        end
        local rs = state.player(pi).roles[name];
        local values = {}
        for i = 4, #a do
            -- Require a non-empty key and value separated by the first equals
            -- sign; malformed optional arguments are ignored here and caught
            -- later when required named values are missing.
            local k, v = a[i]:match("^([^=]+)=(.+)$")
            if k then
                values[k] = v
            end
        end
        if task == "move_to" then
            local x, y = tonumber(values.x), tonumber(values.y)
            if not x or not y then
                say(pi, "move_to requires x=<number> y=<number>")
                return
            end
            rs.destination = {
                x = x,
                y = y
            }
        elseif role.logic.configure_task then
            local ok, reason = role.logic.configure_task(rs, task, values)
            if not ok then say(pi, reason); return end
        end
        rs.task = task;
        rs.scan = nil;
        rs.target = nil
        rs.waiting_inventory = nil
        rs.waiting_accept_any_quality = nil
        manager.enable(pi, name, true);
        say(pi, name .. " task=" .. task);
        return
    end
    if action == "on" or action == "off" or action == "toggle" then
        operate(pi, name, action)
    else
        say(pi, "unknown action '" .. action .. "'")
    end
end

---Register the canonical command with Factorio.
function M.register()
    commands.add_command("mab", {"mab.command-description"}, function(c)
        M.execute(c.player_index, c.parameter)
    end)
end

return M
