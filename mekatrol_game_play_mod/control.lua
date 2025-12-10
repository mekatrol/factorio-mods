----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Purpose:
--   Implements runtime logic for the "mekatrol-game-play-bot" entity.
--
--   This script:
--     * Listens for the custom hotkey "mekatrol-game-play-bot-toggle".
--     * For each player, toggles a hidden helper entity:
--         - If the player has no bot: create one at the player's position.
--         - If the player already has a bot: destroy it.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- PRINT HELPER: print_bot_message(player, color, fmt, ...)
--
-- PURPOSE:
--   Provides a unified, readable, color-coded print function for all
--   game-play-bot messages.
--
-- PARAMETERS:
--   player : LuaPlayer
--       The player who receives the message.
--
--   color : string
--       Name of a Factorio rich-text color, such as:
--         "red", "green", "yellow", "orange", "cyan", "pink",
--         "blue", "purple", "white", "black".
--       (Must be supported by the rich text system.)
--
--   fmt : string
--       A Lua format string that may contain standard placeholders:
--         %s (string)
--         %d (integer)
--         %.2f (float with precision)
--         etc.
--
--   ... : any
--       Arguments to fill the placeholders in the format string.
--
-- BEHAVIOR:
--   * Constructs a "[Game Play Bot]" tag wrapped in a color tag:
--         [color=<color>][Game Play Bot][/color]
--   * Expands the message text via string.format(fmt, ...)
--   * Prints the message to the player using player.print{} with the
--     correct rich-text structure.
--
-- OUTPUT EXAMPLE:
--   If called as:
--       print_bot_message(player, "red", "Bot failed at %d,%d", 10, 25)
--
--   The player will see:
--       [Game Play Bot] Bot failed at 10,25
--   with the tag colored red.
----------------------------------------------------------------------
local function print_bot_message(player, color, fmt, ...)
    -- Validate the player first.
    if not (player and player.valid) then
        return
    end

    ------------------------------------------------------------------
    -- 1) Format the message text using Lua's string.format
    --
    --    This expands placeholders inside 'fmt' with the parameters
    --    passed via "...".
    --
    --    For example:
    --        string.format("Hello %s (%d)", "Bob", 5)
    --    produces:
    --        "Hello Bob (5)"
    ------------------------------------------------------------------
    local text
    local ok, result = pcall(string.format, fmt, ...)
    if ok then
        text = result
    else
        -- If formatting fails (wrong number/type of arguments), fall
        -- back to a safe error message.
        text = "<formatting error>"
    end

    ------------------------------------------------------------------
    -- 2) Build the colored prefix using rich text.
    --
    --    Factorio rich text color syntax:
    --        [color=<name>] ... [/color]
    --
    --    The prefix is included as plain text inside a localized
    --    string array:
    --        player.print{ "", "<prefix>", text }
    --
    --    The empty string "" at the start allows concatenation inside
    --    a localized message array.
    ------------------------------------------------------------------
    local prefix = string.format("[color=%s][Game Play Bot][/color] ", color)

    ------------------------------------------------------------------
    -- 3) Print the colored prefix + message to the player.
    --
    --    player.print{ "", prefix, text }
    --    tells Factorio to concatenate all array elements into one
    --    final display string.
    ------------------------------------------------------------------
    player.print {"", prefix, text}
end

----------------------------------------------------------------------
-- PERSISTENT STATE LAYOUT (Factorio 2.x: use `storage`)
--
-- Factorio 2.x provides a special global table named `storage` that:
--   * Is automatically serialized and persisted between saves.
--   * Is isolated per-mod (no need for namespacing with other mods).
--
-- We define a dedicated namespace under storage:
--
--   storage.mekatrol_bot = {
--       [player_index] = {
--           entity = <LuaEntity or nil>
--       }
--   }
--
-- Where:
--   - player_index: numeric key (1..N) corresponding to each player.
--   - entity:       reference to the player's "mekatrol-game-play-bot"
--                   entity, or nil if the bot is currently inactive.
----------------------------------------------------------------------
local function ensure_storage_tables()
    -- This helper ensures top-level table exists inside `storage`.
    -- It is safe to call multiple times; it only initializes missing entries.
    storage.mekatrol_bot = storage.mekatrol_bot or {}
end

----------------------------------------------------------------------
-- Get (and optionally create) per-player state
--
-- Returns:
--   * The table that holds the bot state for a given player index.
--   * If no state exists yet, it initializes an empty state table.
--
-- Usage:
--   local state = get_player_state(player.index)
--   state.entity = some_entity
----------------------------------------------------------------------

local function get_player_state(player_index)
    ensure_storage_tables()

    local all = storage.mekatrol_bot
    local state = all[player_index]

    if not state then
        state = {}
        all[player_index] = state
    end

    return state
end

----------------------------------------------------------------------
-- Destroy a player's bot entity (if present)
--
-- This function:
--   * Checks if the player has an associated bot entity.
--   * If the entity exists and is valid, it is destroyed.
--   * The reference in the per-player state is cleared.
--
-- Parameters:
--   player : LuaPlayer      - Player whose bot is being destroyed.
--   silent : boolean|nil    - If true, do not print status messages.
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local state = get_player_state(player.index)

    local bot = state.entity
    if bot and bot.valid then
        bot.destroy()
    end

    state.entity = nil

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

