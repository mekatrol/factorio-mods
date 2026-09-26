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

The bot locks onto one connected belt component at a time. Connections are read
from Factorio's belt graph, including splitter branches and paired underground
belts. It will not select a different component until every eligible entity in
the active component has been upgraded. A bright orange inner border plus a
wider translucent border highlights only the entities in the active component
that still require upgrading. Already-upgraded entities remain traversal links
but are not outlined. `/ub status` reports the number of upgradeable entities
remaining in that component.
Build, mining, destruction, rotation, robot-build, and script-raised events queue
an outline rebuild for the next bot tick; no periodic graph polling is used.
`/ub refresh` forces an immediate rebuild of the current track and its outline.

The bot's cargo capacity is configured in `config.lua` and is currently twenty
individual items, not twenty item types. It can collect a mixed batch of belts,
underground belts, and splitters, perform as many upgrades as that batch permits,
and then return all recovered items before collecting the next batch. When a
return container has no room, the bot stops upgrading and follows the player. A
red world-space border and an item-labelled chart tag mark the blocked container
on the map and minimap. The bot checks that destination for space and resumes the
return and upgrade workflow automatically when room becomes available.

Commands:

```text
/upgrade-bot on
/upgrade-bot off
/upgrade-bot task yellow-to-red-belts
/upgrade-bot tasks
/upgrade-bot status
/upgrade-bot refresh
```

`/ub` is a short alias. New jobs belong in `tasks.lua`; the bot engine does not
contain entity names. Each job has a name, optional aliases, and a `mappings`
table of source prototype names to target prototype names. A mapping may instead
be a table with `target`, `required_item`, `recovered_item`, and optional
`create_parameters(entity, player)` fields when an
entity has state that must be preserved. Jobs may also provide an
`execute(player, entity, mapping)` function for entirely non-standard upgrades.
