-- Central rendering ownership. IDs remain transient and are recreated from logical state.
local config = require("config")
local M = {};
-- Rendering objects cannot be stored in persistent `storage`. This transient
-- ownership map centralizes their lifetime and is rebuilt from logical state.
local owned = {}
local session_lines_reclaimed = false

---Remove target lines left by a previous Lua session.
---Render objects survive save/load, but the non-persistent `owned` index does
---not. Target lines are the only line objects created by this mod, so reclaim
---them once on the first runtime tick; active controllers recreate theirs.
function M.reclaim_session_lines()
    if session_lines_reclaimed then
        return
    end
    session_lines_reclaimed = true
    for _, object in pairs(rendering.get_all_objects(script.mod_name)) do
        if object.valid and object.type == "line" then
            object.destroy()
        end
    end
    -- Do not retain invalid handles if this is invoked after initialization in
    -- a newly created session rather than after loading an existing save.
    for key, objects in pairs(owned) do
        local retained = {}
        for _, object in pairs(objects or {}) do
            if object and object.valid then
                retained[#retained + 1] = object
            end
        end
        owned[key] = retained
    end
end

---Resolve which player may see a role-owned rendering.
local function player_filter(player_index, key)
    -- Most callers provide the owner explicitly. Older/internal call sites encode
    -- it at the beginning of keys such as `3:repair`; parse that as a fallback.
    -- Map/site keys do not begin with digits and correctly produce nil here.
    local index = player_index or tonumber(key:match("^(%d+):"))
    local player = index and game.get_player(index)
    if not (player and player.valid) then
        return nil
    end
    -- The rendering API expects an array of permitted player indices, not a
    -- single scalar. Restricting it prevents one player's bot UI leaking to all.
    return {player.index}
end

---Destroy every transient rendering owned by a logical key.
function M.clear_role(key)
    for _, object in pairs(owned[key] or {}) do
        if object and object.valid then
            object.destroy()
        end
    end
    -- Retain an empty bucket rather than nil so repeated clear/update calls have
    -- a consistent iterable value and cannot rediscover destroyed handles.
    owned[key] = {}
end

---Create or update the line connecting a bot to its current target.
function M.target_line(key, from, to, player_index)
    if not (from and from.valid and to) or to.valid == false then
        M.clear_role(key)
        return
    end
    local players = player_filter(player_index, key)
    if not players then
        M.clear_role(key)
        return
    end
    -- A target line has exactly one object. Reuse it when valid because changing
    -- endpoints is cheaper and visually smoother than destroy/recreate.
    local objects = owned[key]
    local line = objects and objects[1]
    if line and line.valid then
        line.from = from
        line.to = to
        return
    end
    M.clear_role(key)
    owned[key] = {rendering.draw_line {
        color = config.visuals.colors.target,
        width = 1,
        from = from,
        to = to,
        surface = from.surface,
        draw_on_ground = true,
        only_in_alt_mode = false,
        players = players
    }}
end

---Create or update the player-visible role/task label over a bot.
function M.bot_label(key, entity, role, task, player_index)
    -- Prefix labels separately because the base role key owns its target line.
    -- The two visuals can then be updated or cleared independently.
    local label_key = "label:" .. key
    local objects = owned[label_key]
    local label = objects and objects[1]
    local text = role .. ": " .. task
    if label and label.valid then
        label.text = text
        label.target = entity
        return
    end
    M.clear_role(label_key)
    if not (entity and entity.valid) then
        return
    end
    local players = player_filter(player_index, key)
    if not players then
        return
    end
    owned[label_key] = {rendering.draw_text {
        text = text,
        surface = entity.surface,
        target = entity,
        target_offset = config.visuals.label_offset,
        color = config.visuals.colors.label,
        scale = config.visuals.label_scale,
        alignment = "center",
        vertical_alignment = "top",
        only_in_alt_mode = false,
        players = players
    }}
end

---Draw a short-lived ring around a newly mapped entity.
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

---Draw a short-lived world-position marker for a destroyed player entity.
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

---Draw or refresh the marker identifying a player-selected cliff.
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

---Visualize remaining health as both arc length and a red-to-green gradient.
function M.health(key, entity)
    if not (entity and entity.valid and entity.health and entity.max_health) then
        return
    end
    -- Normalize health to [0,1]. The arc API also interprets its angle as a
    -- fraction of a full revolution, so this value drives length directly.
    local ratio = entity.health / entity.max_health;
    M.clear_role("health:" .. key)
    local bad, good = config.visuals.colors.health_bad, config.visuals.colors.health_good;
    -- Linear interpolation per channel: bad + (good - bad) * ratio. At zero it
    -- is exactly the bad color; at one it is exactly the good color.
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
        -- Factorio's draw_arc uses a fraction of one turn, not radians. The
        -- normalized health ratio therefore maps directly to visible arc length.
        angle = ratio,
        target = entity,
        surface = entity.surface,
        time_to_live = 180
    }}
end

---Schedule incremental deletion for all rendering keys with a prefix.
function M.begin_clear(root, prefix)
    root.visual_clear = {
        prefix = prefix,
        cursor = nil
    }
end

---Inspect and optionally destroy one owned rendering group.
function M.step_clear(root)
    local job = root.visual_clear;
    if not job then
        return false
    end
    -- Lua's `next(table, previous_key)` resumes hash-table iteration without
    -- materializing all keys. The cursor is transiently meaningful only while
    -- `owned` remains unchanged enough for this best-effort cleanup job.
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
        -- Use false rather than nil during `next` iteration. Deleting the current
        -- key can make the next cursor invalid in Lua; false removes ownership
        -- semantically while leaving the key available to resume iteration.
        owned[key] = false
    end
    return true
end

return M
