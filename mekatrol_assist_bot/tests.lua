-- Lightweight pure checks run by maintainers and at initialization when debug=true.
local config = require("config")
local registry = require("role_registry")
local formation = require("formation")
local validate = require("validate")
local polygon = require("polygon")
local discovery = require("discovery")
local command = require("commands")
local technology = require("technology")
local logistics = require("logistics")
local repair_role = require("bot_role_repair")
local cleanup_role = require("bot_role_cleanup")
local track_role = require("bot_role_track")
local upgrade_role = require("bot_role_upgrade")
local manager = require("bot_manager")
local pathfinding = require("pathfinding")
local M = {}

---Assert exact equality while adding consistent mod-specific context.
local function eq(a, b, message)
    if a ~= b then
        error("MAB test failed: " .. message .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
    end
end

---Run deterministic unit-style checks that require no temporary world fixture.
function M.run()
    validate.run(config, registry.roles)
    local odd = formation.slots({"builder", "repair", "upgrade"}, "right");
    eq(odd.repair.y, 0, "odd formation centers middle slot")
    local even = formation.slots({"builder", "repair"}, "right");
    eq(even.builder.y, -even.repair.y, "even formation is symmetric")
    eq(registry.get("s").name, "surveyor", "s alias")
    eq(registry.has_task(registry.get("builder"), "construct"), true, "builder construct task")
    eq(registry.has_task(registry.get("logistics"), "pickup"), true, "logistics pickup task")
    eq(logistics.first_product_name({{name = "rail", count = 1}}, "straight-rail"), "rail",
        "builder resolves placement item from prototype metadata")
    local square = {{
        x = 0,
        y = 0
    }, {
        x = 2,
        y = 0
    }, {
        x = 2,
        y = 2
    }, {
        x = 0,
        y = 2
    }};
    eq(polygon.area(square), 4, "polygon area");
    eq(polygon.contains(square, {
        x = 1,
        y = 1
    }), true, "polygon membership")
    local fake = {
        unit_number = 42
    };
    eq(discovery.identity(fake), "u:42", "stable unit identity")
    local order = {};
    local records = {};
    eq(discovery.store(order, records, "u:42", {name = "first"}), true, "first identity is inserted")
    eq(discovery.store(order, records, "u:42", {name = "updated"}), false, "duplicate identity is updated")
    eq(#order, 1, "duplicate identity is not appended")
    eq(records["u:42"].name, "updated", "duplicate identity refreshes its record")
    local contained_edge = polygon.contains(square, {x = 0.5, y = 1})
    eq(contained_edge, true, "survey polygon membership remains deterministic")
    local parsed = command.parse("u task combined");
    eq(parsed.role_name, "upgrade", "command parser expands role alias")
    eq(parsed.action, "task", "command parser extracts action")
    eq(parsed.arguments[3], "combined", "command parser preserves task")
    eq(#technology.missing_from({a = true}, {"a", "b"}, "all"), 1, "all gate reports missing technology")
    eq(#technology.missing_from({a = true}, {"a", "b"}, "any"), 0, "any gate accepts one technology")
    eq(#technology.missing_from({}, {}, "all"), 0, "empty technology gate is open")
    local player_force = {}
    local enemy_force = {}
    local damaged = {name = "test", force = player_force, health = 50, max_health = 100}
    eq(repair_role.valid(damaged, nil, {force = player_force}), true,
        "repair accepts a damaged entity on the player's force")
    damaged.force = enemy_force
    eq(repair_role.valid(damaged, nil, {force = player_force}), false,
        "repair rejects a damaged entity on another force")
    eq(pathfinding.within_goal({x = 9, y = 10}, {x = 10.99, y = 10.99}, 1.5), false,
        "repair path does not stop outside exact interaction range near a tile edge")
    eq(pathfinding.within_goal({x = 10, y = 10}, {x = 10.99, y = 10.99}, 1.5), true,
        "repair path accepts a tile centre inside exact interaction range")
    local repair_position = {x = 17, y = -4}
    local repair_scan_state = {repair_chain_scan = true}
    eq(repair_role.scan_center(repair_scan_state, {position = {x = 0, y = 0}}, {position = repair_position}),
        repair_position,
        "repair chains its next scan from the bot position")
    eq(repair_role.scan_phase(repair_scan_state), "moving",
        "repair remains in place during a chained scan")
    eq(cleanup_role.should_flush_cargo({task = "cleanup", cargo_count = config.supply.cleanup_capacity - 1}), false,
        "cleanup retains partial cargo while more items may remain")
    eq(cleanup_role.should_flush_cargo({task = "cleanup", cargo_count = config.supply.cleanup_capacity}), true,
        "cleanup flushes cargo at capacity")
    eq(cleanup_role.should_flush_cargo({task = "cleanup", cargo_count = 1, scan = {done = true}}), true,
        "cleanup flushes partial cargo after exhausting its search")
    eq(cleanup_role.should_flush_cargo({task = "follow", cargo_count = 1}), true,
        "cleanup flushes retained cargo after changing tasks")
    eq(cleanup_role.scan_phase({cargo_count = 0}), "idle", "empty cleanup bot follows while watching")
    eq(cleanup_role.scan_phase({cargo_count = 1}), "moving", "cleanup does not follow formation between pickups")
    eq(cleanup_role.scan_phase({cargo_count = 0, target = {valid = true}}), "moving",
        "cleanup stops following after selecting a target")
    eq(cleanup_role.cargo_phase(false), "working", "cleanup does not follow formation while finding a chest")
    eq(cleanup_role.cargo_phase(nil), "idle", "cleanup may follow while waiting for player inventory space")
    eq(track_role.scan_phase, "idle", "track follows formation while searching for a belt graph")
    eq(upgrade_role.scan_phase, "idle", "upgrade follows formation while searching for a target")
    eq(manager.activity({phase = "idle", task = "combined", waiting_inventory = "fast-transport-belt"}),
        "follow (fast-transport-belt)", "inventory wait label names the required item")
    eq(manager.activity({phase = "idle", task = "track"}), "follow", "ordinary idle label remains follow")
    local allowed = technology.task_allowed({recipes = {}}, "track", "track")
    eq(allowed, true, "track may wait for later recipe research")
    local many = formation.slots({"builder", "repair", "upgrade", "track", "lamp", "cliff", "logistics", "cleanup",
                                  "mapper", "surveyor"}, "right");
    eq(many.surveyor.x, many.builder.x, "all roles remain in one trailing column")
    eq(formation.has_unique_slots(many), true, "formation slots never overlap")
    local mirrored = formation.slots({"builder", "repair", "upgrade", "track", "lamp", "cliff", "logistics", "cleanup",
                                      "mapper", "surveyor"}, "left")
    for role, slot in pairs(many) do
        eq(mirrored[role].x, -slot.x, "formation mirrors role " .. role)
        eq(mirrored[role].y, slot.y, "formation mirror preserves row for " .. role)
    end
    local upward = formation.slots({"builder", "repair", "upgrade"}, "up")
    eq(upward.repair.y, config.formation.side_distance, "upward travel puts bots below player")
    eq(upward.builder.x, -upward.upgrade.x, "upward formation spreads horizontally")
    local downward = formation.slots({"builder", "repair", "upgrade"}, "down")
    eq(downward.repair.y, -config.formation.side_distance, "downward travel puts bots above player")
    eq(downward.builder.x, -downward.upgrade.x, "downward formation spreads horizontally")
    eq(downward.builder.x, upward.builder.x, "vertical reversal preserves role order")
    local reflowed = formation.slots({"builder", "upgrade", "track", "lamp", "cliff"}, "right")
    eq(formation.has_unique_slots(reflowed), true, "formation remains unique after disable reflow")
    eq(reflowed.builder.y, -reflowed.cliff.y, "shortened column remains centered")
    return true
end

return M
