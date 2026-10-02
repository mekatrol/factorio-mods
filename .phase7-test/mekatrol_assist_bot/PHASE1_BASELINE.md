# Phase 1 baseline

Captured on 2026-10-02 with Factorio 2.0.77 (build 84539, Windows) from
repository base commit `9eed176df2af252c997b06b5604059089f697146` plus the current working-tree
implementation.

## Reproducible save

The debug fixture produced the disposable save
`%TEMP%\mab-phase1-validation\phase1.zip` (869,606 bytes, SHA-256
`0D8A9E74E79A78EBB82C9D710FF20D6351277B3A78A022926D5152687380B223`). It
contains only `mekatrol_assist_bot` plus the installed official Factorio mods;
the source copy used for that save had `config.debug=true`. Do not use a debug
fixture in a real game.

The load completed with `[MAB test] Phase 1 fixture passed on Factorio 2.0.77`.
The normal checked-in setting remains `config.debug=false`.

## Command and visible-behaviour baseline

The pure check harness covers tokenization, role aliases, legacy forwarded
commands, default actions, task arguments, configuration validation, formation
slots, discovery identity/deduplication, polygons, task registration, and
technology modes.

The command surface recorded for subsequent parity checks is:

```text
/mab <role|all> <on|off|toggle|status>
/mab <role> task <task-name>
/mab <role> tasks
/mab <role> refresh
/mab help [role]
/mab status [role|all]
```

Status lines have the stable form
`[MAB] <role>: <on|off>, task=<task>, phase=<phase>[, missing=<technology,...>]`.
Unknown roles/actions and invalid tasks produce actionable `[MAB]` messages.
The temporary `/ub`, `/tb`, `/cb`, `/lb`, and `/db` aliases select their
corresponding roles; a bare `/ub` retains the legacy upgrade-mode cycle.

The visible baseline is ten deterministic formation slots, mirrored by player
horizontal direction. Construction-family roles use construction-robot
graphics, while logistics and cleanup use logistic-robot graphics. Each role
has idle, moving, and working visual prototypes.

## Performance baseline

Factorio's `LuaProfiler`, measured during isolated `on_init`, reported:

- Ten role-bot entities over 900 movement ticks: 14.584300 ms total.
- A 4,096-entity iron-ore field scanned in 25 bounded work units: 12.040300 ms
  total.

These are regression reference points, not universal hardware targets. The
fixture asserts that the dense-field scan sees all 4,096 resources.

## Factorio 2.0 prototype catalogue

The fixture verifies these names against the live prototype tables before it
runs:

- Technologies: `construction-robotics`, `logistic-robotics`, `lamp`,
  `cliff-explosives`, and `electronics`.
- Robot families: `construction-robot` and `logistic-robot`.
- Required items/entities: `repair-pack`, `small-lamp`, `cliff-explosives`,
  `transport-belt`, `fast-transport-belt`, `express-transport-belt`, and
  `turbo-transport-belt`.

Factorio 2.0 uses the technology name `lamp`, not the former assumed `optics`;
the default lamp gate was corrected from the catalogue result.
