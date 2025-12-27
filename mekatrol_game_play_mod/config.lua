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
    },

    ["mapper"] = {
        follow_offset_y = -2,
        highlight_color = {
            r = 0.5,
            g = 0.5,
            b = 0.5,
            a = 0.3
        }
    },

    ["repairer"] = {
        follow_offset_y = -0.666,
        highlight_color = {
            r = 0.5,
            g = 0.0,
            b = 0.0,
            a = 0.3
        }
    },

    ["constructor"] = {
        follow_offset_y = 0.666,
        highlight_color = {
            r = 0.0,
            g = 0.5,
            b = 0.0,
            a = 0.3
        }
    },

    ["cleaner"] = {
        follow_offset_y = 2,
        highlight_color = {
            r = 0.0,
            g = 0.0,
            b = 0.5,
            a = 0.3
        }
    }
}

config.bot_names = {"mapper", "repairer", "constructor", "cleaner"}

function config.get_bot_config(bot_name)
    return config.bot[bot_name]
end

return config

