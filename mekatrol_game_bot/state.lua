local state = {}
local config = require("config")
local constants = require("constants")

function state.ensure()
    -- Factorio persists `storage` across saves. Defensive initialization also
    -- supports adding this mod to an existing game and configuration changes.
    storage[constants.STORAGE_KEY] = storage[constants.STORAGE_KEY] or {players = {}}
    storage[constants.STORAGE_KEY].players = storage[constants.STORAGE_KEY].players or {}
    storage[constants.STORAGE_KEY].cleanup_players = storage[constants.STORAGE_KEY].cleanup_players or {}
    storage[constants.STORAGE_KEY].lamp_players = storage[constants.STORAGE_KEY].lamp_players or {}
    storage[constants.STORAGE_KEY].track_players = storage[constants.STORAGE_KEY].track_players or {}
end

function state.get_track(player_index)
    state.ensure()
    local players = storage[constants.STORAGE_KEY].track_players
    local value = players[player_index]
    if not value then
        -- This mirrors the mature upgrade engine's state, but is deliberately
        -- isolated so both helpers can work concurrently without sharing cargo.
        value = {enabled = false, task_name = config.track.default_task, entity = nil, target = nil,
                 supply = nil, phase = constants.PHASE.FOLLOW, cargo = {}, next_scan_tick = 0,
                 job_network = nil, return_destination = nil, return_item = nil, source_container = nil,
                 track = nil, track_highlights = {}, target_scan = nil, paired_underground_target = nil,
                 track_refresh_requested = false, pickup_queue = {}, delivery_queue = {},
                 blocked_destination = nil, blocked_tag = nil, blocked_highlight = nil, cargo_origins = {},
                 last_player_position = nil, side_offset_x = config.track.follow_offset.x,
                 upgraded = 0, failures = 0, highlight = nil, mode_label = nil}
        players[player_index] = value
    end
    value.cargo = value.cargo or {}
    value.track_highlights = value.track_highlights or {}
    value.pickup_queue = value.pickup_queue or {}
    value.delivery_queue = value.delivery_queue or {}
    value.cargo_origins = value.cargo_origins or {}
    value.side_offset_x = value.side_offset_x or config.track.follow_offset.x
    return value
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
                 track = nil, track_highlights = {},
                 target_scan = nil,
                 paired_underground_target = nil,
                 track_refresh_requested = false,
                 pickup_queue = {}, delivery_queue = {},
                 blocked_destination = nil, blocked_tag = nil, blocked_highlight = nil,
                 cargo_origins = {},
                 last_player_position = nil, side_offset_x = config.follow_offset.x,
                 upgraded = constants.EMPTY_COUNT, failures = constants.EMPTY_COUNT, highlight = nil,
                 mode_label = nil}
        storage[constants.STORAGE_KEY].players[player_index] = value
    end
    value.cargo = value.cargo or {}
    -- Backfill fields introduced by newer mod versions without invalidating an
    -- existing save's useful task and cargo state.
    value.phase = value.phase or constants.PHASE.FOLLOW
    value.side_offset_x = value.side_offset_x or config.follow_offset.x
    value.track_highlights = value.track_highlights or {}
    value.pickup_queue = value.pickup_queue or {}
    value.delivery_queue = value.delivery_queue or {}
    value.cargo_origins = value.cargo_origins or {}
    -- Saves that had the old lamp mode selected now activate the independent
    -- lamp helper and return the upgrade helper to its normal default task.
    if value.task_name == "place-lamps" then
        value.task_name = config.default_task
        state.get_lamp(player_index).enabled = true
    end
    -- Belt modes from pre-1.8 saves migrate to the new independent helper.
    if value.task_name == "yellow-to-red-belts" or value.task_name == "red-to-blue-belts" then
        local track_value = state.get_track(player_index)
        track_value.task_name = value.task_name == "red-to-blue-belts" and
                                    "red-to-blue-tracks" or constants.TRACK_DEFAULT_TASK_NAME
        -- Entity creation belongs to the controller, so migration records the
        -- stage but leaves activation to the player's new track-bot toggle.
        track_value.enabled = false
        value.task_name = config.default_task
    end
    return value
end

function state.get_lamp(player_index)
    state.ensure()
    local players = storage[constants.STORAGE_KEY].lamp_players
    local value = players[player_index]
    if not value then
        value = {enabled = false, entity = nil, mode = "follow", target = nil,
                 supply = nil, next_scan_tick = constants.NO_TICK_DELAY,
                 last_player_position = nil, side_offset_x = config.lamp.follow_offset.x,
                 status_label = nil}
        players[player_index] = value
    end
    value.mode = value.mode or "follow"
    value.side_offset_x = value.side_offset_x or config.lamp.follow_offset.x
    value.next_scan_tick = value.next_scan_tick or constants.NO_TICK_DELAY
    return value
end

function state.destroy_lamp(value)
    if value.status_label and value.status_label.valid then value.status_label.destroy() end
    value.status_label = nil
    if value.entity and value.entity.valid then value.entity.destroy() end
    value.entity = nil
    value.enabled = false
end

function state.get_cleanup(player_index)
    state.ensure()
    local players = storage[constants.STORAGE_KEY].cleanup_players
    local value = players[player_index]
    if not value then
        value = {enabled = false, entity = nil, mode = "follow", target = nil, cargo = {},
                 unplaceable = {}, last_player_position = nil,
                 side_offset_x = config.cleanup.follow_offset.x, status_label = nil,
                 target_line = nil, chest_highlight = nil}
        players[player_index] = value
    end
    value.cargo = value.cargo or {}
    value.unplaceable = value.unplaceable or {}
    value.mode = value.mode or "follow"
    value.side_offset_x = value.side_offset_x or config.cleanup.follow_offset.x
    return value
end

function state.destroy_cleanup(value)
    for _, field in ipairs({"status_label", "target_line", "chest_highlight"}) do
        local object = value[field]
        if object and object.valid then object.destroy() end
        value[field] = nil
    end
    if value.entity and value.entity.valid then value.entity.destroy() end
    value.entity = nil
    value.enabled = false
end

function state.clear_track(value)
    -- Track render objects outlive invalidated belt entities unless explicitly
    -- destroyed. Clearing both visual and logical state makes task switching
    -- atomic from the player's perspective.
    for _, object in pairs(value.track_highlights or {}) do
        if object and object.valid then object.destroy() end
    end
    value.track_highlights = {}
    value.track = nil
    value.target_scan = nil
    value.paired_underground_target = nil
    value.track_refresh_requested = false
end

function state.clear_blocked_destination(value)
    -- Map tags and rendering objects are independent engine resources. Destroy
    -- both when the blockage clears so warning markers cannot become stale.
    if value.blocked_tag and value.blocked_tag.valid then value.blocked_tag.destroy() end
    if value.blocked_highlight and value.blocked_highlight.valid then value.blocked_highlight.destroy() end
    value.blocked_tag = nil
    value.blocked_highlight = nil
    value.blocked_destination = nil
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
    state.clear_track(value)
    state.clear_blocked_destination(value)
    if value.mode_label and value.mode_label.valid then value.mode_label.destroy() end
    value.mode_label = nil
    if value.entity and value.entity.valid then value.entity.destroy() end
    value.entity = nil
    value.enabled = false
end

return state
