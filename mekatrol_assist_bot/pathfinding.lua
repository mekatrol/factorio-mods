-- Resumable tile A* for repair travel. Expansion is explicitly budgeted by the scheduler.
local M = {}
local dirs = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}

local function tile(p)
    return {
        x = math.floor(p.x),
        y = math.floor(p.y)
    }
end

local function key(p)
    return p.x .. "," .. p.y
end

local function h(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function less(a, b)
    return a.f < b.f or (a.f == b.f and key(a.p) < key(b.p))
end

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

function M.start(surface, from, to, max_radius)
    local a, b = tile(from), tile(to);
    local k = key(a)
    return {
        surface_index = surface.index,
        start = a,
        goal = b,
        max_radius = max_radius or 96,
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

local function blocked(surface, p)
    local entities = surface.find_entities_filtered {
        area = {{p.x + 0.1, p.y + 0.1}, {p.x + 0.9, p.y + 0.9}},
        type = {"wall", "gate"},
        limit = 1
    }
    return #entities > 0
end

local function pop(job)
    local heap = job.open;
    if #heap == 0 then
        return nil
    end
    local root = heap[1];
    heap[1] = heap[#heap];
    heap[#heap] = nil;
    local i = 1
    while true do
        local left = i * 2;
        if left > #heap then
            break
        end
        local right = left + 1;
        local child = right <= #heap and less(heap[right], heap[left]) and right or left;
        if not less(heap[child], heap[i]) then
            break
        end
        heap[i], heap[child] = heap[child], heap[i];
        i = child
    end
    return root
end

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
        local x, y = k:match("^([^,]+),(.+)$");
        job.path[#job.path + 1] = {
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
    if key(node.p) == key(job.goal) then
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
        local g = node.g + 1
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
