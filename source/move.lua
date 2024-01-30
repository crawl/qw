----------------------
-- General movement calculations

function can_move_to(pos, ignore_hostiles)
    return is_traversable_at(pos)
        and not view.withheld(pos.x, pos.y)
        and (supdist(pos) > qw.los_radius
            or not monster_in_way(pos, ignore_hostiles))
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
        if mons and not mons:is_firewood() then
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
function monster_in_way(pos, ignore_hostiles)
    local mons = get_monster_at(pos)
    if not mons then
        return false
    end

    local attitude = mons:attitude()
    return mons:name() == "orb of destruction"
        or not ignore_hostiles and attitude == const.attitude.hostile
        -- Attacking neutrals causes penance under the good gods.
        or attitude == const.attitude.neutral
            and mons:attacking_causes_penance()
        -- Strict neutral and up will swap with us, but we have to check that
        -- they can. We assume we never want to attack these.
        or mons:attitude() > const.attitude.neutral
            and not friendly_can_swap_to(mons, const.origin)
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

function best_move_towards(map_pos, ignore_exclusions)
    local dist_map = get_distance_map(map_pos)
    local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
    local current_dist = map[qw.map_pos.x][qw.map_pos.y]
    if current_dist == 0 then
        return
    end

    local result
    local safe_result
    for pos in adjacent_iter(qw.map_pos) do
        local los_pos = position_difference(pos, qw.map_pos)
        local dist = map[pos.x][pos.y]
        local better_dist = dist and (not current_dist or dist < current_dist)
        if better_dist
                and can_move_to(los_pos)
                and is_safe_at(pos)
                and (not safe_result or dist < safe_result.dist) then
            safe_result = { move = los_pos, dest = map_pos, dist = dist,
                safe = true }
        end

        if better_dist
                and not safe_result
                and can_move_to(los_pos, true)
                and (not result or dist < result.dist) then
            result = { move = los_pos, dest = map_pos, dist = dist }
        end
    end

    if safe_result then
        return safe_result
    else
        return result
    end
end

function best_move_towards_positions(map_positions, ignore_exclusions)
    local best_result
    for _, pos in ipairs(map_positions) do
        if positions_equal(qw.map_pos, pos) then
            return
        end

        local result = best_move_towards(pos, ignore_exclusions)
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
            reachable_position = dist_map.pos
            return
        end
    end

    reachable_position = qw.map_pos
end

--[[ Check any feature types flagged in check_reachable_features during the map
--update. These have been seen but not are not currently reachable LOS-wise, so
--check whether our reachable_position distance map indicates they are in fact
--reachable, and update their los state if so. ]]--
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
    local dist_map = get_distance_map(reachable_position)
    local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
    return map[pos.x][pos.y]
end

function best_move_towards_features(feats, ignore_exclusions)
    local positions = get_feature_map_positions(feats)
    if positions then
        return best_move_towards_positions(positions, ignore_exclusions)
    end
end

function best_move_towards_items(item_names, ignore_exclusions)
    local positions = get_item_map_positions(item_names)
    if positions then
        return best_move_towards_positions(positions, ignore_exclusions)
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
                and (allow_unsafe or map_is_unexcluded_at(pos))
                and map_is_reachable_at(pos, true)
                and (open_runed_doors and map_has_adjacent_runed_doors_at(pos)
                    or map_has_adjacent_unseen_at(pos)) then
            return best_move_towards(pos, true)
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
            return best_move_towards(pos, true)
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
    elseif qw.move_reason == "monster" and qw.danger_in_los then
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
        if debug_channel("explore") then
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

function move_to(pos)
    local mons_in_way = monster_in_way(pos)
    if mons_in_way and not get_monster_at(pos):player_can_attack() then
        return false
    end

    if mons_in_way and have_ranged_weapon() and not unable_to_shoot() then
        return shoot_launcher(pos)
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
