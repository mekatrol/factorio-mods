----------------------------------------------------------------------
-- control.lua
--
-- Cleanup bot logic:
--   - Each player can toggle a cleanup bot on/off via hotkey.
--   - The bot roams randomly within a radius around the player.
--   - It looks for items on the ground (type = "item-entity").
--   - When carrying items, it returns to the nearest iron chest and
--     inserts them. If no chest is found, it uses the player inventory
--     and finally spills any leftovers near the player.
--
-- Factorio 2.0: uses `storage` instead of `global`.
----------------------------------------------------------------------
local visuals = require("visuals")

----------------------------------------------------------------------
-- TUNABLE CONSTANTS
----------------------------------------------------------------------

-- How often the bot logic runs (in ticks).
-- 5 ticks ~ 12 updates per second.
local CLEANUP_BOT_UPDATE_INTERVAL = 5

-- Bot movement:
-- Tiles per second, converted to tiles per update step.
local BOT_SPEED_TILES_PER_SECOND = 6.0
local TICKS_PER_SECOND = 60
local BOT_STEP_DISTANCE = (BOT_SPEED_TILES_PER_SECOND * CLEANUP_BOT_UPDATE_INTERVAL) / TICKS_PER_SECOND

-- Distance considered "arrived" at a target point (squared for comparison).
local BOT_TARGET_REACH_DISTANCE = 0.7

-- If the bot appears not to move for this many game ticks, pick a new direction.
local BOT_STUCK_TICKS = 120

-- Roaming radius around the player. The bot will try to stay within
-- this distance of the player position.
local CLEANUP_ROAM_RADIUS = 25.0

-- Radius to search for ground items (around bot, and occasionally around player).
local ITEM_SEARCH_RADIUS = 12.0

-- Distance within which the bot is allowed to interact with the chest.
local CHEST_INTERACT_DISTANCE = 1.5

-- Visual offsets
local BOT_HIGHLIGHT_Y_OFFSET = -1.0
local CHEST_HIGHLIGHT_Y_OFFSET = 0.0

-- Max different item types the bot can carry at once.
local BOT_MAX_ITEM_COUNT = 5

-- Where the bot sits relative to the player when it can't place items.
local FOLLOW_OFFSET = {
    x = -2,
    y = 2
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
-- "roam"	    Bot is wandering randomly within the player radius.
-- "pickup"	    Bot has located an item on the ground and is moving to pick it up.
-- "returning"	Bot is carrying items and is moving to the storage chest to deposit.
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
    pdata.mode = pdata.mode or "idle" -- "idle", "roam", "pickup", "returning"
    pdata.target_position = pdata.target_position or nil
    pdata.last_bot_position = pdata.last_bot_position or nil
    pdata.stuck_tick_counter = pdata.stuck_tick_counter or 0

    -- Carried items: table[name] = count, plus running total.
    pdata.carried_items = pdata.carried_items or {}
    pdata.unplaceable_items = pdata.unplaceable_items or {}

    -- line from bot to current target (item, chest, or roam point).
    -- The visual function itself will only show it in pickup mode.
    if pdata.target_position then
        visuals.draw_target_line(bot, pdata, pdata.target_position, pdata.mode or "idle")
    else
        visuals.draw_target_line(bot, pdata, nil, pdata.mode or "idle") -- clears old line
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
        position = player.position,
        radius = CONTAINER_SEARCH_RADIUS,
        force = player.force,
        type = CONTAINER_TYPES
    }

    local best
    local best_d2
    local bp = bot.position

    for _, c in pairs(candidates) do
        if c.valid then
            local inv = c.get_inventory(defines.inventory.chest)
            if inv and inv.valid and inv.get_item_count(item_name) > 0 then
                local d2 = distance_squared(bp, c.position)
                if not best_d2 or d2 < best_d2 then
                    best = c
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
        player.print("[CleanupBot] Failed to create cleanup bot.")
        return nil
    end

    -- Use the bot more like a flying helper. Usually safe to be indestructible.
    bot.destructible = false

    pdata.cleanup_bot = bot
    pdata.target_position = nil
    pdata.mode = "idle"
    pdata.last_bot_position = {
        x = bot.position.x,
        y = bot.position.y
    }
    pdata.stuck_tick_counter = 0

    player.print("[CleanupBot] Cleanup bot spawned.")

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
-- RANDOM TARGET SELECTION (ROAMING)
----------------------------------------------------------------------

