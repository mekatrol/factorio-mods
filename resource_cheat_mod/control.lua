-- control.lua
script.on_event("give-yellow-science", function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    -- Vanilla yellow + purple science
    player.insert {
        name = "utility-science-pack",
        count = 100
    } -- yellow
    player.insert {
        name = "production-science-pack",
        count = 100
    } -- purple

    player.print("Gave you 100 yellow + 100 purple science packs.")
end)
