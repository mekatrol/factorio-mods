-- One parser serves /mab and the five temporary compatibility aliases.
local config = require("config")
local registry = require("role_registry")
local state = require("state")
local manager = require("bot_manager")
local technology = require("technology")
local visuals = require("visuals")
local discovery = require("discovery")
local M = {}

local function words(s)
    local out = {}
    for w in (s or ""):gmatch("%S+") do
        out[#out + 1] = w
    end
    return out
end

function M.parse(text, forced)
    local arguments = words(text)
    local bare_forced = forced ~= nil and #arguments == 0
    if forced then
        table.insert(arguments, 1, forced)
    end
    local role = registry.get(arguments[1] or "")
    return {
        arguments = arguments,
        bare_forced = bare_forced,
        role = role,
        role_name = role and role.name or (arguments[1] == "all" and "all" or nil),
        action = arguments[2] or "toggle"
    }
end

local function say(pi, text)
    local p = game.get_player(pi);
    if p then
        p.print("[MAB] " .. text)
    end
end

local function status(pi, name)
    local ps = state.player(pi);
    local names = name and name ~= "all" and {name} or config.formation.role_order
    local player = game.get_player(pi);
    for _, r in ipairs(names) do
        local x = ps.roles[r];
        local missing = technology.missing(player.force, r);
        say(pi, r .. ": " .. (x.enabled and "on" or "off") .. ", task=" .. x.task .. ", phase=" .. x.phase ..
            (#missing > 0 and ", missing=" .. table.concat(missing, ",") or ""))
    end
end

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

function M.execute(pi, text, forced)
    if not pi then
        game.print("[MAB] command must be run by a player")
        return
    end
    local parsed = M.parse(text, forced);
    local a = parsed.arguments;
    local bare_forced = parsed.bare_forced;
    if #a == 0 or a[1] == "help" then
        local requested = a[2] and registry.get(a[2]);
        if requested then
            say(pi,
                requested.name .. " tasks: " .. table.concat(requested.tasks, ", ") ..
                    "; actions on/off/toggle/status/refresh" .. (requested.name == "cliff" and "/mark/clear" or ""))
        else
            say(pi, "/mab <role|all> <on|off|toggle|status>; /mab <role> task <name>; /mab status [role|all]")
        end
        return
    end
    if a[1] == "status" then
        status(pi, registry.get(a[2] or "") and registry.get(a[2]).name or a[2]);
        return
    end
    local role = parsed.role;
    if a[1] ~= "all" and not role then
        say(pi, "unknown role '" .. a[1] .. "'")
        return
    end
    local name = parsed.role_name;
    local action = parsed.action
    if bare_forced and name == "upgrade" then
        local rs = state.player(pi).roles.upgrade;
        local cycle = {"yellow-to-red-belts", "red-to-blue-belts", "blue-to-green-inserters", "containers", "combined"};
        local next_index = 1;
        for i, v in ipairs(cycle) do
            if v == rs.task then
                next_index = i % #cycle + 1
            end
        end
        rs.task = cycle[next_index];
        rs.scan = nil;
        rs.target = nil;
        manager.enable(pi, "upgrade", true);
        say(pi, "upgrade task=" .. rs.task);
        return
    end
    if action == "status" then
        status(pi, name);
        return
    end
    if name == "cliff" and action == "clear" then
        local root = state.root();
        root.cliffs = {};
        visuals.begin_clear(root, "cliff:");
        say(pi, "cliff marks cleared");
        return
    end
    if name == "cliff" and action == "mark" then
        local p = game.get_player(pi);
        p.cursor_stack.set_stack {
            name = "mekatrol-assist-cliff-planner",
            count = 1
        };
        return
    end
    if name == "mapper" and action == "clear" then
        discovery.clear();
        say(pi, "map cleared");
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
        say(pi, name .. " refreshed");
        return
    end
    if action == "task" then
        local task = a[3];
        if not task or not registry.has_task(role, task) then
            say(pi, "invalid task; use /mab " .. name .. " tasks")
            return
        end
        local rs = state.player(pi).roles[name];
        rs.task = task;
        rs.scan = nil;
        rs.target = nil
        if task == "move_to" then
            local values = {}
            for i = 4, #a do
                local k, v = a[i]:match("^([^=]+)=(.+)$");
                if k then
                    values[k] = tonumber(v)
                end
            end
            if not values.x or not values.y then
                say(pi, "move_to requires x=<number> y=<number>")
                return
            end
            rs.destination = {
                x = values.x,
                y = values.y
            }
        end
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

function M.register()
    commands.add_command("mab", "Mekatrol Assist Bot control", function(c)
        M.execute(c.player_index, c.parameter)
    end)
    for alias, role in pairs {
        ub = "upgrade",
        tb = "track",
        cb = "cleanup",
        lb = "lamp",
        db = "cliff"
    } do
        commands.add_command(alias, "Deprecated; use /mab " .. role, function(c)
            M.execute(c.player_index, c.parameter, role)
        end)
    end
end

return M
