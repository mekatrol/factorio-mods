-- Owns the sole persistent root and save-safe player/role records.
local config = require("config")
local M = {}

---Return the mod's sole persistent root, repairing additive fields as needed.
---This lazy normalization is intentionally safe to call from every subsystem:
---old saves gain newly introduced tables before any caller indexes them.
function M.root()
    -- `storage` is Factorio 2.0's save-serialized global table. The `or`
    -- preserves an existing save verbatim; the literal is used only for a new
    -- game or a save which has never loaded this mod.
    storage.mekatrol_assist_bot = storage.mekatrol_assist_bot or {
        schema_version = config.schema_version,
        players = {},
        discovery = {
            records = {},
            order = {},
            by_name = {},
            groups = {},
            grouped = {},
            queues = {}
        },
        cliffs = {},
        destroyed_sites = {},
        scheduler = {
            cursor = 1
        }
    }
    local r = storage.mekatrol_assist_bot;
    -- These additive defaults are intentionally outside the initial literal.
    -- That makes loading an older schema safe before the incremental migration
    -- has had scheduler time to finish.
    r.destroyed_sites = r.destroyed_sites or {};
    r.discovery.by_name = r.discovery.by_name or {}
    r.discovery.grouped = r.discovery.grouped or {}
    r.discovery.queues = r.discovery.queues or {}
    if not r.discovery.index_version then
        -- Rebuild the secondary name index once for saves created before it
        -- existed. The authoritative records remain untouched.
        for id, record in pairs(r.discovery.records) do
            local bucket = r.discovery.by_name[record.name] or {}
            bucket[id] = true
            r.discovery.by_name[record.name] = bucket
        end
        r.discovery.index_version = 1
    end
    return r
end

---Return or initialize one player's persistent state and every role record.
function M.player(index)
    local r = M.root();
    local p = r.players[index]
    if not p then
        -- Direction 1 is the legacy representation of "right" and remains
        -- accepted by formation.lua, allowing old and new saves to coexist.
        p = {
            roles = {},
            direction = 1,
            last_position = nil
        };
        r.players[index] = p
    end
    if not p.scheduler_registered then
        -- Stable numeric ordering makes round-robin behavior deterministic and
        -- ensures a player is registered exactly once across repeated calls.
        r.scheduler.player_order = r.scheduler.player_order or {};
        r.scheduler.player_order[#r.scheduler.player_order + 1] = index;
        table.sort(r.scheduler.player_order);
        p.scheduler_registered = true
    end
    for _, name in ipairs(config.formation.role_order) do
        -- Preserve existing role state, including in-progress serializable jobs.
        -- Only roles absent from an old save receive a fresh default record.
        p.roles[name] = p.roles[name] or {
            enabled = false,
            task = config.roles[name].default_task,
            phase = "idle",
            cargo = {}
        }
    end
    return p
end

---Return the next player/role pair from the global round-robin cursor.
---The cursor advances even for disabled roles; the scheduler decides whether
---the returned record warrants work. This prevents one player from consuming
---the budget simply because more of their bots are enabled.
function M.next_role()
    local r = M.root();
    local s = r.scheduler;
    s.player_order = s.player_order or {};
    if #s.player_order == 0 then
        return nil
    end
    -- Lua arrays are one-based. A missing cursor therefore begins at one, not
    -- zero; persisted cursors resume rather than restarting each tick.
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
        -- Player deletion normally removes the index eagerly. Recursing skips
        -- any stale entry left by an unusual event ordering.
        return M.next_role()
    end
    return {
        player_index = pi,
        name = name,
        state = p.roles[name]
    }
end

return M
