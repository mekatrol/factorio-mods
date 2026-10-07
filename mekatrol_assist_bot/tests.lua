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
local supply = require("supply")
local cleanup_role = require("bot_role_cleanup")
local ammo_role = require("bot_role_ammo")
local track_role = require("bot_role_track")
local upgrade_role = require("bot_role_upgrade")
local lamp_role = require("bot_role_lamp")
local manager = require("bot_manager")
local pathfinding = require("pathfinding")
local M = {}

---Assert exact equality while adding consistent mod-specific context.
local function eq(a, b, message)
    if a ~= b then
        error("MAB test failed: " .. message .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
    end
end

---Assert approximate equality for geometry calculated with trigonometry.
local function near(a, b, message)
    if math.abs(a - b) > 0.000001 then
        error("MAB test failed: " .. message .. " (" .. tostring(a) .. " !~= " .. tostring(b) .. ")")
    end
end

---Run deterministic unit-style checks that require no temporary world fixture.
function M.run()
    validate.run(config, registry.roles)
    local odd = formation.slots({"builder", "repair", "upgrade"}, "right");
    near(odd.repair.y, 0, "odd formation centers middle slot")
    local even = formation.slots({"builder", "repair"}, "right");
    near(even.builder.y, -even.repair.y, "even formation is symmetric")
    eq(registry.get("s").name, "surveyor", "s alias")
    eq(registry.get("a").name, "ammo", "a alias")
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
    local supply_count = 1
    local supply_inventory = {
        get_item_count = function(name)
            return name == "repair-pack" and supply_count or 0
        end,
        remove = function(stack)
            local removed = math.min(stack.count, supply_count)
            supply_count = supply_count - removed
            return removed
        end
    }
    local supply_player = {
        position = {x = 10, y = 0},
        get_main_inventory = function()
            return supply_inventory
        end
    }
    local supply_bot = {
        valid = true,
        position = {x = 0, y = 0}
    }
    supply_bot.teleport = function(position)
        supply_bot.position = position
    end
    local supply_state = {}
    eq(supply.take(supply_state, supply_player, {surface = {}}, supply_bot, "repair-pack", 1), nil,
        "player supply travel yields the work unit")
    eq(supply_state.waiting_inventory, "repair-pack",
        "player supply travel suppresses target navigation")
    eq(supply_state.player_supply_name, "repair-pack",
        "player supply travel suppresses formation following")
    local quality_count = 2
    local quality_inventory = {
        get_item_count = function(item)
            return type(item) == "table" and item.quality == "rare" and quality_count or 0
        end,
        get_item_quality_counts = function(name)
            return name == "bulk-inserter" and {rare = quality_count} or {}
        end,
        remove = function(stack)
            local removed = stack.quality == "rare" and math.min(stack.count, quality_count) or 0
            quality_count = quality_count - removed
            return removed
        end
    }
    local quality_player = {
        position = {x = 0, y = 0},
        get_main_inventory = function() return quality_inventory end
    }
    supply_bot.position = {x = 0, y = 0}
    local quality_state = {}
    eq(supply.take(quality_state, quality_player, {surface = {}}, supply_bot, "bulk-inserter", 1, 2, true), nil,
        "upgrade supply accepts non-normal quality")
    eq(quality_state.supplied_qualities["bulk-inserter"], "rare",
        "upgrade supply records the withdrawn quality")
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
    eq(cleanup_role.cargo_phase(nil), "moving", "cleanup physically returns cargo to the player")
    local no_destination = {target = {valid = true}, best_distance = 1}
    ammo_role.after_scan(no_destination)
    eq(no_destination.target, nil, "ammo bot abandons turret when no yellow-ammo container exists")
    eq(ammo_role.scan_phase({}), "idle", "ammo bot follows while scanning without a container")
    eq(ammo_role.scan_phase({ammo_container = {}, ammo_waiting_turret = {}}), "moving",
        "ammo bot holds position once both ends of a job are known")
    local ammo_scan_origin = {x = 12, y = -7}
    eq(ammo_role.scan_center({}, {position = {x = 0, y = 0}}, {position = ammo_scan_origin}), ammo_scan_origin,
        "ammo bot chains its next scan from its delivery position")
    local function ammo_container(load, x, can_insert)
        local inv = {
            get_item_count = function(item)
                if item == nil then return load end
                return type(item) == "table" and item.name == config.tasks.ammo.item and 1 or 0
            end,
            can_insert = function() return can_insert end
        }
        return {
            valid = true,
            type = "container",
            position = {x = x, y = 0},
            get_inventory = function(id)
                return id == defines.inventory.chest and inv or nil
            end
        }
    end
    local ammo_scan_state = {}
    ammo_role.begin_scan(ammo_scan_state)
    local full_near_container = ammo_container(100, 1, false)
    local loaded_near_container = ammo_container(80, 2, true)
    local empty_far_container = ammo_container(10, 20, true)
    ammo_role.scan_entity(full_near_container, ammo_scan_state, nil, {position = {x = 0, y = 0}})
    ammo_role.scan_entity(loaded_near_container, ammo_scan_state, nil, {position = {x = 0, y = 0}})
    ammo_role.scan_entity(empty_far_container, ammo_scan_state, nil, {position = {x = 0, y = 0}})
    eq(ammo_scan_state.ammo_container, empty_far_container,
        "ammo bot prefers the container with the lowest inventory load")
    eq(ammo_scan_state.ammo_container_load, 10, "ammo bot records the selected container load")
    local partial_destination_inventory = {
        insert = function(stack) return math.min(stack.count, 3) end
    }
    local partial_destination = {
        valid = true,
        position = {x = 0, y = 0},
        get_inventory = function(id)
            return id == defines.inventory.chest and partial_destination_inventory or nil
        end
    }
    local partial_delivery_state = {
        cargo = {[config.tasks.ammo.item] = 8},
        cargo_order = {config.tasks.ammo.item},
        cargo_cursor = 1,
        cargo_count = 8,
        cargo_stacks = {[config.tasks.ammo.item] = {name = config.tasks.ammo.item, quality = "normal"}},
        cargo_destinations = {[config.tasks.ammo.item] = partial_destination},
        cargo_lowest_inventory = {[config.tasks.ammo.item] = true}
    }
    local stationary_bot = {valid = true, position = {x = 0, y = 0}}
    eq(supply.flush_cargo(partial_delivery_state, {}, stationary_bot), false,
        "partial ammo delivery retains the undelivered magazines")
    eq(partial_delivery_state.cargo[config.tasks.ammo.item], 5,
        "partial ammo delivery removes only the inserted magazines from cargo")
    eq(partial_delivery_state.cargo_destinations[config.tasks.ammo.item], false,
        "partial ammo delivery searches for another matching container")
    eq(partial_delivery_state.waiting_ammo_container, true,
        "partial ammo delivery enters the ammo-container wait state")
    eq(ammo_role.cargo_phase(false), "idle",
        "ammo bot follows formation while carrying ammo without a destination")
    eq(ammo_role.cargo_phase(partial_destination), "working",
        "ammo bot owns movement while delivering to a concrete container")
    eq(manager.activity({phase = "idle", task = "unload", waiting_ammo_container = true}), "follow (unload)",
        "carried ammo without container capacity is labelled follow unload")
    eq(track_role.scan_phase, "idle", "track follows formation while searching for a belt graph")
    eq(upgrade_role.scan_phase({}), "idle", "upgrade follows formation during an empty background scan")
    eq(upgrade_role.scan_phase({supplied = {["iron-chest"] = 4}}), "moving",
        "upgrade retains movement control between targets in a supply batch")
    eq(upgrade_role.scan_phase({cargo_count = 1}), "moving",
        "upgrade retains movement control while carrying recovered items")
    eq(lamp_role.scan_phase({scan = {}}), "idle", "lamp follows formation while watching for night work")
    eq(lamp_role.scan_phase({scan = {}, supplied = {["small-lamp"] = 4}}), "moving",
        "lamp retains movement control while carrying a placement batch")
    eq(lamp_role.before_step({}, {surface = {darkness = config.tasks.lamp.darkness - 0.01}}), "idle",
        "lamp follows formation rather than working during daylight")
    eq(lamp_role.before_step({}, {surface = {darkness = config.tasks.lamp.darkness}}), nil,
        "lamp work begins at the configured night threshold")
    eq(config.scheduler.role_intervals.lamp, 1, "lamp navigation runs every tick for smooth full-speed movement")
    eq(manager.activity({phase = "idle", task = "combined", waiting_inventory = "fast-transport-belt"}),
        "follow (fast-transport-belt: red)", "upgrade inventory wait label includes the item colour")
    eq(manager.activity({phase = "idle", task = "combined", waiting_inventory = "bulk-inserter"}),
        "follow (bulk-inserter: green)", "bulk inserter wait label distinguishes it from the blue fast inserter")
    eq(manager.activity({phase = "idle", task = "combined", waiting_inventory = "iron-chest"}),
        "follow (iron-chest)", "non-colour-coded upgrades omit a colour")
    eq(manager.activity({phase = "idle", task = "repair", waiting_inventory = "repair-pack"}),
        "follow (repair-pack)", "non-upgrade inventory wait labels remain unchanged")
    eq(manager.activity({phase = "idle", task = "track"}), "follow", "ordinary idle label remains follow")
    eq(manager.activity({phase = "idle", task = "unload", waiting_ammo_container = true}), "follow (unload)",
        "ammo container wait is shown as a follow substate")
    local allowed = technology.task_allowed({recipes = {}}, "track", "track")
    eq(allowed, true, "track may wait for later recipe research")
    local many = formation.slots(config.formation.role_order, "right");
    near(many.surveyor.x, many.builder.x, "arc endpoints have equal trailing distance")
    near(many.builder.y, -many.surveyor.y, "arc endpoints are symmetric")
    eq(formation.has_unique_slots(many), true, "formation slots never overlap")
    local previous
    for _, role in ipairs(config.formation.role_order) do
        local slot = many[role]
        eq(slot.x < 0, true, "rightward arc keeps role " .. role .. " behind player")
        if previous then
            local dx, dy = slot.x - previous.x, slot.y - previous.y
            eq(dx * dx + dy * dy >= config.formation.slot_spacing ^ 2 - 0.000001, true,
                "adjacent arc slots preserve configured clearance")
        end
        previous = slot
    end
    local mirrored = formation.slots(config.formation.role_order, "left")
    for role, slot in pairs(many) do
        near(mirrored[role].x, -slot.x, "formation mirrors role " .. role)
        near(mirrored[role].y, slot.y, "formation mirror preserves row for " .. role)
    end
    local upward = formation.slots({"builder", "repair", "upgrade"}, "up")
    near(upward.repair.y, config.formation.radius, "upward travel puts center bot below player")
    near(upward.builder.x, -upward.upgrade.x, "upward formation spreads horizontally")
    local downward = formation.slots({"builder", "repair", "upgrade"}, "down")
    near(downward.repair.y, -config.formation.radius, "downward travel puts center bot above player")
    near(downward.builder.x, -downward.upgrade.x, "downward formation spreads horizontally")
    near(downward.builder.x, upward.builder.x, "vertical reversal preserves role order")
    local reflowed = formation.slots({"builder", "upgrade", "track", "lamp", "cliff"}, "right")
    eq(formation.has_unique_slots(reflowed), true, "formation remains unique after disable reflow")
    near(reflowed.builder.y, -reflowed.cliff.y, "shortened arc remains centered")
    return true
end

return M
