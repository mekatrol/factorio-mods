local search = {}

local config = require("config")
local module = require("module")
local polygon = require("polygon")
local positioning = require("positioning")
local util = require("util")

local BOT_CONF = config.bot
local DETECTION_RADIUS = BOT_CONF.search.detection_radius / 3

----------------------------------------------------------------------
-- Search task
----------------------------------------------------------------------

local function init_spiral(ps, bpos)
    ps.search_spiral = {
        origin = {
            x = bpos.x,
            y = bpos.y
        },

        -- square spiral state
        dir = 0, -- 0=E,1=N,2=W,3=S
        leg_len = 1, -- how many steps in current leg
        leg_progress = 0, -- steps taken in current leg
        legs_done = 0, -- completed legs (every 2 legs, leg_len++)
        offset_x = 0,
        offset_y = 0
    }
end

local function spiral_advance(ps)
    local s = ps.search_spiral
    if not s then
        return
    end

    -- move DETECTION_RADIUS cells in current direction
    if s.dir == 0 then
        s.offset_x = s.offset_x + DETECTION_RADIUS
    elseif s.dir == 1 then
        s.offset_y = s.offset_y - DETECTION_RADIUS
    elseif s.dir == 2 then
        s.offset_x = s.offset_x - DETECTION_RADIUS
    else
        s.offset_y = s.offset_y + DETECTION_RADIUS
    end

    s.leg_progress = s.leg_progress + 1

    -- if finished this leg, turn right; every 2 legs increase length
    if s.leg_progress >= s.leg_len then
        s.leg_progress = 0
        s.dir = (s.dir + 1) % 4
        s.legs_done = s.legs_done + 1
        if (s.legs_done % 2) == 0 then
            s.leg_len = s.leg_len + 1
        end
    end
end

function search.pick_new_search_target_spiral(ps, bpos)
    if not ps.search_spiral then
        init_spiral(ps, bpos)
    end

    spiral_advance(ps)

    local s = ps.search_spiral
    local step = BOT_CONF.search.step_distance

    return {
        x = s.origin.x + s.offset_x * step,
        y = s.origin.y + s.offset_y * step
    }
end

local function find_entity(player, ps, bot, pos, surf, find_name)
    local entity_group = module.get_module("entity_group")

    bot.task.next_survey_entities = bot.task.next_survey_entities or {}

    local next_entities = bot.task.next_survey_entities

    -- if there are any queued then remove until a valid one is found
    while #next_entities > 0 do
        -- resort table as different entities may now be closer to bot position
        util.sort_entities_by_position(next_entities, pos)

        local e = table.remove(next_entities, 1)

        if e and e.valid then
            -- recheck this entity may have been added prior to boundary for this area created
            if not entity_group.is_in_any_entity_group(ps, surf.index, e) then
                return e
            end
        end
    end

    local found = util.find_entities(player, pos, BOT_CONF.search.detection_radius, surf, find_name, true, true)

    local char = player.character
    local next_found_entity = nil

    for _, e in ipairs(found) do
        if not entity_group.is_survey_ignore_target(e) then
            -- Ignore entities already covered by an existing entity_group polygon
            if not entity_group.is_in_any_entity_group(ps, surf.index, e) then
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

local function get_search_name(player, ps, bot)
    if bot.task.search_name then
        return bot.task.search_name
    end

    -- try an get next search name in list
    bot.task.search_name = util.dict_array_pop(bot.task.args, "search_list")

    return bot.task.search_name
end

function search.update(player, ps, state, bot)
    if not (player and player.valid and bot and bot.entity and bot.entity.valid) then
        return
    end

    local bot_module = module.get_module(bot.name)

    local surf = bot.entity.surface
    local target_pos = bot.task.target_position
    local bpos = bot.entity.position

    if not target_pos then
        local search_name = get_search_name(player, ps, bot)

        local entity = find_entity(player, ps, bot, bpos, surf, search_name)

        if entity then
            -- record what we found (optional, but useful for overlay/debug)
            bot.task.survey_entity = entity

            -- move to the entity and then switch to survey task
            -- to survey the entity group
            bot.task.target_position = {
                x = entity.position.x,
                y = entity.position.y
            }

            -- reset search spiral so searching restarts cleanly after
            bot.task.search_spiral = nil

            return
        else
            local name = bot.task.survey_entity.name
            local prefix = bot.task.search_name

            if name ~= nil and prefix ~= nil and string.sub(name, 1, #prefix) == prefix then
                -- clean current name
                bot.task.search_name = nil

                -- update search name to next type
                search_name = get_search_name(player, ps, bot)

                -- clear previous found entity
                bot.task.survey_entity = nil
            end

            if not search_name then
                -- no more search list
                bot.task.args["search_list"] = nil

                -- return to follow mode
                bot_module.set_bot_task(player, ps, "follow", nil, bot.task.args)
                return
            end
        end

        target_pos = search.pick_new_search_target_spiral(ps, bot.entity.position)

        -- move to the entity and then swtich to survey task
        bot.task.target_position = target_pos
    end

    positioning.move_entity_towards(player, bot.entity, target_pos)

    if not positioning.positions_are_close(target_pos, bpos) then
        return
    end

    -- destination reached, so clear target position
    bot.task.target_position = nil

    -- return if no current search name
    if bot.task.search_name == nil then
        return
    end

    bot.task.survey_entity = bot.task.survey_entity or {
        name = bot.task.search_name
    }

    -- switch to survey task once destination reached so that we can survey the location
    bot_module.set_bot_task(player, ps, "survey", "search", bot.task.args)
end

return search
