# Game Play Mod Commands

## Hotkeys

| Shortcut | Custom input | Action |
| --- | --- | --- |
| `Ctrl + Shift + G` | `mekatrol-game-play-bot-toggle` | Toggle the game play bot group on or off. |

## Console Commands

The mod registers two equivalent commands:

```text
/bot <bot> <task> [args]
/b <bot> <task> [args]
```

Arguments after the task are parsed as key/value pairs by `util.parse_kv_list`.

The mod also registers status commands:

```text
/bot-status
/bs
```

These print and log each full bot name, entity state, current task, next task,
target position, task args, queued discoveries, and selected bot-specific
details.

The mod also logs a warning automatically when a bot remains on the same
non-follow task, target, and group state for several seconds. The warning
includes the full bot name and the same status details as `/bs`.

## Bot Names

| Short | Full name |
| --- | --- |
| `a` | `all` |
| `c` | `constructor` |
| `l` | `logistics` |
| `m` | `mapper` |
| `r` | `repairer` |
| `v` | `surveyor` |

Note: `control.lua` currently maps surveyor shorthand to `v`. The command usage
string mentions `s`, but `s` is not mapped as a bot name.

## Tasks

| Bot | Supported tasks | Short task names |
| --- | --- | --- |
| `constructor` | `follow`, `construct`, `move_to` | `f` = `follow`, `c` = `construct` |
| `logistics` | `follow`, `collect`, `pickup`, `move_to` | `f` = `follow`, `c` = `collect` |
| `mapper` | `follow`, `search`, `move_to` | `f` = `follow`, `s` = `search` |
| `repairer` | `follow`, `repair`, `move_to` | `f` = `follow`, `r` = `repair` |
| `surveyor` | `follow`, `search`, `survey`, `move_to` | `f` = `follow`, `s` = `search` |

## Examples

```text
/b a f
/b l collect
/b m search
/b v survey
/b r repair
/b c construct
/bot logistics pickup
/bs
/bot-status
```
