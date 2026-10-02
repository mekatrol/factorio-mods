-- Data-stage definitions: controls, planner, shortcuts, and neutral scripted robots.
local config = require("config")
local constants = require("constants")

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

local function prototype(role, family, state)
    local base = data.raw[family .. "-robot"][family .. "-robot"]
    if not base then
        error("mekatrol_assist_bot: missing base " .. family .. "-robot")
    end
    local p = table.deepcopy(base)
    p.name = constants.prototype(role, state);
    p.localised_name = {"entity-name.mekatrol-assist-bot", role}
    p.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
    p.max_payload_size = 0;
    p.construction_radius = 0;
    p.logistic_radius = 0;
    p.energy_per_move = "0J";
    p.energy_per_tick = "0J"
    if state == "idle" then
        p.in_motion = table.deepcopy(base.idle);
        p.shadow_in_motion = table.deepcopy(base.shadow_idle)
    elseif state == "working" then
        p.idle = table.deepcopy(base.working or base.idle);
        p.in_motion = table.deepcopy(base.working or base.in_motion);
        p.shadow_idle = table.deepcopy(base.shadow_working or base.shadow_idle);
        p.shadow_in_motion = table.deepcopy(base.shadow_working or base.shadow_in_motion)
    end
    return p
end

local out = {}

for _, role in ipairs(config.formation.role_order) do
    for _, state in ipairs {"idle", "moving", "working"} do
        out[#out + 1] = prototype(role, config.roles[role].prototype_family, state)
    end
end

data:extend(out)
