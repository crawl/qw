----------------------
-- General movement calculations

function can_move_to(pos, allow_hostiles)
    return is_traversable_at(pos)
        and not view.withheld(pos.x, pos.y)
        and (supdist(pos) > qw.los_radius
            or not monster_in_way(pos, allow_hostiles))
end

function traversal_function(assume_flight)
    return function(pos)
        -- XXX: This needs to run before update_map() and hence before
        -- traversal_map is updated, so we have to do an uncached check.
        -- Ideally we'd use the traversal map, but this requires separating the
        -- traversal map update to its own path and somehow retaining
        -- information about the per-cell changes so update_map() can propagate
        -- updates to adjacent cells.
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

        return view.feature_at(pos.x, pos.y) ~= "unseen"
            and is_safe_at(pos, assume_flight)
            and not view.withheld(pos.x, pos.y)
    end
end

function friendly_can_swap_to(mons, pos)
    return not (mons:is_constricted()
            or mons:is_caught()
            or mons:status("petrified")
            or mons:status("paralysed")
            or mons:status("constricted by roots")
            or mons:is("sleeping")
            or not mons:can_traverse(pos)
            or view.feature_at(pos.x, pos.y) == "trap_zot")
end

-- Should only be called for adjacent squares.
function monster_in_way(pos, allow_hostiles)
    local mons = get_monster_at(pos)
    if not mons then
        return false
    end

    -- Strict neutral and up will swap with us, but we have to check that
    -- they can. We assume we never want to attack these.
    return mons:attitude() > const.attitude.neutral
            and not friendly_can_swap_to(mons, const.origin)
        or not allow_hostiles
        or not mons:player_can_attack(1)
end

function get_move_closer(pos)
    local best_move, best_dist
    for apos in adjacent_iter(const.origin) do
        local traversable = is_traversable_at(apos)
        local dist = position_distance(pos, apos)
        if traversable and (not best_dist or dist < best_dist) then
            best_move = apos
            best_dist = dist
        end
    end

    return best_move, best_dist
end

