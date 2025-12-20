local state = {}

local config = require("configuration")
local utils = require("utils")
local visuals = require("visuals")

local BOT = config.bot

----------------------------------------------------------------------
-- Storage and player state
----------------------------------------------------------------------

function state.ensure_storage_tables()
    storage.game_bot = storage.game_bot or {}
end

function state.get_player_state(player_index)
    state.ensure_storage_tables()

    local all = storage.game_bot
    local ps = all[player_index]

    if not ps then
        ps = {
            bot_entity = nil,
            bot_enabled = false,

            bot_mode = "follow",
            last_player_position = nil,
            last_player_side_offset_x = -BOT.movement.side_offset_distance,

            bot_target_position = nil,

            ------------------------------------------------------------------
            -- Survey data:
            --
            -- survey_mapped_entities:
            --   Map of stable entity_key -> info snapshot (position, name, etc).
            --
            -- survey_mapped_positions:
            --   Set of quantized "x,y" keys. This is "coverage"; it prevents
            --   repeatedly re-adding frontier nodes for already-surveyed places.
            --
            -- survey_frontier:
            --   Queue/list of frontier nodes (positions the bot should visit).
            --
            -- survey_done:
            --   List of already-visited frontier nodes (for visuals/debug).
            --
            -- survey_seen:
            --   Set of quantized "x,y" keys so we don't enqueue the same node
            --   multiple times.
            ------------------------------------------------------------------
            survey_render_mapped = true,
            survey_render_points = true,

            survey_mapped_entities = {},
            survey_mapped_positions = {},
            survey_frontier = {},
            survey_done = {},
            survey_seen = {},

            ------------------------------------------------------------------
            -- Hull data:
            --
            -- hull:
            --   The last completed hull polygon, if any.
            --
            -- hull_job:
            --   The current incremental job state (serializable table). When
            --   present, we advance it a limited amount each tick.
            --
            -- hull_quantized_count / hull_quantized_hash:
            --   A cheap fingerprint of the point set used for the *last
            --   completed hull*. If the mapped point set changes, these will
            --   no longer match and we schedule a new job.
            --
            -- hull_tick:
            --   When hull was last completed (used to avoid rebuilding too often).
            --
            -- hull_last_eval_tick:
            --   When we last computed (points,count,hash) from mapped entities.
            --   This allows us to avoid recomputing mapped points/hash every tick.
            ------------------------------------------------------------------
            hull = nil,
            hull_job = nil,
            hull_quantized_count = 0,
            hull_quantized_hash = 0,
            hull_tick = 0,
            hull_last_eval_tick = 0,
            hull_point_set = {}, -- set: "x,y" => true for quantized hull input points we've already seen

            visuals = {
                bot_highlight = nil,
                lines = nil,
                radius_circle = nil,
                mapped_entities = {},
                survey_frontier = {},
                survey_done = {}
            }
        }

        all[player_index] = ps
    else
        -- Defensive initialization for upgrades / older saves.
        ps.survey_render_mapped = ps.survey_render_mapped or false
        ps.survey_render_points = ps.survey_render_points or false
        ps.survey_frontier = ps.survey_frontier or {}
        ps.survey_done = ps.survey_done or {}
        ps.survey_seen = ps.survey_seen or {}
        ps.survey_mapped_entities = ps.survey_mapped_entities or {}
        ps.survey_mapped_positions = ps.survey_mapped_positions or {}

        ps.hull = ps.hull or nil
        ps.hull_job = ps.hull_job or nil
        ps.hull_quantized_count = ps.hull_quantized_count or 0
        ps.hull_quantized_hash = ps.hull_quantized_hash or 0
        ps.hull_tick = ps.hull_tick or 0
        ps.hull_last_eval_tick = ps.hull_last_eval_tick or 0
        ps.hull_point_set = ps.hull_point_set or {}

        ps.visuals = ps.visuals or {}
        ps.visuals.lines = ps.visuals.lines or nil
        ps.visuals.bot_highlight = ps.visuals.bot_highlight or nil
        ps.visuals.radius_circle = ps.visuals.radius_circle or nil
        ps.visuals.mapped_entities = ps.visuals.mapped_entities or {}
        ps.visuals.survey_frontier = ps.visuals.survey_frontier or {}
        ps.visuals.survey_done = ps.visuals.survey_done or {}
    end

    return ps
end

----------------------------------------------------------------------
-- Bot lifecycle
----------------------------------------------------------------------

function state.destroy_player_bot(player, silent)
    local ps = state.get_player_state(player.index)

    -- Destroy the bot entity (if present).
    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_entity.destroy()
    end

    -- Clear ALL render objects / visuals.
    visuals.clear_all(ps)

    -- Disable + clear entity reference.
    ps.bot_entity = nil
    ps.bot_enabled = false

    ------------------------------------------------------------------
    -- Reset behavior state back to "follow".
    ------------------------------------------------------------------
    ps.bot_mode = "follow"
    ps.bot_target_position = nil

    -- Movement bookkeeping.
    ps.last_player_position = nil
    ps.last_player_side_offset_x = -BOT.movement.side_offset_distance

    ------------------------------------------------------------------
    -- Clear ALL survey / mapping point sets.
    ------------------------------------------------------------------
    ps.survey_render_mapped = true
    ps.survey_render_points = true
    ps.survey_mapped_entities = {}
    ps.survey_mapped_positions = {}
    ps.survey_frontier = {}
    ps.survey_done = {}
    ps.survey_seen = {}

    ------------------------------------------------------------------
    -- Clear ALL hull state (including incremental job + fingerprints).
    ------------------------------------------------------------------
    ps.hull = nil
    ps.hull_job = nil
    ps.hull_point_set = {}
    ps.hull_quantized_count = 0
    ps.hull_quantized_hash = 0
    ps.hull_tick = 0
    ps.hull_last_eval_tick = 0

    ------------------------------------------------------------------
    -- Clear any stored visual ids (so visuals code doesn't try to reuse them).
    -- visuals.clear_all(ps) should already destroy render ids; this just resets
    -- your bookkeeping tables to empty.
    ------------------------------------------------------------------
    ps.visuals = {
        bot_highlight = nil,
        lines = nil,
        radius_circle = nil,
        mapped_entities = {},
        survey_frontier = {},
        survey_done = {}
    }

    if not silent then
        utils.print_bot_message(player, "yellow", "deactivated")
    end
end

function state.create_player_bot(player)
    local ps = state.get_player_state(player.index)

    if ps.bot_entity and ps.bot_entity.valid then
        ps.bot_enabled = true
        return ps.bot_entity
    end

    local pos = player.position
    local ent = player.surface.create_entity {
        name = "mekatrol-game-play-bot",
        position = {pos.x - 2, pos.y - 2},
        force = player.force,
        raise_built = true
    }

    if not ent then
        utils.print_bot_message(player, "red", "create failed")
        return nil
    end

    ps.bot_entity = ent
    ps.bot_enabled = true
    ent.destructible = true

    utils.print_bot_message(player, "green", "created")
    return ent
end

return state
