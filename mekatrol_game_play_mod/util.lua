local util = {}

local module = require("module")

----------------------------------------------------------------------
-- Print helpers
----------------------------------------------------------------------

function util.print_player_or_game(player_or_game, color, fmt, ...)
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

function util.print_red(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = "<format error>"
    end

    local color = "red"
    local text = {"", string.format("[color=%s][Game Play Bot][/color] ", color), msg}

    game.print(text)
end

function util.print_modules()
    util.print_player_or_game(game, "red", "modules:")
    for key, value in pairs(module.modules) do
        util.print_player_or_game(game, "red", "  %s = %s", key, tostring(value))
    end
end

function util.tile_normalised_position(pos)
    -- normalise the position corner of tile for which the position is contained
    local tile_x = math.floor(pos.x)
    local tile_y = math.floor(pos.y)

    return {
        x = tile_x,
        y = tile_y
    }
end

function util.tile_center_position(pos)
    -- normalise the position corner of tile for which the position is contained
    local tile_x = math.floor(pos.x)
    local tile_y = math.floor(pos.y)

    -- return center of tile (normalised + 0.5)
    return {
        x = tile_x + 0.5,
        y = tile_y + 0.5
    }
end

function util.generated_id(ent)
    local pos = util.tile_normalised_position(ent.position)
    local unit_number = ent.unit_number or 0
    local id = string.format("%s.%d.%d.%d.%d", ent.name, ent.surface.index, pos.x, pos.y, unit_number)
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

function util.get_value(t, key)
    if type(t) ~= "table" then
        return nil
    end

    return t[key]
end

function util.print_table(player_or_game, t, opts)
    local color = "yellow"

    opts = opts or {}
    local indent_step = opts.indent_step or 2
    local max_depth = opts.max_depth or 10

    local visited = {}

    local function indent(level)
        return string.rep(" ", level * indent_step)
    end

    local function is_array(tbl)
        local n = #tbl
        if n == 0 then
            return next(tbl) == nil
        end

        for k in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
                return false
            end
        end
        return true
    end

    local function print_value(key, value, level)
        local prefix = indent(level)

        if type(value) ~= "table" then
            util.print_player_or_game(player_or_game, color, "%s[%s] = %s", prefix, tostring(key), tostring(value))
            return
        end

        if visited[value] then
            util.print_player_or_game(player_or_game, color, "%s[%s] = <cycle>", prefix, tostring(key))
            return
        end

        if level >= max_depth then
            util.print_player_or_game(player_or_game, color, "%s[%s] = <max depth>", prefix, tostring(key))
            return
        end

        visited[value] = true

        local array = is_array(value)
        util.print_player_or_game(player_or_game, color, "%s[%s] = %s:", prefix, tostring(key),
            array and "array" or "dict")

        if array then
            for i = 1, #value do
                print_value(i, value[i], level + 1)
            end
        else
            for k, v in pairs(value) do
                print_value(k, v, level + 1)
            end
        end
    end

    if t == nil then
        util.print_player_or_game(player_or_game, color, "table is nil")
        return
    end

    if type(t) ~= "table" then
        util.print_player_or_game(player_or_game, color, "<not a table>")
        return
    end

    visited[t] = true

    local array = is_array(t)
    util.print_player_or_game(player_or_game, color, "%s:", array and "array" or "dict")

    if array then
        for i = 1, #t do
            print_value(i, t[i], 1)
        end
    else
        for k, v in pairs(t) do
            print_value(k, v, 1)
        end
    end
end

function util.array_peek(array)
    if type(array) ~= "table" then
        return nil
    end

    if #array < 1 then
        return nil
    end

    return array[1]
end

function util.array_pop(array)
    local value = util.array_peek(array)

    if value then
        table.remove(array, 1)
    end

    return value
end

function util.remove_key(t, key)
    -- no table then no remove
    if t == nil then
        return
    end

    if type(t) ~= "table" then
        return false
    end

    if t[key] ~= nil then
        t[key] = nil
        return true
    end

    return false
end

function util.remove_array_value(array, value)
    if type(array) ~= "table" then
        return false
    end

    local n = #array
    for i = 1, n do
        if array[i] == value then
            table.remove(array, i)
            return true
        end
    end

    return false
end

function util.peek_dict_value(t, key)
    local array = util.get_value(t, key)

    if not array then
        return nil
    end

    return util.array_peek(array)
end

function util.dict_array_pop(t, key)
    local array = util.get_value(t, key)

    if not array then
        return nil
    end

    return util.array_pop(array)
end

function util.filter_player_and_bots(player, ents)
    -- Filter player character safely
    local character = nil
    if player and player.valid then
        character = player.character -- may be nil, that's fine
    end

    for i = #ents, 1, -1 do
        local ent = ents[i]

        -- make sure ent is valid
        if not ent or not ent.valid then
            table.remove(ents, i)
            -- do not remove player
        elseif character and ent == character then
            table.remove(ents, i)
            -- do not remove bot
        elseif ent.name == "mekatrol-game-play-bot" then
            table.remove(ents, i)
        end
    end

    return ents
end

function util.sort_entities_by_position(entities, pos)
    -- sort from nearest to bot to farthest from bot
    table.sort(entities, function(a, b)
        local a_valid = a and a.valid
        local b_valid = b and b.valid

        -- Invalids always go last
        if not a_valid and not b_valid then
            return false
        end
        if not a_valid then
            return false
        end
        if not b_valid then
            return true
        end

        local ax = a.position.x - pos.x
        local ay = a.position.y - pos.y
        local bx = b.position.x - pos.x
        local by = b.position.y - pos.y

        return (ax * ax + ay * ay) < (bx * bx + by * by)
    end)
end

function util.find_entities(player, pos, search_radius, surface, find_name, find_others, find_starts_with, sort_by_pos)
    local found = {}
    local others = {}

    -- Build a set for "others" names for fast lookup
    local others_set = nil
    if find_others ~= nil then
        others_set = {}
        for i = 1, #find_others do
            local item = find_others[i]
            if item and item.name then
                others_set[item.name] = true
            end
        end
    end

    local prefix = find_name
    local want_name = find_name ~= nil

    -- If we're doing starts-with/contains, we can't pass name=... to the filter.
    local filter = {
        position = pos,
        radius = search_radius
    }

    if find_name ~= nil and not find_starts_with then
        filter.name = find_name
    end

    for _, ent in pairs(surface.find_entities_filtered(filter)) do
        if ent.valid then
            local is_match = false

            if find_name == nil then
                is_match = true
            elseif not find_starts_with then
                -- exact match (and filter.name already restricted it)
                is_match = (ent.name == find_name)
            else
                -- contains
                is_match = (string.find(ent.name, prefix, 1, true) ~= nil)
            end

            if is_match then
                found[#found + 1] = ent
            else
                if others_set and others_set[ent.name] then
                    others[#others + 1] = ent
                end
            end
        end
    end

    if sort_by_pos then
        util.sort_entities_by_position(found, pos)
    end

    return util.filter_player_and_bots(player, found), util.filter_player_and_bots(player, others)
end

function util.scan_entities(player, pos, search_radius, surface, search_list)
    local found = {}

    -- Build a set of names to match against
    local entity_set = nil

    if search_list ~= nil then
        entity_set = {}
        for i = 1, #search_list do
            local item = search_list[i]
            if item and item.name then
                entity_set[item.name] = true
            end
        end
    end

    if not entity_set then
        return {}
    end

    local filter = {
        position = pos,
        radius = search_radius
    }

    for _, ent in pairs(surface.find_entities_filtered(filter)) do
        if ent.valid then
            local match = false

            -- ent.name contains ANY of the others_set names
            for name in pairs(entity_set) do
                if string.find(ent.name, name, 1, true) then
                    match = true
                    break
                end
            end

            if match then
                found[#found + 1] = ent
            end
        end
    end

    return util.filter_player_and_bots(player, found)
end

return util
