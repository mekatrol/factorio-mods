----------------------------------------------------------------------
-- control.lua
--
-- Cleanup bot logic:
--   - Each player can toggle a cleanup bot on/off via hotkey.
--   - The bot follows the player when it has no cleanup target.
--   - It looks for items on the ground (type = "item-entity").
--   - When carrying items, it prefers a nearby container already holding
--     that item. Otherwise it returns to the player and uses their inventory.
--
-- Factorio 2.0: uses `storage` instead of `global`.
----------------------------------------------------------------------
local visual = require("visual")

----------------------------------------------------------------------
-- TUNABLE CONSTANTS
----------------------------------------------------------------------
local CUSTOM_BOT_HEALTH = 500

-- Move and update every simulation tick so the scripted teleport motion is
-- visually continuous, matching the upgrade bot instead of jumping 12 times
-- per second.
local CLEANUP_BOT_UPDATE_INTERVAL = 1

-- Match mekatrol_game_bot's scripted movement exactly: both bots update every tick
-- and teleport at most 0.18 tiles toward their destination per update.
local BOT_STEP_DISTANCE = 0.18

-- Keep the same following formation and dead band as mekatrol_game_bot.
local BOT_FOLLOW_DISTANCE = 2.5
local BOT_HORIZONTAL_DIRECTION_THRESHOLD = 0.1

-- Distance considered "arrived" at a target point (squared for comparison).
local BOT_TARGET_REACH_DISTANCE = 0.7

-- If the bot appears not to move for this many game ticks, pick a new direction.
local BOT_STUCK_TICKS = 120

-- Radius to search for ground items (around bot, and occasionally around player).
local ITEM_SEARCH_RADIUS = 12.0

-- Distance within which the bot is allowed to interact with the chest.
local CHEST_INTERACT_DISTANCE = 1.5

-- Visual offsets
local CHEST_HIGHLIGHT_Y_OFFSET = 0.0

-- Max different item types the bot can carry at once.
local BOT_MAX_ITEM_COUNT = 100

-- Where the bot sits relative to the player when it can't place items.
local FOLLOW_OFFSET = {
    x = -2,
    y = -1
}

-- Radius (around the player) to search for containers that already
-- contain a given item type.
local CONTAINER_SEARCH_RADIUS = 30.0

-- Name of the storage chest type we prefer.
local STORAGE_CHEST_NAME = "iron-chest"

local CONTAINER_TYPES = {"container", "logistic-container"}

-- Key under storage where we keep all mod state.
local STORAGE_KEY = "mekatrol_cleanup_mod"

----------------------------------------------------------------------
-- MODE MEANING
-- "idle"	    Bot just spawned or is enabled but has not selected any behavior yet.
-- "follow"	Bot is following the player in a trailing side formation.
-- "pickup"	    Bot has located an item on the ground and is moving to pick it up.
-- "returning"	Bot is carrying items and is moving to a container or the player to deposit.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- INTERNAL UTILS
----------------------------------------------------------------------

local function get_mod_storage()
    storage[STORAGE_KEY] = storage[STORAGE_KEY] or {}
    local s = storage[STORAGE_KEY]
    s.players = s.players or {}
    return s
end

local function get_player_data(player_index)
    local s = get_mod_storage()
    local pdata = s.players[player_index]
    return pdata
end

local function init_player(player)
    if not (player and player.valid) then
        return
    end

    local s = get_mod_storage()
    local pdata = s.players[player.index]

    if not pdata then
        pdata = {}
        s.players[player.index] = pdata
    end

    -- Persisted fields (create if missing).
    pdata.cleanup_bot_enabled = pdata.cleanup_bot_enabled or false
    pdata.cleanup_bot = pdata.cleanup_bot or nil
    pdata.storage_chest = pdata.storage_chest or nil

    -- Movement state:
    pdata.mode = pdata.mode or "idle" -- "idle", "follow", "pickup", "returning"
    pdata.target_position = pdata.target_position or nil
    pdata.last_bot_position = pdata.last_bot_position or nil
    pdata.stuck_tick_counter = pdata.stuck_tick_counter or 0
    pdata.last_player_position = pdata.last_player_position or nil
    pdata.side_offset_x = pdata.side_offset_x or FOLLOW_OFFSET.x

    -- Carried items: table[name] = count, plus running total.
    pdata.carried_items = pdata.carried_items or {}
    pdata.unplaceable_items = pdata.unplaceable_items or {}

    -- Line from bot to its current item or chest target.
    -- The visual function itself will only show it in pickup mode.
    if pdata.target_position then
        visual.draw_target_line(bot, pdata, pdata.target_position, pdata.mode or "idle")
    else
        visual.draw_target_line(bot, pdata, nil, pdata.mode or "idle") -- clears old line
    end

    -- Visual references:
    pdata.vis_bot_highlight = pdata.vis_bot_highlight or nil
    pdata.vis_chest_highlight = pdata.vis_chest_highlight or nil
    pdata.vis_bot_lines = pdata.vis_bot_lines or nil
    pdata.vis_status_text = pdata.vis_status_text or nil
    pdata.vis_search_radius_circle = pdata.vis_search_radius_circle or nil
    pdata.vis_target_line = pdata.vis_target_line or nil
