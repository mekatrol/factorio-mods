-- Runtime composition root. All expensive work enters the shared scheduler.
local config = require("config")
local registry = require("role_registry")
require("validate").run(config, registry.roles)
local constants = require("constants")
local state = require("state")
local manager = require("bot_manager")
local scheduler = require("scheduler")
local scanner = require("entity_scanner")
local discovery = require("discovery")
discovery.set_registry(registry)
local technology = require("technology")
local command = require("commands")
local tests = require("tests")
local runtime_tests = require("runtime_tests")
local visuals = require("visuals")

command.register()

---Initialize validated persistent/runtime state after creation or mod changes.
---The operation is idempotent because configuration changes may invoke it on
---an established save; each subsystem repairs or resumes its own state.
local function initialize()
    tests.run();
    technology.validate();
    local root = state.root();
    root.destroyed_visual_job = {cursor = nil}
    runtime_tests.run()
    for _, p in pairs(game.players) do
        local ps = state.player(p.index);
        for _, role in ipairs(config.formation.role_order) do
            if ps.roles[role].enabled then
                local ok = manager.enable(p.index, role, true);
                if not ok then
                    manager.disable(p.index, role)
                end
            end
        end
    end
end

script.on_init(initialize)

script.on_configuration_changed(initialize)

script.on_event(defines.events.on_tick, scheduler.tick)

-- Player removal is the one lifecycle point where persistent role records and
-- transient bot/rendering objects must both be discarded.
script.on_event(defines.events.on_player_removed, function(e)
    manager.remove_player(e.player_index)
end)

-- Register new players immediately so their position in the deterministic
-- scheduler order does not depend on which command they use first.
script.on_event(defines.events.on_player_created, function(e)
    state.player(e.player_index)
end)

script.on_event({defines.events.on_research_finished, defines.events.on_research_reversed}, manager.enforce_gates)

-- Re-check destination-force technology requirements after a force change.
-- Visual robots remain neutral and outside player logistic networks.
script.on_event(defines.events.on_player_changed_force, function(e)
    local ps = state.player(e.player_index);
    for _, role in ipairs(config.formation.role_order) do
        local rs = ps.roles[role];
        if rs.enabled then
            local ok = manager.enable(e.player_index, role, true);
            if not ok then
                manager.disable(e.player_index, role, "technology requirement on new force")
            end
        end
    end
end)

-- Rejoining or respawning may replace the character used as anchor. `enable`
-- is idempotent and restores any visual entity that disappeared meanwhile.
script.on_event({defines.events.on_player_joined_game, defines.events.on_player_respawned}, function(e)
    local ps = state.player(e.player_index);
    for _, role in ipairs(config.formation.role_order) do
        if ps.roles[role].enabled then
            manager.enable(e.player_index, role, true)
        end
    end
end)

-- Each configured role gets a dedicated hotkey with identical toggle behavior.
for _, role in ipairs(config.formation.role_order) do
    script.on_event(constants.input(role), function(e)
        manager.toggle(e.player_index, role)
    end)
end

-- "All" means enable all when at least one role is off; only an already-complete
-- set is turned off. This makes the shortcut useful for recovering partial state.
script.on_event(constants.input("all"), function(e)
    local ps = state.player(e.player_index);
    local turn_on = false
    for _, r in ipairs(config.formation.role_order) do
        if not ps.roles[r].enabled then
            turn_on = true
            break
        end
    end
    for _, r in ipairs(config.formation.role_order) do
        if turn_on then
            manager.enable(e.player_index, r)
        else
            manager.disable(e.player_index, r, "all disabled")
        end
    end
end)

-- Map clearing changes logical state immediately; detached rendering and record
-- tables are reclaimed incrementally by background scheduler work.
script.on_event(constants.input("clear_map"), function(e)
    discovery.clear();
    local p = game.get_player(e.player_index);
    if p then
        p.print("[MAB] map cleared")
    end
end)

---Put the cliff selection tool in the invoking player's cursor.
local function planner(e)
    local p = game.get_player(e.player_index);
    if p then
        p.cursor_stack.set_stack {
            name = "mekatrol-assist-cliff-planner",
            count = 1
        }
    end
end

script.on_event(constants.input("cliff_planner"), planner)

script.on_event(defines.events.on_lua_shortcut, function(e)
    if e.prototype_name == "mekatrol-assist-cliff-planner" then
        planner(e)
    end
end)

---Queue a bounded area scan to mark or unmark cliffs selected by the tool.
local function selection(e, mark)
    if e.item ~= "mekatrol-assist-cliff-planner" then
        return
    end
    local root = state.root();
    root.selection_jobs = root.selection_jobs or {}
    root.selection_jobs[#root.selection_jobs + 1] = {
        mark = mark,
        scan = scanner.start_area(game.surfaces[e.surface_index], e.area, {
            type = "cliff"
        })
    }
end

script.on_event(defines.events.on_player_selected_area, function(e)
    selection(e, true)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(e)
    selection(e, false)
end)

---Create a stable key for a destroyed entity site.
local function site_key(entity)
    -- Quantize to sixteenth-tile coordinates. Entity positions can contain
    -- fractions and minor floating-point differences; fixed-point integers make
    -- a stable string key while remaining precise enough to distinguish normal
    -- neighbouring factory entities. Surface is included for cross-surface safety.
    return entity.surface.index .. ":" .. math.floor(entity.position.x * 16) .. ":" ..
               math.floor(entity.position.y * 16)
end

---Return whether a force is the player force or one of its friends.
local function belongs_to_player_force(force)
    if not force then
        return false
    end
    -- Checking live player force objects also supports custom player-created
    -- forces; hard-coding the force name "player" would miss those factories.
    for _, player in pairs(game.players) do
        if player.force == force then
            return true
        end
    end
    return false
end

script.on_event(defines.events.on_entity_died, function(e)
    local entity = e.entity;
    if not entity or not entity.valid then
        return
    end
    state.root().cliffs[discovery.identity(entity)] = nil
    -- Assist bots are implementation visuals, not destroyed factory sites.
    if belongs_to_player_force(entity.force) and not entity.name:find("^mekatrol%-assist%-") then
        local key = site_key(entity);
        state.root().destroyed_sites[key] = {
            surface_index = entity.surface.index,
            position = {
                x = entity.position.x,
                y = entity.position.y
            },
            name = entity.name,
            tick = e.tick
        };
        visuals.destroyed_site(key, entity.surface, entity.position)
    end
end)

---Record newly built entities in the discovery index.
local function built(e)
    local entity = e.entity or e.created_entity or e.destination;
    if entity and entity.valid then
        local key = site_key(entity);
        state.root().destroyed_sites[key] = nil;
        visuals.clear_role("site:" .. key)
    end
end

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity,
                 defines.events.script_raised_built, defines.events.script_raised_revive,
                 defines.events.on_entity_cloned}, built)