local function pick_random_roam_target(player, bot, pdata)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local center = player.position
    local radius = CLEANUP_ROAM_RADIUS

    -- Try a few random points within radius.
    for _ = 1, 10 do
        local offset_x = (math.random() * 2 - 1) * radius
        local offset_y = (math.random() * 2 - 1) * radius
        local target = {
            x = center.x + offset_x,
            y = center.y + offset_y
        }

        if distance_squared(target, center) <= radius * radius then
            pdata.target_position = target
            pdata.mode = "roam"
            return
        end
    end

    -- Fallback: stay near player if no random target chosen.
    pdata.target_position = {
        x = center.x - 1,
        y = center.y - 1
    }
    pdata.mode = "roam"
end

----------------------------------------------------------------------
-- BOT MOVEMENT
--
-- Moves the bot a single step towards the target position.
-- The bot is a flying construction robot, so we simply teleport it
-- along a straight line.
----------------------------------------------------------------------

local function move_bot_towards(bot, target)
    if not (bot and bot.valid and target) then
        return
    end

    local before = bot.position
    local dx = target.x - before.x
    local dy = target.y - before.y
    local d2 = dx * dx + dy * dy

    if d2 == 0 then
        return
    end

    local dist = math.sqrt(d2)
    if BOT_STEP_DISTANCE <= 0 then
        game.print("[CleanupBot] ERROR: BOT_STEP_DISTANCE <= 0")
        return
    end

    local new_pos
    if dist <= BOT_STEP_DISTANCE then
        new_pos = target
    else
        local nx = dx / dist
        local ny = dy / dist
        new_pos = {
            x = before.x + nx * BOT_STEP_DISTANCE,
            y = before.y + ny * BOT_STEP_DISTANCE
        }
    end

    local ok = bot.teleport(new_pos)
    local after = bot.position

    -- game.print(string.format("[CleanupBot] STEP from (%.2f, %.2f) to (%.2f, %.2f), ok=%s, after=(%.2f, %.2f)", before.x,
    --     before.y, new_pos.x, new_pos.y, tostring(ok), after.x, after.y))
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
local function pick_up_nearby_items(player, bot, pdata)
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
        if total > 0 and (pdata.mode == "idle" or pdata.mode == "roam") then
            pdata.mode = "pickup"
        end
    end

    return picked_any
end

