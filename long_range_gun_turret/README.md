# Long-Range Gun Turret

Adds a long range variant of the vanilla gun turret.

- Maximum range: 60 tiles (vanilla: 18; matches the long-range flamethrower)
- Damage modifier: 2 (twice normal damage)
- Ammunition: piercing (red) or uranium magazines; firearm (yellow) magazines are rejected
- Recipe: 1 standard gun turret and 2 engine units
- Technology: unlocked by Military 2

The mod reuses the vanilla graphics and tints their mask layers red, so it does
not duplicate Factorio's image assets.

Factorio groups yellow, red, and uranium magazines into one ammunition category.
A small runtime check returns yellow magazines to the ground beside the turret,
allowing the new turret to enforce the red-or-better ammunition requirement
without changing the behaviour of vanilla weapons or ammunition.

All mod-specific prototype names, balance values, appearance values, recipe
ingredients, crafting time, output, source-prototype selections, and ammunition
restriction are kept in `config.lua`.
