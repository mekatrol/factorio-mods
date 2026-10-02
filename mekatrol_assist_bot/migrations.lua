-- Incremental legacy import. It copies intent/data, never legacy entity/render handles.
local config = require("config")
local state = require("state")
local discovery = require("discovery")
local M = {}

local function copy_enabled(dst, src, role)
    if src and src.enabled ~= nil then
        dst.roles[role].enabled = src.enabled
    end
    if src and src.task_name then
        dst.roles[role].task = src.task_name
    end
end

function M.run()
    local root = state.root();
    local previous_schema = root.schema_version or 1
    if previous_schema < config.schema_version then
        root.scheduler = root.scheduler or {};
        root.destroyed_sites = root.destroyed_sites or {};
        if previous_schema < 5 then
            for pi, legacy in pairs((storage.mekatrol_repair_mod and storage.mekatrol_repair_mod.players) or {}) do
                local dst = state.player(pi).roles.repair
                dst.repair_health_pool = tonumber(legacy.repair_health_pool) or dst.repair_health_pool or 0
            end
        end
        root.schema_version = config.schema_version
    end
    if root.import_complete or not config.compatibility.import_legacy_state then
        return
    end
    local old = storage.mekatrol_game_bot
    if old then
        for pi, v in pairs(old.players or {}) do
            copy_enabled(state.player(pi), v, "upgrade")
        end
        for pi, v in pairs(old.track_players or {}) do
            copy_enabled(state.player(pi), v, "track")
        end
        for pi, v in pairs(old.cleanup_players or {}) do
            copy_enabled(state.player(pi), v, "cleanup")
        end
        for pi, v in pairs(old.lamp_players or {}) do
            copy_enabled(state.player(pi), v, "lamp")
        end
        for pi, v in pairs(old.cliff_players or {}) do
            copy_enabled(state.player(pi), v, "cliff")
        end
    end
    local map = storage.mapping_bot_mod
    if map then
        for pi, v in pairs(map.players or {}) do
            if v.mapping_bot_enabled ~= nil then
                state.player(pi).roles.mapper.enabled = v.mapping_bot_enabled
            end
        end
    end
    local gp = storage.mekatrol_game_play_bot
    if gp then
        for pi, v in pairs(gp) do
            if type(pi) == "number" and v.bot_enabled then
                for _, r in ipairs {"builder", "logistics", "mapper", "repair", "surveyor"} do
                    state.player(pi).roles[r].enabled = true
                end
            end
        end
    end
    local repair = storage.mekatrol_repair_mod
    if repair and repair.players then
        for pi, v in pairs(repair.players) do
            local dst = state.player(pi).roles.repair;
            if v.repair_bot_enabled ~= nil then
                dst.enabled = v.repair_bot_enabled
            else
                copy_enabled(state.player(pi), v, "repair")
            end
            dst.repair_health_pool = tonumber(v.repair_health_pool) or dst.repair_health_pool or 0
        end
    end
    if old or map or gp or repair then
        root.migration = {
            phase = "mapping",
            cursor = nil,
            done = false
        }
    end
    root.schema_version = config.schema_version;
    root.import_complete = true
end

function M.step()
    local root = state.root();
    local job = root.migration;
    if not job or job.done then
        return false
    end
    if job.phase == "mapping" then
        local source = storage.mapping_bot_mod and storage.mapping_bot_mod.shared_mapped_entities or {};
        local k, e = next(source, job.cursor);
        job.cursor = k
        if k ~= nil then
            if e and e.valid then
                discovery.add(e)
            end
            return true
        end
        job.phase = "gameplay";
        job.cursor = nil;
        job.player_cursor = nil;
        job.entity_cursor = nil;
        return true
    end
    if job.phase == "gameplay" then
        local source = storage.mekatrol_game_play_bot or {}
        if not job.player_cursor then
            local k, ps = next(source, job.cursor);
            job.cursor = k;
            if k == nil then
                job.phase = "destroyed";
                job.cursor = nil;
                return true
            end
            if type(k) == "number" then
                job.player_cursor = k;
                job.entity_cursor = nil
            else
                return true
            end
        end
        local ps = source[job.player_cursor];
        local records = ps and ps.discovered_entities and ps.discovered_entities.by_id or {};
        local k, wrap = next(records, job.entity_cursor);
        job.entity_cursor = k
        if k == nil then
            job.player_cursor = nil;
            job.entity_cursor = nil;
            return true
        end
        if wrap and wrap.entity and wrap.entity.valid then
            discovery.add(wrap.entity)
        end
        return true
    end
    local sites = storage.mekatrol_repair_mod and storage.mekatrol_repair_mod.destroyed_sites or {}
    if not job.surface_cursor then
        local k, list = next(sites, job.cursor);
        job.cursor = k;
        if k == nil then
            job.done = true;
            return false
        end
        job.surface_cursor = k;
        job.site_index = 1
    end
    local list = sites[job.surface_cursor] or {};
    local site = list[job.site_index];
    job.site_index = job.site_index + 1
    if not site then
        job.surface_cursor = nil;
        return true
    end
    local x, y = site.x or site.position.x, site.y or site.position.y;
    local key = job.surface_cursor .. ":" .. math.floor(x * 16) .. ":" .. math.floor(y * 16);
    root.destroyed_sites[key] = {
        surface_index = job.surface_cursor,
        position = {
            x = x,
            y = y
        },
        name = site.name,
        tick = 0
    };
    return true
end

return M
