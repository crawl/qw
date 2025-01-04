----------------------
-- Distance-mapped movement calculations for the player.

local move_keys = { "trap", "cloud", "blocked", "unexcluded",
    "melee_count", "slow", "enemy_dist" }
local reversed_move_keys = { trap = true, cloud = true, blocked = true,
    melee_count = true, slow = true }

function assess_move(to_pos, from_pos, dist_map, best_result, use_unsafe)
    local to_los_pos = position_difference(to_pos, qw.map_pos)
    local result = { move = to_los_pos, dest = dist_map.pos,
        safe = not use_unsafe, trap = 0, cloud = 0, blocked = 0,
        unexcluded = 0, melee_count = 0, slow = 0,
        enemy_dist = const.inf_dist }

    if debug_channel("move-all") and map_is_traversable_at(to_pos) then
        dsay("Checking " .. (use_unsafe and "unsafe" or "safe")
            .. " move to " .. cell_string_from_map_position(to_pos))
    end

    local map = use_unsafe and dist_map.map or dist_map.excluded_map
    result.dist = map[hash_position(to_pos)]
    if not result.dist then
        if debug_channel("move-all") and map_is_traversable_at(to_pos) then
            dsay("No path to destination")
        end

        return
    end

    local current_dist = map[hash_position(from_pos)]
    if current_dist and result.dist >= current_dist then
        if debug_channel("move-all") then
            dsay("Distance of " .. result.dist .. " does not improve the"
                .. " starting position distance of " .. current_dist)
        end

        return
    end

    local best_ok = best_result and (use_unsafe or best_result.safe)
    if best_ok and result.dist > best_result.dist then
        if debug_channel("move-all") then
            dsay("Distance of " .. result.dist .. " is worse than the current"
                .. " best distance of " .. best_result.dist)
        end

        return
    end

    local from_los_pos = position_difference(from_pos, qw.map_pos)
    if not can_move_to(to_los_pos, from_los_pos, use_unsafe) then
        if debug_channel("move-all") then
            dsay("Can't move to position")
        end

        return
    end

    if use_unsafe then
        local feat = view.feature_at(to_los_pos.x, to_los_pos.y)
        local trap
        if feat:find("^trap_") then
            trap = feat:gsub("trap_", "")
        end
        if trap == "zot" then
            result.trap = 2
        elseif not c_trap_is_safe(trap) then
            result.trap = 1
        end

        local cloud = view.cloud_at(to_los_pos.x, to_los_pos.y)
        if cloud_is_dangerous(cloud) then
            result.cloud = 2
        elseif not cloud_is_safe(cloud) then
            result.cloud = 1
        end

        local mons = get_monster_at(to_los_pos)
        if mons and not mons:is_friendly() then
            result.blocked = mons:is_harmless() and 1 or 2
        end

        result.unexcluded = map_is_unexcluded_at(to_pos) and 1 or 0
    elseif not is_safe_at(to_los_pos) then
        if debug_channel("move-all") then
            dsay("Position is not safe")
        end

        return
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

    if not best_ok
            or compare_table_keys(result, best_result, move_keys,
                reversed_move_keys) then
        return result
    end
end

