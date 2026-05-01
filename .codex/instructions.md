# Coding Instructions

Follow the existing Factorio mod style.

- Target Factorio `2.0`; runtime scripts should use `storage`, not legacy
  `global`.
- Keep each mod self-contained. `require("module")` resolves inside the current
  mod folder, so avoid cross-mod Lua imports unless a dependency is declared and
  intentionally designed.
- Preserve existing file roles: `info.json` for metadata, `data.lua` for
  prototypes and custom inputs, `control.lua` for runtime events, and supporting
  modules for reusable logic.
- Prefer small, direct Lua helpers over broad refactors. These mods are
  script-heavy and event-driven, so keep state transitions explicit.
- Guard Factorio API objects with validity checks before use:
  `if not (entity and entity.valid) then return end`.
- Initialize persistent tables from `script.on_init`,
  `script.on_configuration_changed`, or lazy `ensure_*` helpers before reading
  nested fields.
- Use deterministic tick throttling for repeated work. Expensive scans should be
  gated with `event.tick % interval == 0` or per-player next-tick fields.
- Keep rendered visual object ids in storage and destroy or replace them when
  state changes to avoid stale overlays.
- When adding hotkeys, define the `custom-input` in `data.lua` and register the
  matching `script.on_event("<input-name>", handler)` in `control.lua`.
- When adding entities, prefer script-controlled prototypes like
  `simple-entity-with-owner` if the script owns movement and behavior.
- Do not edit zip mod artifacts unless the task is specifically about those zip
  packages.

Be careful with existing user changes. Check `git status --short` before and
after edits, and avoid reverting unrelated work.

