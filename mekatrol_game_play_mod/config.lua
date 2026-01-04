local config = {}

----------------------------------------------------------------------
-- BOT TUNING
----------------------------------------------------------------------

config.bot = {
    update_interval = 1,
    remove_discovered_tick_duration = 1000,

    movement = {
        step_distance = 0.18,
        follow_distance = 1.0,
        side_offset_distance = 2.0
    },

    search = {
        step_distance = 5.0,
        detection_radius = 64.0
    },

    survey = {
        radius = 16,
        arrival_threshold = 0.5 -- distance threshold for "arrived at frontier node"
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

    ["logistics"] = {
        follow_offset_y = 2,
        highlight_color = {
            r = 0.0,
            g = 0.0,
            b = 0.5,
            a = 0.3
        }
    },
    
    ["mapper"] = {
        follow_offset_y = -3.333,
        highlight_color = {
            r = 0.5,
            g = 1.0,
            b = 0.0,
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
    
    ["surveyor"] = {
        follow_offset_y = -2,
        highlight_color = {
            r = 0.5,
            g = 0.5,
            b = 0.5,
            a = 0.3
        }
    }
}

config.bot_names = {"constructor", "logistics", "mapper", "repairer", "surveyor"}

function config.get_bot_config(bot_name)
    return config.bot[bot_name]
end

return config

