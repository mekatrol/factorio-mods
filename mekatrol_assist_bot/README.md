# Mekatrol Assist Bot

`mekatrol_assist_bot` provides ten coordinated helper roles for Factorio 2.0.

## Roles

| Role | Tasks | Behaviour | Technology |
| --- | --- | --- | --- |
| builder | `follow`, `move_to`, `construct` | Builds nearby same-force ghosts using the prototype-defined placement item. | Construction robotics |
| repair | `follow`, `move_to`, `repair` | Flies directly to damaged player-force entities and repairs them using repair packs. | Repair pack |
| upgrade | `follow`, `yellow-to-red-belts`, `red-to-blue-belts`, `blue-to-green-inserters`, `containers`, `combined` | Replaces the configured belts, inserters, and chests. | Construction robotics plus an available target recipe |
| track | `follow`, `track` | Locks and traverses one connected belt component, including underground peers, then progressively upgrades it. | Construction robotics; later stages wait for their recipes |
| lamp | `follow`, `place` | Places lamps beside nearby electric poles after configured darkness. | Construction robotics + lamp |
| cliff | `follow`, `demolish` | Destroys only cliffs marked with the planner, consuming cliff explosives. | Cliff explosives |
| logistics | `follow`, `collect`, `pickup` | Collects ground items, drains inventories in bounded batches, and incrementally mines recoverable neutral entities/resources. | Logistic robotics |
| cleanup | `follow`, `cleanup` | Collects loose item entities and prefers a nearby container already holding that item. | None |
| mapper | `follow`, `search` | Progressively scans an outward deterministic cell spiral and maps static entities into the shared discovery index. | Electronics |
| surveyor | `follow`, `search`, `survey` | Traces resource boundaries and builds connected, polygon-backed discovery groups. | Electronics |

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

Mapper discoveries are published into independent persistent repair, logistics,
and surveyor queues declared by the role registry. Each consumer advances only when the shared scheduler grants
it a work unit, then falls back to a bounded local scan after its queue ends.

Repair work is split into `tasks.repair.health_per_action` health-point steps.
Each consumed repair pack contributes exactly
`supply.repair_pack_durability` points to a persistent pool, including the
remainder after a target is healed. The bot self-repairs below
`tasks.repair.self_repair_threshold`, consumes shared discoveries progressively,
and flies directly over obstacles to targets within
`tasks.repair.interaction_distance`. Destroyed entity sites remain highlighted until
an entity is rebuilt at that site.

## Controls

| Action | Default |
| --- | --- |
| Toggle all unlocked bots | `Ctrl+Shift+A` |
| Builder | `Ctrl+Shift+B` |
| Cleanup | `Ctrl+Shift+C` |
| Cliff | `Ctrl+Shift+D` |
| Logistics | `Ctrl+Shift+G` |
| Lamp | `Ctrl+Shift+L` |
| Mapper | `Ctrl+Shift+M` |
| Repair | `Ctrl+Shift+R` |
| Surveyor | `Ctrl+Shift+S` |
| Track | `Ctrl+Shift+T` |
| Upgrade | `Ctrl+Shift+U` |
| Clear discovery map | `Ctrl+Alt+M` |
| Take cliff planner | `Ctrl+Alt+D` |

These are normal custom inputs and can be rebound under **Settings > Controls >
Mods**. Old custom-input bindings cannot be migrated automatically.

## Commands

```text
/mab <role|all> <on|off|toggle|status>
/mab <role> task <task-name> [key=value ...]
/mab <role> tasks
/mab <role> refresh
/mab help [role]
/mab status [role|all]
```

`move_to` requires `x=<number> y=<number>`. `/mab logistics task pickup
name=<prototype> count=<positive integer>` requests a bounded quantity;
`collect` clears that request and resumes general collection. Builder
`construct` revives same-force entity ghosts only after shared supply provides
the item reported by the ghost prototype. `/mab mapper clear` clears discovery;
`/mab cliff mark` takes the planner and `/mab cliff clear` removes all marks.
`refresh` discards the role's current target and resumable planning cursors so
its configured task starts a fresh search.

