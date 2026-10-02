-- Owns the sole persistent root and save-safe player/role records.
local config = require("config")
local M = {}

function M.root()
    storage.mekatrol_assist_bot = storage.mekatrol_assist_bot or {
        schema_version = config.schema_version,
        players = {},
        discovery = {
            records = {},
            order = {},
            groups = {}
        },
        cliffs = {},
        destroyed_sites = {},
        scheduler = {
            cursor = 1
        }
    }
    local r = storage.mekatrol_assist_bot;
    r.destroyed_sites = r.destroyed_sites or {};
    return r
end

function M.player(index)
    local r = M.root();
    local p = r.players[index]
    if not p then
        p = {
            roles = {},
            direction = 1,
            last_position = nil
        };
        r.players[index] = p
    end
    if not p.scheduler_registered then
        r.scheduler.player_order = r.scheduler.player_order or {};
        r.scheduler.player_order[#r.scheduler.player_order + 1] = index;
        table.sort(r.scheduler.player_order);
        p.scheduler_registered = true
    end
    for _, name in ipairs(config.formation.role_order) do
        p.roles[name] = p.roles[name] or {
            enabled = false,
            task = config.roles[name].default_task,
            phase = "idle",
            cargo = {}
        }
    end
    return p
end

function M.next_role()
    local r = M.root();
    local s = r.scheduler;
    s.player_order = s.player_order or {};
    if #s.player_order == 0 then
        return nil
    end
    s.player_cursor = s.player_cursor or 1;
    s.role_cursor = s.role_cursor or 1
    if s.player_cursor > #s.player_order then
        s.player_cursor = 1
    end
    local pi = s.player_order[s.player_cursor];
    local name = config.formation.role_order[s.role_cursor];
    local p = r.players[pi]
    s.role_cursor = s.role_cursor + 1;
    if s.role_cursor > #config.formation.role_order then
        s.role_cursor = 1;
        s.player_cursor = s.player_cursor + 1
    end
    if not p then
        return M.next_role()
    end
    return {
        player_index = pi,
        name = name,
        state = p.roles[name]
    }
end

return M
