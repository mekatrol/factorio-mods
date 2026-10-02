# Mekatrol Game Bot Consolidation Plan

## Goal and scope

Create a new mod named `mekatrol_assist_bot` and merge the useful behavior of
`entity_repair_mod`, `mapping_bot_mod`, `mekatrol_game_play_mod`, and
`mekatrol_game_bot` into it. `mekatrol_assist_bot` is the new codebase and merge
target—not a rename performed inside any legacy directory. It starts at version
`0.1.0`; pre-1.0 minor versions may mark completed migration milestones. The
resulting mod will be the only runtime mod required for these helpers. It will
retain the useful behavior of all four codebases while
using one lifecycle, one state model, one command system, one formation system,
and one documented `config.lua`.

`config.lue` in the request is treated as `config.lua`, the filename Factorio
and the existing mods already use.

The merge should not begin by copying all source files into the target. Several
modules implement the same concepts in incompatible ways, and two advertised
gameplay tasks are not implemented. The work should first establish shared
services in the target and then port each bot onto those services.

## Current mod inventory

### `mekatrol_game_bot` (legacy source)

This is the newest and best-separated codebase. It has per-player persistent
state, shared movement and player-anchor modules, task registries, incremental
area scans, supply discovery, target lines, connected-belt tracking, and
specialized controllers.

Current bots and functions:

| Bot | Current function | Current controls |
| --- | --- | --- |
| Upgrade | Upgrades selected entity families. Built-in modes cover yellow-to-red and red-to-blue belts, blue-to-green inserters, wooden/iron chests, and a combined mode. It fetches materials from logistic networks or nearby/player containers, carries recovered items back, locks connected belt groups, and reports blocked returns. | `Ctrl+Shift+U`; `/upgrade-bot`, `/ub`; bare `/ub` cycles modes; actions `on`, `off`, `toggle`, `task`, `tasks`, `status`, `refresh`. |
| Track upgrade | Progressively upgrades connected belts, underground belts, and splitters in yellow -> red -> blue -> optional green order. It waits for the appropriate recipe/technology and completes one connected component at a time. | `Ctrl+Shift+T`; `/track-upgrade-bot`, `/tb`; actions `on`, `off`, `status`, `refresh`. |
| Cleanup | Collects item entities from the ground into scripted cargo, prefers a nearby container already containing that item, and falls back to player inventory. | `Ctrl+Shift+C`; `/cleanup-bot`, `/cb`; actions `on`, `off`, `toggle`, `status`. |
| Lamp | During non-full-daylight periods, obtains lamps from player inventory or a passive-provider chest and places one at a time in powered, buildable, unlit locations. | `Ctrl+Shift+L`; `/lamp-bot`, `/lb`; actions `on`, `off`, `toggle`, `status`. |
| Cliff | Lets the player mark/unmark cliffs, flies to marked cliffs, and launches the normal cliff-explosives projectile. | `Ctrl+Shift+D` toggle; `Ctrl+Alt+D` planner; shortcut-bar planner; `/cliff-bot`, `/db`; actions `on`, `off`, `toggle`, `mark`, `clear`, `status`. |

Current visual entities use static `picture` fields copied from vanilla robot
idle sprites. Upgrade, track, lamp, and cliff use a construction-robot image;
cleanup uses a logistic-robot image. They do not currently reproduce the full
vanilla idle/in-motion/working animation states.

### `mekatrol_game_play_mod`

This mod creates a five-bot group and supplies the richer general-purpose
discovery framework: common bot lifecycle and rendering, smooth teleport-step
movement, direction-aware formation following, spiral searches, discovered
entity indexing, entity groups, polygon geometry, resource-boundary surveying,
inventory/mining helpers, and a master controller that passes discoveries to
other bots.

