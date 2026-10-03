-- Central rendering ownership. IDs remain transient and are recreated from logical state.
local config = require("config")
local M = {};
local owned = {}

function M.clear_role(key)
    for _, object in pairs(owned[key] or {}) do
        if object and object.valid then
            object.destroy()
        end
    end
    owned[key] = {}
end

function M.target_line(key, from, to)
    M.clear_role(key)
    if not (from and from.valid and to and to.valid) then
        return
    end
    owned[key] = {rendering.draw_line {
        color = config.visuals.colors.target,
        width = 2,
        from = from,
        to = to,
        surface = from.surface,
        time_to_live = 120
    }}
end

function M.map_marker(id, entity)
    if not (entity and entity.valid) then
        return
    end
    local key = "map:" .. id;
    M.clear_role(key)
    owned[key] = {rendering.draw_circle {
        color = config.visuals.colors.map,
        radius = 0.45,
        width = 1,
        filled = false,
        target = entity,
        surface = entity.surface,
        time_to_live = config.visuals.lifetime_ticks
    }}
end

function M.destroyed_site(key, surface, position)
    M.clear_role("site:" .. key);
    owned["site:" .. key] = {rendering.draw_circle {
        color = config.visuals.colors.destroyed,
        radius = 0.7,
        width = 2,
        filled = false,
        target = position,
        surface = surface,
        time_to_live = config.visuals.lifetime_ticks
    }}
end

function M.cliff_marker(id, entity)
    local key = "cliff:" .. id;
    M.clear_role(key);
    if entity and entity.valid then
        owned[key] = {rendering.draw_circle {
            color = config.visuals.colors.cliff,
            radius = 0.9,
            width = 3,
            filled = false,
            target = entity,
            surface = entity.surface,
            time_to_live = config.visuals.lifetime_ticks
        }}
    end
end

function M.health(key, entity)
    if not (entity and entity.valid and entity.health and entity.max_health) then
        return
    end
    local ratio = entity.health / entity.max_health;
    M.clear_role("health:" .. key)
    local bad, good = config.visuals.colors.health_bad, config.visuals.colors.health_good;
    local color = {
        r = bad.r + (good.r - bad.r) * ratio,
        g = bad.g + (good.g - bad.g) * ratio,
        b = bad.b + (good.b - bad.b) * ratio,
        a = bad.a + (good.a - bad.a) * ratio
    }
    owned["health:" .. key] = {rendering.draw_arc {
        color = color,
        max_radius = 0.65,
        min_radius = 0.56,
        start_angle = 0,
        angle = ratio,
        target = entity,
        surface = entity.surface,
        time_to_live = 180
    }}
end

function M.begin_clear(root, prefix)
    root.visual_clear = {
        prefix = prefix,
        cursor = nil
    }
end

function M.step_clear(root)
    local job = root.visual_clear;
    if not job then
        return false
    end
    local key, value = next(owned, job.cursor);
    job.cursor = key
    if key == nil then
        root.visual_clear = nil;
        return false
    end
    if key:sub(1, #job.prefix) == job.prefix then
        if value then
            for _, object in pairs(value) do
                if object and object.valid then
                    object.destroy()
                end
            end
        end
        owned[key] = false
    end
    return true
end

return M
