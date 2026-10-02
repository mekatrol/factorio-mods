# Phase 3 visual and formation verification

Verified on 2026-10-02 with Factorio 2.0.77.

## Visual prototypes

`robot_prototypes.lua` provides separate construction and logistic builders.
Each builder deep-copies the installed vanilla robot, preserving its icon and
directional animation/shadow definitions. Construction roles use vanilla idle,
in-motion, and working graphics. Factorio 2.0.77's logistic robot has no
dedicated `working` field, so logistic working variants use its complete
in-motion animation rather than inventing or flattening a sprite. Payload and
work radii are zeroed so scripted clones cannot take independent
logistic-network jobs.

The data stage rejects a missing vanilla animation field or unknown configured
family. The debug runtime fixture confirms that all thirty role/state entities
exist with the configured construction-robot or logistic-robot prototype type,
then creates and moves every role prototype.

## Formation and lifecycle

Pure initialization checks cover odd and even centering, multiple columns,
unique coordinates, whole-formation horizontal mirroring, and centered reflow
after a role is removed. Stable configured role order is the only input, so
coordinates remain deterministic across save/load and multiplayer peers.

Runtime lifecycle continues to destroy and recreate only the visual entity when
idle/moving/working state changes; logical role state remains in the persistent
role record. Enablement, disablement, bot destruction, research reversal and
regain all pass through `bot_manager.lua`. Idle roles ease toward newly computed
slots through `movement.lua`, including after roster changes, rather than being
teleported to the new formation position.

The disposable debug fixture completed with:

```text
[MAB test] Phase 3 fixture passed on Factorio 2.0.77
```
