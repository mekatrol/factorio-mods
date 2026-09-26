# Upgrade Bot

`Ctrl+Shift+U` toggles the bot. It starts with the `yellow-to-red-belts` task,
which upgrades transport belts, underground belts, and splitters near the player.
It does not create replacement items. For targets inside a player-force
roboport construction area, the bot first asks that logistic network for the
required item using Factorio's provider/storage/buffer source selection. It
flies to the selected source, removes one item, and carries it to the target.
If the logistic network cannot supply an item, the bot also searches ordinary
player-owned containers within 64 tiles of the target. Logistic-network supply
still has priority. After a network-backed upgrade, the bot carries the removed
lower-tier item to the network's normal selected storage destination. After an
ordinary-container upgrade, it returns that item to the same container. If the
destination has no space, it retains the item in cargo. When no target or supply
is available, the bot follows the player.

Commands:

```text
/upgrade-bot on
/upgrade-bot off
/upgrade-bot task yellow-to-red-belts
/upgrade-bot tasks
/upgrade-bot status
```

`/ub` is a short alias. New jobs belong in `tasks.lua`; the bot engine does not
contain entity names. Each job has a name, optional aliases, and a `mappings`
table of source prototype names to target prototype names. A mapping may instead
be a table with `target`, `required_item`, `recovered_item`, and optional
`create_parameters(entity, player)` fields when an
entity has state that must be preserved. Jobs may also provide an
`execute(player, entity, mapping)` function for entirely non-standard upgrades.
