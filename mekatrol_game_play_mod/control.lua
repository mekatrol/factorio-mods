----------------------------------------------------------------------
-- control.lua (Factorio 2.x / Space Age)
--
-- Full rewrite implementing:
--   * follow, wander, survey modes
--   * entity-adjacency BFS survey expansion
--   * nearest-frontier-first traversal (movement style C)
--   * natural step movement (no teleportation)
--
-- Survey Mode Architecture:
--
--   Survey begins with the bot's current position, scans SURVEY_RADIUS.
--   Any newly discovered entity is added as a frontier node.
--
--   The system maintains:
--       player_state.survey_frontier = {
--           { x=..., y=... }, ...
--       }
--
--       player_state.survey_seen = {
--           ["x,y"] = true
--       }
--
--   Each tick:
--       1. Select the frontier node closest to the bot's current position.
--       2. Walk toward it using move_bot_towards(...)
--       3. When within arrival threshold:
--             * run survey scan
--             * add newly discovered entities to frontier
--       4. When frontier becomes empty AND no new discoveries:
--             * survey ends → follow mode
--
----------------------------------------------------------------------
local visuals = require("visuals")

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------

local BOT_UPDATE_INTERVAL = 1
local BOT_STEP_DISTANCE = 0.18
local BOT_FOLLOW_DISTANCE = 1.0
local BOT_SIDE_OFFSET_DISTANCE = 2.0

local WANDER_STEP_DISTANCE = 5.0
local WANDER_DETECTION_RADIUS = 5.0

-- Survey tuning
local SURVEY_RADIUS = 6.0
local SURVEY_ARRIVAL_THRESHOLD = 0.5 -- distance threshold for "arrived at frontier node"

----------------------------------------------------------------------
-- MODES
----------------------------------------------------------------------

local BOT_MODES = {"follow", "wander", "survey"}
local BOT_MODE_INDEX = {}
for i, m in ipairs(BOT_MODES) do
    BOT_MODE_INDEX[m] = i
end

----------------------------------------------------------------------
-- NON-MAPPABLE TYPES
----------------------------------------------------------------------

local NON_STATIC_TYPES = {
    ["character"] = true,
    ["car"] = true,
    ["spider-vehicle"] = true,
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wwagon"] = true,

    ["unit"] = true,
    ["unit-spawner"] = true,

    ["corpse"] = true,
    ["character-corpse"] = true,

    ["fish"] = true,

    ["combat-robot"] = true,
    ["construction-robot"] = true,
    ["logistic-robot"] = true,

    ["projectile"] = true,
    ["beam"] = true,
    ["flying-text"] = true,
    ["smoke"] = true,
    ["fire"] = true,
    ["stream"] = true,
    ["decorative"] = true
}

----------------------------------------------------------------------
-- PRINT HELPERS
----------------------------------------------------------------------

local function print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = "<format error>"
    end

    player.print({"", string.format("[color=%s][Game Play Bot][/color] ", color), msg})
end

----------------------------------------------------------------------
-- STORAGE & PLAYER STATE
----------------------------------------------------------------------

local function ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

local function get_player_state(player_index)
    ensure_storage_tables()
    local all = storage.game_bot
    local ps = all[player_index]

    if not ps then
        ps = {
            bot_entity = nil,
            bot_enabled = false,

            bot_mode = "follow",
            last_player_position = nil,
            last_player_side_offset_x = -BOT_SIDE_OFFSET_DISTANCE,

            wander_target_position = nil,

            -- survey data
            survey_mapped_entities = {},
            survey_frontier = {}, -- list of {x,y}
            survey_seen = {}, -- set of "x,y"

            visuals = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                mapped_entities = {}
            }
        }
        all[player_index] = ps
    else
        ps.visuals = ps.visuals or {}
        ps.visuals.lines = ps.visuals.lines or nil
        ps.visuals.bot_highlight = ps.visuals.bot_highlight or nil
        ps.visuals.radius_circle = ps.visuals.radius_circle or nil
        ps.visuals.mapped_entities = ps.visuals.mapped_entities or {}

        ps.survey_frontier = ps.survey_frontier or {}
        ps.survey_seen = ps.survey_seen or {}
        ps.survey_mapped_entities = ps.survey_mapped_entities or {}
    end

    return ps