end

local function distance_squared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function get_total_carried(pdata)
    local total = 0
    if not pdata or not pdata.carried_items then
        game.print("zero carried")
        return 0
    end
    for _, count in pairs(pdata.carried_items) do
        if count and count > 0 then
            total = total + count
        end
    end
    return total
end

-- How much free capacity (by item count) remains.
local function get_free_capacity(pdata)
    local carried = get_total_carried(pdata)
    local free = BOT_MAX_ITEM_COUNT - carried
    if free < 0 then
        free = 0
    end
    return free
end

local function find_best_container_for_item(player, bot, item_name)
    if not (player and player.valid and bot and bot.valid) then
        return nil
    end

    local surface = bot.surface
    if not surface then
        return nil
    end

    -- Look near the player, so "local" storage around you is used.
    local candidates = surface.find_entities_filtered {
        position = bot.position,
        radius = CONTAINER_SEARCH_RADIUS,
        force = player.force,
        type = CONTAINER_TYPES
    }

    local best_matching
    local best_matching_d2
    local bp = bot.position

    for _, c in pairs(candidates) do
        if c.valid then
            local inv = c.get_inventory(defines.inventory.chest)
            if inv and inv.valid and inv.can_insert {name = item_name, count = 1} then
                local d2 = distance_squared(bp, c.position)

                -- Only containers already holding this item are eligible. A
                -- matching but full container is excluded by can_insert above.
                if inv.get_item_count(item_name) > 0 then
                    if not best_matching_d2 or d2 < best_matching_d2 then
                        best_matching = c
                        best_matching_d2 = d2
                    end
                end
            end
        end
    end

    return best_matching
end

local function player_can_accept_item(player, item_name)
    local inv = player and player.valid and player.get_main_inventory()
    return inv and inv.valid and inv.can_insert {name = item_name, count = 1} or false
end

local function player_can_accept_any_carried_item(player, bot, pdata)
    for name, count in pairs(pdata.carried_items or {}) do
        if count and count > 0 and not find_best_container_for_item(player, bot, name) and
            player_can_accept_item(player, name) then
            return true
        end
    end
    return false
end

-- Find the nearest suitable container for ANY carried item type.
local function find_any_container_for_carried_items(player, bot, pdata)
    if not (player and player.valid and bot and bot.valid) then
        return nil
    end

    if not pdata.carried_items then
        return nil
    end

    local best
    local best_d2
    local bp = bot.position

    for name, count in pairs(pdata.carried_items) do
        if count and count > 0 then
            local container = find_best_container_for_item(player, bot, name)
            if container and container.valid then
                local d2 = distance_squared(bp, container.position)
                if not best_d2 or d2 < best_d2 then
                    best = container
                    best_d2 = d2
                end
            end
        end
    end

    return best
end

----------------------------------------------------------------------
-- BOT CREATION / ENSURING
----------------------------------------------------------------------

local function ensure_bot_for_player(player, pdata)
    if not (player and player.valid and player.surface and player.force) then
        return nil
    end

    if pdata.cleanup_bot and pdata.cleanup_bot.valid then
        return pdata.cleanup_bot
    end

    local surface = player.surface
    local pos = player.position

    local bot = surface.create_entity {
        name = "mekatrol-cleanup-bot",
        position = {
            x = pos.x - 2,
            y = pos.y + 1
        },
        force = player.force
    }

    if not bot then
        player.print("[color=red][MekatrolCleanupBot][/color] failed to create cleanup bot.")
        return nil
    end

    -- Use the bot more like a flying helper. Usually safe to be indestructible.
    bot.destructible = true
    bot.health = CUSTOM_BOT_HEALTH
    
    pdata.cleanup_bot = bot
    pdata.target_position = nil
    pdata.mode = "idle"
    pdata.last_bot_position = {
        x = bot.position.x,
        y = bot.position.y
    }
    pdata.stuck_tick_counter = 0

    player.print("[color=green][MekatrolCleanupBot][/color] bot spawned.")

    return bot
