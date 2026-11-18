----------------------
-- Distance-mapped movement calculations for the player.

function move_distance(move_type, pos, dest_pos)
    if not dest_pos then
        dest_pos = qw.map_pos
    end

    local dist_map = get_distance_map(move_type, dest_pos)
    return dist_map.map[pos.hash]
end

function map_is_reachable_at(pos, move_type, dest_pos)
    if not move_type then
        move_type = const.move.traversable
    end

    return move_distance(move_type, pos, dest_pos) ~= nil
end

local move_keys = { "trap", "cloud", "blocked", "excluded", "melee_count", "slow", "enemy_dist" }
local reversed_move_keys =
    { trap = true, cloud = true, blocked = true, excluded = true, melee_count = true, slow = true }

function assess_move(to_pos, dest_pos, best_result, unsafe)
    local to_los_pos = los_position(to_pos)
    local result = {
        to_pos = to_pos,
        move = to_los_pos,
        dest_pos = dest_pos,
        unsafe = unsafe,
        trap = 0,
        cloud = 0,
        blocked = 0,
        excluded = 0,
        melee_count = 0,
        slow = 0,
        enemy_dist = const.inf_dist,
    }

    if debug_channel("move-distance") then
        dsayf("Checking %s move to %s", unsafe and "unsafe" or "safe",
            cell_string_from_map_position(to_pos))
    end

    local move_type = unsafe and const.move.traversable or const.move.safe
    result.dist = move_distance(move_type, to_pos, dest_pos)
    if not result.dist then
        if debug_channel("move-distance") then
            dsay("No path to destination")
        end

        return
    end

    local current_dist = move_distance(move_type, qw.map_pos, dest_pos)
    if current_dist and result.dist >= current_dist then
        if debug_channel("move-distance") then
            dsayf("Distance of %d does not improve the starting distance of %d",
                result.dist, current_dist)
        end

        return
    end

    -- We may have a best move that's unsafe yet the current viable move is
    -- safe, in which case prefer the safe move.
    local best_ok = best_result and best_result.unsafe == unsafe
    if best_ok and result.dist > best_result.dist then
        if debug_channel("move-distance") then
            dsayf("Distance of %d is worse than the current best distance of %d",
                result.dist, best_result.dist)
        end

        return
    end

    if not can_move_to(to_los_pos, const.origin, unsafe) then
        if debug_channel("move-distance") then
            dsay("Can't move to position")
        end

        return
    end

    local mons = get_monster_at(to_los_pos)
    if mons and not mons:player_can_swap() then
        if not mons:player_can_attack() then
            result.blocked = 5
        elseif mons:is_friendly() then
            result.blocked = 4
        elseif mons:attitude() == const.attitude.neutral then
            result.blocked = 3
        elseif mons:is_enemy() then
            result.blocked = 2
        else
            result.blocked = 1
        end
    end

    if unsafe then
        local feat = map_feature_at(to_pos)
        if feature_is_trap(feat) then
            result.trap = const.trap_scores[feat]
        end

        local cloud = view.cloud_at(to_los_pos.x, to_los_pos.y)
        if cloud_is_dangerous(cloud) then
            result.cloud = 2
        elseif not cloud_is_safe(cloud) then
            result.cloud = 1
        end

        result.excluded = map_is_excluded_at(to_pos) and 1 or 0
    end

    if in_water_at(to_los_pos) and not intrinsic_amphibious() then
        result.slow = 1
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:can_melee_at(to_los_pos) then
            result.melee_count = result.melee_count + 1
        end

        local dist = enemy:melee_move_distance(to_los_pos)
        if dist < result.enemy_dist then
            result.enemy_dist = dist
        end
    end

    if not best_ok or compare_table_keys(result, best_result, move_keys, reversed_move_keys) then
        return result
    end
end

