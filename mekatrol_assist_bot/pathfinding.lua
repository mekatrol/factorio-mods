-- Resumable tile A* for repair travel. Expansion is explicitly budgeted by the scheduler.
local M = {}
-- Four neighbours produce cardinal movement on the tile grid. Diagonals are
-- intentionally excluded, so every edge has cost one and Manhattan distance
-- is an admissible A* heuristic.
local dirs = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}

---Map a continuous world position to the integer coordinates of its tile.
local function tile(p)
    return {
        x = math.floor(p.x),
        y = math.floor(p.y)
    }
end

---Serialize a tile into a stable key suitable for save-safe Lua tables.
local function key(p)
    return p.x .. "," .. p.y
end

---Manhattan distance: the minimum number of cardinal moves on an empty grid.
local function h(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

---Order A* nodes by total estimated cost `f = g + h`.
---The lexical coordinate tie-breaker makes equal-cost searches deterministic.
local function less(a, b)
    return a.f < b.f or (a.f == b.f and key(a.p) < key(b.p))
end

---Insert a node into the binary min-heap and restore its heap invariant.
---A child lives at i and its parent at floor(i/2); repeatedly swapping upward
---takes O(log n) time while keeping the cheapest node at index one.
local function push(heap, node)
    local i = #heap + 1;
    heap[i] = node;
    while i > 1 do
        local parent = math.floor(i / 2);
        if not less(heap[i], heap[parent]) then
            break
        end
        heap[i], heap[parent] = heap[parent], heap[i];
        i = parent
    end
end

---Starts a save-safe path search. `goal_distance` permits interaction beside an
---occupied target tile, which is essential when the target itself is a wall.
function M.start(surface, from, to, max_radius, goal_distance)
    local a, b = tile(from), tile(to);
    local k = key(a)
    return {
        surface_index = surface.index,
        start = a,
        goal = b,
        -- Keep the exact world coordinate as well as its tile.  Interaction
        -- range is Euclidean; a Manhattan distance between tile coordinates
        -- can claim success while the bot is still physically out of range.
        goal_position = {x = to.x, y = to.y},
        -- Defaults keep the standalone helper useful: 96 tiles bounds an
        -- omitted search, while zero requires reaching the exact goal tile.
        max_radius = max_radius or 96,
        goal_distance = goal_distance or 0,
        open = {{
            p = a,
            g = 0,
            f = h(a, b)
        }},
        scores = {
            [k] = 0
        },
        parents = {},
        done = false,
        failed = false,
        path = nil
    }
end

---Return whether the centre of a candidate tile is inside interaction range.
---Exported for deterministic geometry tests.
function M.within_goal(p, goal_position, goal_distance)
    local dx = p.x + 0.5 - goal_position.x
    local dy = p.y + 0.5 - goal_position.y
    return dx * dx + dy * dy <= goal_distance * goal_distance
end

---Return whether the pathfinder treats this tile as occupied.
local function blocked(surface, p)
    -- Query inside the tile rather than on its borders, where entities in an
    -- adjacent tile could be returned. Only walls and gates obstruct this
    -- lightweight repair pathfinder; flying visuals ignore other collisions.
    local entities = surface.find_entities_filtered {
        area = {{p.x + 0.1, p.y + 0.1}, {p.x + 0.9, p.y + 0.9}},
        type = {"wall", "gate"},
        limit = 1
    }
    return #entities > 0
end

---Remove and return the cheapest node from the binary min-heap.
---The last node fills the hole at the root and is sifted downward, always
---choosing the cheaper child, until parent <= children is restored.
local function pop(job)
    local heap = job.open;
    if #heap == 0 then
        return nil
    end
    -- Index one is the minimum because `push` maintains a min-heap.
    local root = heap[1];
    -- Move the final element into the root hole, then shorten the array. When
    -- there was only one element this correctly assigns then clears index one.
    heap[1] = heap[#heap];
    heap[#heap] = nil;
    local i = 1
    while true do
        local left = i * 2;
        if left > #heap then
            break
        end
        local right = left + 1;
        -- Prefer the right child only when it exists and is strictly cheaper;
        -- otherwise choose left. This expression also gives deterministic left
        -- preference when both children compare equal.
        local child = right <= #heap and less(heap[right], heap[left]) and right or left;
        if not less(heap[child], heap[i]) then
            break
        end
        heap[i], heap[child] = heap[child], heap[i];
        i = child
    end
    return root
end

---Advance a path job by exactly one bounded unit of work.
---A search call expands one tile. Once the goal is found, later calls prepend
---one parent tile at a time. Both phases are incremental so large searches do
---not monopolize a Factorio tick, and all job fields remain serializable.
function M.step(job)
    if job.done then
        return true
    end
    if job.phase == "reconstruct" then
        local k = job.reconstruct_key;
        if not k then
            job.cursor = #job.path;
            job.done = true;
            return true
        end
        -- Keys were serialized as `x,y`. Splitting at the first comma is safe
        -- for negative and decimal text because neither contains another comma.
        local x, y = k:match("^([^,]+),(.+)$");
        -- Parents point from child toward the start, so this array is built
        -- goal-to-start. Controllers consume it from `cursor = #path`, which
        -- consequently walks start-to-goal without reversing the whole array.
        job.path[#job.path + 1] = {
            -- Search coordinates name tile corners; movement destinations use
            -- centers, hence the half-tile offset on both axes.
            x = tonumber(x) + 0.5,
            y = tonumber(y) + 0.5
        };
        job.reconstruct_key = job.parents[k];
        return false
    end
    local surface = game.surfaces[job.surface_index];
    local node = pop(job)
    if not surface or not node then
        job.done = true;
        job.failed = true;
        return true
    end
    -- Older in-progress saves have only `goal`; its centre is the closest
    -- faithful reconstruction of the original continuous target position.
    local goal_position = job.goal_position or {x = job.goal.x + 0.5, y = job.goal.y + 0.5}
    if M.within_goal(node.p, goal_position, job.goal_distance) then
        job.path = {};
        job.reconstruct_key = key(node.p);
        job.phase = "reconstruct";
        return false
    end
    for _, d in ipairs(dirs) do
        local p = {
            x = node.p.x + d[1],
            y = node.p.y + d[2]
        };
        local k = key(p);
        -- Every cardinal edge costs one, hence candidate g = parent's g + 1.
        local g = node.g + 1
        -- max_radius bounds both CPU/memory growth and how far a bot may stray.
        -- A candidate is useful only if it is traversable and improves the
        -- best route previously found to the same tile.
        -- `scores[k]` is absent for an unseen tile. For a seen tile, accept only
        -- a strictly cheaper route; equal routes add no information and would
        -- bloat the open heap with duplicates.
        if h(job.start, p) <= job.max_radius and not blocked(surface, p) and (not job.scores[k] or g < job.scores[k]) then
            job.scores[k] = g;
            job.parents[k] = key(node.p);
            push(job.open, {
                p = p,
                g = g,
                f = g + h(p, job.goal)
            })
        end
    end
    return false
end

return M
