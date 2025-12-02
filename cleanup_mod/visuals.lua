----------------------------------------------------------------------
-- visuals.lua
--
-- All visual / rendering helpers for the cleanup bot.
-- Nothing in here affects gameplay; it only draws overlays
-- so you can see what the bot is doing.
----------------------------------------------------------------------
local visuals = {}

-- Must match "name" in info.json
local MOD_NAME = "cleanup_mod"

----------------------------------------------------------------------
-- Helper: safely clear ALL rendering objects created by this mod
-- for a given player state (pdata).
--
-- This is a blunt hammer used when disabling the bot or when
-- you suspect some rendering references might be stale.
----------------------------------------------------------------------

function visuals.force_clear_mod_objects(pdata)
    if not pdata then
        return
    end
    -- pcall protects against errors if rendering is not ready for some reason.
    pcall(rendering.clear, MOD_NAME)
end

----------------------------------------------------------------------
-- Internal helpers: clear individual kinds of overlays
----------------------------------------------------------------------

---------------------------------------------------
-- Helper to safely destroy a rendering object
---------------------------------------------------
local function destroy_render_handle(handle)
    if not handle then
        return
    end

    local t = type(handle)

    -- If it's a numeric id (normal case)
    if t == "number" then
        local ok, obj = pcall(rendering.get_object_by_id, handle)
        if ok and obj and obj.valid then
            obj.destroy()
        end
        return
    end

    -- If it's a rendering object/userdata from previous code
    if (t == "userdata" or t == "table") and handle.destroy then
        if handle.valid ~= false then
            handle:destroy()
        end
    end
end

local function clear_object(ref_name, pdata)
    local obj = pdata[ref_name]
    if obj and obj.valid then
        obj:destroy()
    end
    pdata[ref_name] = nil
end

local function clear_list(ref_name, pdata)
    local list = pdata[ref_name]
    if not list then
        return
    end
    for _, obj in pairs(list) do
        if obj and obj.valid then
            obj:destroy()
        end
    end
    pdata[ref_name] = nil
end

----------------------------------------------------------------------
-- Clear higher-level groups
----------------------------------------------------------------------

function visuals.clear_bot_highlight(pdata)
    clear_object("vis_bot_highlight", pdata)
end

function visuals.clear_chest_highlight(pdata)
    clear_object("vis_chest_highlight", pdata)
end

function visuals.clear_bot_line(pdata)
    if not pdata then
        return
    end

    local list = pdata.vis_bot_lines
    if list then
        for _, obj in pairs(list) do
            if obj and obj.valid then
                obj:destroy()
            end
        end
    end

    -- IMPORTANT: leave an empty table instead of nil
    pdata.vis_bot_lines = {}
end

function visuals.clear_status_text(pdata)
    clear_object("vis_status_text", pdata)
end

----------------------------------------------------------------------
-- Draw a simple rectangle around the bot.
--
-- bot_highlight_y_offset:
--   vertical offset applied to the rectangle to keep it visually
--   aligned if your bot sprite is tall or offset.
----------------------------------------------------------------------

function visuals.draw_bot_highlight(bot, pdata, has_unplaceable)
    if not (bot and bot.valid) then
        visuals.clear_bot_highlight(pdata)
        return
    end

    local color
    if has_unplaceable then
        -- Rule 4: bright red rectangle when container cannot be found.
        color = {
            r = 1.0,
            g = 0.1,
            b = 0.1,
            a = 0.6
        }
    else
        color = {
            r = 0.2,
            g = 0.2,
            b = 0.0,
            a = 0.2
        }
    end

    local pos = bot.position
    local size = 0.6

    local ui_y = pos.y
    local left_top = {pos.x - size, ui_y - size}
    local right_bottom = {pos.x + size, ui_y + size}

    if pdata.vis_bot_highlight and pdata.vis_bot_highlight.valid then
        pdata.vis_bot_highlight.left_top = left_top
        pdata.vis_bot_highlight.right_bottom = right_bottom
        return
    end

    pdata.vis_bot_highlight = rendering.draw_rectangle {
        color = color,
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }
end

---------------------------------------------------
-- Bright-blue search radius circle around the bot
---------------------------------------------------
function visuals.update_search_radius_circle(player, pdata, bot, radius)
    -- Destroy old circle if it exists (handles both id and object)
    if pdata.vis_search_radius_circle then
        destroy_render_handle(pdata.vis_search_radius_circle)
        pdata.vis_search_radius_circle = nil
    end

    if not (bot and bot.valid) then
        return
    end

    -- Draw a new bright-blue circle, anchored to the bot
    local id = rendering.draw_circle {
        color = {
            r = 0.2,
            g = 0.2,
            b = 0,
            a = 0.1
        }, -- bright blue
        radius = radius,
        width = 4,
        filled = true,
        target = bot, -- anchor so it follows the bot
        surface = bot.surface,
        players = {player},
        draw_on_ground = true
    }

    -- Store the numeric id
    pdata.vis_search_radius_circle = id
end

function visuals.clear_search_radius_circle(pdata)
    if pdata.vis_search_radius_circle then
        destroy_render_handle(pdata.vis_search_radius_circle)
        pdata.vis_search_radius_circle = nil
    end
end

----------------------------------------------------------------------
-- Draw a rectangle around the storage chest the bot is using.
----------------------------------------------------------------------