Role aliases are `b` builder, `r` repair, `u` upgrade, `t` track, `l` lamp,
`d` cliff, `g` logistics, `c` cleanup, `m` mapper, and `s` surveyor.

## Configuration reference

All policy is in `config.lua`; its inline comments are the source-level
reference. Defaults and accepted values are summarized below. Distances and
radii are in tiles and radius comparisons are inclusive. Counts are integers;
60 ticks equal one second at normal game speed. The top-level sections are
`controls`, `scheduler`, `formation`, `movement`, `scanning`, `supply`, `tasks`,
`visuals`, `roles`, plus `schema_version` and `debug`.

| Setting | Default | Purpose and accepted value |
| --- | ---: | --- |
| `schema_version` | `7` | Positive persistent-state schema integer. |
| `controls.<action>` | See Controls | Non-empty Factorio key sequence for every role, `all`, `clear_map`, and `cliff_planner`. |
| `scheduler.work_per_tick` | `24` | Global work units per tick; integer >= 1. |
| `scheduler.background_work_per_tick` | `4` | Maximum units used by clearing, selection, and visual rebuilds per tick; integer >= 1. |
| `scheduler.idle_interval` | `1` | Ticks between formation-follow passes; integer >= 1. Keep at `1` for smooth pursuit. |
| `scheduler.role_intervals.<role>` | `1`, except lamp `6`, mapper/surveyor `2` | Ticks between eligible role work units; integer >= 1. |
| `formation.role_order` | Ten roles above | Every registered role exactly once; fixes deterministic slot and scheduler order. |
| `formation.slot_spacing` | `3.5` | Minimum straight-line separation between adjacent bots; finite > 0. |
| `formation.radius` | `6` | Minimum distance of the rear arc from the player; finite > 0. Crowded formations expand this automatically. |
| `formation.arc_degrees` | `140` | Width of the circular arc behind movement; finite > 0 and < 180. |
| `formation.direction_threshold` | `0.1` | Player movement needed to place the formation behind their cardinal heading; finite > 0. |
| `movement.step` | `0.18` | Maximum movement per bot per game tick across all role work; finite > 0. |
| `movement.arrival_distance` | `0.01` | Arrival dead band; finite > 0. |
| `scanning.cell_size` | `16` | Width and height of one bounded query cell; finite > 0. |
| `scanning.prune_interval` | `30` | Ticks between stale-discovery pruning passes; integer >= 1. |
| `scanning.prune_per_step` | `16` | Records checked per pruning pass; integer >= 1. |
| `scanning.entities_per_cell` | `512` | Maximum returned entities handled from one cell; integer >= 1. |
| `supply.radius` | `48` | Player/container source-search radius; finite > 0. |
| `supply.source_priority` | `player`, then `containers` | Ordered unique list containing either or both supported policies. |
| `supply.cleanup_capacity` | `100` | Cleanup cargo capacity; integer >= 0, where zero disables pickup. |
| `supply.repair_pack_durability` | `300` | Health points contributed by one repair pack; finite > 0. |
| `tasks.<role>.radius` | upgrade/track/cliff/logistics/repair `64`; builder/cleanup/lamp `48`; surveyor `128` | Role search radius; finite > 0. |
| `tasks.upgrade.mode_radii.<mode>` | Inserters `10` | Optional per-mode radius override; finite > 0. |
| `tasks.upgrade.mappings` | Vanilla belt/inserter/chest progression | Source-to-target prototype map; unavailable optional targets are skipped. |
| `tasks.cliff.projectile_speed` | `0.3` | Scripted projectile speed; finite > 0. |
| `tasks.logistics.inventory_slots_per_action` | `1` | Inventory slots transferred in one work unit; integer >= 1. |
| `tasks.logistics.resource_units_per_action` | `1` | Resource units mined in one work unit; integer >= 1. |
| `tasks.surveyor.boundary_max_steps` | `4096` | Maximum points in a resumable boundary trace; integer >= 1. |
| `tasks.lamp.darkness` | `0.35` | Minimum surface darkness for placement, in `[0,1]`. |
| `tasks.lamp.items_per_trip` | `100` | Lamp carrying capacity; each pickup is reduced to current valid-site demand. |
| `tasks.repair.threshold` | `0.999` | Other-entity health ratio below which repair is eligible, in `[0,1]`. |
| `tasks.repair.self_repair_threshold` | `0.9` | Bot health ratio below which self-repair takes priority, in `[0,1]`. |
| `tasks.repair.health_per_action` | `25` | Maximum health restored in one work unit; finite > 0. |
| `tasks.repair.interaction_distance` | `1.5` | Distance at which repair can begin; finite > 0. |
| `tasks.repair.ignored_names` | Empty | Exact entity prototype names excluded from repair. |
| `visuals.colors.<use>.<channel>` | See `config.lua` | Target, map, cliff, and destroyed-site RGBA channels, each in `[0,1]`. |
| `visuals.lifetime_ticks` | `3600` | Lifetime for temporary render objects; integer >= 1. |
| `roles.<role>.prototype_family` | Per role | `construction` or `logistic`; selects the cloned vanilla graphic family. |
| `roles.<role>.required_technologies` | Per role | Technology prototype-name array; empty means no gate. |
| `roles.<role>.technology_mode` | `all` | `all` or `any` requirement semantics. |
| `roles.<role>.default_task` | Per role | Registered task assigned to new role state. |
| `debug` | `false` | Runs destructive integration fixtures when true; use only in a disposable save. |

