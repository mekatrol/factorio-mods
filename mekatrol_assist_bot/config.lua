-- Public configuration for both Factorio stages. Keep this file free of runtime globals.
return {
    -- Persistent-state/configuration schema. Positive integer.
    schema_version = 4,
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
        work_per_tick = 24,
        background_work_per_tick = 4,
        idle_interval = 6, -- Counts/ticks, integers >=1; 60 ticks = one second.
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
        } -- Scheduled ticks between role work units; integers >=1.
    },
    formation = {
        role_order = {"builder", "repair", "upgrade", "track", "lamp", "cliff", "logistics", "cleanup", "mapper",
                      "surveyor"},
        slot_spacing = 1.5,
        side_distance = 3,
        column_spacing = 2, -- Tiles, finite >0.
        max_slots_per_column = 5, -- Positive integer.
        direction_threshold = 0.2 -- Tiles of horizontal movement before mirroring; >0.
    },
    movement = {
        step = 0.35,
        arrival_distance = 0.25
    }, -- Tiles per step / inclusive dead band; >0.
    scanning = {
        cell_size = 16,
        radius = 96,
        mapper_radius = 64, -- Inclusive tile distances, finite >0.
        cells_per_step = 1,
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
            radius = 64
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
            threshold = 0.999,
            ignored_names = {}
        } -- Health ratio is [0,1]; names are exact prototypes.
    },
    visuals = {
        -- RGBA channels are each in [0,1].
        colors = {
            target = {
                r = 1,
                g = 0.6,
                b = 0.1,
                a = 0.8
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
            },
            health_good = {
                r = 0,
                g = 1,
                b = 0,
                a = 0.9
            },
            health_bad = {
                r = 1,
                g = 0,
                b = 0,
                a = 0.9
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
            required_technologies = {"construction-robotics"},
            technology_mode = "all",
            default_task = "repair"
        },
        upgrade = {
            prototype_family = "construction",
            required_technologies = {"construction-robotics"},
            technology_mode = "all",
            default_task = "combined"
        },
        track = {
            prototype_family = "construction",
            required_technologies = {"construction-robotics"},
            technology_mode = "all",
            default_task = "track"
        },
        lamp = {
            prototype_family = "construction",
            required_technologies = {"construction-robotics", "lamp"},
            technology_mode = "all",
            default_task = "place"
        },
        cliff = {
            prototype_family = "construction",
            required_technologies = {"cliff-explosives"},
            technology_mode = "all",
            default_task = "demolish"
        },
        logistics = {
            prototype_family = "logistic",
            required_technologies = {"logistic-robotics"},
            technology_mode = "all",
            default_task = "collect"
        },
        cleanup = {
            prototype_family = "logistic",
            required_technologies = {"logistic-robotics"},
            technology_mode = "all",
            default_task = "cleanup"
        },
        mapper = {
            prototype_family = "construction",
            required_technologies = {"electronics"},
            technology_mode = "all",
            default_task = "search"
        },
        surveyor = {
            prototype_family = "construction",
            required_technologies = {"electronics"},
            technology_mode = "all",
            default_task = "survey"
        }
    },
    compatibility = {
        mapping_remote_interface = "mapping_bot_mod",
        import_legacy_state = true,
        snapshot_limit = 1000
    }, -- Records per synchronous compatibility call; integer >=1.
    debug = false
}
