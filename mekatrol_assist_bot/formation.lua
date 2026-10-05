-- This module performs two related jobs:
--   1. It calculates a deterministic formation slot for every active bot.
--   2. It remembers the player's latest cardinal travel direction so the
--      entire formation stays behind the player and leaves the view ahead clear.
--
-- All positions returned by this module are offsets relative to the player.
-- This module does not create, move, or retain any LuaEntity objects.
local config = require("config")

---A two-dimensional player position or formation offset.
---@class FormationPosition
---@field x number Horizontal world coordinate or relative offset.
---@field y number Vertical world coordinate or relative offset.

-- Exported functions are collected in M and returned at the bottom of the file.
local M = {}

---Convert a persisted direction into a unit heading vector.
---
---Factorio's map coordinates increase to the right on X and downward on Y:
---  right = ( 1,  0)
---  left  = (-1,  0)
---  down  = ( 0,  1)
---  up    = ( 0, -1)
---
---Any missing or unknown value defaults to right, which is also the initial
---direction used by state.lua.
local function heading(direction)
    if direction == "left" then
        return -1, 0
    -- Negative Y is upward in Factorio's world coordinate system.
    elseif direction == "up" then
        return 0, -1
    -- Positive Y is downward in Factorio's world coordinate system.
    elseif direction == "down" then
        return 0, 1
    end

    -- "right", nil, and unexpected values all use the safe default.
    return 1, 0
end

---Calculate player-relative slots for all active bot roles.
---@param active string[] Role names in their stable configured display order.
---@param direction string Cardinal direction.
---@return table<string, FormationPosition> slots Offset indexed by role name.
function M.slots(active, direction)
    -- heading_x/heading_y point in the direction the player is travelling.
    local heading_x, heading_y = heading(direction)

    -- Keep configured role order stable when the player reverses direction.
    -- Horizontal travel always lays rows from top to bottom; vertical travel
    -- always lays them from left to right. Only the trailing axis is mirrored.
    local row_x, row_y
    if heading_x ~= 0 then
        row_x, row_y = 0, 1
    else
        row_x, row_y = 1, 0
    end

    local result = {}
    local count = #active
    if count == 0 then
        return result
    end

    -- Distribute every active bot over a circular arc centred directly behind
    -- the player's heading. The arc never reaches the player's forward half.
    local arc = math.rad(config.formation.arc_degrees)
    local angle_step = count > 1 and arc / (count - 1) or 0
    local radius = config.formation.radius
    if count > 1 then
        -- Chord length is 2r*sin(angle/2). Enlarge crowded formations so the
        -- requested clearance applies to actual world distance, not arc length.
        radius = math.max(radius, config.formation.slot_spacing / (2 * math.sin(angle_step / 2)))
    end

    for i, name in ipairs(active) do
        local angle = count > 1 and (-arc / 2 + (i - 1) * angle_step) or 0
        local behind = radius * math.cos(angle)
        local across = radius * math.sin(angle)
        result[name] = {
            x = -heading_x * behind + row_x * across,
            y = -heading_y * behind + row_y * across
        }
    end

    -- Callers add each returned offset to the live player anchor position.
    return result
end

---Return true when every role has a distinct slot.
---@param slots table<string, FormationPosition> Formation offsets by role.
---@return boolean unique True if no two roles occupy the same coordinates.
function M.has_unique_slots(slots)
    -- Treat this table as a set of normalized coordinate strings.
    local occupied = {}

    -- Role names are irrelevant here; only their calculated offsets matter.
    for _, slot in pairs(slots) do
        -- Nine decimal places make equivalent floating-point offsets compare
        -- consistently without depending on Lua table identity.
        local key = string.format("%.9f:%.9f", slot.x, slot.y)

        -- Finding an existing key proves that at least two roles overlap.
        if occupied[key] then
            return false
        end

        -- Mark this coordinate as occupied for subsequent roles.
        occupied[key] = true
    end

    -- No duplicate coordinate was encountered.
    return true
end

---Update and return a player's most recent cardinal travel direction.
---@param ps table Persistent per-player state owned by state.lua.
---@param pos FormationPosition Current player/character anchor position.
---@return string|nil direction Current direction or default value.
function M.update_direction(ps, pos)
    -- A previous sample is required before a movement delta can be calculated.
    if ps.last_position then
        -- Positive dx means right; positive dy means down in Factorio coordinates.
        local dx = pos.x - ps.last_position.x;
        local dy = pos.y - ps.last_position.y

        -- Ignore sub-threshold drift. Retaining the previous direction prevents
        -- the formation from rapidly flipping while the player is stationary.
        if math.abs(dx) >= config.formation.direction_threshold or
            math.abs(dy) >= config.formation.direction_threshold then
            -- Reduce diagonal movement to its dominant cardinal axis. Using the
            -- larger component makes the trailing side stable and predictable.
            if math.abs(dx) >= math.abs(dy) then
                -- Horizontal movement dominates: select right or left by sign.
                ps.direction = dx > 0 and "right" or "left"
            else
                -- Vertical movement dominates: select down or up by sign.
                ps.direction = dy > 0 and "down" or "up"
            end
        end
    end

    -- Store a plain coordinate copy. Persisting the supplied position object
    -- itself could retain an engine-owned or subsequently mutated table.
    ps.last_position = {
        x = pos.x,
        y = pos.y
    };

    -- The bot manager passes this value back into M.slots on the same tick.
    return ps.direction
end

-- Expose only the public formation operations defined above.
return M
