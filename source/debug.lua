------------------
-- Debug functions

function initialize_debug()
    qw.debug_mode = DEBUG_MODE
    qw.debug_channels = {}
    for _, channel in ipairs(DEBUG_CHANNELS) do
        qw.debug_channels[channel] = true
    end
end

function toggle_debug()
    qw.debug_mode = not qw.debug_mode
    dsay((qw.debug_mode and "Enabling" or "Disabling") .. " debug mode")
end

function debug_channel(channel)
    return qw.debug_mode and qw.debug_channels[channel]
end

function toggle_debug_channel(channel)
    qw.debug_channels[channel] = not qw.debug_channels[channel]
    dsay((qw.debug_channels[channel] and "Enabling " or "Disabling ")
      .. channel .. " debug channel")
end

function disable_all_debug_channels()
    dsay("Disabling all debug channels")
    qw.debug_channels = {}
end

function dsay(x, do_note)
    -- Convert x to string to make debugging easier. We don't do this for say()
    -- and note() so we can catch errors.
    local str
    if type(x) == "table" then
        str = qw.stringify_table(x)
    else
        str = qw.stringify(x)
    end

    str = you.turns() .. " ||| " .. str
    crawl.mpr(str)

    if do_note then
        note(str)
    end
end

function test_radius_iter()
    dsay("Testing 3, 3 with radius 1")
    for pos in radius_iter({ x = 3, y = 3 }, 1) do
        dsay("x: " .. tostring(pos.x) .. ", y: " .. tostring(pos.y))
    end

    dsay("Testing const.origin with radius 3")
    for pos in radius_iter(const.origin, 3) do
        dsay("x: " .. tostring(pos.x) .. ", y: " .. tostring(pos.y))
    end
end

function print_traversal_map(center)
    if not center then
        center = const.origin
    end

    crawl.setopt("msg_condense_repeats = false")

    local map_center = position_sum(qw.map_pos, center)
    say("Traversal map at " .. cell_string_from_map_position(map_center))
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        local str = ""
        for x = -20, 20 do
            local pos = position_sum(map_center, { x = x, y = y })
            local traversable = map_is_traversable_at(pos)
            local char
            if positions_equal(pos, qw.map_pos) then
                if traversable == nil then
                    str = str .. "✞"
                else
                    str = str .. (traversable and "@" or "7")
                end
            elseif positions_equal(pos, map_center) then
                if traversable == nil then
                    str = str .. "W"
                else
                    str = str .. (traversable and "&" or "8")
                end
            elseif traversable == nil then
                str = str .. " "
            else
                str = str .. (traversable and "." or "#")
            end
        end
        say(str)
    end

    crawl.setopt("msg_condense_repeats = true")
end

function print_unexcluded_map(center)
    if not center then
        center = const.origin
    end

    crawl.setopt("msg_condense_repeats = false")

    local map_center = position_sum(qw.map_pos, center)
    say("Unexcluded map at " .. cell_string_from_map_position(map_center))
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        local str = ""
        for x = -20, 20 do
            local pos = position_sum(map_center, { x = x, y = y })
            local unexcluded = map_is_unexcluded_at(pos)
            local char
            if positions_equal(pos, qw.map_pos) then
                if unexcluded == nil then
                    str = str .. "✞"
                else
                    str = str .. (unexcluded and "@" or "7")
                end
            elseif positions_equal(pos, map_center) then
                if unexcluded == nil then
                    str = str .. "W"
                else
                    str = str .. (unexcluded and "&" or "8")
                end
            elseif unexcluded == nil then
                str = str .. " "
            else
                str = str .. (unexcluded and "." or "#")
            end
        end
        say(str)
    end

    crawl.setopt("msg_condense_repeats = true")
end

function print_adjacent_floor_map(center)
    if not center then
        center = const.origin
    end

    crawl.setopt("msg_condense_repeats = false")

    local map_center = position_sum(qw.map_pos, center)
    say("Adjacent floor map at " .. cell_string_from_map_position(map_center))
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        local str = ""
        for x = -20, 20 do
            local pos = position_sum(map_center, { x = x, y = y })
            local floor_count = adjacent_floor_map[pos.x][pos.y]
            local char
            if positions_equal(pos, qw.map_pos) then
                if floor_count == nil then
                    str = str .. "✞"
                else
                    str = str .. (floor_count <= 3 and "@" or "7")
                end
            elseif positions_equal(pos, map_center) then
                if floor_count == nil then
                    str = str .. "W"
                else
                    str = str .. (floor_count <= 3 and "&" or "8")
                end
            elseif floor_count == nil then
                str = str .. " "
            else
                str = str .. floor_count
            end
        end
        say(str)
    end

    crawl.setopt("msg_condense_repeats = true")
