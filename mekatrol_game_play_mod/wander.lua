local wander = {}

local config = require("configuration")
local entitygroup = require("entitygroup")
local mapping = require("mapping")
local polygon = require("polygon")
local positioning = require("positioning")
local state = require("state")
local util = require("util")
local visual = require("visual")

local BOT = config.bot

----------------------------------------------------------------------
-- Wander mode
----------------------------------------------------------------------

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

local function find_entity(player, ps, pos, surf)
    local found = surf.find_entities_filtered {
        position = pos,
        radius = BOT.wander.detection_radius
    }

    -- sort from nearest to bot to farthest from bot
    table.sort(found, function(a, b)
        -- Put invalids at the end
        if not (a and a.valid) then
            return false
        end
        if not (b and b.valid) then
            return true
        end

        local ax = a.position.x - pos.x
        local ay = a.position.y - pos.y
        local bx = b.position.x - pos.x
        local by = b.position.y - pos.y

        return (ax * ax + ay * ay) < (bx * bx + by * by)
    end)

    local char = player.character
    for _, e in ipairs(found) do
        if e.valid and e ~= bot and e ~= char and not entitygroup.is_survey_ignore_target(e) then
            -- Ignore entities already covered by an existing entity_group polygon
            if not entitygroup.is_in_any_entity_group(ps, surf.index, e.position) then
                -- record what we found (optional, but useful for overlay/debug)
                ps.survey_entity = e

                -- move to the entity
                ps.bot_target_position = {
                    x = e.position.x,
                    y = e.position.y
                }

                return e
            end
        end
    end

    return nil
end

function wander.update(player, ps, bot)
    if not (player and player.valid and bot and bot.valid) then
        return
    end

    local surf = bot.surface
    local target = ps.bot_target_position
    local bpos = bot.position

    if not target then
        local found = find_entity(player, ps, bpos, surf)

        if found then
            -- switch to move_to mode
            state.set_player_bot_mode(player, ps, "move_to")

            -- reset wander spiral so wandering restarts cleanly after
            ps.wander_spiral = nil

            return
        end

        target = wander.pick_new_wander_target_spiral(ps, bot.position)
        ps.bot_target_position = target
    end

    positioning.move_bot_towards(player, bot, target)

    local dx = target.x - bpos.x
    local dy = target.y - bpos.y
    local step = BOT.movement.step_distance

    if dx * dx + dy * dy > step * step then
        return
    end

    ps.bot_target_position = nil
end

return wander
