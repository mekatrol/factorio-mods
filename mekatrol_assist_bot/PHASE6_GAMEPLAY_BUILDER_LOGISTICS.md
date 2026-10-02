# Phase 6: Gameplay logistics and builder

Completed 2026-10-02 against Factorio 2.0.77.

## Delivered behavior

- Builder scans same-force entity ghosts incrementally, resolves the placement
  item from prototype metadata, obtains one item through shared supply, and
  returns it if revival fails.
- Logistics collects ground stacks, transfers a configured inventory-slot batch,
  incrementally mines neutral resources, and mines empty recoverable entities.
- `pickup name=<prototype> count=<n>` persists its remaining quantity and
  returns to general collection when complete.
- The role registry declares discovery consumers. Discovery publishes IDs into
  persistent per-role queues with per-player consumer cursors under the global
  scheduler; no second tick handler or master controller is used.

## Budget and verification

One scheduler work unit performs at most one dequeue, scanner cell, configured
inventory/resource batch, movement step, supply cell, or ghost revival. Queue,
scan, transfer, pickup, and supply cursors survive save/load under schema 6.

Initialization checks validate the new logistics budgets, registered tasks, and
prototype placement-product selection. Factorio 2.0.77 headless startup checks
data/control-stage loading and runs those initialization checks.
