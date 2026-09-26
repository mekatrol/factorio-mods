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

    -- Targets remain local to the player; network supplies can be much farther
    -- away without requiring an expensive surface-wide entity scan.
    search_radius = 32,

    -- Ordinary containers are a local convenience fallback, not a replacement
    -- for building a connected logistics network across the whole factory.
    nearby_container_radius = 64,

    -- The bot must visibly reach an entity before mutating its inventory/world
    -- state, while allowing enough tolerance for differently sized entities.
    work_distance = 1.25,

    -- Scripted teleport steps emulate flight without collision pathfinding.
    movement_step = 0.18,

    -- This dead band prevents constant micro-adjustment while following.
    follow_distance = 2.5,
    
    -- The offset keeps the helper beside and slightly behind the character.
    follow_offset = {x = -2, y = -1},
    
    -- Orange visually distinguishes upgrade work from the role colors used by
    -- the reference gameplay mod's other bots.
    highlight_color = {r = 1, g = 0.45, b = 0, a = 0.8}
}
