local config = {}

----------------------------------------------------------------------
-- BOT TUNING
----------------------------------------------------------------------

config.bot = {
    update_interval = 1,
    update_hull_interval = 1000,

    movement = {
        step_distance = 0.18,
        follow_distance = 1.0,
        side_offset_distance = 2.0,
    },

    wander = {
        step_distance = 5.0,
        detection_radius = 5.0,
    },

    survey = {
        radius = 6.0,
        arrival_threshold = 0.5, -- distance threshold for "arrived at frontier node"
    },
}

----------------------------------------------------------------------
-- MODES
----------------------------------------------------------------------

config.modes = {
    list = { "follow", "wander", "survey" },
    index = {}
}

for i, mode in ipairs(config.modes.list) do
    config.modes.index[mode] = i
end

----------------------------------------------------------------------
-- NON-MAPPABLE TYPES
----------------------------------------------------------------------

config.non_static_types = {
    character = true,
    car = true,
    ["spider-vehicle"] = true,
    locomotive = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,

    unit = true,
    ["unit-spawner"] = true,

    corpse = true,
    ["character-corpse"] = true,

    fish = true,

    ["combat-robot"] = true,
    ["construction-robot"] = true,
    ["logistic-robot"] = true,

    projectile = true,
    beam = true,
    ["flying-text"] = true,
    smoke = true,
    fire = true,
    stream = true,
    decorative = true,
}

return config
