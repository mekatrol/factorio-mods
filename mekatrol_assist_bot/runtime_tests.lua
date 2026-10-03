-- Opt-in integration fixture. It exercises real Factorio objects when config.debug is true.
local config = require("config")
local state = require("state")
local manager = require("bot_manager")
local scheduler = require("scheduler")
local scanner = require("entity_scanner")
local constants = require("constants")
local formation = require("formation")
local movement = require("movement")
local migrations = require("migrations")
local M = {}

---Attempt fixture entity creation without allowing a prototype error to abort setup.
local function create(surface, params)
    local ok, e = pcall(surface.create_entity, params);
    return ok and e or nil
end

---Assert that required vanilla and generated prototypes exist with expected types.
local function validate_catalogue()
    for _, name in ipairs {"construction-robotics", "logistic-robotics", "repair-pack", "lamp", "cliff-explosives", "electronics"} do
        assert(prototypes.technology[name], "MAB prototype catalogue missing technology: " .. name)
    end
    for _, name in ipairs {"construction-robot", "logistic-robot", "repair-pack", "small-lamp", "cliff-explosives",
                           "transport-belt", "fast-transport-belt", "express-transport-belt", "turbo-transport-belt"} do
        assert(prototypes.item[name] or prototypes.entity[name], "MAB prototype catalogue missing item/entity: " .. name)
    end
    for _, role in ipairs(config.formation.role_order) do
        local expected_type = config.roles[role].prototype_family .. "-robot"
        for _, visual in ipairs{"idle", "moving", "working"} do
            local name = constants.prototype(role, visual)
            local prototype = assert(prototypes.entity[name], "MAB missing visual prototype: " .. name)
            assert(prototype.type == expected_type,
                "MAB visual prototype family mismatch: " .. name .. " is " .. prototype.type)
        end
    end
end

---Exercise prototype creation and movement when no player character is available.
local function run_headless_baseline()
    local surface = game.surfaces[1];
    local slots = formation.slots(config.formation.role_order, 1);
    local bots = {}
    for _, role in ipairs(config.formation.role_order) do
        bots[#bots + 1] = assert(create(surface, {
            name = constants.prototype(role, "moving"),
            position = {0, 0},
            force = "neutral"
        }), "MAB baseline could not create role bot: " .. role)
    end
    local bot_profiler = game.create_profiler()
    for tick = 1, 900 do
        for i, role in ipairs(config.formation.role_order) do
            local slot = slots[role];
            movement.step(bots[i], {
                x = slot.x + (tick % 120 < 60 and 8 or -8),
                y = slot.y
            })
        end
    end
    bot_profiler.stop()
    log("[MAB baseline] ten role bots, 900 movement ticks (next line)")
    log(bot_profiler)

    local field_surface = game.create_surface("mab-baseline-field", {});
    for x = 0, 63 do
        for y = 0, 63 do
            create(field_surface, {
                name = "iron-ore",
                position = {x, y},
                amount = 1000
            })
        end
    end
    local field_scan = scanner.start_area(field_surface, {{0, 0}, {64, 64}}, {
        type = "resource"
    });
    local field_profiler = game.create_profiler();
    local field_steps = 0;
    local field_entities = 0
    repeat
        local done, found = scanner.step(field_scan);
        field_steps = field_steps + 1;
        field_entities = field_entities + #found
    until done
    field_profiler.stop()
    assert(field_entities >= 4096, "MAB large-field scan missed resource entities")
    log("[MAB baseline] 4096-resource bounded scan, " .. field_steps .. " work units (next line)")
    log(field_profiler)
    log("[MAB test] consolidated fixture passed on Factorio " .. script.active_mods.base)
end

---Create the opt-in in-world integration fixture and remember its entities.
function M.seed()
    if not config.debug then
        return
    end
    do
        local fixture_index = 9001
        state.root().phase2_headless_fixture = fixture_index
        storage.mekatrol_game_bot = {
            players = {[fixture_index] = {enabled = true, task_name = "combined"}},
            track_players = {[fixture_index] = {enabled = true, task_name = "track"}},
            cleanup_players = {},
            lamp_players = {},
            cliff_players = {}
        }
        storage.mekatrol_game_play_bot = {[fixture_index] = {bot_enabled = true}}
        local mapped = create(game.surfaces[1], {
            name = "stone",
            position = {9001, 9001},
            amount = 100
        })
        storage.mapping_bot_mod = {
            players = {[fixture_index] = {mapping_bot_enabled = true}},
            shared_mapped_entities = {mapped}
        }
        storage.mekatrol_repair_mod = {players = {[fixture_index] = {repair_bot_enabled = true}}}
        return
    end
    -- The multiplayer integration fixture below is retained for a later phase,
    -- when it can be driven by real connected players rather than removed APIs.
    local player = game.create_player {
        name = "mab-integration-test"
    };
    player.teleport({0, 0}, game.surfaces[1])
    local mapped = create(player.surface, {
        name = "stone",
        position = {2, 2},
        amount = 100
    })
    local second_surface = game.create_surface("mab-test-surface", {});
    local second = game.create_player {
        name = "mab-integration-test-2"
    };
    second.teleport({0, 0}, second_surface)
    storage.mekatrol_game_bot = {
        players = {
            [player.index] = {
                enabled = true,
                task_name = "combined"
            }
        },
        track_players = {},
        cleanup_players = {},
        lamp_players = {},
        cliff_players = {}
    }
    storage.mapping_bot_mod = {
        players = {
            [player.index] = {
                mapping_bot_enabled = true
            }
        },
        shared_mapped_entities = {mapped}
    }
