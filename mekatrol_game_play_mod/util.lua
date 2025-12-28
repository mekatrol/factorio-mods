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

function util.tile_normalised_position(pos)
    -- normalise the position corner of tile for which the position is contained
    local tx = math.floor(pos.x)
    local ty = math.floor(pos.y)

    return {
        x = tx,
        y = ty
    }
end

function util.tile_center_position(pos)
    -- normalise the position corner of tile for which the position is contained
    local tx = math.floor(pos.x)
    local ty = math.floor(pos.y)

    -- return center of tile (normalised + 0.5)
    return {
        x = tx + 0.5,
        y = ty + 0.5
    }
end

function util.generated_id(ent)
    local pos = util.tile_normalised_position(ent.position)
    local id = string.format("%d.%d.%d", ent.surface.index, pos.x, pos.y)
    return id
end

function util.parse_kv_list(args)
    local kv_args = {}

    args = tostring(args or "")

    -- Accept either whitespace or commas as separators: "coal=500,iron-plate=200"
    for token in string.gmatch(args, "[^%s,;]+") do
        local name, count_s = string.match(token, "^([^=]+)=(%d+)$")

        if name and count_s then
            kv_args[name] = tonumber(count_s)
        end
    end

    return kv_args
end

function util.table_size(t)
    if type(t) ~= "table" then
        return 0
    end

    -- If it looks like an array, use length operator
    local n = #t
    if n > 0 then
        return n
    end

    -- Otherwise count keys (map-style table)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return util
