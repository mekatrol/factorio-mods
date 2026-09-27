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
    PRIMARY_COMMAND_NAME = "upgrade-bot",
    SHORT_COMMAND_NAME = "ub",
    STORAGE_KEY = "mekatrol_game_bot",
    DEFAULT_TASK_NAME = "yellow-to-red-belts",
    LAMP_MODE_KIND = "place-lamps",

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
