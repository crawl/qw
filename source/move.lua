----------------------
-- General movement calculations

function can_move_to(to_pos, from_pos, allow_hostiles)
    return is_traversable_at(to_pos)
        and not view.withheld(to_pos.x, to_pos.y)
        and (supdist(to_pos) > qw.los_radius
            or not monster_in_way_at(to_pos, from_pos, allow_hostiles))
end

function traversal_function(assume_flight)
    return function(pos)
        -- XXX: This needs to run before update_map() and hence before
        -- traversal_map is updated, so we have to do an uncached check.
        -- Ideally we'd use the traversal map, but this requires separating
        -- the traversal map update to its own path and somehow retaining
        -- information about the per-cell changes so update_map() can
        -- propagate updates to adjacent cells.
        return feature_is_traversable(view.feature_at(pos.x, pos.y),
            assume_flight)
    end
end

function tab_function(assume_flight)
    return function(pos)
        local mons = get_monster_at(pos)
        if mons and not mons:is_harmless() then
            return false
        end

        return is_safe_at(pos, assume_flight)
            and not view.withheld(pos.x, pos.y)
    end
end

function friendly_can_swap_to(mons, pos)
    return mons:can_seek()
        and mons:can_traverse(pos)
        and view.feature_at(pos.x, pos.y) ~= "trap_zot"
end

function monster_in_way_at(to_pos, from_pos, allow_hostiles)
    local mons = get_monster_at(to_pos)
    if not mons then
        return false
    end

    -- Strict neutral and up will swap with us, but we have to check that
    -- they can. We assume we never want to attack these.
    return mons:attitude() > const.attitude.neutral
            and not friendly_can_swap_to(mons, from_pos)
        or not allow_hostiles
        or not mons:player_can_attack()
end

function get_move_closer(pos)
    local best_move, best_dist
    for apos in adjacent_iter(const.origin) do
        local dist = position_distance(pos, apos)
        if is_safe_at(pos) and (not best_dist or dist < best_dist) then
            best_move = apos
            best_dist = dist
        end
    end

    return best_move, best_dist
end

function search_from(search, pos, current, is_deviation)
    if positions_equal(pos, current) then
        return false
    end

    if debug_channel("move-all") then
        dsay("Checking " .. (is_deviation and "deviation " or "")
            .. "move from " .. cell_string_from_position(current)
            .. " to " .. cell_string_from_position(pos))
    end

    if is_deviation and search.num_deviations >= 2 then
        if debug_channel("move-all") then
            dsay("Too many deviation movements")
        end

        return false
    end

    if position_distance(search.center, pos) > 2 * qw.los_radius then
        if debug_channel("move-all") then
            dsay("Search traveled too far")
        end

        return false
    end

    if not search.attempted[pos.x] then
        search.attempted[pos.x] = {}
    end

    if search.attempted[pos.x][pos.y]
            and search.attempted[pos.x][pos.y] <= search.num_deviations then
        if debug_channel("move-all") then
            dsay("Not attempting previously failed search")
        end

        return false
    end

    if positions_equal(current, search.center) then
        search.first_pos = nil
        search.last_pos = nil
        search.dist = 0
        search.num_deviations = 0
    end

    search.attempted[pos.x][pos.y] = search.num_deviations
        + (is_deviation and 1 or 0)

    if search.square_func(pos) then
        if is_deviation then
            search.num_deviations = search.num_deviations + 1
        end
        search.dist = search.dist + 1

        local set_first_pos = not search.first_pos
        if set_first_pos then
            search.first_pos = pos
        end
        search.last_pos = pos

        if do_move_search(search, pos) then
            return true
        else
            if is_deviation then
                search.num_deviations = search.num_deviations - 1
            end
            search.dist = search.dist - 1

            if set_first_pos then
                search.first_pos = nil
            end

            return false
        end
    end

    if debug_channel("move-all") then
        dsay("Square function failed")
    end

    return false
end

