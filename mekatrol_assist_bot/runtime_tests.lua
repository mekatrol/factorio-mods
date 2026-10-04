-- Opt-in integration checks using real Factorio objects when config.debug is true.
local config = require("config")
local scanner = require("entity_scanner")
local constants = require("constants")
local formation = require("formation")
local movement = require("movement")
local M = {}

local function create(surface, params)
    local ok, entity = pcall(surface.create_entity, params)
    return ok and entity or nil
end

local function validate_catalogue()
    for _, name in ipairs {"construction-robotics", "logistic-robotics", "repair-pack", "lamp",
                           "cliff-explosives", "electronics"} do
        assert(prototypes.technology[name], "MAB prototype catalogue missing technology: " .. name)
    end
    for _, name in ipairs {"construction-robot", "logistic-robot", "repair-pack", "small-lamp",
                           "cliff-explosives", "transport-belt", "fast-transport-belt",
                           "express-transport-belt", "turbo-transport-belt"} do
        assert(prototypes.item[name] or prototypes.entity[name],
            "MAB prototype catalogue missing item/entity: " .. name)
    end
    for _, role in ipairs(config.formation.role_order) do
        local expected_type = config.roles[role].prototype_family .. "-robot"
        for _, visual in ipairs {"idle", "moving", "working"} do
            local name = constants.prototype(role, visual)
            local prototype = assert(prototypes.entity[name], "MAB missing visual prototype: " .. name)
            assert(prototype.type == expected_type,
                "MAB visual prototype family mismatch: " .. name .. " is " .. prototype.type)
        end
    end
end

local function run_headless_baseline()
    local surface = game.surfaces[1]
    local slots = formation.slots(config.formation.role_order, "right")
    local bots = {}
    for _, role in ipairs(config.formation.role_order) do
        bots[#bots + 1] = assert(create(surface, {
            name = constants.prototype(role, "moving"), position = {0, 0}, force = "neutral"
        }), "MAB baseline could not create role bot: " .. role)
    end
    for tick = 1, 900 do
        for i, role in ipairs(config.formation.role_order) do
            local slot = slots[role]
            movement.step(bots[i], {x = slot.x + (tick % 120 < 60 and 8 or -8), y = slot.y})
        end
    end

    local field_surface = game.create_surface("mab-baseline-field", {})
    for x = 0, 63 do
        for y = 0, 63 do
            create(field_surface, {name = "iron-ore", position = {x, y}, amount = 1000})
        end
    end
    local scan = scanner.start_area(field_surface, {{0, 0}, {64, 64}}, {type = "resource"})
    local found_count = 0
    repeat
        local done, found = scanner.step(scan)
        found_count = found_count + #found
    until done
    assert(found_count >= 4096, "MAB large-field scan missed resource entities")
    log("[MAB test] headless baseline passed on Factorio " .. script.active_mods.base)
end

function M.run()
    if config.debug then
        validate_catalogue()
        run_headless_baseline()
    end
end

return M
