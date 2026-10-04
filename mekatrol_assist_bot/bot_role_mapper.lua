-- Mapper role policy: scan an unbounded square spiral and publish static entities.
local config = require("config")
local M = {
    tasks = {"follow", "search"},
    scan_phase = "moving"
}

-- Mobile and transient entities would make discovery records stale almost
-- immediately, so only stationary world features are retained.
local mobile = {
    character = true,
    car = true,
    ["spider-vehicle"] = true,
    locomotive = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
    unit = true,
    corpse = true,
    ["character-corpse"] = true,
    fish = true,
    ["combat-robot"] = true,
    ["construction-robot"] = true,
    ["logistic-robot"] = true,
    projectile = true,
    beam = true,
    ["flying-text"] = true,
    smoke = true,
    fire = true,
    stream = true
}

function M.command(action, context)
    if action == "clear" then
        require("discovery").clear()
        context.say("map cleared")
        return true
    end
    return false
end

function M.radius()
    return nil
end

function M.filter()
    return {}
end

function M.valid(entity)
    return not mobile[entity.type]
end

---Mapper consumes scan results directly instead of selecting a nearest target.
function M.scan_entity(entity)
    if M.valid(entity) then
        require("discovery").add(entity)
    end
end

function M.act(_, _, entity)
    require("discovery").add(entity)
    return true
end

---Return the next cell in an outward square spiral.
---Directions cycle right, down, left, up. Leg lengths are 1,1,2,2,3,3,
---enumerating every cell without retaining an unbounded future-work queue.
function M.scan_area(rs, anchor)
    if rs.mapper_surface ~= anchor.surface.index then
        rs.mapper_surface = anchor.surface.index
        rs.mapper_origin = {x = anchor.position.x, y = anchor.position.y}
        rs.mapper_leg, rs.mapper_leg_progress, rs.mapper_leg_length = 0, 0, 1
        rs.mapper_x, rs.mapper_y, rs.mapper_direction = 0, 0, 1
    end
    -- mapper_x/y are offsets measured in scan cells, while the returned area is
    -- expressed in world tiles. Floor anchors the spiral to the containing cell.
    local cell_size_tiles = config.scanning.cell_size
    local cell_x = math.floor(rs.mapper_origin.x / cell_size_tiles) + rs.mapper_x
    local cell_y = math.floor(rs.mapper_origin.y / cell_size_tiles) + rs.mapper_y
    local area = {{cell_x * cell_size_tiles, cell_y * cell_size_tiles},
                  {(cell_x + 1) * cell_size_tiles, (cell_y + 1) * cell_size_tiles}}
    -- Direction indices map to right, down, left, and up cell offsets.
    local cell_step_x = ({1, 0, -1, 0})[rs.mapper_direction]
    local cell_step_y = ({0, 1, 0, -1})[rs.mapper_direction]
    rs.mapper_x, rs.mapper_y = rs.mapper_x + cell_step_x, rs.mapper_y + cell_step_y
    rs.mapper_leg_progress = rs.mapper_leg_progress + 1
    if rs.mapper_leg_progress >= rs.mapper_leg_length then
        rs.mapper_leg_progress = 0
        rs.mapper_direction = rs.mapper_direction % 4 + 1
        rs.mapper_leg = rs.mapper_leg + 1
        if rs.mapper_leg % 2 == 0 then
            rs.mapper_leg_length = rs.mapper_leg_length + 1
        end
    end
    return area
end

return M
