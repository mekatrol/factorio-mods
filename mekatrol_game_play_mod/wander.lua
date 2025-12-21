local wander = {}

local config = require("configuration")
local polygon = require("polygon")
local positioning = require("positioning")
local state = require("state")
local util = require("util")

local BOT = config.bot

----------------------------------------------------------------------
-- Wander mode
----------------------------------------------------------------------

local function is_survey_ignore_target(e)
    if not e or not e.valid then
        return true
    end

    -- cliffs are their own type; trees are type "tree"
    if e.type == "cliff" or e.type == "tree" then
        return true
    end

    return false
end

local function is_in_any_entity_group(ps, surface_index, pos)
    local groups = ps.entity_groups
    if not groups then
        return false
    end

    local margin = 1.0 -- tiles (world units)

    for _, g in pairs(groups) do
        if g and g.surface_index == surface_index and g.boundary and #g.boundary >= 3 then
            -- Treat points within 1 tile outside the boundary as "inside"
            if polygon.contains_point_buffered then
                if polygon.contains_point_buffered(g.boundary, pos, margin) then
                    return true
                end
            else
                -- Fallback if you haven't added contains_point_buffered yet
                if polygon.point_in_poly(g.boundary, pos) then
                    return true
                end
            end
        end
    end

    return false
end

local function init_spiral(ps, bpos)
    ps.wander_spiral = {
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
    local s = ps.wander_spiral
    if not s then
        return
    end

    -- move one cell in current direction
    if s.dir == 0 then
        s.offset_x = s.offset_x + 1
    elseif s.dir == 1 then
        s.offset_y = s.offset_y - 1
    elseif s.dir == 2 then
        s.offset_x = s.offset_x - 1
    else
        s.offset_y = s.offset_y + 1
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

function wander.pick_new_wander_target_spiral(ps, bpos)
    if not ps.wander_spiral then
        init_spiral(ps, bpos)
    end

    spiral_advance(ps)

    local s = ps.wander_spiral
    local step = BOT.wander.step_distance

    return {
        x = s.origin.x + s.offset_x * step,
        y = s.origin.y + s.offset_y * step
    }
end

function wander.pick_new_wander_target_random(ps, bpos)
    local angle = math.random() * 2 * math.pi
    local step = BOT.wander.step_distance
    local min_d = step * 0.4
    local max_d = step
    local dist = min_d + (max_d - min_d) * math.random()

    return {
        x = bpos.x + math.cos(angle) * dist,
        y = bpos.y + math.sin(angle) * dist
    }
end

function wander.update(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target = ps.bot_target_position

    if not target then
        target = wander.pick_new_wander_target_spiral(ps, bot.position)
        ps.bot_target_position = target
    end

    positioning.move_bot_towards(player, bot, target)

    local bpos = bot.position
    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local step = BOT.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.bot_target_position = nil

    local found = surf.find_entities_filtered {
        position = bpos,
        radius = BOT.wander.detection_radius
    }

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and not is_survey_ignore_target(e) then
            -- Ignore entities already covered by an existing entity_group polygon
            if not is_in_any_entity_group(ps, surf.index, e.position) then
                ps.survey_entity = {
                    name = e.name,
                    type = e.type
                }
                state.set_player_bot_mode(player, ps, "survey")
                ps.wander_spiral = nil
                return
            end
        end
    end

end

return wander
