# Phase 5: Repair bot

Phase 5 replaces the gameplay repair placeholder with the shared repair
controller. Damage discovery consumes the common discovery cursor first and
then a bounded cell scan; commands and ticks never perform a full-radius query.

Repair work restores at most `tasks.repair.health_per_action` health per
scheduled work unit. Packs become the configured durability pool, whose unused
remainder persists in role state. Supply lookup follows the configured priority
and uses the resumable scanner. The same pool self-repairs the bot below its
configured threshold.

Travel is direct flight and stops within interaction distance. Walls, gates,
and other ground obstacles do not affect the route of the airborne repair bot.

Destroyed sites are recorded on death and highlighted until a build, revive, or
clone replaces the entity at that site. Legacy repair enabled state, destroyed
sites, and unused repair-health pools migrate without old entity/render handles.
Maximum health comes from `LuaEntityPrototype.max_health`; normal play performs
no diagnostic file writes.

The opt-in headless fixture asserts target repair, self-repair, container
sourcing, and retained partial pack durability. Startup validation covers the
new health/action, threshold, and interaction-distance ranges. Verification
target: Factorio 2.0.77.
