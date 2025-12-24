local search = {}

local config = require("config")
local entitygroup = require("entitygroup")
local polygon = require("polygon")
local positioning = require("positioning")
local state = require("state")
local util = require("util")
local visual = require("visual")

local BOT_CONF = config.bot
local DETECTION_RADIUS = BOT_CONF.search.detection_radius / 3

----------------------------------------------------------------------
-- Search mode
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

local function sort_entities_by_position(entities, pos)
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

local function find_entity(player, ps, bot, pos, surf)
    ps.next_survey_entities = ps.next_survey_entities or {}

    local next_entities = ps.next_survey_entities

    -- if there are any queued then remove until a valid one is found
    while #next_entities > 0 do
        -- resort table as different entities may now be closer to bot position
        sort_entities_by_position(next_entities, pos)

        local e = table.remove(next_entities, 1)

        if e and e.valid then

            -- recheck this entity may have been added prior to boundary for this area created
            if not entitygroup.is_in_any_entity_group(ps, surf.index, e) then
                return e
            end
        end
    end

    local found = surf.find_entities_filtered {
        position = pos,
        radius = BOT_CONF.search.detection_radius
    }

    sort_entities_by_position(found, pos)

    local char = player.character
    local next_found_entity = nil

    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and not entitygroup.is_survey_ignore_target(e) then
            -- Ignore entities already covered by an existing entity_group polygon
            if not entitygroup.is_in_any_entity_group(ps, surf.index, e) then
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

function search.update(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target_pos = ps.task.target_position
    local bpos = bot.position

    if not target_pos then
        local entity = find_entity(player, ps, bot, bpos, surf)

        if entity then
            -- record what we found (optional, but useful for overlay/debug)
            ps.survey_entity = entity

            -- move to the entity and then switch to survey mode
            -- to survey the entity group
            ps.task.target_position = {
                x = entity.position.x,
                y = entity.position.y
            }

            -- switch to move_to mode
            state.set_player_bot_task(player, ps, "move_to")

            -- reset search spiral so searching restarts cleanly after
            ps.search_spiral = nil

            return
        end

        target_pos = search.pick_new_search_target_spiral(ps, bot.position)
        -- move to the entity and then swtich to survey mode
        ps.task.target_position = target_pos
    end

    positioning.move_bot_towards(player, bot, target_pos)

    local dx = target_pos.x - bpos.x
    local dy = target_pos.y - bpos.y
    local step = BOT_CONF.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.task.target_position = nil
end

return search