end

----------------------------------------------------------------------
-- MODE SETTING
----------------------------------------------------------------------

local function set_player_bot_mode(player, ps, new_mode)
    if not BOT_MODE_INDEX[new_mode] then
        new_mode = "follow"
    end
    if ps.bot_mode == new_mode then
        return
    end

    ps.bot_mode = new_mode
    print_bot_message(player, "green", "mode set to %s", new_mode)

    -- survey mode setup reset if entering survey
    if new_mode == "survey" then
        ps.survey_frontier = {}
        ps.survey_seen = {}
        -- seed initial frontier with current bot position
        if ps.bot_entity and ps.bot_entity.valid then
            local p = ps.bot_entity.position
            table.insert(ps.survey_frontier, {
                x = p.x,
                y = p.y
            })
            ps.survey_seen[string.format("%s,%s", p.x, p.y)] = true
        end
    end
end

----------------------------------------------------------------------
-- BOT LIFECYCLE
----------------------------------------------------------------------

local function destroy_player_bot(player, silent)
    local ps = get_player_state(player.index)
    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_entity.destroy()
    end
    visuals.clear_all(ps)

    ps.bot_entity = nil
    ps.bot_enabled = false

    if not silent then
        print_bot_message(player, "yellow", "deactivated")
    end
end

local function create_player_bot(player)
    local ps = get_player_state(player.index)

    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_enabled = true
        return ps.bot_entity
    end

    local pos = player.position
    local ent = player.surface.create_entity {
        name = "mekatrol-game-play-bot",
        position = {pos.x - 2, pos.y - 2},
        force = player.force,
        raise_built = true
    }

    if ent then
        ps.bot_entity = ent
        ps.bot_enabled = true
        ent.destructible = true

        print_bot_message(player, "green", "created")
        return ent
    else
        print_bot_message(player, "red", "create failed")
        return nil
    end
end

----------------------------------------------------------------------
-- HOTKEY HANDLERS
----------------------------------------------------------------------

