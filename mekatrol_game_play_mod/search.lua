local search = {}

local config = require("config")
local module = require("module")
local positioning = require("positioning")
local util = require("util")

local BOT_CONFIG = config.bot

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

    local DETECTION_RADIUS = BOT_CONFIG.search.detection_radius

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
    local step = BOT_CONFIG.search.step_distance

    return {
        x = s.origin.x + s.offset_x * step,
        y = s.origin.y + s.offset_y * step
    }
end

local function scan_entities(player, ps, bot, pos, surface, search_radius, tick)
    local search_list = bot.task.search_list

    local entities_found = util.scan_entities(player, pos, search_radius, surface, search_list)

    if #entities_found > 0 then
        -- add to discovered entities
        ps.discovered_entities:add_many(ps, surface.index, entities_found, tick)

        -- refresh visuals
        ps.refresh_discovered_entities = true
    end

    return entities_found
end

function search.update(player, ps, bot, tick)
    if not (player and player.valid and bot and bot.entity and bot.entity.valid) then
        return
    end

    local bot_module = module.get_module(bot.name)

    local surface = bot.entity.surface
    local target_pos = bot.task.target_position
    local bpos = bot.entity.position

    if not target_pos then
        target_pos = search.pick_new_search_target_spiral(ps, bot.entity.position)
        bot.task.target_position = target_pos

        -- Scan at starting point
        scan_entities(player, ps, bot, bpos, surface, BOT_CONFIG.search.detection_radius, tick)
    end

    positioning.move_entity_towards(player, bot.entity, target_pos)

    if not positioning.positions_are_close(target_pos, bpos) then
        return
    end

    -- destination reached, so clear target position
    bot.task.target_position = nil
end

return search
