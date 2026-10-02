-- Bounded builder/logistics primitives. This module owns no global state: callers
-- persist cursors so inventory transfer and resource harvesting resume after load.
local M = {}

---Selects the first deterministic placement product from prototype metadata.
---Exposed separately so pure tests can validate modded multi-product metadata.
function M.first_product_name(products, fallback)
    local first = products and products[1]
    return first and first.name or fallback
end

---Returns the item prototype name required to revive an entity ghost.
---Falls back to the ghost name for compatibility with simple modded entities.
function M.placement_item(ghost)
    if not (ghost and ghost.valid and ghost.type == "entity-ghost") then
        return nil
    end
    local prototype = ghost.ghost_prototype
    local products = prototype and prototype.items_to_place_this
    return M.first_product_name(products, ghost.ghost_name)
end

---Returns whether an entity matches an optional pickup name.
function M.matches_pickup(entity, name)
    if not name then
        return true
    end
    if entity.type == "item-entity" then
        local stack = entity.stack
        return stack and stack.valid_for_read and stack.name == name
    end
    if entity.type == "resource" then
        local products = entity.prototype and entity.prototype.mineable_properties and
                             entity.prototype.mineable_properties.products
        return (products and products[1] and products[1].name == name) or entity.name == name
    end
    return entity.name == name
end

return M
