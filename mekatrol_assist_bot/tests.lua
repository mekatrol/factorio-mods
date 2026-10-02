-- Lightweight pure checks run by maintainers and at initialization when debug=true.
local config = require("config")
local registry = require("role_registry")
local formation = require("formation")
local validate = require("validate")
local polygon = require("polygon")
local discovery = require("discovery")
local command = require("commands")
local technology = require("technology")
local M = {}

local function eq(a, b, message)
    if a ~= b then
        error("MAB test failed: " .. message .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
    end
end

function M.run()
    validate.run(config, registry.roles)
    local odd = formation.slots({"builder", "repair", "upgrade"}, 1);
    eq(odd.repair.y, 0, "odd formation centers middle slot")
    local even = formation.slots({"builder", "repair"}, 1);
    eq(even.builder.y, -even.repair.y, "even formation is symmetric")
    eq(registry.get("s").name, "surveyor", "s alias");
    eq(registry.get("v").name, "surveyor", "legacy v alias")
    eq(registry.has_task(registry.get("builder"), "construct"), true, "builder construct task")
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
    local parsed = command.parse("u task combined");
    eq(parsed.role_name, "upgrade", "command parser expands role alias")
    eq(parsed.action, "task", "command parser extracts action")
    eq(parsed.arguments[3], "combined", "command parser preserves task")
    local legacy = command.parse("", "upgrade");
    eq(legacy.bare_forced, true, "legacy bare command is identified")
    eq(legacy.action, "toggle", "legacy bare command defaults action")
    eq(#technology.missing_from({a = true}, {"a", "b"}, "all"), 1, "all gate reports missing technology")
    eq(#technology.missing_from({a = true}, {"a", "b"}, "any"), 0, "any gate accepts one technology")
    eq(#technology.missing_from({}, {}, "all"), 0, "empty technology gate is open")
    local many = formation.slots({"builder", "repair", "upgrade", "track", "lamp", "cliff"}, 1);
    eq(many.cliff.x ~= many.builder.x, true, "formation creates another column")
    return true
end

return M
