local constants = require("constants")

-- Ordered stages are the progression contract: the controller only advances
-- after a complete local scan finds no source entities for the current colour.
return {{
    name = "yellow-to-red-tracks", label = "Tracks: Yellow -> Red", progressive_tracks = true,
    grouping = constants.GROUP_STRATEGY.BELT_NETWORK,
    mappings = {
        -- Each mapping names both consumed and recovered inventory items.
        ["transport-belt"] = {target="fast-transport-belt", required_item="fast-transport-belt", recovered_item="transport-belt"},
        ["underground-belt"] = {target="fast-underground-belt", required_item="fast-underground-belt", recovered_item="underground-belt", create_parameters=function(e) return {type=e.belt_to_ground_type} end},
        ["splitter"] = {target="fast-splitter", required_item="fast-splitter", recovered_item="splitter"}
    }
}, {
    name = "red-to-blue-tracks", label = "Tracks: Red -> Blue", progressive_tracks = true,
    grouping = constants.GROUP_STRATEGY.BELT_NETWORK,
    mappings = {
        -- Underground endpoint roles are preserved during fast replacement.
        ["fast-transport-belt"] = {target="express-transport-belt", required_item="express-transport-belt", recovered_item="fast-transport-belt"},
        ["fast-underground-belt"] = {target="express-underground-belt", required_item="express-underground-belt", recovered_item="fast-underground-belt", create_parameters=function(e) return {type=e.belt_to_ground_type} end},
        ["fast-splitter"] = {target="express-splitter", required_item="express-splitter", recovered_item="fast-splitter"}
    }
}, {
    -- Turbo (green) belts exist when Space Age or another compatible mod adds
    -- their prototypes. Missing prototypes/recipes leave this stage safely idle.
    name = "blue-to-green-tracks", label = "Tracks: Blue -> Green", progressive_tracks = true,
    grouping = constants.GROUP_STRATEGY.BELT_NETWORK,
    mappings = {
        -- Prototype checks in the registry make every optional mapping safe.
        ["express-transport-belt"] = {target="turbo-transport-belt", required_item="turbo-transport-belt", recovered_item="express-transport-belt"},
        ["express-underground-belt"] = {target="turbo-underground-belt", required_item="turbo-underground-belt", recovered_item="express-underground-belt", create_parameters=function(e) return {type=e.belt_to_ground_type} end},
        ["express-splitter"] = {target="turbo-splitter", required_item="turbo-splitter", recovered_item="express-splitter"}
    }
}}