| Bot | Current function | Current controls |
| --- | --- | --- |
| Constructor | Follows or moves to a requested position. `construct` is accepted as a task name but has no implementation in its update loop. | Group toggle `Ctrl+Shift+G`; `/bot constructor <task>` or `/b c <task>`; tasks `follow`, `construct`, `move_to`. |
| Logistics | Collects/picks up queued entities or groups, including crash-site discoveries, and transfers/mines recoverable contents to the player. | Group toggle; `/bot logistics <task>` or `/b l <task>`; tasks `follow`, `collect`, `pickup`, `move_to`. |
| Mapper | Runs an outward spiral search for configured entities such as crash-site entities, resources, trees, oil, and rocks, storing results in the shared discovered-entity index. | Group toggle; `/bot mapper <task>` or `/b m <task>`; tasks `follow`, `search`, `move_to`. |
| Repairer | Follows or moves to a requested position. `repair` is accepted as a task name but has no repair implementation in its update loop. | Group toggle; `/bot repairer <task>` or `/b r <task>`; tasks `follow`, `repair`, `move_to`. |
| Surveyor | Searches for discovered targets, traces resource boundaries with a Moore-neighbour walk, creates/merges polygon entity groups, and publishes groups for other bots. | Group toggle; `/bot surveyor <task>` or `/b v <task>`; tasks `follow`, `search`, `survey`, `move_to`. The usage text incorrectly advertises `s` even though code maps `v`. |

The group also provides `/bot-status` and `/bs`, plus stuck-task diagnostics.
All five roles currently share one static construction-robot picture and are
created/destroyed as one group.

### `mapping_bot_mod`

This standalone mapping bot follows the player, scans a radius at a throttled
interval, filters out mobile/non-static entity types, records mapped entities,
draws mapping visuals, and owns a shared map. It exposes generated “entity
mapped” and “map cleared” events plus a remote snapshot API for other mods.

Controls are `Ctrl+Shift+M` to toggle and `Ctrl+Shift+N` to clear. It has no
console command. Its entity prototype is cloned from the vanilla construction
robot and uses the vanilla working animation for idle and movement.

The merged mapper should retain the gameplay mapper's search/index/group
pipeline and the standalone mod's clear operation and compatibility API.

### `entity_repair_mod`

This is the functional repair implementation. It finds damaged player-force
entities, builds a nearest-target route, moves with wall-aware A* pathfinding,
repairs itself and nearby entities, tracks destroyed entity sites, and renders
health, target, path, damage, chest, and destroyed-site visuals. Repair packs
become a pooled repair-health budget; the bot prefers packs from a cached
nearby chest and falls back to player inventory. It can consume mapping-bot
events to learn about mapped entities.

Its only control is `Ctrl+Shift+W`; it has no console command. Configuration is
currently embedded at the top of `control.lua`, including scan intervals,
radii, speed, follow distance, repair-pack economics, health overrides, and
ignored entity names.

## Common code and consolidation decisions

