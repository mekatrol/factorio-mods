# Phase 2 architecture verification

Verified on 2026-10-02 with Factorio 2.0.77.

## Architecture delivered

- `state.lua` owns the sole schema-versioned persistent root and stable
  per-player, per-role records. `migrations.lua` imports enablement, task,
  discovery, and destroyed-site intent from all four legacy storage roots while
  deliberately excluding legacy entities and rendering handles.
- `role_registry.lua` is the canonical role/task catalogue used by commands and
  controllers. `bot_manager.lua` owns gated creation, recreation, visual-state
  replacement, enable/disable, player removal, and formation reflow.
- `scheduler.lua` distributes one global work budget across players, roles,
  migration, selection, and visual cleanup. `entity_scanner.lua` persists its
  cursor and subdivides dense cells so each query has a configured result cap.
- `commands.lua` provides the `/mab` parser and compatibility forwarding;
  `validate.lua` rejects invalid configuration before runtime work begins.
- General and progressive track upgrades use the same parameterized scan,
  connected-component, supply, movement, replacement, and return flow in
  `controllers.lua`, with bounded component traversal isolated in `track.lua`.

## Verification

The opt-in disposable-save fixture seeds recognizable data in all four legacy
storage roots and asserts imported role enablement and upgrade/track task state.
It also validates every required live prototype, moves all ten visual role
prototypes for 900 steps, and scans a synthetic 4,096-resource field through
bounded scanner work units. Multiplayer, lifecycle, and gameplay-controller
integration remain acceptance work for their corresponding later phases.

The run completed with:

```text
[MAB test] Phase 2 fixture passed on Factorio 2.0.77
```

The fixture is destructive by design and only runs when `config.debug=true` in
a disposable save. The checked-in setting remains `false`.
