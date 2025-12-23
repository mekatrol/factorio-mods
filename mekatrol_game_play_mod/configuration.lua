local config = {}

----------------------------------------------------------------------
-- BOT TUNING
----------------------------------------------------------------------

config.bot = {
    update_interval = 1,

    movement = {
        step_distance = 0.18,
        follow_distance = 1.0,
        side_offset_distance = 2.0
    },

    search = {
        step_distance = 5.0,
        detection_radius = 32.0
    },

    survey = {
        radius = 6.0,
        arrival_threshold = 0.5 -- distance threshold for "arrived at frontier node"
    }
}

----------------------------------------------------------------------
-- MODES
----------------------------------------------------------------------

config.modes = {
    list = {"follow", "search", "survey", "move_to"},
    index = {}
}

for i, mode in ipairs(config.modes.list) do
    config.modes.index[mode] = i
end

return config

