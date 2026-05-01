# Project Description

This workspace is a collection of local Factorio 2.0 helper mods stored directly
under the Factorio user mods directory.

The repository root contains several unpacked mods:

- `mekatrol_game_play_mod`: multi-bot gameplay assistant with constructor,
  logistics, mapper, repairer, and surveyor bot roles. It is the most modular
  mod in this workspace.
- `cleanup_mod`: script-driven cleanup bot that collects dropped items and
  deposits them into nearby storage.
- `entity_repair_mod`: repair bot that tracks damaged or destroyed entities and
  repairs or rebuilds them where possible.
- `mapping_bot_mod`: mapping bot that scans static entities, stores mapped
  references, renders visual markers, and emits custom mapping events.
- `tree_spawn_mod`: small toggleable helper that periodically spawns trees near
  enabled players.
- `resource_cheat_mod`: custom input helper that grants utility and production
  science packs.

The root also contains downloaded zip mods that should usually be treated as
third-party artifacts unless the user explicitly asks to inspect or replace
them.