| Concern | Duplicated/current implementations | Consolidated target |
| --- | --- | --- |
| Bot lifecycle | Four storage roots, several create/destroy routines, group-only activation in gameplay mod | `bot_manager.lua` owns registration, creation, enable/disable, technology checks, entity recreation, removal, and per-player role state. |
| State | `mekatrol_game_bot/state.lua`, gameplay `state.lua`, and ad hoc standalone tables | One versioned `storage.mekatrol_assist_bot` schema with import migrations and role-keyed state. Persistent data contains no rendering objects that cannot be recreated. |
| Player anchor | Direct `player.position/surface` access and the legacy game bot's `player_anchor.lua` | Port and extend `player_anchor.lua`, then use it everywhere, including editor/remote-view safe handling. |
| Movement | Target's straight teleport step, gameplay `positioning.lua`, repair A*, and mapping's instant teleport | `movement.lua` supplies distance/arrival helpers and smooth flight. `pathfinding.lua` is an optional wall-aware strategy for repair/other ground-constrained jobs. No controller implements its own follow movement. |
| Formation | Hard-coded offsets in both larger mods, with separately duplicated direction switching | `formation.lua` computes all active slots from a stable role order and configured spacing. It mirrors the whole formation when horizontal travel changes direction. |
| Entity finding | Full-radius scans, gameplay `util.find_entities/scan_entities`, spiral search, repair scans, cleanup scans, and the legacy game bot's cell-based incremental scan | `entity_scanner.lua` provides filtered radius scans, incremental cell scans, nearest selection, deduplication by stable identity, invalid-entity pruning, and per-tick budgets. Spiral exploration remains a higher-level mapper strategy using this service. |
| Discovery/map | Standalone mapped tables/events and gameplay entity index/groups | One `discovery.lua` service backed by the gameplay entity index. It publishes map/clear events and a compatibility remote interface while groups/survey polygons reference the same records. |
| Inventory/supply | Gameplay inventory helpers, cleanup cargo logic, repair chest lookup, and target supply module | Keep focused `inventory.lua` primitives and expand `supply.lua` with configurable source policies. Each role declares what it can withdraw, carry, return, or give to the player. |
| Visuals | Three visual modules plus target lines and track borders | Split reusable rendering into `visuals.lua` (lines, labels, circles, highlights, health bars, map tags) and role-specific overlays. All render IDs are owned and cleared through one API. |
| Commands | Per-bot target commands, generic gameplay commands, hotkey-only standalone mods | One parser and role registry drives commands, help, aliases, hotkeys, status, and technology-denied messages. |
| Task declarations | Target task registries and hard-coded gameplay task lists | One role registry defines each bot; upgrade mappings and task-specific policies remain declarative task data. |
| Tick scheduling | Multiple `on_tick` handlers and scan intervals | One scheduler updates enabled bots with per-role intervals and scan budgets, preventing all expensive scans from landing on the same tick. |

The legacy game bot's `bot.lua` and `track_upgrade_bot.lua` are substantially duplicated.
Before adding ports, extract their shared fetch/upgrade/return state machine into
an upgrade controller parameterized by task registry and progression policy.

## Mandatory tick-budget and responsiveness rule

Implemented code must never perform a potentially large operation or scan in a
single tick. All discovery, entity finding, target selection, route and task
planning, pathfinding, connected-component traversal, inventory/source search,
grouping, surveying, pruning, migration, and similar work must be incremental,
budgeted, and resumable across many ticks. This applies even when an operation
is initiated by a command, hotkey, event, configuration change, or bot task;
those entry points enqueue or initialize work and must not complete an
unbounded search synchronously.

Each such operation must store explicit progress in persistent state, process
only its configured per-tick item/cell/node/time budget, and yield to the shared
scheduler when that budget is exhausted. Iteration order and saved cursors must
remain deterministic and valid across save/load. Results may be consumed
progressively where safe, but controllers must tolerate incomplete scans and
plans without restarting them from the beginning every tick.

No controller may use a full-surface scan, a large-radius entity query, or an
unbounded Lua loop during normal gameplay. Large radii must be divided into
cells or another bounded work queue; entity queries within each unit of work
must also have a defensible maximum size. Work budgets must be coordinated by
the shared scheduler so multiple enabled bots cannot each spend the full global
budget in the same tick. The design goal is stable gameplay frame time: a large
factory or search area may make a task take more ticks to finish, but must not
cause a long gameplay pause or slowdown.

## Unified bot roster, appearance, and technology gates

Every role is independently enableable. “All” is a convenience operation, not
a separate entity. Recommended initial role registry:

| Role | Primary behavior after merge | Vanilla visual family | Default minimum technology |
| --- | --- | --- | --- |
| `builder` | Gameplay constructor; initially follow/move plus real ghost construction added during its port | Construction robot | `construction-robotics` |
| `repair` | Full entity-repair behavior | Construction robot, working while repairing | `construction-robotics` |
| `upgrade` | General declarative upgrades | Construction robot, working at target | `construction-robotics` plus mapping recipe availability |
| `track` | Progressive connected-belt upgrades | Construction robot, working at target | `construction-robotics` plus each stage's required recipes |
| `lamp` | Powered nighttime lamp placement | Construction robot | `construction-robotics` and `optics` |
| `cliff` | Marked cliff demolition | Construction robot, working during launch | `cliff-explosives` |
| `logistics` | Gameplay group collection/mining and player delivery | Logistic robot | `logistic-robotics` |
| `cleanup` | Loose-item pickup and sorted return | Logistic robot | `logistic-robotics` |
| `mapper` | Spiral/static scanning, discovery publication, map clear/API | Construction robot | `electronics` |
| `surveyor` | Resource boundary trace and entity-group production | Construction robot | `electronics` |

