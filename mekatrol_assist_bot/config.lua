-- Mekatrol Assist Bot configuration root.
--
-- User-tunable settings will be migrated here as each legacy bot is ported.
-- Every setting must document its purpose, units, valid range, and disabling
-- behavior before it becomes part of the public configuration surface.
return {
    -- Configuration schema used by validation and save migrations.
    -- Valid range: positive integer. Increment when configuration semantics
    -- change incompatibly; ordinary value tuning does not require a change.
    schema_version = 1
}
