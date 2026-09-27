local constants = require("constants")

-- These values are intentionally collected as tuning constants. They describe
-- policy rather than transient state, making range and movement changes safe
-- without hunting through the bot's decision logic.
return {
    -- The registry resolves this at runtime, allowing the default to be changed
    -- without coupling persistent state to a particular entity family.
    default_task = constants.DEFAULT_TASK_NAME,

    -- Movement is intentionally smooth, so updates occur every simulation tick.
    update_interval = 1,

    -- Idle scans are throttled because repeated area and inventory searches are
    -- unnecessary while factory state is unchanged.
    scan_interval = 30,

    -- Lamp mode works locally around the player. Existing lamps reserve their
    -- illuminated neighbourhood so each placement changes the next scan.
    lamp_darkness_threshold = 0,
    lamp_search_radius = 14,
    lamp_light_radius = 8,
    lamp_candidate_spacing = 2,

    -- Targets remain local to the player; network supplies can be much farther
    -- away without requiring an expensive surface-wide entity scan.
    search_radius = 32,
    -- A small anchor search reconnects a saved track to the replacement entity
    -- occupying its original seed position after fast replacement.
    track_anchor_search_radius = 2,

    -- Ordinary containers are a local convenience fallback, not a replacement
    -- for building a connected logistics network across the whole factory.
    nearby_container_radius = 64,

    -- Slots allow a useful batch while keeping the helper materially less
    -- capable than a train or large logistics chest. Item types may be mixed.
    cargo_capacity = 100,

    -- The bot must visibly reach an entity before mutating its inventory/world
    -- state, while allowing enough tolerance for differently sized entities.
    work_distance = 1.25,

    -- Scripted teleport steps emulate flight without collision pathfinding.
    movement_step = 0.18,

    -- This dead band prevents constant micro-adjustment while following.
    follow_distance = 2.5,
    
    -- The offset keeps the helper beside and slightly behind the character.
    follow_offset = {x = -2, y = -0.75},

    cleanup = {
        follow_offset = {x = -2, y = 0.75},
        search_radius = 12,
        container_radius = 30,
        work_distance = 1.5,
        target_reach_distance = 0.7,
        cargo_capacity = 100
    },
    
    -- Orange visually distinguishes upgrade work from the role colors used by
    -- the reference gameplay mod's other bots.
    highlight_color = {r = 1, g = 0.45, b = 0, a = 0.8},
    -- The narrow bright stroke remains legible over belts and their moving items.
    track_highlight_inner_color = {r = 1, g = 0.75, b = 0.15, a = 1},
    -- The wider translucent stroke provides the requested glow without hiding
    -- belt contents or making dense splitter layouts unreadable.
    track_highlight_outer_color = {r = 1, g = 0.3, b = 0, a = 0.22},

    -- Red distinguishes a blocked storage destination from orange track work.
    blocked_container_color = {r = 1, g = 0, b = 0, a = 0.9}
}