The exact defaults are policy and therefore live in `config.lua`. During
implementation, validate every configured technology name against
`prototypes.technology`; an absent optional technology must produce a clear
startup/configuration error or an explicitly documented fallback, never an
unreachable bot. A role supports one or more required technologies with
documented `all` semantics. Task-level recipe checks remain in addition to the
role's minimum technology.

Technology is checked on enable, command/task assignment, configuration change,
research completion, and research reversal. A locked bot is not spawned and
the player receives the localized missing-technology message. Already active
bots are safely recalled/disabled if their requirement becomes unmet.

## Formation design

Use the existing behavior shared conceptually by `mekatrol_game_play_mod` and
`mekatrol_game_bot`: bots trail on the opposite side of horizontal movement and
move smoothly toward a player-relative target. Replace manually assigned Y
offsets with generated, evenly spaced slots.

1. Take the configured stable role order and filter it to active, valid bots.
2. For `n` active bots and configured `slot_spacing`, assign centered offsets
   `y = (index - (n + 1) / 2) * slot_spacing`. This yields symmetric, equal
   spacing for odd and even counts.
3. Use one configured `side_distance` for X. Player movement beyond a
   configurable direction threshold flips X for the entire formation.
4. Preserve each bot's slot while it works. On return, recompute from the
   current active set and ease toward the new slot; do not teleport directly.
5. Use an arrival dead band and movement step from `config.lua` to avoid jitter.
6. For many active bots, support configurable `max_slots_per_column` and
   `column_spacing` so a large roster forms evenly spaced centered columns
   instead of extending indefinitely up/down the screen.
7. Spawn at the computed slot, using `find_non_colliding_position` only if the
   selected prototype requires it. Formation ordering must be deterministic
   across save/load and multiplayer peers.

## Robot icons and animations

Create two reusable prototype builders in the data stage:

- Construction-family roles clone the vanilla construction-robot prototype
  graphics and icon definitions.
- Logistics-family roles clone the vanilla logistic-robot prototype graphics
  and icon definitions.

Each role receives a distinct prototype/localized name but reuses the full
vanilla `idle`, `in_motion`, `working`, shadow, and directional animation data.
The controller changes role animation state according to follow/travel/work
where the Factorio prototype API permits it; if scripted entities cannot select
those states directly, define separate visual variants and switch them without
losing logical role state. Do not reduce animation tables to a single static
sprite.

Use the corresponding vanilla construction or logistic item icon everywhere a
bot is represented: prototype icon, shortcut, map tag, status display, and help
text. Add a small role badge/tint only when needed to distinguish multiple bots
of the same family; preserve recognizable vanilla robot artwork. Validate
animations at all 16 directions, idle, moving, working, shadow alignment, zoom
levels, and both normal and high-resolution sprite definitions available in
the installed Factorio version.

## Configuration plan

All user-tunable behavior belongs in `mekatrol_assist_bot/config.lua`. Keep only
true implementation constants and stable external identifiers in
`constants.lua`. `data.lua` and control-stage modules both read the relevant
sections from `config.lua`; the file must not access runtime-only globals.

Recommended top-level layout:

```lua
return {
    schema_version = 2,
    controls = { ... },
    scheduler = { ... },
    formation = { ... },
    movement = { ... },
    scanning = { ... },
    visuals = { ... },
    supply = { ... },
    roles = {
        builder = { enabled_by_default = false, prototype_family = "construction", required_technologies = { ... }, ... },
        cleanup = { prototype_family = "logistic", required_technologies = { ... }, ... },
        -- every other role
    },
    tasks = { upgrade = { ... }, track = { ... } },
    compatibility = { ... }
}
```

