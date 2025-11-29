local TICK_INTERVAL = 60 * 60 -- 60 seconds at 60 UPS

local function init()
    storage.tree_spawn_mod = storage.tree_spawn_mod or {
        players = {}
    }

    -- Ensure all existing players have an entry
    for _, player in pairs(game.players) do
        local pdata = storage.tree_spawn_mod.players[player.index]
        if not pdata then
            storage.tree_spawn_mod.players[player.index] = {
                enabled = false -- default: off
            }
        end
    end
end

script.on_init(init)

script.on_configuration_changed(function(cfg)
    init()
end)

script.on_load(function()
    -- nothing needed here for this simple mod
end)

-- Helper: ensure we have player data
local function get_player_data(player_index)
    local s = storage.tree_spawn_mod
    s.players = s.players or {}
    local pdata = s.players[player_index]
    if not pdata then
        pdata = {
            enabled = false
        }
        s.players[player_index] = pdata
    end
    return pdata
end

-- Helper: place a tree near a given player
local function place_tree_near_player(player)
    if not (player and player.valid and player.character) then
        return
    end

    local surface = player.surface
    local pos = player.position

    -- random direction and distance
    local distance = math.random(3, 10) -- 3–10 tiles
    local angle = math.random() * 2 * math.pi
    local target = {
        x = pos.x + math.cos(angle) * distance,
        y = pos.y + math.sin(angle) * distance
    }

    local tree_name = "tree-01" -- you can randomize from a list if you like

    -- find a nearby non-colliding position
    local position = surface.find_non_colliding_position(tree_name, target, 5, 0.5)
    if position then
        surface.create_entity {
            name = tree_name,
            position = position,
            force = "neutral"
        }
    else
        player.print("[Augment] No free space to place a tree nearby.")
    end
end

-- Toggle hotkey handler
script.on_event("augment-toggle-tree", function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    local pdata = get_player_data(event.player_index)
    pdata.enabled = not pdata.enabled

    if pdata.enabled then
        player.print("[Augment] Tree spawning enabled.")
    else
        player.print("[Augment] Tree spawning disabled.")
    end
end)

-- Main tick handler (runs every 60 seconds)
script.on_event(defines.events.on_tick, function(event)
    if event.tick % TICK_INTERVAL ~= 0 then
        return
    end

    for _, player in pairs(game.connected_players) do
        local pdata = get_player_data(player.index)
        if pdata.enabled then
            place_tree_near_player(player)
        end
    end
end)