end

---Advance/assert the integration scenario, cleaning it up when complete.
function M.run()
    if not config.debug then
        return
    end
    validate_catalogue()
    local fixture_index = state.root().phase2_headless_fixture
    if fixture_index then
        local fixture = state.player(fixture_index)
        assert(state.root().import_complete, "MAB legacy migration did not complete")
        assert(fixture.roles.upgrade.enabled and fixture.roles.upgrade.task == "combined",
            "MAB game-bot upgrade state was not imported")
        assert(fixture.roles.track.enabled and fixture.roles.track.task == "track",
            "MAB game-bot track state was not imported")
        assert(fixture.roles.builder.enabled and fixture.roles.logistics.enabled and fixture.roles.surveyor.enabled,
            "MAB gameplay group state was not imported")
        assert(fixture.roles.mapper.enabled, "MAB mapping state was not imported")
        assert(fixture.roles.repair.enabled, "MAB repair state was not imported")
        local steps = 0
        while state.root().migration and not state.root().migration.done and steps < 32 do
            migrations.step()
            steps = steps + 1
        end
        assert(state.root().migration.done, "MAB bounded migration fixture did not finish")
        assert(#state.root().discovery.order == 1, "MAB mapping records were not imported")
        run_headless_baseline()
        return
    end
    local player = game.get_player("mab-integration-test");
    assert(player, "MAB migration fixture player missing");
    player.force.research_all_technologies()
    local second = game.get_player("mab-integration-test-2");
    second.force.research_all_technologies()
    local mapped_event = remote.call("mapping_bot_mod", "get_event");
    local clear_event = remote.call("mapping_bot_mod", "get_clear_event");
    script.on_event(mapped_event, function()
        state.root().test_mapped_event = true
    end);
    script.on_event(clear_event, function()
        state.root().test_clear_event = true
    end)
    local inv = player.get_main_inventory()
    for _, s in ipairs {{"transport-belt", 100}, {"express-transport-belt", 100}, {"iron-chest", 20},
                        {"small-lamp", 20}, {"cliff-explosives", 20}} do
        if prototypes.item[s[1]] then
            inv.insert {
                name = s[1],
                count = s[2]
            }
        end
    end
    local surface = player.surface
    surface.freeze_daytime = true;
    surface.daytime = 0.5
    local source = create(surface, {
        name = "steel-chest",
        position = {3, 8},
        force = player.force
    });
    local source_inv = source.get_inventory(defines.inventory.chest);
    source_inv.insert {
        name = "fast-transport-belt",
        count = 100
    };
    source_inv.insert {
        name = "repair-pack",
        count = 20
    };
    source_inv.insert {
        name = "wooden-chest",
        count = 5
    }
    local sorted = create(surface, {
        name = "iron-chest",
        position = {3, 4},
        force = player.force
    });
    sorted.get_inventory(defines.inventory.chest).insert {
        name = "iron-plate",
        count = 1
    }
    local damaged = create(surface, {
        name = "assembling-machine-1",
        position = {8, 0},
        force = player.force
    });
    if damaged then
        damaged.health = math.max(1, damaged.health - 20)
    end
    for y = -4, 4 do
        create(surface, {
            name = "stone-wall",
            position = {4, y},
            force = player.force
        })
    end
    for x = 10, 20 do
        create(surface, {
            name = "transport-belt",
            position = {x, 2},
            force = player.force,
            direction = defines.direction.east
        })
    end
    create(surface, {
        name = "underground-belt",
        position = {10, 5},
        force = player.force,
        direction = defines.direction.east,
        type = "input"
    });
    create(surface, {
        name = "underground-belt",
        position = {15, 5},
        force = player.force,
        direction = defines.direction.east,
        type = "output"
    })
    local loose = create(surface, {
        name = "item-on-ground",
        position = {4, 2},
        stack = {
            name = "iron-plate",
            count = 10
        }
    })
    create(surface, {
        name = "medium-electric-pole",
        position = {5, 5},
        force = player.force
    })
    create(surface, {
        name = "iron-ore",
        position = {12, 12},
        amount = 1000
    })
    local ghost = create(surface, {
        name = "entity-ghost",
        inner_name = "wooden-chest",
        position = {7, 7},
        force = player.force
    })
    for _, role in ipairs(config.formation.role_order) do
        local ok, why = manager.enable(player.index, role, true);
        if not ok then
            error("MAB integration enable " .. role .. ": " .. tostring(why))
        end
    end
    local repair_state = state.player(player.index).roles.repair
    repair_state.entity.health = math.max(1, repair_state.entity.max_health - 10)
    for _, role in ipairs(config.formation.role_order) do
        assert(manager.enable(second.index, role, true), "MAB second-player enable failed: " .. role)
    end
    local bot_profiler = game.create_profiler()
    for tick = 1, 900 do
        scheduler.tick {
            tick = tick
        }
    end
    bot_profiler.stop()
    log("[MAB baseline] ten roles x two players, 900 scheduler ticks: " .. tostring(bot_profiler))

    local field_surface = game.create_surface("mab-baseline-field", {});
    for x = 0, 63 do
        for y = 0, 63 do
            create(field_surface, {
                name = "iron-ore",
                position = {x, y},
                amount = 1000
            })
        end
    end
    local field_scan = scanner.start_area(field_surface, {{0, 0}, {64, 64}}, {
        type = "resource"
    });
    local field_profiler = game.create_profiler();
    local field_steps = 0;
    local field_entities = 0
    repeat
        local done, found = scanner.step(field_scan);
        field_steps = field_steps + 1;
        field_entities = field_entities + #found
    until done
    field_profiler.stop()
    assert(field_entities >= 4096, "MAB large-field scan missed resource entities")
    log("[MAB baseline] 4096-resource bounded scan, " .. field_steps .. " work units: " .. tostring(field_profiler))
    assert(state.root().import_complete and state.player(player.index).roles.mapper.enabled,
        "MAB legacy migration did not import")
    for _, role in ipairs(config.formation.role_order) do
        local rs = state.player(player.index).roles[role];
        assert(rs.entity and rs.entity.valid, "MAB integration bot invalid: " .. role)
    end
    for _, role in ipairs(config.formation.role_order) do
        local rs = state.player(second.index).roles[role];
        assert(rs.entity and rs.entity.valid and rs.entity.surface == second.surface,
            "MAB second-player surface invalid: " .. role)
    end
    assert(not loose.valid or loose.stack.count < 10, "MAB integration cleanup did not collect")
    assert(not ghost.valid, "MAB integration builder did not revive ghost")
    assert(not damaged.valid or damaged.health >= damaged.max_health, "MAB integration repair did not heal")
    assert(repair_state.entity.valid and repair_state.entity.health >= repair_state.entity.max_health *
        config.tasks.repair.self_repair_threshold, "MAB repair bot did not self-repair")
    assert((repair_state.repair_health_pool or 0) > 0,
        "MAB repair pack durability was not retained as a partial persistent pool")
    assert(surface.count_entities_filtered {
        area = {{9, 1}, {21, 3}},
        name = "transport-belt"
    } < 11, "MAB integration upgrade did not replace belts")
    assert(surface.count_entities_filtered {
        area = {{9, 4}, {16, 6}},
        name = "underground-belt"
    } < 2, "MAB underground pair was not upgraded")
    assert(source_inv.get_item_count("fast-transport-belt") < 100 and source_inv.get_item_count("repair-pack") < 20,
        "MAB container sourcing was not used")
    assert(sorted.get_inventory(defines.inventory.chest).get_item_count("iron-plate") > 1,
        "MAB cleanup did not sort into matching container")
    assert(surface.count_entities_filtered {
        area = {{-16, -16}, {32, 32}},
        name = "small-lamp"
    } > 0, "MAB lamp role placed no lamp")
    assert(#state.root().discovery.order > 0, "MAB integration mapper discovered nothing")
    local has_polygon = false;
    for _, g in pairs(state.root().discovery.groups) do
        if g.polygon and #g.polygon >= 3 then
            has_polygon = true
            break
        end
    end
    assert(has_polygon, "MAB surveyor produced no polygon group")
    local snapshot = remote.call("mapping_bot_mod", "get_mapped_entities");
    assert(#snapshot > 0 and snapshot[1].entity == nil, "MAB compatibility snapshot leaked entity references")
    local cleanup = state.player(player.index).roles.cleanup;
    cleanup.entity.destroy();
    scheduler.tick {
        tick = 901
    };
    assert(cleanup.entity and cleanup.entity.valid, "MAB destroyed bot was not recreated")
    player.force.technologies["construction-robotics"].researched = false;
    manager.enforce_gates();
    assert(not state.player(player.index).roles.builder.enabled, "MAB research reversal did not recall builder")
    player.force.technologies["construction-robotics"].researched = true;
    assert(manager.enable(player.index, "builder", true), "MAB research regain did not permit builder")
    assert(state.root().test_mapped_event, "MAB mapping event was not raised");
    remote.call("mapping_bot_mod", "clear_mapped_entities");
    assert(state.root().test_clear_event and #state.root().discovery.order == 0, "MAB clear event/state failed");
    script.on_event(mapped_event, nil);
    script.on_event(clear_event, nil)
    log("[MAB test] consolidated fixture passed on Factorio " .. script.active_mods.base)
end

return M