Every field gets a purpose/units/range comment immediately above it. Document
and validate at least these range families:

| Setting family | Units and valid range |
| --- | --- |
| Tick intervals and per-tick budgets | Integer ticks/counts, `>= 1`; document 60 ticks = 1 second at normal speed. |
| Distances, radii, spacing, movement steps | Tiles, finite number `> 0`; explicitly state whether inclusive and whether compared squared internally. |
| Darkness | Unit interval `[0, 1]`, where 0 is daylight and 1 is full darkness. |
| Colors | Each RGBA channel `[0, 1]`. |
| Capacities and item counts | Integer `>= 0`; state whether zero disables the behavior. |
| Health and repair durability | Health points, finite `> 0`; percentages use `[0, 1]`, not mixed percent notation. |
| Technology lists | Array of technology prototype names; empty means no gate; `technology_mode` is `"all"` or `"any"`. |
| Key sequences | Factorio custom-input key-sequence strings; empty string means unbound only if Factorio accepts it for that prototype. |
| Role order/formation columns | Unique registered role names; positive integer column limit. |

Move all embedded repair constants, health overrides, mapping scan settings,
gameplay search/survey settings, formation offsets, update intervals, cargo
limits, colors, task radii, and controls into this file. Add startup validation
with messages naming the exact invalid path, supplied value, and accepted
range. Update `README.md` with a configuration reference; the source comments
remain the authoritative exhaustive documentation.

## Consistent controls and commands

Use `Ctrl+Shift+<mnemonic>` only for toggles and `Ctrl+Alt+<mnemonic>` for a
secondary/destructive/planner action. Recommended defaults:

| Action | Default binding |
| --- | --- |
| Toggle all currently unlocked bots | `Ctrl+Shift+A` |
| Builder | `Ctrl+Shift+B` |
| Cleanup | `Ctrl+Shift+C` |
| Cliff | `Ctrl+Shift+D` |
| Logistics (“goods”) | `Ctrl+Shift+G` |
| Lamp | `Ctrl+Shift+L` |
| Mapper | `Ctrl+Shift+M` |
| Repair | `Ctrl+Shift+R` |
| Surveyor | `Ctrl+Shift+S` |
| Track upgrade | `Ctrl+Shift+T` |
| General upgrade | `Ctrl+Shift+U` |
| Clear map | `Ctrl+Alt+M` |
| Take cliff planner | `Ctrl+Alt+D` |

Standardize console control on:

```text
/mab <role|all> <on|off|toggle|status> [options]
/mab <role> task <task-name> [key=value ...]
/mab <role> tasks
/mab <role> refresh
/mab help [role]
/mab status [role|all]
```

`/mab` is the single public command namespace; do not register `/bot`, `/b`, or
`/bot-status` for the new mod. Resolve `s` consistently to `surveyor`; use full
role names in persisted data. Retain `/ub`, `/tb`, `/cb`, `/lb`, and `/db` as
documented compatibility aliases for one deprecation cycle, forwarding them to
the `/mab` parser. Existing saved custom key assignments cannot be migrated by
script, so document renamed input prototypes and the new defaults in release
notes.

## Documentation and comment standard

Each module starts with a short responsibility header explaining its purpose,
the state it owns, and why it exists separately. Public functions receive LuaDoc
comments covering contract, significant parameters/return values, state changes,
and failure behavior. State machines explain phases, transitions, invariants,
and why expensive work is throttled. Non-obvious Factorio constraints—data vs
control stage, invalid `LuaEntity` references, deterministic iteration,
multiplayer, and rendering cleanup—must be documented at the relevant boundary.

Do not add comments that merely narrate syntax or arithmetic. Existing comments
such as “compute dx” or “return false” should be removed when touched. Prefer
names and small functions for mechanics; comments explain purpose and design
reasoning.

