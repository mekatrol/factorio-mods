local util = {}

----------------------------------------------------------------------
-- Print helpers
----------------------------------------------------------------------

function util.print(player_or_game, color, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = "<format error>"
    end

    local text = {"", string.format("[color=%s][Game Play Bot][/color] ", color), msg}

    -- game and LuaPlayer both have .print, but be explicit and safe
    if player_or_game == game then
        game.print(text)
    elseif player_or_game and player_or_game.valid then
        player_or_game.print(text)
    end
end

-- Simple, fast, order-independent hash combiner.
-- Uses 32-bit wrap semantics implemented via Lua numbers.
function util.hash_combine(h, v)
    h = h + v * 0x9e3779b1
    h = h - math.floor(h / 0x100000000) * 0x100000000
    return h
end

function util.parse_kv_list(s)
    -- Supports: "coal=500 iron-plate=200" (space-separated)
    local out = {}

    if not s or s == "" then
        return out
    end

    for token in string.gmatch(s, "%S+") do
        local name, count_s = string.match(token, "^([^=]+)=(%d+)$")
        if name and count_s then
            out[name] = tonumber(count_s)
        end
    end

    return out
end

return util
