-- Public configuration for both Factorio stages. Keep this file free of runtime globals.
return {
    -- Persistent-state/configuration schema. Positive integer.
    schema_version = 7,
    controls = {
        -- Factorio key sequences. These defaults may be rebound in Controls > Mods.
        all = "CONTROL + SHIFT + A",
        builder = "CONTROL + SHIFT + B",
        cleanup = "CONTROL + SHIFT + C",
        cliff = "CONTROL + SHIFT + D",
        logistics = "CONTROL + SHIFT + G",
        lamp = "CONTROL + SHIFT + L",
        mapper = "CONTROL + SHIFT + M",
        repair = "CONTROL + SHIFT + R",
        surveyor = "CONTROL + SHIFT + S",
        track = "CONTROL + SHIFT + T",
        upgrade = "CONTROL + SHIFT + U",
        clear_map = "CONTROL + ALT + M",
        cliff_planner = "CONTROL + ALT + D"
    },
    scheduler = {
        -- Total scheduler work units shared by all players and roles each tick; integer >=1.
        work_per_tick = 24,
        -- Maximum units per tick spent on clearing, selection, and visual rebuilds; integer >=1.
        background_work_per_tick = 4,
        -- Ticks between formation-follow passes; keep at 1 for smooth pursuit.
        -- 60 ticks = one second.
        idle_interval = 1,
        -- Ticks between eligible work units for each role; registered role names, integers >=1.
        role_intervals = {
            builder = 1,
            repair = 1,
            upgrade = 1,
            track = 1,
            lamp = 6,
            cliff = 1,
            logistics = 1,
            cleanup = 1,
            mapper = 2,
            surveyor = 2
        }
    },
    formation = {
        role_order = {"builder", "repair", "upgrade", "track", "lamp", "cliff", "logistics", "cleanup", "mapper",
                      "surveyor"},
        slot_spacing = 1.333,
        side_distance = 2,
        column_spacing = 2, -- Tiles, finite >0.
        -- Keep every bot in one vertical column behind the player, as in the
        -- pre-consolidation follow implementation.
        max_slots_per_column = 10, -- Positive integer.
        direction_threshold = 0.1 -- Tiles of movement before choosing the trailing side; >0.
    },
    movement = {
        -- Values restored from mekatrol_game_play_mod's proven movement code.
        -- This is a per-bot, per-game-tick ceiling across all scheduler calls.
        step = 0.18,
        arrival_distance = 0.01
    }, -- Tiles per step / inclusive dead band; >0.
    scanning = {
        cell_size = 16, -- Query-cell width and height in tiles; finite >0.
        prune_interval = 30, -- Ticks between bounded stale-record pruning passes; integer >=1.
        prune_per_step = 16,
        entities_per_cell = 512 -- Work counts, integers >=1; dense cells yield capped batches.
    },
    supply = {
        radius = 48, -- Inclusive tile distance, finite >0.
        source_priority = {"player", "containers"}, -- Ordered unique policies: player and/or containers.
        cleanup_capacity = 100, -- Items, integer >=0; zero disables pickup.
        repair_pack_durability = 300 -- Health points per pack, finite >0.
    },
    tasks = {
        upgrade = {
            radius = 64,
            mode_radii = {
                ["blue-to-green-inserters"] = 10
            },
            mappings = {
                ["transport-belt"] = "fast-transport-belt",
                ["underground-belt"] = "fast-underground-belt",
                splitter = "fast-splitter",
                ["fast-transport-belt"] = "express-transport-belt",
                ["fast-underground-belt"] = "express-underground-belt",
                ["fast-splitter"] = "express-splitter",
                ["express-transport-belt"] = "turbo-transport-belt",
                ["express-underground-belt"] = "turbo-underground-belt",
                ["express-splitter"] = "turbo-splitter",
                ["burner-inserter"] = "inserter",
                inserter = "fast-inserter",
                ["fast-inserter"] = "bulk-inserter",
                ["wooden-chest"] = "iron-chest",
                ["iron-chest"] = "steel-chest"
            }
        }, -- Source-to-target entity/item prototype names; absent optional targets are skipped.
        track = {
            radius = 64
        },
        builder = {
            radius = 48
        },
        cleanup = {
            radius = 48
        },
        cliff = {
            radius = 64,
            projectile_speed = 0.3
        },
        logistics = {
            radius = 64,
            -- Inventory slots transferred by one scheduled work unit; integer >= 1.
            inventory_slots_per_action = 1,
            -- Resource units mined by one scheduled work unit; integer >= 1.
            resource_units_per_action = 1
        },
        surveyor = {
            radius = 128,
            boundary_max_steps = 4096
        }, -- Inclusive radius/grouping width >0; trace cap integer >=1.
        lamp = {
            radius = 48,
            darkness = 0.35
        }, -- Darkness is [0,1].
        repair = {
            radius = 64,
            threshold = 1.0,
            self_repair_threshold = 0.9, -- Health ratio [0,1]; repair the bot before seeking another target.
            health_per_action = 25, -- Maximum health points restored by one scheduled work unit; finite >0.
            interaction_distance = 1.5, -- Inclusive tile distance from the target at which repair may begin; >0.
            ignored_names = {}
        } -- Health ratio is [0,1]; names are exact prototypes.
    },
    visuals = {
        label_offset = {0, 1},
        label_scale = 0.85,
        -- RGBA channels are each in [0,1].
        colors = {
            label = {
                r = 0.7,
                g = 1,
                b = 0.15,
                a = 0.9
            },
            target = {
                r = 0.7,
                g = 1,
                b = 0.15,
                a = 0.35
            },
            map = {
                r = 0.2,
                g = 0.8,
                b = 1,
                a = 0.35
            },
            cliff = {
                r = 1,
                g = 0.45,
                b = 0.05,
                a = 0.85
            },
            destroyed = {
                r = 1,
                g = 0.15,
                b = 0.1,
                a = 0.8
            }
        },
        lifetime_ticks = 3600 -- Positive integer ticks; temporary objects expire safely after save/load.
    },
    roles = {
        builder = {
            prototype_family = "construction",
            required_technologies = {"construction-robotics"},
            technology_mode = "all",
            default_task = "construct"
        },
        repair = {
            prototype_family = "construction",
            required_technologies = {"repair-pack"},
            technology_mode = "all",
            default_task = "repair"
        },
        upgrade = {
            prototype_family = "construction",
            required_technologies = {"fast-inserter"},
            technology_mode = "all",
            default_task = "combined"
        },
        track = {
            prototype_family = "construction",
            required_technologies = {"logistics-2"},
            technology_mode = "all",
            default_task = "track"
        },
        lamp = {
            prototype_family = "construction",
            required_technologies = {"lamp"},
            technology_mode = "all",
            default_task = "place"
        },
        cliff = {
            prototype_family = "construction",
            required_technologies = {},
            technology_mode = "all",
            default_task = "demolish"
        },
        logistics = {
            prototype_family = "logistic",
            required_technologies = {},
            technology_mode = "all",
            default_task = "collect"
        },
        cleanup = {
            prototype_family = "logistic",
            required_technologies = {},
            technology_mode = "all",
            default_task = "cleanup"
        },
        mapper = {
            prototype_family = "construction",
            required_technologies = {},
            technology_mode = "all",
            default_task = "search"
        },
        surveyor = {
            prototype_family = "construction",
            required_technologies = {},
            technology_mode = "all",
            default_task = "survey"
        }
    },
    -- Runs destructive integration fixtures during initialization; keep false outside disposable saves.
    debug = false
}
