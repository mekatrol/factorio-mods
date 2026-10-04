# Long-Range Gun Turret

Adds a long range variant of the vanilla gun turret.

- Maximum range: 60 tiles (vanilla: 18; matches the long-range flamethrower)
- Damage modifier: 2 (twice normal damage)
- Ammunition: piercing (red) or uranium magazines; firearm (yellow) magazines are rejected
- Recipe: 1 standard gun turret and 2 engine units
- Technology: unlocked by Military 2

The mod reuses the vanilla graphics and tints their mask layers red, so it does
not duplicate Factorio's image assets.

The mod assigns yellow magazines a separate ammunition category and extends
ordinary bullet weapons to accept both categories. The long-range turret accepts
only the original category used by red and uranium magazines, so inserters leave
yellow magazines on their belt instead of loading and spilling them.

All mod-specific prototype names, balance values, appearance values, recipe
ingredients, crafting time, output, source-prototype selections, and ammunition
restriction are kept in `config.lua`.