--[[
Get the best move towards the given map position using a distance map.
@table                 dest_pos         The destination map position.
@boolean               fallback_unsafe  If true, allow fallback movement to an
                                        unsafe square if no safe square is
                                        available. If false, only safe moves
                                        will be considered valid.
@return nil if no move was found. Otherwise a table with the keys `move` (los
        coordinates of the best move), `to_pos` (map coordinates of `move`),
        `dest_pos`, `unsafe` (boolean indicating if the move is unsafe),
        `dist` (the distance to `dest_pos` from `move`), along with keys for
        evaluating aspects of the move (see `move_keys`).
--]]
function best_move_towards(dest_pos, fallback_unsafe, want_melee)
    if want_melee then
        local melee_pos = closest_melee_position(dest_pos, qw.map_pos, const.move.safe)
        if fallback_unsafe and not melee_pos then
            melee_pos = closest_melee_position(dest_pos, qw.map_pos, const.move.traversable)
        end

        if melee_pos then
            dest_pos = melee_pos
        else
            return
        end
    end

    local unsafe_dist
    if fallback_unsafe then
        unsafe_dist = move_distance(const.move.traversable, qw.map_pos, dest_pos)
    end
    local dist = move_distance(const.move.safe, qw.map_pos, dest_pos)
    if dist == 0 or unsafe_dist == 0 or not dist and not unsafe_dist then
        return
    end

    if debug_channel("move") then
        local desc_str, dist_str
        if unsafe_dist then
            desc_str = "safe/unsafe distances"
            dist_str = tostring(dist) .. "/" .. tostring(unsafe_dist)
        else
            desc_str = "safe distance"
            dist_str = tostring(dist)
        end
        dsayf("Determining next move to destination %s with %s distance %s",
            cell_string_from_map_position(dest_pos), desc_str, dist_str)
    end

    local best_result
    for pos in adjacent_iter(qw.map_pos) do
        local result = assess_move(pos, dest_pos, best_result)
        if not result
                and fallback_unsafe
                and (not best_result or best_result.unsafe) then
            result = assess_move(pos, dest_pos, best_result, true)
        end

        if result then
            best_result = result
        end
    end

    return best_result
end

function best_move_towards_positions(positions, fallback_unsafe, want_melee)
    -- Find the best move for each position.
    local best_results, best_dist, best_unsafe
    for _, pos in ipairs(positions) do
        if positions_equal(qw.map_pos, pos) then
            return
        end

        local result = best_move_towards(pos, fallback_unsafe, want_melee)
        if not result then
            goto continue
        end

        if not best_results
                or best_unsafe and not result.unsafe
                or best_unsafe == result.unsafe
                    and result.dist < best_dist then
            best_results = { result }
            best_dist = result.dist
            best_unsafe = result.unsafe
        elseif result.dist == best_dist then
            table.insert(best_results, result)
        end

        ::continue::
    end

    if not best_results then
        return
    end

    -- We may have multiple positions with best moves at the same destination
    -- distance, so compare these to find a best one. We already know that
    -- these share the same move type and distance.
    local best_result
    for _, result in ipairs(best_results) do
        if not best_result
                or compare_table_keys(result, best_result, move_keys,
                    reversed_move_keys) then
            best_result = result
        end
    end
    return best_result
end

function best_move_towards_features(feats, allow_unsafe)
    if debug_channel("move") then
        dsay("Determining best move towards feature(s): " .. table.concat(feats, ", "))
    end

    local positions = get_feature_positions(feats)
    if positions then
        return best_move_towards_positions(positions, allow_unsafe)
    end
end

function best_move_towards_items(item_names, allow_unsafe)
    if debug_channel("move") then
        dsay("Determining best move towards item(s): " .. table.concat(item_names, ", "))
    end

    local positions = get_item_positions(item_names)
    if positions then
        return best_move_towards_positions(positions, allow_unsafe)
    end
end

function map_has_adjacent_unseen_at(pos)
    for apos in adjacent_iter(pos) do
        if map_is_unseen_at(apos) then
            return true
        end
    end

    return false
end

function map_has_adjacent_runed_doors_at(pos)
    for apos in adjacent_iter(pos) do
        if map_feature_at(apos) == "runed_clear_door" then
            return true
        end
    end

    return false
end

