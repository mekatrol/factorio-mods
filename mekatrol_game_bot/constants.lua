-- Central names and scalar values shared by the data and control stages.
-- Keeping them here prevents behavior from depending on unexplained literals
-- scattered through the implementation. Task-specific prototype and item
-- names deliberately remain in tasks.lua because they are task configuration.
local constants = {
    -- Stable external identifiers must never drift independently because saves,
    -- key bindings, console commands, and prototypes refer to them by name.
    MOD_PREFIX = "Upgrade Bot",
    BOT_ENTITY_NAME = "upgrade-bot",
    BASE_ROBOT_ENTITY_NAME = "construction-robot",
    CUSTOM_INPUT_NAME = "upgrade-bot-toggle",
    CUSTOM_INPUT_KEY_SEQUENCE = "CONTROL + SHIFT + U",
    CLEANUP_BOT_ENTITY_NAME = "cleanup-bot",
    CLEANUP_CUSTOM_INPUT_NAME = "cleanup-bot-toggle",
    CLEANUP_CUSTOM_INPUT_KEY_SEQUENCE = "CONTROL + SHIFT + C",
    CLEANUP_COMMAND_NAME = "cleanup-bot",
    CLEANUP_SHORT_COMMAND_NAME = "cb",
    -- The lamp worker is a separate entity instance, but reuses the existing
    -- upgrade-bot prototype so control-stage hot reloads cannot reference a
    -- data-stage prototype that the running Factorio session has not loaded.
    LAMP_BOT_ENTITY_NAME = "upgrade-bot",
    LAMP_CUSTOM_INPUT_NAME = "lamp-bot-toggle",
    LAMP_CUSTOM_INPUT_KEY_SEQUENCE = "CONTROL + SHIFT + L",
    LAMP_COMMAND_NAME = "lamp-bot",
    LAMP_SHORT_COMMAND_NAME = "lb",
    PRIMARY_COMMAND_NAME = "upgrade-bot",
    SHORT_COMMAND_NAME = "ub",
    STORAGE_KEY = "mekatrol_game_bot",
    DEFAULT_TASK_NAME = "containers",
    -- The track helper has independent controls and persistent state because
    -- rail/belt progression must never be mixed with general factory upgrades.
    TRACK_BOT_ENTITY_NAME = "upgrade-bot",
    TRACK_CUSTOM_INPUT_NAME = "track-upgrade-bot-toggle",
    TRACK_CUSTOM_INPUT_KEY_SEQUENCE = "CONTROL + SHIFT + T",
    TRACK_COMMAND_NAME = "track-upgrade-bot",
    TRACK_SHORT_COMMAND_NAME = "tb",
    TRACK_DEFAULT_TASK_NAME = "yellow-to-red-tracks",
    -- The composite mode is registered after the concrete upgrade tasks so it
    -- can safely combine their mappings without duplicating task data.
    ALL_TASK_NAME = "all-upgrades",
    PASSIVE_PROVIDER_CHEST_NAME = "passive-provider-chest",

    -- Phase names define the persisted state-machine vocabulary.
    PHASE = {
        FOLLOW = "follow",
        FETCH = "fetch",
        UPGRADE = "upgrade",
        RETURN = "return",
        BLOCKED_RETURN = "blocked-return"
    },

    -- Command actions are centralized so parsing and help text describe the
    -- same public interface.
    ACTION = {
        ON = "on",
        START = "start",
        OFF = "off",
        STOP = "stop",
        TOGGLE = "toggle",
        TASK = "task",
        TASKS = "tasks",
        STATUS = "status",
        REFRESH = "refresh"
    },

    -- Semantic colors keep message intent readable at every call site.
    COLOR = {
        ERROR = "red",
        SUCCESS = "green",
        WARNING = "yellow",
        INFORMATION = "cyan"
    },

    -- Prototype type identifiers used by generic surface filters.
    ENTITY_TYPE = {
        CONTAINER = "container",
        LOGISTIC_CONTAINER = "logistic-container",
        UNDERGROUND_BELT = "underground-belt",
        ELECTRIC_POLE = "electric-pole",
        ENTITY_GHOST = "entity-ghost",
        LAMP = "lamp"
    },

    GROUP_STRATEGY = {
        BELT_NETWORK = "belt-network"
    },

    -- Scalar constants below capture invariants and engine-facing defaults;
    -- their names explain why a particular number participates in the logic.
    ITEM_TRANSFER_COUNT = 1,
    UNDERGROUND_PAIR_SIZE = 2,
    EMPTY_COUNT = 0,
    FIRST_INDEX = 1,
    NO_TICK_DELAY = 0,
    HORIZONTAL_DIRECTION_THRESHOLD = 0.1,
    FALLBACK_SPRITE_SIZE = 32,
    BOT_COLLISION_HALF_SIZE = 0.2,
    BOT_MAX_HEALTH = 500,
    HIGHLIGHT_LINE_WIDTH = 2,
    TRACK_HIGHLIGHT_INNER_WIDTH = 2,
    TRACK_HIGHLIGHT_OUTER_WIDTH = 6,
    BLOCKED_CONTAINER_LINE_WIDTH = 6,
    MODE_LABEL_OFFSET = {0, 1},
    MODE_LABEL_SCALE = 0.85,
    DISTANCE_SQUARED_EXPONENT = 2,
    COMMAND_DESCRIPTION = "Control the upgrade bot",
    CLEANUP_COMMAND_DESCRIPTION = "Control the cleanup bot",
    CLEANUP_COMMAND_USAGE = "[Cleanup Bot] usage: /cb [on|off|toggle|status]",
    LAMP_COMMAND_DESCRIPTION = "Control the lamp bot",
    LAMP_COMMAND_USAGE = "[Lamp Bot] usage: /lb [on|off|toggle|status]",
    TRACK_COMMAND_DESCRIPTION = "Control the progressive track upgrade bot",
    TRACK_COMMAND_USAGE = "[Track Bot] usage: /tb [on|off|toggle|status|refresh]",
    COMMAND_USAGE = "[Upgrade Bot] usage: /ub [on|off|toggle|task NAME|tasks|status|refresh] (bare /ub changes mode)",
    TASK_LIST_PREFIX = "[Upgrade Bot] tasks: ",
    EMPTY_TEXT = "",
    NONE_TEXT = "none",
    EMPTY_CARGO_TEXT = "empty",
    LIST_SEPARATOR = ",",
    LIST_DISPLAY_SEPARATOR = ", ",
    COMMAND_PATTERN = "^(%S+)%s*(.-)%s*$",
    STATUS_FORMAT = "enabled=%s task=%s phase=%s upgraded=%d failures=%d target=%s cargo=%s/%d track_remaining=%d",
    BLOCKED_CONTAINER_TAG_TEXT = "Upgrade Bot: make room"
}

return constants