function move_search(search, current)
    local diff = position_difference(search.target, current)
    if supdist(diff) <= search.min_dist then
        search.move = position_difference(search.first_pos, search.center)
        return true
    end

    local function search_from(pos)
        if search.attempted[pos.x] and search.attempted[pos.x][pos.y]
                -- Our search should never leave LOS of the center.
                or position_distance(search.center, pos) > qw.los_radius then
            return false
        end

        if positions_equal(current, search.center) then
            search.first_pos = nil
            search.last_pos = nil
        end

        if search.square_func(pos) then
            if not search.first_pos then
                search.first_pos = pos
            end

            if not search.attempted[pos.x] then
                search.attempted[pos.x] = {}
            end
            search.attempted[pos.x][pos.y] = true

            search.last_pos = pos
            return move_search(search, pos)
        end

        return false
    end

    local pos
    if abs(diff.x) > abs(diff.y) then
        if abs(diff.y) == 1 then
            pos = { x = current.x + sign(diff.x), y = current.y }
            if search_from(pos) then
                return true
            end
        end

        pos = { x = current.x + sign(diff.x), y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end

        pos = { x = current.x + sign(diff.x), y = current.y }
        if search_from(pos) then
            return true
        end

        if abs(diff.x) > abs(diff.y) + 1 then
            pos = { x = current.x + sign(diff.x), y = current.y + 1 }
            if search_from(pos) then
                return true
            end

            pos = { x = current.x + sign(diff.x), y = current.y - 1 }
            if search_from(pos) then
                return true
            end
        end

        pos = { x = current.x, y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end
    elseif abs(diff.x) == abs(diff.y) then
        pos = { x = current.x + sign(diff.x), y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end

        pos = { x = current.x + sign(diff.x), y = current.y }
        if search_from(pos) then
            return true
        end

        pos = { x = current.x, y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end
    else
        if abs(diff.x) == 1 then
            pos = { x = current.x, y = current.y + sign(diff.y) }
            if search_from(pos) then
                return true
            end
        end

        pos = { x = current.x + sign(diff.x), y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end

        pos = { x = current.x, y = current.y + sign(diff.y) }
        if search_from(pos) then
            return true
        end

        if abs(diff.y) > abs(diff.x) + 1 then
            pos = { x = current.x + 1, y = current.y + sign(diff.y) }
            if search_from(pos) then
                return true
            end

            pos = { x = current.x - 1, y = current.y + sign(diff.y) }
            if search_from(pos) then
                return true
            end
        end

        pos = { x = current.x + sign(diff.x), y = current.y }
        if search_from(pos) then
            return true
        end
    end

    return false
end

function move_search_result(center, target, square_func, min_dist)
    if not min_dist then
        min_dist = 0
    end

    if position_distance(center, target) <= min_dist then
        return
    end

    search = {
        center = center, target = target, square_func = square_func,
        min_dist = min_dist
    }
    search.attempted = { [center.x] = { [center.y] = true } }

    if move_search(search, center) then
        return search
    end
end

--[[
Get the best move towards the given map position
@table                 dest_pos      The destination map position.
@table[opt=qw.map_pos] from_pos      The starting map position. Defaults to
                                     qw's current position.
@boolean               allow_unsafe  If true, allow movements to squares that
                                     are unsafe due to clouds, traps, etc. or
                                     that contain hostile monsters.
@boolean               flee_monsters If true, assume we are attempting to flee.
                                     Don't attempt moves where we either move
                                     closer to monsters or would not be able to
                                     outrun a monster given considerations of
                                     move speed and the distance needed to
                                     reach the flee destination.
--]]
function best_move_towards(dest_pos, from_pos, allow_unsafe, flee_monsters)
    if not from_pos then
        from_pos = qw.map_pos
    end

    local dist_map = get_distance_map(dest_pos)
    local current_dist
    if allow_unsafe then
        current_dist = dist_map.map[from_pos.x][from_pos.y]
    end

    local current_safe_dist = dist_map.excluded_map[from_pos.x][from_pos.y]

    if debug_channel("move") then
        dsay("Determining move to "
            .. cell_string_from_map_position(dest_pos)
            .. " from " ..  cell_string_from_map_position(from_pos))
        dsay("Safe distance to dest: " .. tostring(current_safe_dist))

        if allow_unsafe then
            dsay("Unsafe distance to dest: " .. tostring(current_dist))
        end
    end

    if current_safe_dist == 0
            or not current_safe_dist and not current_dist then
        return
    end

    local result
    local safe_result
    for pos in adjacent_iter(from_pos) do
        local los_pos = position_difference(pos, from_pos)
        local safe_dist = dist_map.excluded_map[pos.x][pos.y]
        if safe_dist
                and (not current_safe_dist or safe_dist < current_safe_dist)
                and can_move_to(los_pos)
                and is_safe_at(los_pos)
                and (not flee_monsters or can_flee_to(los_pos, safe_dist + 1))
                and (not safe_result or safe_dist < safe_result.dist) then
            safe_result = { move = los_pos, dest = dest_pos, dist = safe_dist,
                safe = true }
        end

        local dist
        if allow_unsafe then
            dist = dist_map.map[pos.x][pos.y]
        end
        if not safe_result
                and dist
                and dist < current_dist
                and can_move_to(los_pos, true)
                and (not flee_monsters or can_flee_to(los_pos, dist + 1))
                and (not result or dist < result.dist) then
            result = { move = los_pos, dest = dest_pos, dist = dist }
        end
    end

    if safe_result then
        return safe_result
    else
        return result
    end
end

function best_move_towards_positions(map_positions, allow_unsafe,
        flee_monsters)
    local best_result
    for _, pos in ipairs(map_positions) do
        if positions_equal(qw.map_pos, pos) then
            return
        end

        local result = best_move_towards(pos, qw.map_pos, allow_unsafe,
            flee_monsters)
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

--[[ Check any feature types flagged in check_reachable_features during the map
update. These have been seen but not are not currently reachable LOS-wise, so
check whether our reachable position distance map indicates they are in fact
reachable, and if so, update their los state.]]--
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
    local positions = get_feature_map_positions(feats)
    if positions then
        return best_move_towards_positions(positions, allow_unsafe)
    end
end

function best_move_towards_items(item_names, allow_unsafe)
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
                and map_is_reachable_at(pos, true)
                and can_move_to(los_pos, true) then
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

    if monster_in_way(pos, true) then
        if get_monster_at(pos):player_can_attack(1) then
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