--[[
Get the best move towards the given map position using a distance map.
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
    local from_hash = hash_position(from_pos)
    if allow_unsafe then
        current_dist = dist_map.map[from_hash]
    end
    local current_safe_dist = dist_map.excluded_map[from_hash]

    if debug_channel("move-all") then
        local msg = "Determining move from "
            .. cell_string_from_map_position(from_pos)
            .. " to " ..  cell_string_from_map_position(dest_pos)

        if allow_unsafe then
            msg = msg .. " with safe/unsafe distances "
                .. current_safe_dist .. "/" .. current_dist
        else
            msg = msg .. " safe distance " .. current_safe_dist
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
        if map_is_unseen_at(apos) then
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
                dsay("Searched for unexplored in block " .. i / 1000
                    .. " of map positions near "
                    .. cell_string_from_map_position(map_pos))
            end

            coroutine.yield()
        end

        if supdist(pos) <= const.gxm
                and map_is_reachable_at(pos, allow_unsafe)
                and (qw.open_runed_doors
                        and map_has_adjacent_runed_doors_at(pos)
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
                dsay("Searched for safety in block " .. i / 1000
                    .. " of map positions")
            end

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

function assess_flee_blink_position(map_pos)
    if position_distance(map_pos, qw.map_pos) <= 1 then
        return
    end

    local los_pos = position_difference(map_pos, qw.map_pos)
    if not you.see_cell_no_trans(los_pos.x, los_pos.y)
            or not is_safe_at(los_pos) then
        return
    end

    local best_result
    for _, dest_pos in ipairs(qw.flee_positions) do
        if positions_equal(dest_pos, map_pos) then
            local dist_map = get_distance_map(dest_pos)
            local result = assess_move(dest_pos, qw.map_pos, dist_map,
                best_result)
            if result then
                result.blink_pos = los_pos
                best_result = result
            end
        elseif can_flee_to_map_position(dest_pos, map_pos) then
            local result = best_move_towards(dest_pos, map_pos)
            if result and (not best_result
                    or result.dist < best_result.dist) then
                result.blink_pos = los_pos
                best_result = result
            end
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

function distance_map_search_from(search, pos, current)
    local hash = hash_position(pos)
    if search.seen[hash] then
        return false
    end

    if debug_channel("move-all") then
        dsay("Checking distance map move from "
            .. cell_string_from_map_position(current)
            .. " to " .. cell_string_from_map_position(pos))
    end

    local cache = search.cache[hash]
    if cache ~= nil then
        if debug_channel("move-all") then
            dsay("Returning cached result for search")
        end

        if cache then
            for _, ppos in ipairs(cache) do
                table.insert(search.path, ppos)
            end

            return true
        else
            return false
        end
    end

    if search.square_func(pos) then
        table.insert(search.path, pos)
        search.seen[hash] = true
        local cur_i = #search.path

        if do_distance_map_search(search, pos) then
            local cache = { }
            for i = cur_i, #search.path do
                table.insert(cache, search.path[i])
            end
            search.cache[hash] = cache

            return true
        else
            search.path[#search.path] = nil
            search.seen[hash] = nil

            search.cache[hash] = false
            return false
        end
    end

    if debug_channel("move-all") then
        dsay("Square function failed")
    end

    search.cache[hash] = false
    return false
end

function do_distance_map_search(search, current)
    local dist = position_distance(search.target, current)
    if dist == 0
            or search.min_dist > 0
                and positions_can_melee(current, search.target,
                    search.min_dist) then
        search.move = position_difference(search.path[2], search.center)
        return true
    end

    local current_dist = search.map[hash_position(current)]
    if not current_dist then
        return false
    end

    for pos in adjacent_iter(current) do
        local dist = search.map[hash_position(pos)]
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

    if positions_equal(center, target)
            or min_dist > 0
                and positions_can_melee(center, target, min_dist) then
        return
    end

    if debug_channel("move-all") then
        dsay("Distance map move search from "
            .. cell_string_from_map_position(center)
            .. " to " .. cell_string_from_map_position(target))
    end

    local dist_map = get_distance_map(target)
    local map  = allow_unsafe and dist_map.map or dist_map.excluded_map
    local dist = map[hash_position(center)]
    if not dist then
        return
    end

    search = { center = center, target = target, square_func = square_func,
        min_dist = min_dist, allow_unsafe = allow_unsafe, map = map,
        dist = dist, path = { center },
        seen = { [hash_position(center)] = true } }

    if cache then
        search.cache = cache
    else
        search.cache = { }
    end

    if do_distance_map_search(search, center) then
        return search
    end
end