Keep `README.md` updated continuously as each phase and feature is implemented;
documentation is part of the implementation work, not a final cleanup task.
Clearly distinguish planned behavior from behavior available in the current
release, and keep controls, commands, configuration, technology requirements,
compatibility notes, and migration instructions synchronized with the code.
Before declaring the merge complete, move every remaining piece of enduring
user and maintainer documentation from this plan into `README.md`. Once all
acceptance criteria pass and the README is the complete authoritative
documentation for the bot, delete `MERGE_PLAN.md`; no completed implementation
should retain the temporary plan as required operational documentation.

## Implementation phases

Phase status as of 2026-10-02: Phases 1 through 6 are complete and verified
against Factorio 2.0.77. Phase 7 may contain partial implementation, but is not
marked complete until its phase-level behavior and applicable acceptance checks
have been verified. The current stopping point is the end of Phase 6.

### Phase 1: Baseline and acceptance fixtures (complete)

- [x] Tag/copy a known-good save and record current command output and visible bot
  behavior.
- [x] Add a lightweight test/check harness for pure modules: configuration
  validation, command parsing, formation slots, entity identity/deduplication,
  polygon operations, task registry, and technology gates.
- [x] Record performance baselines for ten enabled bots and large entity fields.
- [x] Catalogue prototype and technology names against the installed Factorio 2.0
  data set before finalizing defaults.

Evidence and reproduction details are recorded in `PHASE1_BASELINE.md`.

### Phase 2: New assist-bot architecture (complete)

- [x] Build the new mod in `mekatrol_assist_bot`; port selected code rather than
  continuing development inside a legacy source directory.
- [x] Establish a versioned role registry and import migrations for existing
  `mekatrol_game_bot`, gameplay, mapping, and repair save state.
- [x] Add configuration validation, scheduler, bot manager, formation service,
  scanner, shared visuals, and unified command parser.
- [x] Extract the duplicated general/track upgrade state machine.
- [x] Preserve existing target behavior before porting another mod.

Evidence and reproduction details are recorded in `PHASE2_ARCHITECTURE.md`.

### Phase 3: Visual prototypes and formation (complete)

- [x] Replace static pictures with construction/logistic animation-family
  prototypes and assign the role mapping above.
- [x] Implement generated even spacing and direction-aware formation mirroring.
- [x] Verify enable/disable/research changes reflow the formation without overlap
  or save instability.

Evidence and reproduction details are recorded in `PHASE3_VISUALS_FORMATION.md`.

### Phase 4: Mapping, discovery, and survey (complete)

- [x] Port gameplay `entity_index`, search, entity groups, polygon, and survey
  modules behind `discovery.lua` and `entity_scanner.lua`.
- [x] Merge standalone static-entity mapping, map clearing, visuals, generated
  events, and snapshot API.
- [x] Preserve a compatibility remote interface named `mapping_bot_mod` for at
  least one release, but have it read the assist bot's discovery state.
- [x] Convert repair integration from cross-mod event wiring to the internal
  discovery subscription.

Evidence and reproduction details are recorded in `PHASE4_MAPPING_DISCOVERY.md`.

### Phase 5: Repair bot (complete)

- [x] Port repair-pack pooling, chest sourcing, damage discovery, destroyed-site
  tracking, self-repair, A* wall avoidance, and useful visuals.
- [x] Replace the gameplay repair placeholder with this controller.
- [x] Prefer prototype-derived max health where the runtime API supports it; keep
  documented overrides only for genuine exceptions. Remove diagnostic file
  writes from normal play or guard them behind a debug config flag.

Evidence and reproduction details are recorded in `PHASE5_REPAIR.md`.

### Phase 6: Gameplay logistics and builder (complete)

- [x] Port logistics collection/mining/inventory behavior, sharing supply and
  scanner primitives with cleanup and upgrade bots.
- [x] Define and implement the currently missing builder `construct` contract
  (recommended: fulfill nearby same-force entity ghosts using permitted supply
  sources). Until implemented and tested, do not claim construction support in
  help text.