----------------------------------------------------------------------
-- Create a player's bot entity
--
-- This function:
--   * Spawns the "mekatrol-game-play-bot" entity at the player's
--     current position, on the player's current surface and force.
--   * Stores the entity reference in the per-player state.
--
-- Returns:
--   * The created entity if successful, or nil on failure.
----------------------------------------------------------------------

local function create_player_bot(player)
    local state = get_player_state(player.index)

    -- Clean up stale reference if it exists but is invalid.
    if state.entity and not state.entity.valid then
        state.entity = nil
    end

    -- If an active bot already exists, just return it.
    if state.entity and state.entity.valid then
        return state.entity
    end

    local surface = player.surface
    local position = player.position

    local bot = surface.create_entity {
        name = "mekatrol-game-play-bot", -- must match data.lua prototype
        position = {position.x - 2, position.y - 2},
        force = player.force, -- same force as player (will be attacked by biters)
        raise_built = true
    }

    if bot then
        state.entity = bot

        -- Ensure the bot is destructible so enemies can damage it.
        bot.destructible = true

        -- Usually irrelevant given flags (not-selectable, not-deconstructable),
        -- but we document the intended semantics:
        -- bot.minable = false

        print_bot_message(player, "green", "created")
        return bot
    else
        print_bot_message(player, "red", "create failed")
        return nil
    end
end

----------------------------------------------------------------------
-- TOGGLE HANDLER: Respond to the custom hotkey
--
-- Invoked when the custom input "mekatrol-game-play-bot-toggle"
-- is fired for a player.
--
-- Behavior:
--   * If the player currently has an active bot entity -> destroy it.
--   * Otherwise -> create a new bot entity.
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    local state = get_player_state(player.index)
    local bot = state.entity

    if bot and bot.valid then
        -- Toggle OFF
        destroy_player_bot(player, false)
        return
    end

    -- Toggle ON
    create_player_bot(player)
end

----------------------------------------------------------------------
-- CLEANUP: When bot entities die in the world
--
-- Enemies or other effects might destroy the bot during gameplay.
-- To keep `storage` consistent:
--   * We listen for on_entity_died.
--   * If the dead entity is one of our bots, we clear its reference
--     from the matching player's state (if found) and print a message.
--
-- IMPORTANT:
--   - In Factorio, event.entity for on_entity_died is typically
--     INVALID (entity.valid == false), but you can still read fields
--     like `name`, `unit_number`, etc.
--   - Therefore we MUST NOT early-return just because .valid is false.
----------------------------------------------------------------------

local function on_entity_died(event)
    local entity = event.entity

    -- Only guard against "no entity at all".
    if not entity then
        return
    end

    -- We can safely read entity.name even if entity.valid == false.
    if entity.name ~= "mekatrol-game-play-bot" then
        return
    end

    ensure_storage_tables()
    local all = storage.mekatrol_bot

    -- We stored the same LuaEntity reference in storage when we
    -- created the bot, so even though it is now invalid, pointer
    -- equality (state.entity == entity) still works.
    for player_index, state in pairs(all) do
        if state.entity == entity then
            state.entity = nil

            local player = game.get_player(player_index)
            if player and player.valid then
                print_bot_message(player, "yellow", "destroyed")
            end
        end
    end
end

----------------------------------------------------------------------
-- PLAYER REMOVAL CLEANUP
--
-- When a player is removed from the game, we:
--   * Destroy their bot (if it exists).
--   * Remove their state from storage.mekatrol_bot.
----------------------------------------------------------------------

local function on_player_removed(event)
    ensure_storage_tables()
    local all = storage.mekatrol_bot
    local player_index = event.player_index

    local state = all[player_index]
    if not state then
        return
    end

    local player = game.get_player(player_index)
    if player and player.valid then
        -- Silent = true to avoid printing messages to a removed player.
        destroy_player_bot(player, true)
    else
        -- Player object no longer exists; destroy entity directly if valid.
        if state.entity and state.entity.valid then
            state.entity.destroy()
        end
    end

    all[player_index] = nil
end

----------------------------------------------------------------------
-- LIFECYCLE HOOKS: on_init / on_configuration_changed
--
-- on_init:
--   * Called once when the mod is first added to a save.
--   * We use it to initialize our storage structures.
--
-- on_configuration_changed:
--   * Called when mods or their versions change.
--   * We ensure the `storage` layout is still valid.
--
-- IMPORTANT (Factorio 2.x rule):
--   * `storage` can be written here and in other events, but NOT in
--     `on_load`. We do not use on_load in this file. :contentReference[oaicite:2]{index=2}
----------------------------------------------------------------------

script.on_init(function()
    ensure_storage_tables()
end)

script.on_configuration_changed(function(_)
    ensure_storage_tables()
end)

----------------------------------------------------------------------
-- EVENT REGISTRATION
--
-- We register:
--   * Custom input "mekatrol-game-play-bot-toggle" -> on_toggle_bot
--   * Entity death events -> on_entity_died (for bot cleanup)
--   * Player removal -> on_player_removed (for storage cleanup)
----------------------------------------------------------------------

-- Custom input name must match the prototype in data.lua:
--   name = "mekatrol-game-play-bot-toggle"
script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)