end

function print_distance_map(dist_map, center, excluded)
    if not center then
        center = const.origin
    end

    crawl.setopt("msg_condense_repeats = false")

    local map = excluded and dist_map.excluded_map or dist_map.map
    local map_center = position_sum(qw.map_pos, center)
    say("Distance map at " .. cell_string_from_map_position(dist_map.pos)
        .. " from position " .. cell_string_from_map_position(map_center))
    -- This needs to iterate by row then column for display purposes.
    for y = -20, 20 do
        local str = ""
        for x = -20, 20 do
            local pos = position_sum(map_center, { x = x, y = y })
            local dist = map[pos.x][pos.y]
            if positions_equal(pos, qw.map_pos) then
                if dist == nil then
                    str = str .. "✞"
                else
                    str = str .. (dist > 180 and "7" or "@")
                end
            elseif positions_equal(pos, map_center) then
                if dist == nil then
                    str = str .. "W"
                else
                    str = str .. (dist > 180 and "8" or "&")
                end
            else
                if dist == nil then
                    str = str .. " "
                elseif dist > 180 then
                    str = str .. "∞"
                elseif dist > 61 then
                    str = str .. "Ø"
                else
                    str = str .. string.char(string.byte('A') + dist)
                end
            end
        end
        say(str)
    end

    crawl.setopt("msg_condense_repeats = true")
end

function print_distance_maps(center, excluded)
    if not center then
        center = const.origin
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

function override_goal(goal)
    debug_goal = goal
    update_goal()
end

function get_vars()
    return qw, const
end

function pos_string(pos)
    return tostring(pos.x) .. "," .. tostring(pos.y)
end

function los_pos_string(map_pos)
    return pos_string(position_difference(map_pos, qw.map_pos))
end

function cell_string(cell)
    local str = pos_string(cell.los_pos) .. " ("
    if supdist(cell.los_pos) <= qw.los_radius then
        local mons = monster.get_monster_at(cell.los_pos.x, cell.los_pos.y)
        if mons then
            str = str .. mons:name() .. "; "
        end
    end

    return str .. cell.feat .. ")"
end

function cell_string_from_position(pos)
    return cell_string(cell_from_position(pos))
end

function cell_string_from_map_position(pos)
    return cell_string_from_position(position_difference(pos, qw.map_pos))
end

function monster_string(mons, props)
    if not props then
        props = { move_delay = "move delay", reach_range = "reach",
            is_ranged = "ranged" }
    end

    local vals = {}
    for prop, name in pairs(props) do
        table.insert(vals, name .. ":" .. tostring(mons[prop](mons)))
    end
    return mons:name() .. " (" .. table.concat(vals, "/") .. ") at "
        .. pos_string(mons:pos())
end

function toggle_throttle()
    qw.coroutine_throttle = not qw.coroutine_throttle
    dsay((qw.coroutine_throttle and "Enabling" or "Disabling")
      .. " coroutine throttle")
end

function toggle_delay()
    qw.delayed = not qw.delayed
    dsay((qw.delayed and "Enabling" or "Disabling") .. " action delay")
end

function reset_coroutine()
    qw.update_coroutine = nil
    collectgarbage("collect")
end

function resume_qw()
    qw.abort = false
end

function toggle_single_step()
    qw.single_step = not qw.single_step
    dsay((qw.single_step and "Enabling" or "Disabling")
      .. " single action steps.")
end

function qw.stringify(x)
    local t = type(x)
    if t == "nil" then
        return "nil"
    elseif t == "number" then
        return tostring(x)
    elseif t == "string" then
        return x
    elseif t == "boolean" then
        return x and "true" or "false"
    elseif x.name then
        return item_string(x)
    end
end

function qw.stringify_table(tab, indent_level)
    if not indent_level then
        indent_level = 0
    end

    local spaces = ""
    for i = 1, 2 * indent_level + 1 do
        spaces = spaces .. " "
    end

    if type(tab.pos) == "function" then
        return spaces .. "{ " .. cell_string_from_position(tab:pos()) .. " }"
    end

    local res = spaces .. "{\n"
    for key, val in pairs(tab) do
        res = res .. spaces .. " [" .. qw.stringify(key) .. "] ="
        if type(val) ~= "table" then
            res = res .. " " .. qw.stringify(val) .. ",\n"
        elseif next(val) == nil then -- table is empty
            res = res .. " { },\n"
        else
            res = res .. "\n" .. qw.stringify_table(val, indent_level + 1) .. ",\n"
        end
    end
    res = res .. spaces .. "}"
    return res
end