The default upgrade mappings are yellow to red, red to blue, and blue to turbo
belts/underground belts/splitters; burner to standard to fast to bulk inserters;
and wooden to iron to steel chests. The `blue-to-green-inserters` task name
selects the configured fast-to-bulk inserter step. A mapping is used
only when its target entity/item exists and its recipe is available.

Invalid values fail early with the full configuration path, supplied value, and
accepted range. Unknown technologies fail during initialization.

## Formation, animation, and performance

Active idle bots occupy a centered, evenly spaced circular arc behind the
player's current movement direction. The arc expands to preserve bot and label
clearance. The complete formation
mirrors when horizontal player movement crosses the configured threshold, and
bots ease back into their stable slots after work. Construction roles clone the
full vanilla construction-robot graphics; logistics and cleanup clone the full
logistic-robot graphics. Factorio 2.0.77 has no dedicated logistic-robot working
animation, so its working variant reuses the complete in-motion animation.
Separate idle, moving, and working prototypes preserve directional animation
and shadows while scripted lifecycle code switches visual state without moving
logical role state. Autonomous logistic payload, work-radius, and energy
behaviour is neutralized on these scripted clones.

The scheduler shares `scheduler.work_per_tick` across every player and role.
Large radii are split into `scanning.cell_size` squares, one engine query per
work unit. Increasing budgets improves task latency at the cost of simulation
time; increasing cell size reduces cursor overhead but makes an individual
query more expensive.

## State

The only persistent root is `storage.mekatrol_assist_bot` (schema 7). It contains
per-player role state, resumable jobs, discoveries, groups, and marked cliffs.
Rendering objects are not persisted. Save/load, configuration changes, invalid
entities, player removal, and research reversal are handled at their lifecycle
boundaries.

## Release verification

The mod can be verified with an isolated new-game load and the opt-in runtime fixture. The fixture is implemented in
`runtime_tests.lua`; it does not require a checked-in test directory. Set
`debug=true` only in a copied mod inside a disposable Factorio write-data and
create a new save. The fixture validates role technology and visual prototypes,
then runs the 10-bot and 4,096-resource bounded-work baselines. A successful run
logs `[MAB test] headless baseline passed`. Restore
`debug=false` afterward. Details are recorded in `PHASE7_CONSOLIDATION.md`.

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
`PHASE4_MAPPING_DISCOVERY.md`; Phase 5 repair evidence is in
`PHASE5_REPAIR.md`; Phase 6 builder/logistics evidence is in
`PHASE6_GAMEPLAY_BUILDER_LOGISTICS.md`; Phase 7 consolidation evidence is in
`PHASE7_CONSOLIDATION.md`. Normal configuration keeps `debug=false`.
