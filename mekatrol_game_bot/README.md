# Upgrade Bot

This mod contains five independently controlled helpers. The general upgrade bot uses
`Ctrl+Shift+U` and `/ub`, the cleanup bot uses `Ctrl+Shift+C` and `/cb`, and the
lamp bot uses `Ctrl+Shift+L` and `/lb`. The progressive track bot uses
`Ctrl+Shift+T` and `/tb`. The cliff bot uses `Ctrl+Shift+D` and `/db`. When idle,
all five use separate
formation slots and switch to the trailing side when the player changes
horizontal direction, matching `mekatrol_game_play_mod`.

Press `Ctrl+Alt+D`, use the cliff-explosives toolbar button, or run `/db mark`
to take the cliff destruction planner,
then drag it over cliffs to queue them. Reverse-drag removes cliffs from the
queue. Marking a cliff automatically enables the bot, and `/db clear` clears
the queue. The bot visibly flies to each marked cliff and launches Factorio's
normal cliff-explosives projectile, including its explosion and terrain effects.

The track bot upgrades connected transport belts, underground belts, and
splitters near the player in strict yellow -> red -> blue -> green order. It
does not enter a stage until the prior colour is complete in the active area,
and it waits when the next colour's recipe has not been researched. Green means
the optional turbo tier; without those prototypes the final stage remains idle.

`Ctrl+Shift+U` toggles the general upgrade bot. Track work is intentionally not
part of its task list.
It does not create replacement items. For targets inside a player-force
roboport construction area, the bot first asks that logistic network for the
required item using Factorio's provider/storage/buffer source selection. It
flies to the selected source, removes one item, and carries it to the target.
If the logistic network cannot supply an item, the bot also searches ordinary
and logistic player-owned containers within 64 tiles of either the target or
the bot. This lets the player lead the following bot to a supply chest even
when the locked track is farther away, and also allows a nearby logistic chest
to supply a target outside its network's construction area. Logistic-network
supply still has priority. After a network-backed upgrade, the bot carries the removed
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

The bot's shared upgrade cargo capacity is configured once in `config.lua` and
is currently 100 individual items, not 100 item types. It can collect a mixed batch of belts,
underground belts, and splitters, perform as many upgrades as that batch permits,
and then return all recovered items before collecting the next batch. When a
yellow underground-belt pair is still connected, the bot reserves and carries
both replacement belts before upgrading either endpoint. It then completes the
remembered second endpoint even when replacing the first temporarily removes the
pair from Factorio's live belt graph. When a
return container has no room, the bot stops upgrading and follows the player. A
red world-space border and an item-labelled chart tag mark the blocked container
on the map and minimap. The bot checks that destination for space and resumes the
return and upgrade workflow automatically when room becomes available.

Commands:

```text
/ub                         (cycle upgrade mode)
/upgrade-bot on
/upgrade-bot off
/upgrade-bot task all
/upgrade-bot tasks
/upgrade-bot status
/upgrade-bot refresh
```

The built-in general upgrade modes are `All upgrades`, `Blue -> Green arms`,
and `Containers` (wooden to iron, then iron to steel).
`/ub` cycles upgrade modes; it also remains a short alias when followed by a
command. New jobs belong in `tasks.lua`; the bot engine does not contain entity
names.

The progressive track helper deliberately has no manual task selector:

```text
/tb
/track-upgrade-bot on
/track-upgrade-bot off
/track-upgrade-bot status
/track-upgrade-bot refresh
```

## Lamp bot

The independently controlled lamp bot follows the player when idle and only
works outside full daylight (during dusk, night, and dawn). It uses lamps from
the player's inventory. If none are carried, it collects up to
`lamp_pickup_count` lamps
(50 by default) from a red passive-provider chest anywhere on the current
surface, choosing the closest one that contains lamps. The batch is limited by
the lamps in the chest and free space in the player's main inventory, where the
bot holds them while working. The bot flies to the chest and each
selected location before placing its lamp, and places at most one lamp per scan in
a buildable spot covered by an electric pole and outside the lit radius of any
existing lamp. The next scan includes the newly placed lamp, preventing the bot
from filling the area that lamp has just illuminated. Its current activity is
displayed underneath the bot.

```text
/lb
/lamp-bot on
/lamp-bot off
/lamp-bot toggle
/lamp-bot status
```

Each upgrade job has a name, optional aliases, and a `mappings`
table of source prototype names to target prototype names. A mapping may instead
be a table with `target`, `required_item`, `recovered_item`, and optional
`create_parameters(entity, player)` fields when an
entity has state that must be preserved. Jobs may also provide an
`execute(player, entity, mapping)` function for entirely non-standard upgrades.
The `All upgrades` mode automatically includes every registered general mapping.
The track helper locks onto one connected belt network at a time. Other upgrades
are handled one entity at a time. Each helper uses its own 100-item mixed cargo limit and exhausts locally
usable cargo before it returns recovered items or plans another supply collection.
Discovery advances through small map cells over successive ticks to find the
nearest next target without doing an unbounded planning pass in one update.
If unrelated cargo fills the hold and prevents required pickups, the bot first
places a batch of surplus items into the nearest red passive-provider chest,
limited by the blocked batch size and the chest's available capacity.
Targets are only highlighted or planned when the owning force has unlocked the
recipe for the required upgrade item. Research changes are rechecked before the
replacement is executed.

Lamp-bot settings are grouped together in `config.lua`. Change
`lamp_pickup_count` there to adjust the maximum number of lamps collected per
supply trip.

`Blue -> Green arms` upgrades fast inserters to bulk inserters only when the
target is within 10 tiles of the player. It takes bulk inserters from the
player's inventory first, then from the nearest stocked red passive-provider
chest on the current surface; other chest types and logistic-network sources
are not used for this mode.
If a selected provider empties during a batch, the bot immediately replans the
remaining pickups and can continue from another provider anywhere on the surface.

## Cleanup bot

The cleanup bot collects ground item entities within 12 tiles until its
100-item cargo is full. It deposits each item into the nearest player-owned
container that already holds that item, falling back to the player's inventory.
If neither destination has room, it keeps the cargo and follows the player.

```text
/cb on
/cb off
/cb toggle
/cb status
```
