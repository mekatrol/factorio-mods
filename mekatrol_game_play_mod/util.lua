local util = {}

local module = require("module")

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

function util.print_modules()
    util.print(game, "red", "modules:")
    for key, value in pairs(module.modules) do
        util.print(game, "red", "  %s = %s", key, tostring(value))
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

function util.get_value(t, key)
    if type(t) ~= "table" then
        return nil
    end

    return t[key]
end

function util.print_table(player_or_game, t)
    local color = "yellow"

    if t == nil then
        util.print(player_or_game, color, "table is nil")
        return
    end

    if type(t) ~= "table" then
        util.print(player_or_game, color, "<not a table>")
        return
    end

    -- Detect array (contiguous 1..n)
    local n = #t
    local is_array = true

    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            is_array = false
            break
        end
    end

    if next(t) == nil then
        util.print(player_or_game, color, "<empty table>")
        return
    end

    util.print(player_or_game, color, "%s:", is_array and "array" or "dict")

    if is_array then
        for i = 1, n do
            util.print(player_or_game, color, "  [%d] = %s", i, tostring(t[i]))
        end
    else
        for k, v in pairs(t) do
            util.print(player_or_game, color, "  [%s] = %s", tostring(k), tostring(v))
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

function util.find_entities(player, pos, radius, surf, find_name, find_others, find_starts_with, sort_by_pos)
    local found = {}
    local others = {}

    if find_name == nil or not find_starts_with then

        -- find when name is not specified, or not looking for a name that starts with
        found = surf.find_entities_filtered {
            position = pos,
            radius = radius,
            name = find_name
        }
    else
        -- find when name is specified and caller wants starts with
        local prefix = find_name

        for _, ent in pairs(surf.find_entities_filtered {
            position = pos,
            radius = radius
        }) do
            if ent.valid then
                if string.sub(ent.name, 1, #prefix) == prefix then
                    found[#found + 1] = ent
                else
                    if find_others ~= nil then
                        for k, v in pairs(find_others) do
                            if v.name == ent.name then
                                others[#others + 1] = ent
                            end
                        end
                    end
                end
            end
        end
    end

    if sort_by_pos then
        found = util.filter_player_and_bots(player, found)
    end

    return util.filter_player_and_bots(player, found), util.filter_player_and_bots(player, others)
end

function util.find_entity(player, ps, bot, pos, surface, search_item, search_radius)
    local entity_group = module.get_module("entity_group")

    bot.task.queued_survey_entities = bot.task.queued_survey_entities or {}
    bot.task.future_survey_entities = bot.task.future_survey_entities or {}

    local next_entities = bot.task.queued_survey_entities
    local future_entities = bot.task.future_survey_entities

    if search_item.find_many then
        -- re-sort table as different entities may now be closer to bot position
        util.sort_entities_by_position(next_entities, pos)

        -- if there are any queued then remove until a valid one is found
        while #next_entities > 0 do
            local e = table.remove(next_entities, 1)

            if e and e.valid then
                -- recheck this entity may have been added prior to boundary for this area created
                if not entity_group.is_in_any_entity_group(ps, surface.index, e) then
                    return e
                end
            end
        end
    end

    local search_for_list = util.get_value(bot.task.args, "search_list")
    local entities_found, others_found = util.find_entities(player, pos, search_radius, surface,
        search_item.name, search_for_list, true, true)

    if #others_found > 0 then
        -- add to future entities
        local start = #future_entities
        for i = 1, #others_found do
            future_entities[start + i] = others_found[i]
        end
    end

    local char = player.character
    local next_found_entity = nil

    for _, e in ipairs(entities_found) do
        if not entity_group.is_survey_ignore_target(e) then
            -- Ignore entities already covered by an existing entity_group polygon
            if not entity_group.is_in_any_entity_group(ps, surface.index, e) then
                if not next_found_entity then
                    next_found_entity = e
                else
                    -- Add it to next set to be found
                    next_entities[#next_entities + 1] = e
                end
            end
        end
    end

    return next_found_entity
end

return util
