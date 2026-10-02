# Mekatrol Assist Bot

`mekatrol_assist_bot` consolidates the former repair, mapping, gameplay, and
game-bot mods for Factorio 2.0. The old mods must be disabled. Back up a save
before first enabling this mod; configuration-change migration imports their
enabled roles and mapping data once, without retaining old bot entities.

## Roles

| Role | Behaviour | Technology |
| --- | --- | --- |
| builder | Builds nearby same-force entity ghosts from player inventory. | Construction robotics |
| repair | Repairs damaged player-force entities using repair packs and resumable wall-aware A*. | Construction robotics |
| upgrade | Replaces supported belts, inserters, and chests using player inventory. | Construction robotics |
| track | Traverses and locks one connected belt component, including underground peers, then progressively upgrades it. | Construction robotics |
| lamp | Places lamps beside nearby electric poles after configured darkness. | Construction robotics + lamp |
| cliff | Destroys only cliffs marked with the planner, consuming cliff explosives. | Cliff explosives |
| logistics | Collects ground items and mines recoverable neutral entities to the player. | Logistic robotics |
| cleanup | Collects loose item entities into player inventory. | Logistic robotics |
| mapper | Progressively scans an outward deterministic cell spiral and maps static entities into the shared discovery index. | Electronics |
| surveyor | Traces resource boundaries and builds connected, polygon-backed discovery groups. | Electronics |

Supply-consuming roles prefer player inventory and then incrementally search
nearby player-owned containers. Bots fly to the selected source, remember its
provenance, and return recovered upgrade items there. Full destinations retain
cargo on the bot until space becomes available. Cleanup similarly prefers a
nearby container already holding the collected item before falling back to the
player.
Bots are independently enabled. Locked bots are not created and report every
missing technology. Research reversal recalls affected bots. All role searches,
selection rectangles, pruning, and target planning resume from persistent cell
cursors under one global per-tick budget.

## Controls

| Action | Default |
| --- | --- |
| Toggle all unlocked bots | `Ctrl+Shift+A` |
| Builder / Cleanup / Cliff | `Ctrl+Shift+B/C/D` |
| Logistics / Lamp / Mapper | `Ctrl+Shift+G/L/M` |
| Repair / Surveyor | `Ctrl+Shift+R/S` |
| Track / Upgrade | `Ctrl+Shift+T/U` |
| Clear discovery map | `Ctrl+Alt+M` |
| Take cliff planner | `Ctrl+Alt+D` |

These are normal custom inputs and can be rebound under **Settings > Controls >
Mods**. Old custom-input bindings cannot be migrated automatically.

## Commands

```text
/mab <role|all> <on|off|toggle|status>
/mab <role> task <task-name>
/mab <role> tasks
/mab <role> refresh
/mab help [role]
/mab status [role|all]
```

Short role aliases include `s` for surveyor (`v` remains accepted). `/ub`,
`/tb`, `/cb`, `/lb`, and `/db` forward to upgrade, track, cleanup, lamp, and
cliff for the 1.0 compatibility cycle. `/bot`, `/b`, and `/bot-status` are not
registered.

## Configuration reference

All policy is in `config.lua`; its inline comments are the exhaustive reference.
The top-level sections are `controls`, `scheduler`, `formation`, `movement`,
`scanning`, `supply`, `tasks`, `visuals`, `roles`, and `compatibility`.

- Tick intervals and budgets are integer counts at least 1; 60 ticks is one
  second at normal speed.
- Distances are finite positive tile values. Search radii are inclusive.
- Darkness and RGBA channels use `[0,1]`.
- Capacities are non-negative integers; a zero capacity disables that pickup.
- Technology arrays contain prototype names. `technology_mode` is `all` or
  `any`; an empty array has no gate.
- `role_order` contains each registered role once and determines stable
  formation order. `max_slots_per_column` is a positive integer.

Invalid values fail early with the full configuration path, supplied value, and
accepted range. Unknown technologies fail during initialization.

## Formation, animation, and performance

Active idle bots occupy centered, evenly spaced columns. The complete formation
mirrors when horizontal player movement crosses the configured threshold, and
bots ease back into their stable slots after work. Construction roles clone the
full vanilla construction-robot graphics; logistics and cleanup clone the full
logistic-robot graphics. Separate idle, moving, and working prototypes preserve
directional animation and shadows while scripted lifecycle code switches visual
state.

The scheduler shares `scheduler.work_per_tick` across every player and role.
Large radii are split into `scanning.cell_size` squares, one engine query per
work unit. Increasing budgets improves task latency at the cost of simulation
time; increasing cell size reduces cursor overhead but makes an individual
query more expensive.

## Compatibility and state

The only persistent root is `storage.mekatrol_assist_bot` (schema 4). It contains
per-player role state, resumable jobs, discoveries, groups, and marked cliffs.
Rendering objects are not persisted. On first configuration migration the mod
imports recognizable state from `mekatrol_game_bot`,
`mekatrol_game_play_bot`, `mapping_bot_mod`, and `mekatrol_repair_mod` if those
tables are present. It never creates duplicate legacy entities.

The remote interface `mapping_bot_mod` is retained for one compatibility cycle:

```lua
remote.call("mapping_bot_mod", "get_mapped_entities")
remote.call("mapping_bot_mod", "get_mapped_entities_page", cursor, limit)
remote.call("mapping_bot_mod", "get_mapped_entities_by_name_page", name, cursor, limit)
remote.call("mapping_bot_mod", "clear_mapped_entities")
remote.call("mapping_bot_mod", "get_entity_mapped_event")
remote.call("mapping_bot_mod", "get_map_cleared_event")
```

Snapshots contain up to `compatibility.snapshot_limit` copied metadata records
and positions, not mutable internal tables or entity references. Mapping and
clear events retain the legacy accessors; clearing swaps the live index
immediately and releases old records and renderings incrementally. Save/load,
configuration changes, invalid entities, player
removal, and research reversal are handled at their lifecycle boundaries.

## Maintainer checks

`tests.lua` checks configuration, command parsing, formation symmetry,
mirroring, slot uniqueness and reflow, entity identity/deduplication, polygons,
aliases, task registration, and technology gates during initialization. Setting
`debug=true` runs the destructive headless fixture in a disposable save: it
validates required Factorio 2.0 prototypes and role families, profiles ten role
bots, and scans a 4,096-resource field. Never turn this on in a real save. Phase
1 baselines are in `PHASE1_BASELINE.md`; Phase 2 architecture evidence is in
`PHASE2_ARCHITECTURE.md`; Phase 3 visual and formation evidence is in
`PHASE3_VISUALS_FORMATION.md`; Phase 4 mapping evidence is in
`PHASE4_MAPPING_DISCOVERY.md`. Normal configuration keeps `debug=false`.
