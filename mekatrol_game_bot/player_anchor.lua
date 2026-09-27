local player_anchor = {}

-- Remote view changes LuaPlayer.position/surface to the viewed location.  Bot
-- behavior should remain centred on the character that the player left behind.
function player_anchor.position(player)
    return player.physical_position or
               (player.character and player.character.valid and player.character.position) or
               player.position
end

function player_anchor.surface(player)
    return player.physical_surface or
               (player.character and player.character.valid and player.character.surface) or
               player.surface
end

return player_anchor
