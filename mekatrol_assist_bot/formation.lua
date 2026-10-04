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

    -- Each role receives exactly one offset in this result table.
    local result = {};

    -- A column may contain at most this many bots. The current configuration
    -- sets it to ten, so all ten roles occupy one row perpendicular to travel.
    local per = config.formation.max_slots_per_column

    -- ipairs preserves the configured role order, making layout deterministic.
    for i, name in ipairs(active) do
        -- Convert the one-based role index into a zero-based column index.
        -- Indices 1..per are column 0, per+1..2*per are column 1, and so on.
        local column = math.floor((i - 1) / per);

        -- Record the first one-based role index belonging to this column.
        local first = column * per + 1;

        -- The final column may not be full, so use its actual remaining count.
        -- Centering with the real count prevents a partially filled row from
        -- being visually biased toward one side of the player.
        local count = math.min(per, #active - first + 1);

        -- Convert the global role index into its one-based row within a column.
        local row = i - first + 1

        -- Column 0 sits side_distance behind the player. Overflow columns are
        -- placed another column_spacing farther behind the direction of travel.
        local behind = config.formation.side_distance + column * config.formation.column_spacing

        -- Center row positions around zero. For example, three rows become
        -- -spacing, 0, +spacing; two rows become -spacing/2, +spacing/2.
        local across = (row - (count + 1) / 2) * config.formation.slot_spacing

        -- Negating the heading vector moves the slot behind the player.
        -- Adding the perpendicular row vector spreads bots across that trailing
        -- line. The result remains relative to the player's current position.
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
