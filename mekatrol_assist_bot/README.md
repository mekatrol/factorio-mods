# Mekatrol Assist Bot

`mekatrol_assist_bot` is the new base for consolidating the Mekatrol repair,
mapping, gameplay, and game-bot mods. Development begins at version `0.1.0`.

The mod is intentionally inert at this initial scaffold version. See
[`MERGE_PLAN.md`](MERGE_PLAN.md) for the migration architecture, feature map,
controls, technology gates, validation criteria, and eventual deletion of the
legacy mod directories.

## Planned controls

These are the planned default bindings. They are documentation of the target
interface and are not functional while the mod remains an inert scaffold.

| Action | Default binding |
| --- | --- |
| Toggle all currently unlocked bots | `Ctrl+Shift+A` |
| Toggle builder | `Ctrl+Shift+B` |
| Toggle cleanup | `Ctrl+Shift+C` |
| Toggle cliff demolition | `Ctrl+Shift+D` |
| Toggle logistics | `Ctrl+Shift+G` |
| Toggle lamp placement | `Ctrl+Shift+L` |
| Toggle mapper | `Ctrl+Shift+M` |
| Toggle repair | `Ctrl+Shift+R` |
| Toggle surveyor | `Ctrl+Shift+S` |
| Toggle track upgrade | `Ctrl+Shift+T` |
| Toggle general upgrade | `Ctrl+Shift+U` |
| Clear discovered map data | `Ctrl+Alt+M` |
| Take the cliff planner | `Ctrl+Alt+D` |

`Ctrl+Shift+<mnemonic>` is reserved for bot toggles.
`Ctrl+Alt+<mnemonic>` is used for secondary, destructive, or planner actions.
The bindings will be configurable through Factorio's control settings; the
corresponding custom-input identifiers and configuration details will be added
here as they are implemented.

## Planned console commands

The unified command interface will be:

```text
/mab <role|all> <on|off|toggle|status> [options]
/mab <role> task <task-name> [key=value ...]
/mab <role> tasks
/mab <role> refresh
/mab help [role]
/mab status [role|all]
```

`/mab` is the single command namespace. Role names are `builder`, `repair`,
`upgrade`, `track`, `lamp`, `cliff`, `logistics`, `cleanup`, `mapper`, and
`surveyor`. The legacy `/ub`, `/tb`, `/cb`, `/lb`, and `/db` aliases are planned
to forward to the `/mab` parser for one deprecation cycle.

The README will be updated throughout implementation so it describes what is
actually available in each released version. When consolidation is complete,
it will contain the complete user and maintainer documentation and
`MERGE_PLAN.md` will be deleted.
