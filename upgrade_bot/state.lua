local state = {}
local config = require("config")
local constants = require("constants")

function state.ensure()
    -- Factorio persists `storage` across saves. Defensive initialization also
    -- supports adding this mod to an existing game and configuration changes.
    storage[constants.STORAGE_KEY] = storage[constants.STORAGE_KEY] or {players = {}}
    storage[constants.STORAGE_KEY].players = storage[constants.STORAGE_KEY].players or {}
end

function state.get(player_index)
    state.ensure()
    local value = storage[constants.STORAGE_KEY].players[player_index]
    if not value then
        -- Each player owns an independent bot and task machine so multiplayer
        -- players cannot steal one another's targets, cargo, or render objects.
        value = {enabled = false, task_name = config.default_task, entity = nil, target = nil,
                 supply = nil, phase = constants.PHASE.FOLLOW, cargo = {}, next_scan_tick = constants.NO_TICK_DELAY,
                 job_network = nil, return_destination = nil, return_item = nil,
                 source_container = nil,
                 last_player_position = nil, side_offset_x = config.follow_offset.x,
                 upgraded = constants.EMPTY_COUNT, failures = constants.EMPTY_COUNT, highlight = nil}
        storage[constants.STORAGE_KEY].players[player_index] = value
    end
    value.cargo = value.cargo or {}
    -- Backfill fields introduced by newer mod versions without invalidating an
    -- existing save's useful task and cargo state.
    value.phase = value.phase or constants.PHASE.FOLLOW
    value.side_offset_x = value.side_offset_x or config.follow_offset.x
    return value
end

function state.clear_target(value)
    -- Clear every reference associated with one transaction. Leaving a stale
    -- source or destination could make the next task move to the wrong entity.
    value.target = nil
    value.supply = nil
    value.job_network = nil
    value.source_container = nil
    value.return_destination = nil
    value.return_item = nil
    value.phase = constants.PHASE.FOLLOW
    -- Render objects are engine resources; explicitly destroying them prevents
    -- highlights surviving after their logical target has gone away.
    if value.highlight and value.highlight.valid then value.highlight.destroy() end
    value.highlight = nil
end

function state.destroy(value)
    -- Cargo intentionally remains in persistent state across toggles. Turning
    -- the helper off must not silently delete resources it was carrying.
    state.clear_target(value)
    if value.entity and value.entity.valid then value.entity.destroy() end
    value.entity = nil
    value.enabled = false
end

return state