end

----------------------------------------------------------------------
-- STORAGE CHEST (IRON CHEST) SEARCH
----------------------------------------------------------------------

local function find_nearest_storage_chest(player, pdata)
    if not (player and player.valid) then
        return nil
    end

    -- Reuse cache if still valid and still the correct entity type.
    if pdata.storage_chest and pdata.storage_chest.valid and pdata.storage_chest.name == STORAGE_CHEST_NAME then
        return pdata.storage_chest
    end

    local surface = player.surface
    if not surface then
        pdata.storage_chest = nil
        return nil
    end

    -- For simplicity we search all iron chests of the player’s force on the surface
    -- and pick the nearest one.
    local chests = surface.find_entities_filtered {
        name = STORAGE_CHEST_NAME,
        force = player.force
    }

    if not chests or #chests == 0 then
        pdata.storage_chest = nil
        return nil
    end

    local best
    local best_d2
    local pp = player.position

    for _, chest in pairs(chests) do
        if chest.valid then
            local d2 = distance_squared(pp, chest.position)
            if not best_d2 or d2 < best_d2 then
                best = chest
                best_d2 = d2
            end
        end
    end

    pdata.storage_chest = best
    return best
end

----------------------------------------------------------------------
----------------------------------------------------------------------

----------------------------------------------------------------------
-- BOT MOVEMENT
--
-- Moves the bot a single step towards the target position.
-- The bot is a flying construction robot, so we simply teleport it
-- along a straight line.
----------------------------------------------------------------------

local function move_entity_towards(bot, target)
    if not (bot and bot.valid and target) then
        return
    end

    local pos = bot.position
    local dx, dy = target.x - pos.x, target.y - pos.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance == 0 then
        return
    end

    local step = math.min(BOT_STEP_DISTANCE, distance)
    bot.teleport({x = pos.x + dx / distance * step, y = pos.y + dy / distance * step})
end

-- Match mekatrol_game_bot's follow behavior: trail on the opposite side of the
-- player's horizontal movement and stop adjusting inside the follow dead band.
local function follow_player(player, bot, pdata)
    -- Existing saves may already have player data created before the dynamic
    -- side-follow fields were introduced. Backfill at the point of use so an
    -- on-tick update can never perform arithmetic on nil state.
    pdata.side_offset_x = pdata.side_offset_x or FOLLOW_OFFSET.x

    local previous = pdata.last_player_position
    if previous then
        local dx = player.position.x - previous.x
        if dx < -BOT_HORIZONTAL_DIRECTION_THRESHOLD then
            pdata.side_offset_x = math.abs(FOLLOW_OFFSET.x)
        elseif dx > BOT_HORIZONTAL_DIRECTION_THRESHOLD then
            pdata.side_offset_x = -math.abs(FOLLOW_OFFSET.x)
        end
    end

    pdata.last_player_position = {
        x = player.position.x,
        y = player.position.y
    }

    local position = {
        x = player.position.x + pdata.side_offset_x,
        y = player.position.y + FOLLOW_OFFSET.y
    }

    if distance_squared(bot.position, position) > BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE then
        move_entity_towards(bot, position)
    end
end

----------------------------------------------------------------------
-- GROUND ITEM SEARCH / PICKUP
----------------------------------------------------------------------

local function find_nearest_ground_item(surface, center, radius)
    if not surface then
        return nil
    end

    local items = surface.find_entities_filtered {
        position = center,
        radius = radius,
        type = "item-entity"
    }

    if not items or #items == 0 then
        return nil
    end

    local best
    local best_d2

    for _, ent in pairs(items) do
        if ent.valid and ent.stack and ent.stack.valid_for_read then
            local d2 = distance_squared(center, ent.position)
            if not best_d2 or d2 < best_d2 then
                best = ent
                best_d2 = d2
            end
        end
    end

    return best
end

-- Add a stack of items to the bot's carried-items table.
local function add_to_carried(pdata, name, count)
    if count <= 0 then
        return
    end

    pdata.carried_items = pdata.carried_items or {}
    local t = pdata.carried_items
    t[name] = (t[name] or 0) + count
end

