# Phase 4: Mapping, discovery, and survey

Completed and checked against Factorio 2.0.77 on 2026-10-02.

## Delivered behavior

- `discovery.lua` owns one deduplicated map with stable identity, exact-name
  buckets, deterministic cursors, bounded invalid-record pruning, generated
  mapped/cleared events, and copy-only paged snapshots.
- The mapper persists an outward square spiral. Each scheduled work unit scans
  at most one bounded cell, so exploration continues across ticks and saves.
- The surveyor consumes discovery records before falling back to a bounded
  radius scan. Boundary tracing advances one point per scheduled work unit;
  group membership is then populated by a resumable cell scan and stored with
  the traced polygon, area, and perimeter.
- Clear swaps the live records, indexes, and groups immediately, raises the
  compatibility event, and queues old records and render objects for bounded
  cleanup through the shared scheduler.
- The `mapping_bot_mod` remote interface provides the legacy event accessors
  and snapshot call plus paged all-record and exact-name calls. Returned values
  are metadata copies and never expose mutable internal tables or `LuaEntity`
  references.
- Repair, builder, logistics, and surveyor consume the internal discovery
  cursor directly; no cross-mod event wiring remains.

## Verification

The pure initialization checks cover identity deduplication and polygon
membership. The debug Factorio fixture maps a 4,096-resource field through the
bounded scanner, verifies a survey polygon, confirms snapshots omit entity
handles, observes generated mapped/clear events, and confirms clear resets the
live index. The fixture reports:

```text
[MAB test] Phase 4 fixture passed on Factorio 2.0.77
```

Manual inspection also confirmed that mapper, survey, prune, migration, map
clear, and rendering cleanup retain explicit persistent cursors and yield to
the shared scheduler.
