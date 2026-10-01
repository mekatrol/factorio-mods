# Long-Range Cannon

Adds a heavy, fully rotating defensive cannon with a maximum range of 112 tiles, matching the approximate live-coverage radius of a normal radar.

## Recipes

- Cannon: 10 steel plates, 5 engine units, 5 electronic circuits, and 3 advanced circuits.
- 10 rounds: 20 steel plates and 1 solid fuel (2 steel plates and 0.1 solid fuel per shot).

Both recipes unlock with Military 3. The cannon fires one round every three seconds, has a 12-tile minimum range, and deals explosive damage in a 3-tile blast radius.
The blast is restricted to enemy forces and will not damage allied buildings or players.
The cannon automatically targets only stationary enemy spawners and worm-style turrets in chunks that are currently visible to its force; it ignores enemies hidden by fog of war as well as mobile biters and spitters. It enforces the closest eligible target every game tick. Shells pass harmlessly over intervening structures and apply all impact effects only where the projectile lands.

Balance values and recipe ingredients can be changed in `config.lua`. Restart Factorio after editing the file.