function do_move_search(search, current)
    local diff = position_difference(search.target, current)
    if supdist(diff) <= search.min_dist then
        search.move = position_difference(search.first_pos, search.center)
        return true
    end

    local pos
    local sign_diff_x = sign(diff.x)
    local sign_diff_y = sign(diff.y)
    pos = { x = current.x + sign_diff_x, y = current.y + sign_diff_y }
    if search_from(search, pos, current) then
        return true
    end

    pos = { x = current.x + sign_diff_x, y = current.y }
    if search_from(search, pos, current) then
        return true
    end

    pos = { x = current.x, y = current.y + sign_diff_y}
    if search_from(search, pos, current) then
        return true
    end

    local abs_diff_x = abs(diff.x)
    local abs_diff_y = abs(diff.y)
    if abs_diff_x >= abs_diff_y then
        if abs_diff_y > 0 then
            pos = { x = current.x + sign_diff_x, y = current.y - sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - sign_diff_x, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end
        else
            pos = { x = current.x + sign_diff_x, y = current.y + 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + sign_diff_x, y = current.y - 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x, y = current.y + 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x, y = current.y - 1 }
            if search_from(search, pos, current, true) then
                return true
            end
        end
    elseif abs_diff_x < abs_diff_y then
        if abs_diff_x > 0 then
            pos = { x = current.x - sign_diff_x, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + sign_diff_x, y = current.y - sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end
        else
            pos = { x = current.x + 1, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - 1, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + 1, y = current.y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - 1, y = current.y }
            if search_from(search, pos, current, true) then
                return true
            end
        end
    end

    return false
end

function move_search(center, target, square_func, min_dist)
    if not min_dist then
        min_dist = 0
    end

    if position_distance(center, target) <= min_dist then
        return
    end

    if debug_channel("move-all") then
        dsay("Move search from " .. cell_string_from_position(center)
            .. " to " .. cell_string_from_position(target))
    end

    search = { center = center, target = target, square_func = square_func,
        min_dist = min_dist, dist = 0, num_deviations = 0 }
    search.attempted = { [center.x] = { [center.y] = 0 } }

    if do_move_search(search, center) then
        return search
    end
end

function assess_move(to_pos, from_pos, dist_map, best_result, use_unsafe)
    local los_pos = position_difference(to_pos, qw.map_pos)
    local result = { move = los_pos, dest = dist_map.pos,
        safe = not use_unsafe }

    if debug_channel("move-all") and map_is_traversable_at(to_pos) then
        dsay("Checking " .. (use_unsafe and "unsafe" or "safe")
            .. " move to " .. cell_string_from_map_position(to_pos))
    end

    local map = use_unsafe and dist_map.map or dist_map.excluded_map
    result.dist = map[to_pos.x][to_pos.y]
    if not result.dist then
        if debug_channel("move-all") and map_is_traversable_at(to_pos) then
            dsay("No path to destination")
        end

        return
    end

    local current_dist = map[from_pos.x][from_pos.y]
    if current_dist and result.dist >= current_dist then
        if debug_channel("move-all") then
            dsay("Distance of " .. tostring(result.dist)
                .. " does not improve the starting position distance of "
                .. tostring(current_dist))
        end

        return
    end

    if best_result and result.dist >= best_result.dist then
        if debug_channel("move-all") then
            dsay("Distance of " .. tostring(result.dist)
                .. " does not the improve the current best distance of "
                .. tostring(best_result.dist))
        end

        return false
    end

    local from_los_pos = position_difference(from_pos, qw.map_pos)
    if not can_move_to(los_pos, from_los_pos, use_unsafe) then
        if debug_channel("move-all") then
            dsay("Can't move to position")
        end

        return
    end

    if not use_unsafe and not is_safe_at(los_pos) then
        if debug_channel("move-all") then
            dsay("Position is not safe")
        end

        return
    end

    return result
end

--[[
Get the best move towards the given map position
@table                 dest_pos      The destination map position.
@table[opt=qw.map_pos] from_pos      The starting map position. Defaults to
                                     qw's current position.
@boolean               allow_unsafe  If true, allow movements to squares that
                                     are unsafe due to clouds, traps, etc. or
                                     that contain hostile monsters.
@return nil if no move was found. Otherwise a table with the keys `move` (los
        coordinates of the best move), `dest_pos` (a copy of `dest_pos`),
        `dist` (the distance to `dest_pos` from `move`, and `safe` (true if the
        move is safe).
--]]
function best_move_towards(dest_pos, from_pos, allow_unsafe)
    if not from_pos then
        from_pos = qw.map_pos
    end

    if not map_is_traversable_at(from_pos) then
        return
    end

    local dist_map = get_distance_map(dest_pos)
    local current_dist
    if allow_unsafe then
        current_dist = dist_map.map[from_pos.x][from_pos.y]
    end
    local current_safe_dist = dist_map.excluded_map[from_pos.x][from_pos.y]

    if debug_channel("move-all") then
        local msg = "Determining move from "
            .. cell_string_from_map_position(from_pos)
            .. " to " ..  cell_string_from_map_position(dest_pos)

        if allow_unsafe then
            msg = msg .. " safe/unsafe distances " .. tostring(current_safe_dist)
                .. "/" .. tostring(current_dist)
        else
            msg = msg .. " safe distance " .. tostring(current_safe_dist)
        end

        dsay(msg)
    end

    if current_safe_dist == 0
            or current_dist == 0
            or not current_safe_dist and not current_dist then
        return
    end

    local best_result
    for pos in adjacent_iter(from_pos) do
        local result = assess_move(pos, from_pos, dist_map, best_result)
        if result then
            best_result = result
        elseif allow_unsafe and (not best_result or not best_result.safe) then
            result = assess_move(pos, from_pos, dist_map, best_result, true)
            if result then
                best_result = result
            end
        end
    end

    return best_result
end

function best_move_towards_positions(map_positions, allow_unsafe)
    local best_result
    for _, pos in ipairs(map_positions) do
        if positions_equal(qw.map_pos, pos) then
            return
        end

        local result = best_move_towards(pos, qw.map_pos, allow_unsafe)
        if result and (not best_result
                or result.safe and not best_result.safe
                or result.dist < best_result.dist) then
            best_result = result
        end
    end
    return best_result
end

function update_reachable_position()
    for _, dist_map in pairs(distance_maps) do
        if dist_map.excluded_map[qw.map_pos.x][qw.map_pos.y] then
            qw.reachable_position = dist_map.pos
            return
        end
    end

    qw.reachable_position = qw.map_pos
end

--[[
Check any feature types flagged in check_reachable_features during the map
update. These have been seen but not are not currently reachable LOS-wise, so
check whether our reachable position distance map indicates they are in fact
reachable, and if so, update their los state.
]]--
function update_reachable_features()
    local check_feats = {}
    for feat, _ in pairs(check_reachable_features) do
        table.insert(check_feats, feat)
    end
    if #check_feats == 0 then
        return
    end

    local positions, feats = get_feature_map_positions(check_feats)
    if #positions == 0 then
        return
    end

    for i, pos in ipairs(positions) do
        if map_is_reachable_at(pos, true) then
            update_feature(where_branch, where_depth, feats[i],
                hash_position(pos), { feat = const.explore.reachable })
        end
    end

    check_reachable_features = {}
end

function map_is_reachable_at(pos, ignore_exclusions)
    local dist_map = get_distance_map(qw.reachable_position)
    local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
    return map[pos.x][pos.y]
end

function best_move_towards_features(feats, allow_unsafe)
    if debug_channel("move") then
        dsay("Determining best move towards feature(s): "
            .. table.concat(feats, ", "))
    end

    local positions = get_feature_map_positions(feats)
    if positions then
        return best_move_towards_positions(positions, allow_unsafe)
    end
end

function best_move_towards_items(item_names, allow_unsafe)
    if debug_channel("move") then
        dsay("Determining best move towards item(s): "
            .. table.concat(item_names, ", "))
    end

    local positions = get_item_map_positions(item_names)
    if positions then
        return best_move_towards_positions(positions, allow_unsafe)
    end
end

function map_has_adjacent_unseen_at(pos)
    for apos in adjacent_iter(pos) do
        if traversal_map[apos.x][apos.y] == nil then
            return true
        end
    end

    return false
end

function map_has_adjacent_runed_doors_at(pos)
    for apos in adjacent_iter(pos) do
        local los_pos = position_difference(apos, qw.map_pos)
        if view.feature_at(los_pos.x, los_pos.y) == "runed_clear_door" then
            return true
        end
    end

    return false
end

function best_move_towards_unexplored_near(map_pos, allow_unsafe)
    if debug_channel("move") then
        dsay("Determining best move towards unexplored squares near "
            .. cell_string_from_map_position(map_pos))
    end

    local i = 1
    for pos in radius_iter(map_pos, const.gxm) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched for unexplored in block " .. tostring(i / 1000)
                    .. " of map positions near "
                    .. cell_string_from_map_position(map_pos))
            end

            qw.throttle = true
            coroutine.yield()
        end

        if supdist(pos) <= const.gxm
                and map_is_reachable_at(pos, allow_unsafe)
                and (open_runed_doors and map_has_adjacent_runed_doors_at(pos)
                    or map_has_adjacent_unseen_at(pos)) then
            return best_move_towards(pos, qw.map_pos, allow_unsafe)
        end

        i = i + 1
    end
end

function best_move_towards_unexplored(allow_unsafe)
    return best_move_towards_unexplored_near(qw.map_pos, allow_unsafe)
end

function best_move_towards_unexplored_near_positions(map_positions,
        allow_unsafe)
    local best_result
    for _, pos in ipairs(map_positions) do
        local result = best_move_towards_unexplored_near(pos, allow_unsafe)
        if result and (not best_result or result.dist < best_result.dist) then
            best_result = result
        end
    end
    return best_result
end

function best_move_towards_safety()
    if debug_channel("move") then
        dsay("Determining best move towards safety")
    end

    local i = 1
    for pos in radius_iter(qw.map_pos, const.gxm) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched for safety in block " .. tostring(i / 1000)
                    .. " of map positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        local los_pos = position_difference(pos, qw.map_pos)
        if supdist(pos) <= const.gxm
                and is_safe_at(los_pos)
                and map_is_reachable_at(pos, true) then
            return best_move_towards(pos, qw.map_pos, true)
        end

        i = i + 1
    end
end

function update_move_destination()
    if not qw.move_destination then
        qw.move_reason = nil
        return
    end

    local clear = false
    if qw.move_reason == "goal" and qw.want_goal_update then
        clear = true
    elseif qw.move_reason == "monster" and have_target() then
        clear = true
    elseif positions_equal(qw.map_pos, qw.move_destination) then
        if qw.move_reason == "unexplored"
                and autoexplored_level(where_branch, where_depth)
                and qw.position_is_safe then
            reset_autoexplore(where)
        end

        clear = true
    end

    if clear then
        if debug_channel("move") then
            dsay("Clearing move destination "
                .. cell_string_from_map_position(qw.move_destination))
        end

        local dist_map = distance_maps[hash_position(qw.move_destination)]
        if dist_map and not dist_map.permanent then
            distance_map_remove(dist_map)
        end

        qw.move_destination = nil
        qw.move_reason = nil
    end
end

function move_to(pos, cloud_waiting)
    if cloud_waiting == nil then
        cloud_waiting = true
    end

    if cloud_waiting
            and not qw.position_is_cloudy
            and unexcluded_at(pos)
            and cloud_is_dangerous_at(pos) then
        wait_one_turn()
        return true
    end

    local mons = get_monster_at(pos)
    if mons and monster_in_way_at(pos, const.origin, true) then
        if mons:player_can_attack() then
            return shoot_launcher(pos)
        else
            return false
        end
    end

    magic(delta_to_vi(pos) .. "YY")
    return true
end

function move_towards_destination(pos, dest, reason)
    if move_to(pos) then
        qw.move_destination = dest
        qw.move_reason = reason
        return true
    end

    return false
end

function distance_map_search_from(search, pos, current)
    if positions_equal(pos, current) then
        return false
    end

    if debug_channel("move-all") then
        dsay("Checking distance map move from "
            .. cell_string_from_map_position(current)
            .. " to " .. cell_string_from_map_position(pos))
    end

    if not search.cache[pos.x] then
        search.cache[pos.x] = {}
    end

    local cache_result = search.cache[pos.x][pos.y]
    if cache ~= nil then
        if debug_channel("move-all") then
            dsay("Returning cached result for search")
        end

        if cache_result then
            if not search.first_pos then
                search.first_pos = pos
            end

            search.last_pos = cache_result
        end

        return cache_result
    end

    if positions_equal(current, search.center) then
        search.first_pos = nil
        search.last_pos = nil
    end

    if search.square_func(pos) then
        search.last_pos = pos

        local set_first_pos = not search.first_pos
        if set_first_pos then
            search.first_pos = pos
        end

        if do_distance_map_search(search, pos) then
            search.cache[pos.x][pos.y] = pos
            return true
        else
            if set_first_pos then
                search.first_pos = nil
            end

            search.cache[pos.x][pos.y] = false
            return false
        end
    end

    if debug_channel("move-all") then
        dsay("Square function failed")
    end

    search.cache[pos.x][pos.y] = false
    return false
end

function do_distance_map_search(search, current)
    if position_distance(search.target, current) <= search.min_dist then
        search.move = position_difference(search.first_pos, search.center)
        return true
    end

    local current_dist = search.map[current.x][current.y]
    if not current_dist then
        return false
    end

    for pos in adjacent_iter(current) do
        local dist = search.map[pos.x][pos.y]
        if dist and dist < current_dist then
            if distance_map_search_from(search, pos, current) then
                return true
            end
        end
    end

    return false
end

function distance_map_search(center, target, square_func, min_dist,
        allow_unsafe, cache)
    if not min_dist then
        min_dist = 0
    end

    if position_distance(center, target) <= min_dist then
        return
    end

    if debug_channel("move-all") then
        dsay("Distance map move search from "
            .. cell_string_from_map_position(center)
            .. " to " .. cell_string_from_map_position(target))
    end

    local dist_map = get_distance_map(target)
    local map  = allow_unsafe and dist_map.map or dist_map.excluded_map
    local dist = map[center.x][center.y]
    if not dist then
        return
    end

    search = { center = center, target = target, square_func = square_func,
        min_dist = min_dist, allow_unsafe = allow_unsafe, map = map,
        dist = dist }

    if cache then
        search.cache = cache
    else
        search.cache = { }
    end

    if do_distance_map_search(search, center) then
        return search
    end
end
