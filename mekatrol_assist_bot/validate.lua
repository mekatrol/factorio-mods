-- Pure startup validation with paths in every diagnostic.
local M = {}

local function fail(path, value, range)
    error("mekatrol_assist_bot config " .. path .. "=" .. tostring(value) .. "; expected " .. range, 3)
end

local function num(path, v, min, max, int)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or v < min or (max and v > max) or
        (int and v % 1 ~= 0) then
        fail(path, v, (int and "integer " or "finite number ") .. ">=" .. min .. (max and " and <=" .. max or ""))
    end
end

function M.run(c, known)
    num("schema_version", c.schema_version, 1, nil, true);
    num("scheduler.work_per_tick", c.scheduler.work_per_tick, 1, nil, true);
    num("scheduler.background_work_per_tick", c.scheduler.background_work_per_tick, 1, nil, true);
    num("scheduler.idle_interval", c.scheduler.idle_interval, 1, nil, true)
    for role, interval in pairs(c.scheduler.role_intervals) do
        if not known[role] then
            fail("scheduler.role_intervals." .. role, interval, "registered role")
        end
        num("scheduler.role_intervals." .. role, interval, 1, nil, true)
    end
    for _, k in ipairs {"slot_spacing", "side_distance", "column_spacing", "direction_threshold"} do
        num("formation." .. k, c.formation[k], 0.000001)
    end
    num("formation.max_slots_per_column", c.formation.max_slots_per_column, 1, nil, true)
    local seen = {};
    for i, r in ipairs(c.formation.role_order) do
        if not known[r] then
            fail("formation.role_order[" .. i .. "]", r, "registered role")
        end
        if seen[r] then
            fail("formation.role_order[" .. i .. "]", r, "unique role")
        end
        seen[r] = true
    end
    for role in pairs(known) do
        if not seen[role] then
            fail("formation.role_order", role, "every registered role exactly once")
        end
    end
    for role, r in pairs(c.roles) do
        if r.technology_mode ~= "all" and r.technology_mode ~= "any" then
            fail("roles." .. role .. ".technology_mode", r.technology_mode, "all or any")
        end
        if r.prototype_family ~= "construction" and r.prototype_family ~= "logistic" then
            fail("roles." .. role .. ".prototype_family", r.prototype_family, "construction or logistic")
        end
        if type(r.required_technologies) ~= "table" then
            fail("roles." .. role .. ".required_technologies", r.required_technologies, "array of technology names")
        end
    end
    for _, s in ipairs {"cell_size", "radius", "mapper_radius"} do
        num("scanning." .. s, c.scanning[s], 0.000001)
    end
    num("scanning.cells_per_step", c.scanning.cells_per_step, 1, nil, true);
    num("scanning.prune_per_step", c.scanning.prune_per_step, 1, nil, true);
    num("scanning.entities_per_cell", c.scanning.entities_per_cell, 1, nil, true)
    num("movement.step", c.movement.step, 0.000001);
    num("movement.arrival_distance", c.movement.arrival_distance, 0.000001)
    num("supply.radius", c.supply.radius, 0.000001);
    num("supply.cleanup_capacity", c.supply.cleanup_capacity, 0, nil, true);
    num("supply.repair_pack_durability", c.supply.repair_pack_durability, 0.000001)
    local priorities = {};
    for i, name in ipairs(c.supply.source_priority) do
        if name ~= "player" and name ~= "containers" then
            fail("supply.source_priority[" .. i .. "]", name, "player or containers")
        end
        if priorities[name] then
            fail("supply.source_priority[" .. i .. "]", name, "unique policy")
        end
        priorities[name] = true
    end
    for task, v in pairs(c.tasks) do
        num("tasks." .. task .. ".radius", v.radius, 0.000001)
    end
    for mode, radius in pairs(c.tasks.upgrade.mode_radii) do
        num("tasks.upgrade.mode_radii." .. mode, radius, 0.000001)
    end
    num("tasks.lamp.darkness", c.tasks.lamp.darkness, 0, 1);
    num("tasks.repair.threshold", c.tasks.repair.threshold, 0, 1)
    num("tasks.cliff.projectile_speed", c.tasks.cliff.projectile_speed, 0.000001)
    num("tasks.surveyor.group_cell_size", c.tasks.surveyor.group_cell_size, 0.000001)
    num("tasks.surveyor.boundary_max_steps", c.tasks.surveyor.boundary_max_steps, 1, nil, true)
    for color, value in pairs(c.visuals.colors) do
        for channel, n in pairs(value) do
            num("visuals.colors." .. color .. "." .. channel, n, 0, 1)
        end
    end
    num("visuals.lifetime_ticks", c.visuals.lifetime_ticks, 1, nil, true)
    for action, key in pairs(c.controls) do
        if type(key) ~= "string" or key == "" then
            fail("controls." .. action, key, "non-empty Factorio key sequence")
        end
    end
    num("compatibility.snapshot_limit", c.compatibility.snapshot_limit, 1, nil, true)
    return true
end

return M
