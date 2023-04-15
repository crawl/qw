------------------
-- Debug functions

function set_gameplans(str)
    override_gameplans = str
    initialized = false
    update_coroutine = coroutine.create(turn_update)
    run_update()
end

function restore_gameplans()
    override_gameplans = nil
    initialized = false
    update_coroutine = coroutine.create(turn_update)
    run_update()
end

function initialize_debug()
    if not DEBUG_MODE then
        return
    end

    debug_channels = {}
    for _, channel in ipairs(DEBUG_CHANNELS) do
        debug_channels[channel] = true
    end
end

function toggle_debug()
    DEBUG_MODE = not DEBUG_MODE
end

function toggle_debug_channel(channel)
    debug_channels[channel] = not debug_channels[channel]
end

function debug_channel(channel)
    return DEBUG_MODE and debug_channels[channel]
end

function dsay(x, channel)
    if not channel then
        channel = "main"
    end

    local str
    if type(x) == "table" then
        str = stringify_table(x)
    else
        str = tostring(x)
    end
    -- Convert x to string to make debugging easier. We don't do this for
    -- say() and note() so we can catch errors.
    crawl.mpr(you.turns() .. " ||| " .. str)
end
function toggle_coroutine()
    USE_COROUTINE = not USE_COROUTINE
end

function test_radius_iter()
    dsay("Testing 3, 3 with radius 1")
    for pos in radius_iter({ x = 3, y = 3 }, 1) do
        dsay("x: " .. tostring(pos.x) .. ", y: " .. tostring(pos.y))
    end

    dsay("Testing origin with radius 3")
    for pos in radius_iter(origin, 3) do
        dsay("x: " .. tostring(pos.x) .. ", y: " .. tostring(pos.y))
    end
end

--------------------------------
-- a function to test various things conveniently
function ttt()
    for i = -los_radius, los_radius do
        for j = -los_radius, los_radius do
            m = monster.get_monster_at(i, j)
            if m then
                crawl.mpr("(" .. i .. "," .. j .. "): name = " .. m:name()
                    .. ", desc = " .. m:desc() .. ".")
            end
        end
    end
    --for it in inventory() do
    --    crawl.mpr("name = " .. it.name() .. ", ego = " ..
    --        (it.ego() or "none") .. ", subtype = " ..
    --        (it.subtype() or "none") .. ", slot = " .. slot(it) .. ".")
    --end
    for it in at_feet() do
        local val1, val2 = equip_value(it)
        local val3, val4 = equip_value(it, true)
        crawl.mpr("name = " .. it.name() .. ", ego = " ..
            (it.ego() or "none") .. it.ego_type .. ", subtype = " ..
            (it.subtype() or "none") .. ", slot = " .. (slot(it) or -1) ..
            ", values = " .. val1 .. " " .. val2 .. " " .. val3 .. " " ..
            val4 .. ".")
    end
end

function print_traversal_map()
    local str
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        str = ""
        for x = -20, 20 do
            local pos = position_sum(global_pos, { x = x, y = y })
            local traversable = map_is_traversable_at(pos)
            if traversable == nil then
                str = str .. " "
            else
                str = str .. (traversable and "." or "#")
            end
        end
        say(str)
    end
end

function print_distance_map(dist_map, center, excluded)
    if not center then
        center = global_pos
    end

    local map = excluded and dist_map.excluded_map or dist_map.map
    say("distance map at " .. pos_string(dist_map.pos) .. " ("
        .. cell_string(dist_map.pos, true) .. ") from position "
        .. pos_string(center) .. ":")
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        local str = ""
        for x = -20, 20 do
            if map[center.x + x][center.y + y] == nil then
                str = str .. " "
            elseif map[center.x + x][center.y + y] >= INF_DIST then
                str = str .. "∞"
            else
                str = str .. string.char(string.byte('A')
                    + map[center.x + x][center.y + y])
            end
        end
        say(str)
    end
end

function print_distance_maps(center, excluded)
    if not center then
        center = global_pos
    end

    for _, dist_map in pairs(distance_maps) do
        print_distance_map(dist_map, center, excluded)
    end
end

function set_counter()
    crawl.formatted_mpr("Set game counter to what? ", "prompt")
    local res = crawl.c_input_line()
    c_persist.record.counter = tonumber(res)
    note("Game counter set to " .. c_persist.record.counter)
end

function override_gameplan(gameplan)
    debug_gameplan = gameplan
    update_gameplan()
end

function get_global_pos()
    return global_pos
end

function pos_string(pos)
    return tostring(pos.x) .. ", " .. tostring(pos.y)
end

function cell_string(cell)
    local str = pos_string(cell.los_pos) .. " ("
    if supdist(cell.los_pos) <= los_radius then
        local mons = monster.get_monster_at(cell.los_pos.x, cell.los_pos.y)
        if mons then
            str = mons:name() .. "; "
        end
    end

    return str .. cell.feat .. ")"
end

function cell_string_from_map_position(pos)
    local cell = cell_from_position(position_difference(pos, global_pos))
    if cell then
        return cell_string(cell)
    end
end
