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

function toggle_debug()
    DEBUG_MODE = not DEBUG_MODE
end

function toggle_debug_channel(channel)
    if util.contains(DEBUG_CHANNELS, channel) then
        local list = util.copy_table(DEBUG_CHANNELS)
        for i, e in ipairs(DEBUG_CHANNELS) do
            if e == "plans" then
                table.remove(list, i)
            end
        end
        DEBUG_CHANNELS = list
    else
        table.insert(DEBUG_CHANNELS, channel)
    end
end

function test_radius_iter()
    dsay("Testing 3, 3 with radius 1")
    for x, y in radius_iter(3, 3, 1) do
        dsay("x: " .. tostring(x) .. ", y: " .. tostring(y))
    end

    dsay("Testing 0, 0 with radius 3")
    for x, y in radius_iter(0, 0, 3) do
        dsay("x: " .. tostring(x) .. ", y: " .. tostring(y))
    end
end

--------------------------------
-- a function to test various things conveniently
function ttt()
    for i = -los_radius, los_radius do
        for j = -los_radius, los_radius do
            m = monster.get_monster_at(i, j)
            if m then
                crawl.mpr("(" .. i .. "," .. j .. "): name = " .. m:name() .. ", desc = " .. m:desc() .. ".")
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

function print_level_map()
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local str
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        str = ""
        for x = -20, 20 do
            if level_map[num][dx + x][dy + y] == nil then
                str = str .. " "
            else
                str = str .. level_map[num][dx + x][dy + y]
            end
        end
        say(str)
    end
end

function print_stair_dists()
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local str
    for i = 1, #stair_dists[num] do
    say("---------------------------------------")
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        str = ""
        for x = -20, 20 do
            if stair_dists[num][i][dx + x][dy + y] == nil then
                str = str .. " "
            else
                str = str .. string.char(string.byte('A') +
                stair_dists[num][i][dx + x][dy + y])
            end
        end
        say(str)
    end
    end
end

function set_counter()
    crawl.formatted_mpr("Set game counter to what? ", "prompt")
    local res = crawl.c_input_line()
    c_persist.record.counter = tonumber(res)
    note("Game counter set to " .. c_persist.record.counter)
end

function dsay(x, channel)
    if not channel then
        channel = "main"
    end

    if DEBUG_MODE and util.contains(DEBUG_CHANNELS, channel) then
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
end
