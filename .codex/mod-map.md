# Mod Map

## `mekatrol_game_play_mod`

- Entry points: `data.lua`, `control.lua`.
- Metadata: `info.json` declares Factorio `2.0`, version `1.0.0`.
- Runtime state: `state.lua` owns `storage.mekatrol_game_play_bot`.
- Configuration: `config.lua` defines bot tuning and bot role names.
- Main command surface: `/bot` and `/b`.
- Main hotkey: `mekatrol-game-play-bot-toggle`.
- Bot modules: `constructor_bot.lua`, `logistics_bot.lua`, `mapper_bot.lua`,
  `repairer_bot.lua`, `surveyor_bot.lua`.
- Shared helpers include `common_bot.lua`, `move_to.lua`, `search.lua`,
  `inventory.lua`, `entity_group.lua`, `entity_index.lua`, `visual.lua`, and
  geometry helpers.

## `cleanup_mod`

- Entry points: `data.lua`, `control.lua`.
- Hotkey: `mekatrol-toggle-cleanup-bot`.
- Runtime storage key: `mekatrol_cleanup_mod`.
- Prototype: `mekatrol-cleanup-bot`.
- Behavior: collect ground item entities, carry limited inventory, and deposit
  into suitable containers near the player.

## `entity_repair_mod`

- Entry points: `data.lua`, `control.lua`.
- Hotkey: `mekatrol-toggle-repair-bot`.
- Runtime storage key: `mekatrol_repair_mod`.
- Prototype: `mekatrol-repair-bot`.
- Supporting modules: `pathfinding.lua`, `visual.lua`.
- Behavior: track damaged/destroyed entities, consume repair pack durability,
  and rebuild where supported.

## `mapping_bot_mod`

- Entry points: `data.lua`, `control.lua`.
- Hotkeys: `mekatrol-mapping-bot-toggle`, `mekatrol-mapping-bot-clear`.
- Runtime storage key: `mapping_bot_mod`.
- Prototype: `mekatrol-mapping-bot`.
- Custom events: generated mapping and clear events intended for other mods.

## `tree_spawn_mod`

- Entry points: `data.lua`, `control.lua`.
- Hotkey: `augment-toggle-tree`.
- Runtime storage key: `tree_spawn_mod`.
- Behavior: toggles periodic tree creation near each enabled connected player.

## `resource_cheat_mod`

- Entry points: `data.lua`, `control.lua`.
- Hotkey: `give-yellow-science`.
- Behavior: inserts 100 utility science packs and 100 production science packs
  into the triggering player's inventory.

