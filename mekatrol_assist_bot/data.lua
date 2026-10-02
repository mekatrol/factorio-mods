-- Data-stage definitions: controls, planner, shortcuts, and neutral scripted robots.
local config = require("config")
local constants = require("constants")
local robot_prototypes = require("robot_prototypes")

for _, role in ipairs(config.formation.role_order) do
    data:extend{{
        type = "custom-input",
        name = constants.input(role),
        key_sequence = config.controls[role],
        consuming = "none"
    }}
end

data:extend{{
    type = "custom-input",
    name = constants.input("all"),
    key_sequence = config.controls.all,
    consuming = "none"
}, {
    type = "custom-input",
    name = constants.input("clear_map"),
    key_sequence = config.controls.clear_map,
    consuming = "none"
}, {
    type = "custom-input",
    name = constants.input("cliff_planner"),
    key_sequence = config.controls.cliff_planner,
    consuming = "none"
}, {
    type = "selection-tool",
    name = "mekatrol-assist-cliff-planner",
    icon = "__base__/graphics/icons/cliff-explosives.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    subgroup = "tool",
    order = "c[automated-construction]-z[assist-cliff]",
    stack_size = 1,
    select = {
        border_color = {1, 0.5, 0.1},
        mode = {"nothing"},
        cursor_box_type = "entity"
    },
    alt_select = {
        border_color = {1, 0.1, 0.1},
        mode = {"nothing"},
        cursor_box_type = "entity"
    }
}, {
    type = "shortcut",
    name = "mekatrol-assist-cliff-planner",
    order = "b[blueprints]-z[assist-cliff]",
    action = "spawn-item",
    item_to_spawn = "mekatrol-assist-cliff-planner",
    associated_control_input = constants.input("cliff_planner"),
    icon = "__base__/graphics/icons/cliff-explosives.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/cliff-explosives.png",
    small_icon_size = 64
}}

local out = {}

for _, role in ipairs(config.formation.role_order) do
    local family = config.roles[role].prototype_family
    local builder = robot_prototypes[family]
    if not builder then
        error("mekatrol_assist_bot: unsupported prototype family for " .. role .. ": " .. tostring(family))
    end
    for _, state in ipairs {"idle", "moving", "working"} do
        out[#out + 1] = builder(role, state, constants.prototype(role, state))
    end
end

data:extend(out)
