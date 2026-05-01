# Cleanup Mod Commands

## Hotkeys

| Shortcut | Custom input | Action |
| --- | --- | --- |
| `Ctrl + Shift + C` | `mekatrol-toggle-cleanup-bot` | Toggle the cleanup bot on or off. |

## Behavior

When enabled, the cleanup bot searches for dropped item entities, picks them up,
and tries to deposit them into nearby suitable containers. If it cannot place
items, it falls back to player inventory handling and cleanup behavior from
`control.lua`.

## Console Commands

This mod does not register console commands.