-- Pick up all item entities within a small radius around the bot.
-- Returns true if at least one item was picked up.
local function pickup_nearby_items(player, bot, pdata)
    if not (bot and bot.valid) then
        return false
    end

    local surface = bot.surface
    if not surface then
        return false
    end

    local items = surface.find_entities_filtered {
        position = bot.position,
        radius = 1.0,
        type = "item-entity"
    }

    if not items or #items == 0 then
        return false
    end

    local picked_any = false

    for _, ent in pairs(items) do
        if ent.valid and ent.stack and ent.stack.valid_for_read then
            local free = get_free_capacity(pdata)
            if free <= 0 then
                -- No more capacity at all; stop picking up.
                break
            end

            local name = ent.stack.name
            local stack_count = ent.stack.count
            local take = math.min(stack_count, free)

            if take > 0 then
                add_to_carried(pdata, name, take)

                if take == stack_count then
                    -- Took it all, remove the entity.
                    ent.destroy()
                else
                    -- Partially consume this ground stack.
                    ent.stack.count = stack_count - take
                end

                picked_any = true
            end
        end
    end

    if picked_any then
        local total = get_total_carried(pdata)
        if total > 0 and (pdata.mode == "idle" or pdata.mode == "follow") then
            pdata.mode = "pickup"
        end
    end

    return picked_any
end

----------------------------------------------------------------------
-- DEPOSITING ITEMS INTO CHEST / PLAYER
----------------------------------------------------------------------
local function deposit_carried_items(player, pdata, bot, destination_container)
    local total = get_total_carried(pdata)
    if total <= 0 then
        return false
    end

    pdata.unplaceable_items = pdata.unplaceable_items or {}

    local any_inserted = false

    for name, count in pairs(pdata.carried_items) do
        if count and count > 0 then
            local container = find_best_container_for_item(player, bot, name)
            local inv

            if destination_container and container == destination_container then
                inv = destination_container.get_inventory(defines.inventory.chest)
            elseif not destination_container and not container then
                inv = player.get_main_inventory()
            end

            if inv and inv.valid and inv.can_insert {name = name, count = 1} then
                local inserted = inv.insert {
                    name = name,
                    count = count
                }

                if inserted > 0 then
                    any_inserted = true
                end

                local remaining = count - inserted

                if remaining > 0 then
                    -- Keep the remainder available so the next update can find
                    -- another matching container or wait for player space.
                    pdata.carried_items[name] = remaining
                    pdata.unplaceable_items[name] = nil
                else
                    pdata.carried_items[name] = nil
                    pdata.unplaceable_items[name] = nil
                end
            elseif not container and not player_can_accept_item(player, name) then
                if not pdata.unplaceable_items[name] then
                    player.print("[color=green][MekatrolCleanupBot][/color] No matching container or player inventory space found for item '" ..
                                     name .. "'.")
                end
                pdata.unplaceable_items[name] = true
            end
        end
    end

    return any_inserted
end

----------------------------------------------------------------------
-- MAIN PER-PLAYER BOT UPDATE
----------------------------------------------------------------------

