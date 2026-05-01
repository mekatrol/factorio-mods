# Environment

Working directory:

```text
/home/dad/.factorio/mods
```

Runtime context:

- Factorio user mods directory.
- Unpacked local mods are edited in place.
- Mod metadata targets Factorio `2.0`.
- Lua code runs in the Factorio mod runtime, not standalone Lua.
- There is no project-local build system or test runner in this workspace.

Useful checks:

```bash
git status --short
rg -n "script\\.on_event|commands\\.add_command|data:extend|storage\\." -g '*.lua'
find . -maxdepth 2 -name info.json -print
```

Manual validation usually means starting Factorio with these local mods enabled
and checking the Factorio log for load/runtime errors.

Packaging, when needed, should preserve Factorio's expected folder layout:

```text
<mod-name>/
  info.json
  data.lua
  control.lua
  ...
```

Do not assume a mod can be validated by a plain Lua interpreter; Factorio
globals such as `script`, `game`, `defines`, `storage`, `data`, and `rendering`
are only available inside Factorio.

