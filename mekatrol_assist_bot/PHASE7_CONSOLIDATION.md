# Phase 7: Controls, technology, migration, and consolidation

Verified 2026-10-02 against Factorio 2.0.77.

## Completed behavior

- The documented `Ctrl+Shift` role toggles and `Ctrl+Alt` secondary actions are
  the only new custom inputs. `/mab` owns public command routing; the five 1.0
  compatibility aliases forward into the same parser.
- Command descriptions, help, and technology/recipe denial messages use locale
  keys. Task assignment checks the role gate before mutating persistent state.
  Upgrade modes report unavailable target recipes; track remains enabled while
  waiting for later belt research by design.
- Initialization, configuration change, force change, research completion, and
  research reversal all pass through the shared technology/lifecycle boundary.
- Legacy role intent is imported once. Mapping records, gameplay discoveries,
  and destroyed sites migrate through the scheduler's bounded background work.
- `info.json` declares the four source mods incompatible. Their implementation
  directories were removed only after the reference search and engine fixtures
  below passed. The 1.0 mapping remote API and storage import remain deliberately
  supported for saved-game compatibility.

## Verification evidence

An isolated Factorio write-data directory loaded only `mekatrol_assist_bot` and
created a new save successfully. The debug migration fixture then created a
second disposable save and verified all four legacy storage shapes, every role
family, one imported mapping entity, and completion of the resumable migration
job. The same run reported:

```text
[MAB baseline] ten role bots, 900 movement ticks: 13.972300 ms
[MAB baseline] 4096-resource bounded scan, 25 work units: 13.913200 ms
```

The pre-deletion reference audit found legacy identifiers only inside the four
source directories and the assist bot's intentional migration, remote-interface,
fixture, and documentation compatibility surfaces. No assist module requires a
legacy module or prototype. A backup-first migration procedure is in `README.md`.