local function update_cleanup_bot_for_player(player, pdata, tick)
    if not pdata.cleanup_bot_enabled then
        visual.clear_all(pdata)
        return
    end

    local bot = ensure_bot_for_player(player, pdata)
    if not bot then
        return
    end

    local surface = bot.surface
    local pp = player.position
    local bp = bot.position

    ------------------------------------------------------------------
    -- Look for items near the bot and pick them up.
    ------------------------------------------------------------------
    pickup_nearby_items(player, bot, pdata)

    ------------------------------------------------------------------
    -- Decide what we are trying to do next:
    --   1. If carrying items and a matching container exists: go there.
    --   2. Otherwise, go to the player if their inventory can accept the item.
    --   3. If neither destination can accept it: follow the player and wait.
    --   4. If not carrying items: look for ground items or follow the player.
    ------------------------------------------------------------------
    local carried_total = get_total_carried(pdata)
    local carrying_anything = carried_total > 0

    local has_unplaceable = pdata.unplaceable_items and next(pdata.unplaceable_items) ~= nil

    ------------------------------------------------------------------
    -- Keep building a useful batch before returning to storage. The old
    -- behavior returned as soon as the first small ground stack was picked up,
    -- so the nominal 100-item capacity was rarely used.
    ------------------------------------------------------------------
    local collecting_more = false
    if carrying_anything and get_free_capacity(pdata) > 0 then
        local nearest_item = find_nearest_ground_item(surface, bp, ITEM_SEARCH_RADIUS)
        if not nearest_item then
            nearest_item = find_nearest_ground_item(surface, pp, ITEM_SEARCH_RADIUS)
        end

        if nearest_item and nearest_item.valid then
            collecting_more = true
            pdata.mode = "pickup"
            pdata.target_position = {
                x = nearest_item.position.x,
                y = nearest_item.position.y
            }
        end
    end

    ------------------------------------------------------------------
    -- Retry: if we previously had unplaceable items, see if a
    -- matching container or player inventory slot exists now. If so, clear
    -- the flag so the normal deposit logic runs again.
    ------------------------------------------------------------------
    if has_unplaceable and carrying_anything then
        local retry_container = find_any_container_for_carried_items(player, bot, pdata)
        if (retry_container and retry_container.valid) or player_can_accept_any_carried_item(player, bot, pdata) then
            -- A matching container or player inventory slot exists now.
            -- Let the normal logic below handle movement/deposit.
            pdata.unplaceable_items = {}
            has_unplaceable = false
        end
    end

    ------------------------------------------------------------------
    -- Normal container / player / unavailable logic
    ------------------------------------------------------------------
    if carrying_anything and not has_unplaceable and not collecting_more then
        -- We have items and (currently) no unplaceable ones: try to find a container.
        local container = find_any_container_for_carried_items(player, bot, pdata)

        if container and container.valid then
            local d2_chest = distance_squared(bp, container.position)
            if d2_chest <= (CHEST_INTERACT_DISTANCE * CHEST_INTERACT_DISTANCE) then
                -- Close enough: actually deposit now.
                deposit_carried_items(player, pdata, bot, container)
                carried_total = get_total_carried(pdata)

                if carried_total <= 0 then
                    -- All done; the normal empty state will resume following.
                    pdata.mode = "follow"
                    pdata.target_position = nil
                end
            else
                -- Not at the chest yet: head towards it.
                pdata.mode = "returning"
                pdata.target_position = {
                    x = container.position.x,
                    y = container.position.y
                }
            end
        elseif player_can_accept_any_carried_item(player, bot, pdata) then
            local d2_player = distance_squared(bp, player.position)
            if d2_player <= (CHEST_INTERACT_DISTANCE * CHEST_INTERACT_DISTANCE) then
                deposit_carried_items(player, pdata, bot, nil)
                carried_total = get_total_carried(pdata)

                if carried_total <= 0 then
                    pdata.mode = "follow"
                    pdata.target_position = nil
                end
            else
                pdata.mode = "returning"
                pdata.target_position = {
                    x = player.position.x,
                    y = player.position.y
                }
            end
        else
            -- No matching container or player inventory space for any carried item type.
            pdata.unplaceable_items = pdata.unplaceable_items or {}
            for name, count in pairs(pdata.carried_items) do
                if count and count > 0 then
                    if not pdata.unplaceable_items[name] then
                        pdata.unplaceable_items[name] = true
                        player.print(
                            "[color=green][MekatrolCleanupBot][/color] No matching container or player inventory space found for item '" ..
                                name .. "'.")
                    end
                end
            end
            has_unplaceable = true
        end
    end

    -- If any items are unplaceable, follow the player using the same dynamic
    -- side-switching formation as mekatrol_game_bot.
    if has_unplaceable and not collecting_more then
        pdata.mode = "no-container"
        pdata.target_position = nil
        follow_player(player, bot, pdata)
    elseif not carrying_anything then
        ------------------------------------------------------------------
        -- Normal behaviour when empty: look for items, otherwise follow the player.
        ------------------------------------------------------------------
        local nearest_item = find_nearest_ground_item(surface, bp, ITEM_SEARCH_RADIUS)
        if not nearest_item then
            nearest_item = find_nearest_ground_item(surface, pp, ITEM_SEARCH_RADIUS)
        end

        if nearest_item and nearest_item.valid then
            pdata.mode = "pickup"
            pdata.target_position = {
                x = nearest_item.position.x,
                y = nearest_item.position.y
            }
        else
            pdata.mode = "follow"
            pdata.target_position = nil
            follow_player(player, bot, pdata)
        end
    end

    ------------------------------------------------------------------
    -- If we have a target position, move toward it.
    ------------------------------------------------------------------
    if pdata.target_position then
        move_entity_towards(bot, pdata.target_position)

        local new_bp = bot.position
        local d2_target = distance_squared(new_bp, pdata.target_position)

        if d2_target <= (BOT_TARGET_REACH_DISTANCE * BOT_TARGET_REACH_DISTANCE) then
            -- We’re at the target; clear it so new behavior can be picked next tick.
            pdata.target_position = nil
        end

        -- Stuck detection: if the position does not change, increment a counter
        -- and re-roll a target after some time.
        local last_pos = pdata.last_bot_position
        if last_pos and last_pos.x == new_bp.x and last_pos.y == new_bp.y then
            pdata.stuck_tick_counter = (pdata.stuck_tick_counter or 0) + CLEANUP_BOT_UPDATE_INTERVAL
            if pdata.stuck_tick_counter >= BOT_STUCK_TICKS then
                pdata.stuck_tick_counter = 0
                pdata.target_position = nil
            end
        else
            pdata.stuck_tick_counter = 0
        end

        pdata.last_bot_position = {
            x = new_bp.x,
            y = new_bp.y
        }
    end

    local chest = find_nearest_storage_chest(player, pdata)

    ------------------------------------------------------------------
    -- Visual overlays
    ------------------------------------------------------------------
    -- These overlays were visually overpowering. Clear any instances retained
    -- by an existing save and do not recreate them.
    visual.clear_bot_highlight(pdata)
    visual.clear_search_radius_circle(pdata)

    if chest and chest.valid then
        visual.draw_chest_highlight(chest, pdata, CHEST_HIGHLIGHT_Y_OFFSET)
    else
        visual.clear_chest_highlight(pdata)
    end
    -- Remove player-to-bot lines retained by saves from older versions. This
    -- visual is deliberately not recreated.
    visual.clear_bot_line(pdata)

    local carried_total_for_ui = get_total_carried(pdata)

    visual.draw_status_text(bot, pdata, pdata.mode or "idle", carried_total_for_ui, BOT_MAX_ITEM_COUNT)

    -- Line from bot to its current item or chest target.
    -- The visual function itself will only show it in pickup mode.
    if pdata.target_position then
        visual.draw_target_line(bot, pdata, pdata.target_position, pdata.mode or "idle")
    else
        visual.draw_target_line(bot, pdata, nil, pdata.mode or "idle") -- clears old line
    end
