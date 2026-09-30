local executor = {}

-- This is the default replacement strategy. A future task may provide an
-- `execute(player, entity, mapping)` function to replace this behavior.
function executor.execute(player, entity, mapping, task)
    local target_name = mapping and mapping.target

    -- Validate before invoking either execution strategy. Custom task handlers
    -- must never receive an entity that was destroyed after it was scheduled.
    if not (entity and entity.valid) then return false, "invalid source entity" end
    -- A task-owned executor is an escape hatch for upgrades that cannot be
    -- represented as a normal fast replacement. The scheduler remains generic.
    if task.execute then
        return task.execute(player, entity, mapping)
    end
    if not (target_name and prototypes.entity[target_name]) then
        return false, "invalid target prototype"
    end

    -- Fast replacement preserves connections and operational state far more
    -- faithfully than destroying the source and creating an unrelated entity.
    local parameters = {
        name = target_name,
        position = entity.position,
        direction = entity.direction,
        force = entity.force,
        -- Do not pass `player`: Factorio would then simulate a player fast
        -- replacement and could consume or return items via their inventory.
        -- Supply and recovered items are accounted for by the bot itself.
        fast_replace = true,
        spill = false,
        raise_built = true
    }
    if mapping.create_parameters then
        -- Entity families can contribute only their exceptional construction
        -- fields, such as an underground belt's input/output role.
        for key, value in pairs(mapping.create_parameters(entity, player) or {}) do
            parameters[key] = value
        end
    end

    -- Creating the replacement is the commit point. Cargo is adjusted by the
    -- caller only after this call reports success.
    local replacement = entity.surface.create_entity(parameters)
    if replacement and replacement.valid then return true, replacement end
    return false, "fast replacement failed"
end

return executor