function best_move_towards_unexplored_near(map_pos, fallback_unsafe)
    if debug_channel("move") then
        dsayf("Determining best move towards unexplored squares near %s",
            cell_string_from_map_position(map_pos))
    end

    local i = 1
    for pos in radius_iter(map_pos, const.gxm) do
        if supdist(pos) <= const.gxm
                and map_is_reachable_at(pos, const.move.safe)
                    or fallback_unsafe
                        and map_is_reachable_at(pos, const.move.traversable)
                and (qw.open_runed_doors
                        and map_has_adjacent_runed_doors_at(pos)
                    or map_has_adjacent_unseen_at(pos)) then
            return best_move_towards(pos, fallback_unsafe)
        end

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("move-distance") then
                dsayf("Searched block %d for unexplored positions near %s",
                    i / 1000,
                    cell_string_from_map_position(map_pos))
            end

            coroutine.yield()
        end

        i = i + 1
    end
end

function best_move_towards_unexplored(allow_unsafe)
    return best_move_towards_unexplored_near(qw.map_pos, allow_unsafe)
end

function best_move_towards_unexplored_near_positions(map_positions, fallback_unsafe)
    local best_result
    for _, pos in ipairs(map_positions) do
        local result = best_move_towards_unexplored_near(pos, fallback_unsafe)
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
        if map_is_reachable_at(pos, const.move.safe) then
            local result = best_move_towards(pos, true)
            if result then
                return result
            end
        end

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("move-distance") then
                dsay("Searched block %d for safe positions")
            end

            coroutine.yield()
        end

        i = i + 1
    end
end

function assess_flee_blink_position(map_pos)
    if position_distance(map_pos, qw.map_pos) <= 1 then
        return
    end

    if not map_cell_see_cell(map_pos, qw.map_pos)
            or not map_is_safe_at(map_pos, true) then
        return
    end

    local best_result
    for _, dest_pos in ipairs(qw.flee_positions) do
        local dist
        if positions_equal(dest_pos, map_pos) then
            dist = 0
        elseif can_flee_to(dest_pos, map_pos) then
            dist = move_distance(const.move.flee, map_pos, dest_pos)
        end

        if dist and (not best_result or dist < best_result.dist) then
            best_result = { dist = dist, blink_pos = los_position(map_pos) }
        end
    end

    return best_result
end

function best_blink_towards_flee_position()
    local best_result
    for pos in radius_iter(qw.map_pos, qw.los_radius) do
        local result = assess_flee_blink_position(pos)
        if result and (not best_result or result.dist < best_result.dist) then
            best_result = result
        end
    end
    return best_result
end

function distance_map_move_path(dist_map, to_pos)
    local path = { to_pos }
    local cur_pos = to_pos
    local cur_dist = dist_map.map[to_pos.hash]
    while cur_dist > 0 do
        for pos in adjacent_iter(cur_pos) do
            local dist = dist_map.map[pos.hash]
            if dist and dist < cur_dist then
                -- We want the final path to be in forward order.
                table.insert(path, 1, pos)
                cur_dist = dist
                cur_pos = pos
                break
            end
        end
    end

    return path
end

function closest_melee_position(target_pos, start_pos, move_type, melee_range)
    if not melee_range then
        local mons = get_monster_at(los_position(target_pos))
        if mons then
            melee_range = mons:player_melee_range()
        else
            melee_range = player_melee_range()
        end
    end

    local dist_map = get_distance_map(move_type, start_pos)
    local best_pos, best_dist
    for pos in square_iter(target_pos, melee_range) do
        local dist = dist_map.map[pos.hash]
        if dist and map_positions_can_melee(pos, target_pos, melee_range)
                and (not best_dist or dist < best_dist) then
            best_pos = pos
            best_dist = dist
        end
    end

    return best_pos
end

function move_path(move_type, to_pos, melee_range, from_pos)
    if not from_pos then
        from_pos = qw.map_pos
    end

    if positions_equal(from_pos, to_pos) then
        return
    end

    if melee_range then
        if positions_can_melee(from_pos, to_pos, melee_range) then
            return
        end
    end

    local dist_map = get_distance_map(move_type, from_pos)
    if debug_channel("move-distance") then
        dsayf("%s move search from %s%s",
            distance_map_description(dist_map),
            cell_string_from_map_position(to_pos),
            melee_range and (" with melee range " .. melee_range) or "")
    end

    local best_pos
    if melee_range then
        best_pos = closest_melee_position(to_pos, from_pos, move_type)
        if not best_pos then
            return
        end
    else
        if not dist_map.map[to_pos.hash] then
            return
        end

        best_pos = to_pos
    end

    return distance_map_move_path(dist_map, best_pos)
end