function visuals.draw_chest_highlight(chest, pdata, chest_highlight_y_offset)
    if not (chest and chest.valid) then
        visuals.clear_chest_highlight(pdata)
        return
    end

    local pos = chest.position
    local size = 0.6
    local ui_y = pos.y + (chest_highlight_y_offset or 0)

    local left_top = {pos.x - size, ui_y - size}
    local right_bottom = {pos.x + size, ui_y + size}

    if pdata.vis_chest_highlight and pdata.vis_chest_highlight.valid then
        pdata.vis_chest_highlight.left_top = left_top
        pdata.vis_chest_highlight.right_bottom = right_bottom
        return
    end

    pdata.vis_chest_highlight = rendering.draw_rectangle {
        color = {
            r = 0.0,
            g = 0.8,
            b = 0.8,
            a = 0.2
        },
        filled = false,
        width = 2,
        left_top = left_top,
        right_bottom = right_bottom,
        surface = chest.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }
end

----------------------------------------------------------------------
-- Draw a line between the player and the bot to show the link
-- and give a quick visual hint of what the bot is doing.
--
-- mode is a string:
--   "pickup"    – bot is heading for items
--   "returning" – bot is heading back to chest
--   "roam"      – bot is wandering
--   "idle"      – bot is near the player with nothing to do
----------------------------------------------------------------------

function visuals.draw_bot_player_line(player, bot, pdata, mode)
    if not (player and player.valid and bot and bot.valid and pdata) then
        return
    end

    -- Ensure table exists and is empty
    visuals.clear_bot_line(pdata)
    pdata.vis_bot_lines = pdata.vis_bot_lines or {}

    local color
    if mode == "pickup" then
        color = {
            r = 0.2,
            g = 1.0,
            b = 0.2,
            a = 0.6
        }
    elseif mode == "returning" then
        color = {
            r = 1.0,
            g = 0.8,
            b = 0.1,
            a = 0.6
        }
    elseif mode == "roam" then
        color = {
            r = 0.3,
            g = 0.3,
            b = 1.0,
            a = 0.4
        }
    else
        color = {
            r = 0.6,
            g = 0.6,
            b = 0.6,
            a = 0.3
        }
    end

    local line = rendering.draw_line {
        color = color,
        width = 1,
        from = player.position,
        to = bot.position,
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }

    pdata.vis_bot_lines[#pdata.vis_bot_lines + 1] = line
end

----------------------------------------------------------------------
-- Small status text underneath the bot:
--   shows mode and how many items are currently carried.
----------------------------------------------------------------------

function visuals.draw_status_text(bot, pdata, mode, carried_count, max_capacity)
    if not (bot and bot.valid) then
        visuals.clear_status_text(pdata)
        return
    end

    local pos = bot.position
    local ui_y = pos.y

    local has_unplaceable = pdata.unplaceable_items and next(pdata.unplaceable_items) ~= nil
    local count = carried_count or 0
    local cap = max_capacity or count

    local text
    if has_unplaceable then
        -- Show which items cannot be placed
        local names = {}
        for name, _ in pairs(pdata.unplaceable_items) do
            names[#names + 1] = name
        end
        table.sort(names)
        local list = table.concat(names, ", ")
        text = string.format("NO CONTAINER: %s", list)
    elseif count > 0 then
        -- Always show the live count while carrying anything
        text = string.format("Carrying: %d/%d", count, cap)
    else
        -- Nothing carried
        text = string.format("[%s] items: %d", mode or "idle", 0)
    end

    local Y_OFFSET = 0.8

    if pdata.vis_status_text and pdata.vis_status_text.valid then
        pdata.vis_status_text.target = {
            x = pos.x,
            y = ui_y + Y_OFFSET
        }
        pdata.vis_status_text.text = text
        return
    end

    pdata.vis_status_text = rendering.draw_text {
        text = text,
        surface = bot.surface,
        target = {
            x = pos.x,
            y = ui_y + Y_OFFSET
        },
        color = {
            r = 1,
            g = 1,
            b = 1,
            a = 1
        },
        scale = 0.7,
        draw_on_ground = true,
        alignment = "center",
        only_in_alt_mode = false
    }
end

----------------------------------------------------------------------
-- Line from bot to its current target position.
--
-- We only show this in "pickup" mode; in other modes it is cleared.
----------------------------------------------------------------------
function visuals.draw_target_line(bot, pdata, target_pos, mode)
    if not pdata then
        return
    end

    -- If no valid target or wrong mode, just clear any existing line.
    if mode ~= "pickup" or not (bot and bot.valid and target_pos) then
        visuals.clear_target_line(pdata)
        return
    end

    local from_pos = bot.position
    local to_pos = target_pos

    -- Color: reddish to indicate "hunting items"
    local color = {
        r = 1.0,
        g = 0.2,
        b = 0.2,
        a = 0.7
    }

    if pdata.vis_target_line and pdata.vis_target_line.valid then
        -- Update existing line
        pdata.vis_target_line.from = from_pos
        pdata.vis_target_line.to = to_pos
        pdata.vis_target_line.color = color
        return
    end

    -- Create new line
    pdata.vis_target_line = rendering.draw_line {
        color = color,
        width = 1,
        from = from_pos,
        to = to_pos,
        surface = bot.surface,
        draw_on_ground = true,
        only_in_alt_mode = false
    }
end

function visuals.clear_target_line(pdata)
    clear_object("vis_target_line", pdata)
end

----------------------------------------------------------------------
-- Master reset for all visuals associated with this player’s bot.
----------------------------------------------------------------------

function visuals.clear_all(pdata)
    if not pdata then
        return
    end

    visuals.clear_bot_highlight(pdata)
    visuals.clear_chest_highlight(pdata)
    visuals.clear_search_radius_circle(pdata)
    visuals.clear_bot_line(pdata)
    visuals.clear_status_text(pdata)
    visuals.clear_target_line(pdata)
end

return visuals
