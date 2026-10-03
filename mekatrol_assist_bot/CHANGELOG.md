# Changelog

## 1.0.0 — Phase 7 consolidation

- Fixed repair and health-overlay code for Factorio 2.0 by reading maximum
  health from runtime entities instead of the prototype API.
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
