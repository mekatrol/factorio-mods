local util = {}

----------------------------------------------------------------------
-- Print helpers
----------------------------------------------------------------------

function util.print_bot_message(player, color, fmt, ...)
    if not (player and player.valid) then
        return
    end

    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = "<format error>"
    end

    player.print({"", string.format("[color=%s][Game Play Bot][/color] ", color), msg})
end

-- Simple, fast, order-independent hash combiner.
-- Uses 32-bit wrap semantics implemented via Lua numbers.
function util.hash_combine(h, v)
    h = h + v * 0x9e3779b1
    h = h - math.floor(h / 0x100000000) * 0x100000000
    return h
end

return util