end

---------------------------------------------------
-- CLEANUP HELPERS
---------------------------------------------------
local function cleanup_old_bots()
    for _, surface in pairs(game.surfaces) do
        for _, e in pairs(surface.find_entities_filtered {
            name = "mekatrol-cleanup-bot"
        }) do
            if e.valid then
                e.destroy()
            end
        end
    end
end

----------------------------------------------------------------------
-- EVENT HANDLERS
----------------------------------------------------------------------

script.on_init(function()

    -- cleanup any old bots (if starting from an existing save converted to this mod)
    cleanup_old_bots()

    local s = get_mod_storage()
    -- Initialize existing players (e.g. when mod is added to ongoing save).
    for _, player in pairs(game.players) do
        init_player(player)
    end
end)

script.on_configuration_changed(function(_)
    -- cleanup any old bots when mod/game configuration changes
    cleanup_old_bots()

    local s = get_mod_storage()
    for _, player in pairs(game.players) do
        init_player(player)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    init_player(player)
end)

----------------------------------------------------------------------
-- HOTKEY: toggle cleanup bot
----------------------------------------------------------------------

script.on_event("mekatrol-toggle-cleanup-bot", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    init_player(player) -- ensure pdata exists
    local pdata = get_player_data(event.player_index)
    if not pdata then
        return
    end

    pdata.cleanup_bot_enabled = not pdata.cleanup_bot_enabled

    if pdata.cleanup_bot_enabled then
        ensure_bot_for_player(player, pdata)
        pdata.mode = "idle"
        player.print("[color=green][MekatrolCleanupBot][/color] Enabled.")
    else
        -- Destroy bot entity if present.
        if pdata.cleanup_bot and pdata.cleanup_bot.valid then
            pdata.cleanup_bot.destroy()
        end
        pdata.cleanup_bot = nil

        -- Clear carried items and visual.
        pdata.carried_items = {}
        pdata.unplaceable_items = {}

        visual.clear_all(pdata)

        pdata.target_position = nil
        pdata.mode = "idle"

        player.print("[color=green][MekatrolCleanupBot][/color] Disabled.")
    end
end)

----------------------------------------------------------------------
-- MAIN TICK
----------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % CLEANUP_BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    local s = get_mod_storage()

    -- Handle all connected players so the mod is multiplayer-safe.
    for _, player in pairs(game.connected_players) do
        local pdata = s.players[player.index]
        if pdata then
            update_cleanup_bot_for_player(player, pdata, event.tick)
        end
    end
end)
