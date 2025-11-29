data:extend({ -- Hotkey to toggle the wall bot
{
    type = "custom-input",
    name = "augment-toggle-wall-bot", -- THIS is the event name
    key_sequence = "CONTROL + SHIFT + W", -- change in-game if you like
    consuming = "none"
}, -- Flying wall-repair drone unit
{
    type = "unit",
    name = "augment-wall-drone",

    icon = "__core__/graphics/player-force-icon.png", -- exists on your system
    icon_size = 32,

    flags = {"placeable-neutral", "placeable-player", "not-on-map"},

    max_health = 100,
    order = "z[augment-drone]",

    distraction_cooldown = 300,
    vision_distance = 32,

    movement_speed = 0.15,
    distance_per_frame = 0.1,

    collision_box = {{0, 0}, {0, 0}},
    selection_box = {{-0.2, -0.2}, {0.2, 0.2}},
    drawing_box = {{-0.3, -0.3}, {0.3, 0.3}},

    attack_parameters = {
        type = "projectile",
        ammo_category = "melee",
        cooldown = 1000,
        range = 0.5,

        ammo_type = {
            category = "melee",
            action = {
                type = "direct",
                action_delivery = {
                    type = "instant"
                }
            }
        },

        -- minimal required attack animation
        animation = {
            layers = {{
                filename = "__core__/graphics/empty.png",
                width = 1,
                height = 1,
                frame_count = 1,
                direction_count = 1,
                shift = {0, 0}
            }}
        }
    },

    -- run/idle animation
    run_animation = {
        layers = {{
            filename = "__core__/graphics/goto-icon.png",
            width = 1,
            height = 1,
            frame_count = 1,
            direction_count = 1,
            shift = {0, 0}
        }}
    }
}})
