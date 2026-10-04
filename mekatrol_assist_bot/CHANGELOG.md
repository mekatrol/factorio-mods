# Changelog

## Unreleased

- Assist bots can no longer be collected by holding the mine control while one
  flies beneath the cursor.
- Removed the custom repair health arc; repaired entities use Factorio's native
  health bar instead.
- Fixed supply-seeking bots oscillating between the player and their work
  target while travelling to withdraw an item from player inventory.
- Bots now fly to the live position of a player before withdrawing supplies
  from that player's inventory, then return to their work target before using
  the item.
- Repair bots now fly directly over walls and other ground obstacles instead
  of planning a ground-style route around them.
- Stale bot labels are now reclaimed after save/load, preventing overlapping
  `follow` and active-task text from appearing to flicker between states.
- Repair bots now scan for their next target from their current position and
  no longer return toward formation during that scan.
- Fixed repair bots becoming stuck in the working state on a damaged target
  when no repair packs were available. They now follow formation while waiting
  and automatically resume once a pack becomes available.

- Track bots now follow their player while searching for a belt graph, matching
  the idle-search behaviour of repair and cleanup bots.
- Capped each assist bot's combined movement to 0.18 tiles per game tick, so
  repeated scheduler work in one tick cannot multiply its flight speed beyond
  the fully upgraded finite vanilla worker-robot range.

- Target lines and bot labels now validate their live player viewer instead of
  trusting a potentially stale migrated visual key, preventing tick crashes
  after a player has been removed or indices have changed.
- Repair bots no longer select or repair enemy entities discovered by mapper
  bots, and destroyed-site circles are now limited to player-owned forces.
- Existing destroyed-site records are cleared during migration because older
  records did not store enough force information to remove enemy sites safely.
- Restored the pre-consolidation follow tuning: movement updates every tick at
  0.18 tiles per tick, bots form one centered column two tiles behind the
  player, and that column automatically mirrors with horizontal travel.
- Bots now keep one persistent visual entity instead of being destroyed and
  recreated for animation-state changes, eliminating blurred duplicate sprites
  during per-tick movement.
- Trailing formations now follow all four cardinal headings, moving below the
  player while travelling up and above the player while travelling down.

## 1.0.0 — Phase 7 consolidation

- Fixed repair and health-overlay code for Factorio 2.0 by reading maximum
  health from runtime entities instead of the prototype API.
- Repair bots now keep following their player while background target scans run.
- Cleanup bots now keep following during target/deposit scans and while waiting
  for player inventory space.
- Unified localized command help and enforced role technology gates before task
  mutation, including actionable recipe availability errors for upgrade tasks.
- Added configuration-change migration verification and declared all four source
  mods incompatible; the superseded source directories are no longer shipped.
- Retained the documented legacy storage import and mapping remote API for the
  1.0 compatibility cycle. Back up a save before replacing the old mods.

## Phase 5 verification

- Completed bounded repair actions, exact persistent repair-pack durability
  pooling, self-repair, discovery-fed damage selection, and resumable A* travel.
- Added destroyed-site lifecycle visuals and legacy repair-pool migration; health
  limits are derived from runtime entities.

- Added deterministic outward mapper exploration, indexed shared discovery,
  connected resource survey polygons, incremental clearing, and copy-only
  paged mapping compatibility snapshots.

- Completed and verified construction/logistic animation-family prototypes,
  runtime idle/moving/working visual switching, deterministic centered columns,
  direction mirroring, and roster reflow without overlapping slots.

## 1.0.0

- Consolidated ten independently toggleable roles behind one state root,
  scheduler, formation, scanner, discovery service, and command parser.
- Added full vanilla robot-family animation prototypes and unified controls.
- Added legacy state import, mapping compatibility API, and deprecated command
  aliases for the 1.0 cycle.
- Added bounded A* repair routing, connected belt traversal including underground
  peers, Moore-neighbour resource tracing, polygon groups, container sourcing,
  cargo retention, destroyed-site tracking, and shared target rendering.
- Added a synthetic migrated-save and two-player/two-surface integration fixture.
- Renamed all custom inputs; Factorio cannot migrate users' saved key bindings,
  so bindings must be reapplied in Controls > Mods.

## 1.0.0 - Phase 6

- Completed prototype-aware same-force ghost construction with shared supply sourcing.
- Ported bounded logistics pickup, inventory draining, neutral mining, and quantity requests.
- Replaced the gameplay master controller with persistent role-registry discovery queues.