local function on_toggle_bot(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = get_player_state(p.index)
    if ps.bot_entity and ps.bot_entity.valid then
        destroy_player_bot(p, false)
    else
        create_player_bot(p)
    end
end

local function on_cycle_bot_mode(event)
    local p = game.get_player(event.player_index)
    if not (p and p.valid) then
        return
    end

    local ps = get_player_state(p.index)
    local cur = ps.bot_mode or "follow"
    local idx = BOT_MODE_INDEX[cur] or 1

    idx = idx + 1
    if idx > #BOT_MODES then
        idx = 1
    end

    set_player_bot_mode(p, ps, BOT_MODES[idx])
end

----------------------------------------------------------------------
-- MOVEMENT / POSITION HELPERS
----------------------------------------------------------------------

local function resolve_target_position(target)
    if type(target) == "table" then
        if target.position then
            return target.position, nil
        elseif target.x and target.y then
            return target, nil
        elseif target[1] and target[2] then
            return {
                x = target[1],
                y = target[2]
            }, nil
        end
    end
    return nil, tostring(target)
end

local function move_bot_towards(player, bot, target)
    if not (bot and bot.valid) then
        return
    end
    local pos, err = resolve_target_position(target)
    if not pos then
        print_bot_message(player, "red", "invalid target: %s", err or "?")
        return
    end

    local bp = bot.position
    local dx = pos.x - bp.x
    local dy = pos.y - bp.y
    local d2 = dx * dx + dy * dy
    if d2 == 0 then
        return
    end

    local dist = math.sqrt(d2)
    if dist <= BOT_STEP_DISTANCE then
        bot.teleport({pos.x, pos.y})
        return
    end

    bot.teleport({
        x = bp.x + dx / dist * BOT_STEP_DISTANCE,
        y = bp.y + dy / dist * BOT_STEP_DISTANCE
    })
end

----------------------------------------------------------------------
-- FOLLOW MODE
----------------------------------------------------------------------

local function follow_player(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local ppos = player.position
    local bpos = bot.position

    -- detect movement direction
    local prev = ps.last_player_position
    local left, right = false, false
    if prev then
        local dx = ppos.x - prev.x
        if dx < -0.1 then
            left = true
        elseif dx > 0.1 then
            right = true
        end
    end
    ps.last_player_position = {
        x = ppos.x,
        y = ppos.y
    }

    -- update side offset
    local so = ps.last_player_side_offset_x or -BOT_SIDE_OFFSET_DISTANCE
    if left and so ~= BOT_SIDE_OFFSET_DISTANCE then
        so = BOT_SIDE_OFFSET_DISTANCE
    elseif right and so ~= -BOT_SIDE_OFFSET_DISTANCE then
        so = -BOT_SIDE_OFFSET_DISTANCE
    end
    ps.last_player_side_offset_x = so

    -- check follow distance
    local dx = ppos.x - bpos.x
    local dy = ppos.y - bpos.y
    if dx * dx + dy * dy <= BOT_FOLLOW_DISTANCE * BOT_FOLLOW_DISTANCE then
        return
    end

    local target = {
        x = ppos.x + so,
        y = ppos.y - 2
    }
    move_bot_towards(player, bot, target)
end

----------------------------------------------------------------------
-- PICK WANDER TARGET
----------------------------------------------------------------------

local function pick_new_wander_target(bpos)
    local angle = math.random() * 2 * math.pi
    local min_d = WANDER_STEP_DISTANCE * 0.4
    local max_d = WANDER_STEP_DISTANCE
    local dist = min_d + (max_d - min_d) * math.random()

    return {
        x = bpos.x + math.cos(angle) * dist,
        y = bpos.y + math.sin(angle) * dist
    }
end

----------------------------------------------------------------------
-- WANDER MODE
----------------------------------------------------------------------

local function wander_bot(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end
    local surf = bot.surface
    local bpos = bot.position

    local target = ps.wander_target_position
    if not target then
        target = pick_new_wander_target(bpos)
        ps.wander_target_position = target
    end

    move_bot_towards(player, bot, target)

    local newp = bot.position
    local dx = target.x - newp.x
    local dy = target.y - newp.y
    if dx * dx + dy * dy <= BOT_STEP_DISTANCE * BOT_STEP_DISTANCE then
        ps.wander_target_position = nil
    end

    -- detect nearby entities
    local found = surf.find_entities_filtered {
        position = newp,
        radius = WANDER_DETECTION_RADIUS
    }

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char then
            ps.wander_target_position = nil
            set_player_bot_mode(player, ps, "survey")
            return
        end
    end
end

----------------------------------------------------------------------
-- MAPPABLE ENTITY CHECK
----------------------------------------------------------------------

local function is_static_mappable(entity)
    if not (entity and entity.valid) then
        return false
    end
    if NON_STATIC_TYPES[entity.type] then
        return false
    end
    return true
end

local function get_entity_key(entity)
    if entity.unit_number then
        return entity.unit_number
    end
    local p = entity.position
    return string.format("%s@%s,%s#%d", entity.name, p.x, p.y, entity.surface.index)
end

----------------------------------------------------------------------
-- MAPPING / FRONTIER UPSERT
----------------------------------------------------------------------

local function upsert_mapped_entity(player, ps, entity, tick)
    local key = get_entity_key(entity)
    if not key then
        return false
    end

    local mapped = ps.survey_mapped_entities
    local info = mapped[key]
    local is_new = false

    if not info then
        is_new = true
        info = {
            name = entity.name,
            surface_index = entity.surface.index,
            position = {
                x = entity.position.x,
                y = entity.position.y
            },
            force_name = entity.force and entity.force.name or nil,
            last_seen_tick = tick,
            discovered_by_player_index = player.index
        }
        mapped[key] = info

        -- Draw box
        local box_id = visuals.draw_mapped_entity_box(player, ps, entity)
        ps.visuals.mapped_entities[key] = box_id
    else
        -- update existing
        local pos = entity.position
        info.position.x = pos.x
        info.position.y = pos.y
        info.last_seen_tick = tick
    end

    return is_new
end

----------------------------------------------------------------------
-- SURVEY MODE (BFS ENTITY EXPANSION, NEAREST-FIRST)
----------------------------------------------------------------------

-- Insert new frontier node only if not previously seen
local function add_frontier_node(ps, x, y)
    local key = string.format("%s,%s", x, y)
    if not ps.survey_seen[key] then
        ps.survey_seen[key] = true
        table.insert(ps.survey_frontier, {
            x = x,
            y = y
        })
    end
end

-- Returns distance^2 between bot and a frontier node
local function frontier_distance_sq(bot_pos, node)
    local dx = node.x - bot_pos.x
    local dy = node.y - bot_pos.y
    return dx * dx + dy * dy
end

-- Select nearest frontier location
local function get_nearest_frontier(ps, bot_pos)
    local frontier = ps.survey_frontier
    if #frontier == 0 then
        return nil
    end

    local best_i = 1
    local best_d2 = frontier_distance_sq(bot_pos, frontier[1])

    for i = 2, #frontier do
        local d2 = frontier_distance_sq(bot_pos, frontier[i])
        if d2 < best_d2 then
            best_d2 = d2
            best_i = i
        end
    end

    -- Remove and return
    local node = frontier[best_i]
    table.remove(frontier, best_i)
    return node
end

-- Perform the survey scan when bot arrives at a frontier node
local function perform_survey_scan(player, ps, bot, tick)
    local surf = bot.surface
    local bpos = bot.position

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = SURVEY_RADIUS
    }

    local discovered_any = false

    for _, e in ipairs(found) do
        if e ~= bot and e ~= player and is_static_mappable(e) then
            if upsert_mapped_entity(player, ps, e, tick) then
                discovered_any = true

                -- Seed new frontier positions at the entity’s location
                local p = e.position
                add_frontier_node(ps, p.x, p.y)
            end
        end
    end

    return discovered_any
end

-- Main survey behavior
local function survey_bot(player, ps, bot, tick)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local bot_pos = bot.position

    -- If no frontier remains: survey complete
    if #ps.survey_frontier == 0 then
        set_player_bot_mode(player, ps, "follow")
        return
    end

    -- Select nearest frontier node
    local target = get_nearest_frontier(ps, bot_pos)
    if not target then
        set_player_bot_mode(player, ps, "follow")
        return
    end

    -- Walk towards frontier node
    move_bot_towards(player, bot, target)

    -- Check arrival
    local new_bp = bot.position
    local dx = target.x - new_bp.x
    local dy = target.y - new_bp.y
    local d2 = dx * dx + dy * dy

    if d2 <= (SURVEY_ARRIVAL_THRESHOLD * SURVEY_ARRIVAL_THRESHOLD) then
        -- Arrived → perform a scan
        local discovered = perform_survey_scan(player, ps, bot, tick)

        -- If the scan discovered nothing and no more frontier nodes → done
        if not discovered and #ps.survey_frontier == 0 then
            set_player_bot_mode(player, ps, "follow")
        end
    else
        -- Not arrived; reinsert the target so it will be retried later
        -- (nearest-first guarantees we target the closest each tick)
        table.insert(ps.survey_frontier, target)
    end
end

----------------------------------------------------------------------
-- VISUALS + BEHAVIOR DISPATCH
----------------------------------------------------------------------

local function update_bot_for_player(player, ps, tick)
    local bot = ps.bot_entity
    if not (bot and bot.valid) then
        return
    end

    -- Update visuals
    visuals.clear_lines(ps)
    visuals.draw_bot_highlight(player, ps)

    local radius, radius_color, line_color = nil, nil, nil

    if ps.bot_mode == "wander" then
        radius = WANDER_DETECTION_RADIUS
        radius_color = {
            r = 0,
            g = 0.6,
            b = 1,
            a = 0.8
        }
        line_color = radius_color
    elseif ps.bot_mode == "survey" then
        radius = SURVEY_RADIUS
        radius_color = {
            r = 1.0,
            g = 0.95,
            b = 0.0,
            a = 0.8
        }
        line_color = radius_color
    elseif ps.bot_mode == "follow" then
        line_color = {
            r = 0.3,
            g = 0.3,
            b = 0.3,
            a = 0.1
        }
    end

    if radius and radius > 0 then
        visuals.draw_radius_circle(player, ps, bot, radius, radius_color)
    else
        visuals.clear_radius_circle(ps)
    end

    if line_color then
        visuals.draw_lines(player, ps, bot, line_color)
    end

    -- Behavior dispatch
    if ps.bot_mode == "follow" then
        follow_player(player, ps, bot)

    elseif ps.bot_mode == "wander" then
        wander_bot(player, ps, bot)

    elseif ps.bot_mode == "survey" then
        survey_bot(player, ps, bot, tick)
    end
end

----------------------------------------------------------------------
-- EVENT: ENTITY DIED
----------------------------------------------------------------------

local function on_entity_died(event)
    local ent = event.entity
    if not ent or ent.name ~= "mekatrol-game-play-bot" then
        return
    end

    ensure_storage_tables()
    for idx, ps in pairs(storage.game_bot) do
        if ps.bot_entity == ent then
            ps.bot_entity = nil
            ps.bot_enabled = false
            visuals.clear_all(ps)

            local pl = game.get_player(idx)
            if pl and pl.valid then
                print_bot_message(pl, "yellow", "destroyed")
            end
        end
    end
end

----------------------------------------------------------------------
-- EVENT: PLAYER REMOVED
----------------------------------------------------------------------

local function on_player_removed(event)
    ensure_storage_tables()
    local all = storage.game_bot
    local idx = event.player_index
    local ps = all[idx]
    if not ps then
        return
    end

    local p = game.get_player(idx)
    if p and p.valid then
        destroy_player_bot(p, true)
    else
        if ps.bot_entity and ps.bot_entity.valid then
            ps.bot_entity.destroy()
        end
    end

    all[idx] = nil
end

----------------------------------------------------------------------
-- INIT / CONFIG
----------------------------------------------------------------------

script.on_init(function()
    ensure_storage_tables()
end)

script.on_configuration_changed(function(_)
    ensure_storage_tables()
end)

----------------------------------------------------------------------
-- EVENT REGISTRATION
----------------------------------------------------------------------

script.on_event("mekatrol-game-play-bot-toggle", on_toggle_bot)
script.on_event("mekatrol-game-play-bot-next-mode", on_cycle_bot_mode)

script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_player_removed, on_player_removed)

----------------------------------------------------------------------
-- TICK HANDLER
----------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
    if event.tick % BOT_UPDATE_INTERVAL ~= 0 then
        return
    end

    -- This mod currently supports single-player; extend for MP if needed
    local player = game.get_player(1)
    if not (player and player.valid) then
        return
    end

    local ps = get_player_state(player.index)
    if not ps then
        return
    end

    if ps.bot_enabled and ps.bot_entity and ps.bot_entity.valid then
        update_bot_for_player(player, ps, event.tick)
    end
end)