----------------------------------------------------------------------
-- DEPOSITING ITEMS INTO CHEST / PLAYER
----------------------------------------------------------------------
local function deposit_carried_items(player, pdata, bot)
    local total = get_total_carried(pdata)
    if total <= 0 then
        return false
    end

    pdata.unplaceable_items = pdata.unplaceable_items or {}

    local any_inserted = false

    for name, count in pairs(pdata.carried_items) do
        if count and count > 0 then
            local container = find_best_container_for_item(player, bot, name)
            if container then
                local inv = container.get_inventory(defines.inventory.chest)
                if inv and inv.valid then
                    local inserted = inv.insert {
                        name = name,
                        count = count
                    }

                    if inserted > 0 then
                        any_inserted = true
                    end

                    local remaining = count - inserted

                    if remaining > 0 then
                        -- Container already has the item but is now full.
                        pdata.carried_items[name] = remaining
                        pdata.unplaceable_items[name] = true
                        player.print("[CleanupBot] No container space for item '" .. name .. "'.")
                    else
                        pdata.carried_items[name] = nil
                        pdata.unplaceable_items[name] = nil
                    end
                end
            else
                -- Rule 1: no container available that already has this type.
                pdata.unplaceable_items[name] = true
                player.print("[CleanupBot] No container found that already contains '" .. name .. "'.")
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
        visuals.clear_all(pdata)
        return
    end

    local bot = ensure_bot_for_player(player, pdata)
    if not bot then
        return
    end

    local surface = bot.surface
    local pp = player.position
    local bp = bot.position

    -- If bot somehow wandered too far, snap it back near the player.
    local max_d2 = (CLEANUP_ROAM_RADIUS * 1.3) ^ 2
    if distance_squared(bp, pp) > max_d2 then
        bot.teleport({
            x = pp.x - 1,
            y = pp.y - 1
        })
        bp = bot.position
        pdata.target_position = nil
    end

    ------------------------------------------------------------------
    -- Look for items near the bot and pick them up.
    ------------------------------------------------------------------
    pick_up_nearby_items(player, bot, pdata)

    ------------------------------------------------------------------
    -- Decide what we are trying to do next:
    --   1. If carrying items and we have a chest: head to chest.
    --   2. If not carrying items:
    --        a) Look for the nearest ground item (around bot, then player).
    --        b) If found, head for it.
    --        c) Otherwise, random roam within the radius.
    ------------------------------------------------------------------
    local carried_total = get_total_carried(pdata)
    local carrying_anything = carried_total > 0

    -- When carrying items, always try to deposit into suitable containers.
    if carrying_anything then
        deposit_carried_items(player, pdata, bot)
        carried_total = get_total_carried(pdata) -- recompute after deposit
    end

    local has_unplaceable = pdata.unplaceable_items and next(pdata.unplaceable_items) ~= nil

    if has_unplaceable then
        ------------------------------------------------------------------
        -- Rule 3: once no suitable container can be found, follow player
        -- at offset (-2, +2).
        ------------------------------------------------------------------
        pdata.mode = "no-container"
        pdata.target_position = {
            x = pp.x + FOLLOW_OFFSET.x,
            y = pp.y + FOLLOW_OFFSET.y
        }
    else
        ------------------------------------------------------------------
        -- Normal behaviour: look for items to pick up, otherwise roam.
        ------------------------------------------------------------------
        local nearest_item = find_nearest_ground_item(surface, bp, ITEM_SEARCH_RADIUS)
        if not nearest_item then
            -- If nothing near bot, try around the player.
            nearest_item = find_nearest_ground_item(surface, pp, ITEM_SEARCH_RADIUS)
        end

        if nearest_item and nearest_item.valid then
            pdata.mode = "pickup"
            pdata.target_position = {
                x = nearest_item.position.x,
                y = nearest_item.position.y
            }
        else
            -- No items, just roam randomly within radius.
            if not pdata.target_position or pdata.mode ~= "roam" then
                pick_random_roam_target(player, bot, pdata)
            end
        end
    end

    ------------------------------------------------------------------
    -- If we have a target position, move toward it.
    ------------------------------------------------------------------
    if pdata.target_position then
        move_bot_towards(bot, pdata.target_position)

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
                if pdata.mode == "roam" then
                    pick_random_roam_target(player, bot, pdata)
                end
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
    local has_unplaceable = pdata.unplaceable_items and next(pdata.unplaceable_items) ~= nil
    visuals.draw_bot_highlight(bot, pdata, BOT_HIGHLIGHT_Y_OFFSET, has_unplaceable)

    -- search circle
    if visuals.update_search_radius_circle then
        visuals.update_search_radius_circle(player, pdata, bot, ITEM_SEARCH_RADIUS)
    end

    if chest and chest.valid then
        visuals.draw_chest_highlight(chest, pdata, CHEST_HIGHLIGHT_Y_OFFSET)
    else
        visuals.clear_chest_highlight(pdata)
    end
    visuals.draw_bot_player_line(player, bot, pdata, pdata.mode or "idle")

    local carried_total_for_ui = get_total_carried(pdata)

    visuals.draw_status_text(bot, pdata, pdata.mode or "idle", carried_total_for_ui, BOT_HIGHLIGHT_Y_OFFSET,
        BOT_MAX_ITEM_COUNT)

    -- line from bot to current target (item, chest, or roam point).
    -- The visual function itself will only show it in pickup mode.
    if pdata.target_position then
        visuals.draw_target_line(bot, pdata, pdata.target_position, pdata.mode or "idle")
    else
        visuals.draw_target_line(bot, pdata, nil, pdata.mode or "idle") -- clears old line
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
        player.print("[CleanupBot] Enabled.")
    else
        -- Destroy bot entity if present.
        if pdata.cleanup_bot and pdata.cleanup_bot.valid then
            pdata.cleanup_bot.destroy()
        end
        pdata.cleanup_bot = nil

        -- Clear carried items and visuals.
        pdata.carried_items = {}
        pdata.unplaceable_items = {}

        visuals.clear_all(pdata)

        pdata.target_position = nil
        pdata.mode = "idle"

        player.print("[CleanupBot] Disabled.")
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