- [x] Port the master-controller handoff as event/queue rules in the role registry
  instead of a second global controller.

Evidence and reproduction details are recorded in
`PHASE6_GAMEPLAY_BUILDER_LOGISTICS.md`.

### Phase 7: Controls, technology, migration, and legacy deletion

- Apply the unified keys/commands and localized help.
- Enforce configured minimum technology for every role and per-task recipe
  availability where applicable.
- On configuration change, migrate target state and optionally import old mod
  state when those storage tables exist. Never spawn duplicate bots.
- Release `mekatrol_assist_bot` with all four source mods declared incompatible
  only after import is tested. Document retaining a backup save.
- After every acceptance criterion passes and the backup/migration path has
  been verified, delete the legacy directories and all code owned solely by
  them: `entity_repair_mod`, `mapping_bot_mod`, `mekatrol_game_play_mod`, and
  `mekatrol_game_bot`. Do not leave duplicate implementations, obsolete
  compatibility shims beyond their stated support window, copied dead modules,
  or documentation that tells users to enable an old mod.
- Treat legacy deletion as a separately reviewed change. Before deletion,
  compare the migrated feature checklist and search the repository for legacy
  requires, prototype names, custom inputs, commands, remote interfaces,
  storage keys, and documentation references. After deletion, load both a new
  game and a migrated backup with only `mekatrol_assist_bot` enabled.

## Validation and acceptance criteria

- Only `mekatrol_assist_bot` is enabled; no missing-prototype or missing-remote
  errors occur when loading a migrated save.
- Every listed role can be toggled independently and through `all`; locked roles
  explain their exact unmet technology and never spawn.
- All active idle bots occupy deterministic, evenly spaced formation slots,
  mirror sides when the player reverses horizontal direction, and reflow when a
  role leaves/returns.
- Construction-family and logistic-family bots display the appropriate vanilla
  icons and correct idle/moving/working animations, including shadows and all
  directions.
- Mapping discoveries feed surveying, logistics, and repair without duplicate
  scans or stale entity crashes; clear removes data and visuals and raises the
  compatibility event.
- Repair consumes the configured repair-pack durability exactly, uses the
  configured supply priority, routes around walls, and cleans destroyed-site
  records when replacements are built.
- Upgrade and track behavior, connected underground pairs, supply returns,
  blocked-container recovery, lamp placement, cliff marking, and cleanup cargo
  retain current behavior.
- All settings are in `config.lua`, documented with units/ranges, and rejected
  early with actionable validation messages when invalid.
- Multiplayer tests cover two players on different surfaces, disconnect/rejoin,
  death/respawn, force change, research gained/reversed, bot destruction, and
  configuration change.
- Profiling confirms scanner work is budgeted and no port introduces a
  full-surface scan on normal ticks. Stress tests confirm that entity finding,
  planning, pathfinding, connected-entity traversal, surveying, pruning, and
  migration all yield at their configured budgets and continue across many
  ticks without noticeable gameplay stalls.
- `README.md`, command help, locale strings, and actual default bindings agree.

## Known risks to address during implementation

- Gameplay logistics contains an apparent `module.get + module("visual")`
  typo; fix it during the port rather than carrying it forward.
- Current max-health inference can mistake an already damaged entity for its
  maximum. Prototype-derived health or explicit overrides are safer.
- The standalone mapping API exposes tables containing entity references;
  compatibility snapshots need pruning/copy semantics so consumers cannot
  mutate internal state or retain invalid references.
- Actual robot prototypes may attempt vanilla logistic behavior if cloned
  carelessly. Prototype builders must neutralize autonomous payload/radius/
  energy behavior while preserving animation and attackability.
- Factorio custom input identifiers and stored entity prototype names are save-
  facing APIs. Rename them only with explicit migration/compatibility handling.
- Ten concurrent bots amplify scan and rendering cost. The shared scheduler and
  scanner budget are required infrastructure, not optional optimization.
