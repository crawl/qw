----------------------
-- Assessment of retreat positions

function destination_component(positions, dest_pos)
    local components = {}
    local dest_ind
    local function merge_components(i, j)
        for _, pos in ipairs(components[j]) do
            table.insert(components[i], pos)
        end
        components[j] = nil
        if dest_ind == j then
            dest_ind = i
        end
    end
    for _, pos in ipairs(positions) do
        local target_ind
        for i, component in ipairs(components) do
            for _, cpos in ipairs(component) do
                if is_adjacent(pos, cpos) then
                    if target_ind then
                        merge_components(target_ind, i)
                    else
                        table.insert(component, pos)
                        target_ind = i
                    end

                    break
                end
            end
        end

        if not target_ind then
            table.insert(components, { pos })
            target_ind = #components
        end

        if not dest_ind
                and (positions_equal(pos, dest_pos)
                    or is_adjacent(pos, dest_pos)) then
            dest_ind = target_ind
        end
    end
    return components[dest_ind]
end

function register_destination_enemy(enemy, center, dest_pos, occupied_positions)
    local dest_hash = hash_position(dest_pos)
    if not occupied_positions[dest_hash] and enemy:can_traverse(dest_pos) then
        occupied_positions[dest_hash] = true
        occupied_positions.size = occupied_positions.size + 1
        return
    end

    local positions = {}
    for pos in radius_iter(center, enemy:reach_range()) do
        if enemy:can_traverse(pos)
            and (enemy:reach_range() == 1
                or positions_can_reach(pos, center)) then
            table.insert(positions, pos)
        end
    end

    local dest_component = destination_component(positions, dest_pos)
    if not dest_component then
        return
    end

    for _, pos in ipairs(dest_component) do
        local hash = hash_position(pos)
        if not occupied_positions[hash] then
            occupied_positions[hash] = true
            occupied_positions.size = occupied_positions.size + 1
            return
        end
    end
end

function player_last_position_towards(dest_pos)
    local dist_map = get_distance_map(qw.map_pos)
    local best_dist, best_pos
    for pos in adjacent_iter(dest_pos) do
        local map_pos = position_sum(qw.map_pos, pos)
        local dist = dist_map.excluded_map[map_pos.x][map_pos.y]
        if dist and can_move_to(dest_pos, pos)
                and is_safe_at(pos)
                and (not best_dist or dist < best_dist) then
            best_dist = dist
            best_pos = pos
        end
    end
    return best_pos
end

function monster_last_position_towards(mons, pos)
    -- The monster is already as close as they need to be.
    if position_distance(mons:pos(), pos) <= mons:reach_range() then
        return mons:pos()
    end

    local traversal_func = function(tpos)
        return mons:can_traverse(tpos)
    end
    local result = move_search(mons:pos(), pos, traversal_func,
        mons:reach_range())
    if result then
        return result.last_pos
    end
end

function attacking_monster_count_at(pos)
    local occupied_positions = { size = 0 }
    local player_dest_pos
    for _, enemy in ipairs(qw.enemy_list) do
        local dest_pos
        if cell_see_cell(enemy:pos(), pos) then
            dest_pos = monster_last_position_towards(enemy, pos)
        else
            if not player_dest_pos then
                player_dest_pos = player_last_position_towards(pos)
            end
            dest_pos = player_dest_pos
        end

        if dest_pos then
            register_destination_enemy(enemy, pos, dest_pos, occupied_positions)
        end
    end
    return occupied_positions.size
end

function can_retreat_from(from_pos, to_pos)
    if view.withheld(from_pos.x, from_pos.y) or not is_safe_at(from_pos) then
        return false
    end

    -- Once we're in the player's los, we start checking for los-related issues
    -- that prevent movement, such as non-hostile monsters we can't move past
    -- or attack to get out of our way.
    if supdist(to_pos) > qw.los_radius then
        return true
    end

    return not monster_in_way_at(to_pos, from_pos, true)
end

function reverse_retreat_move_to(to_pos, dist_map)
    local map = dist_map.excluded_map
    local to_dist = map[to_pos.x][to_pos.y]
    local to_los_pos = position_difference(to_pos, qw.map_pos)
    local best_pos
    for from_pos in adjacent_iter(to_pos) do
        local from_los_pos = position_difference(from_pos, qw.map_pos)
        -- Moving from from_pos to to_pos must make us closer to the player's
        -- position. We already know that to_pos is on the best path to the
        -- retreat position because we started there and are walking backwards
        -- to the player's position.
        local from_dist = map[from_pos.x][from_pos.y]
        if from_dist
                and from_dist < to_dist
                and can_retreat_from(from_los_pos, to_los_pos) then
            local mons = get_monster_at(from_los_pos)
            -- We prefer a move that doesn't force dealing with a hostile
            -- monster, if one is available.
            if not mons then
                return from_pos, false
            end

            if not best_pos and mons:attitude() < const.attitude.peaceful then
                best_pos = from_pos
            end
        end
    end
    return best_pos, true
end

function assess_retreat_position(map_pos, attacking_limit, max_dist)
    local pos = position_difference(map_pos, qw.map_pos)
    if not is_safe_at(pos) then
        return
    end

    local result = { pos = pos, map_pos = map_pos, num_blocking = 0 }
    result.num_attacking = attacking_monster_count_at(result.pos)

    if attacking_limit and result.num_attacking > attacking_limit then
        return
    end

    -- Further calculations not necessary for our current position.
    if position_is_origin(pos) then
        result.dist = 0
        return result
    end

    local dist_map = get_distance_map(qw.map_pos)
    result.dist = dist_map.excluded_map[map_pos.x][map_pos.y]
    if not result.dist
            or max_dist and result.dist > max_dist then
        return
    end

    -- Walk backwarks from the retreat position until we reach the player's
    -- position.
    local cur_pos = map_pos
    while not positions_equal(cur_pos, qw.map_pos) do
        local pos, has_mons = reverse_retreat_move_to(cur_pos, dist_map)
        if not pos then
            return
        end

        result.num_blocking = result.num_blocking + (has_mons and 1 or 0)
        cur_pos = pos
    end
    return result
end

function result_improves_retreat(retreat, result, best_result)
    if not result then
        return false
    end

    if not best_result then
        return true
    end

    return compare_table_keys(result, best_result, retreat.keys,
        retreat.reversed)
end

function best_retreat_position_func(attacking_limit)
    if not map_is_unexcluded_at(qw.map_pos) then
        return
    end

    if debug_channel("retreat") then
        dsay("Calculating best retreat position with attacking limit "
            .. tostring(attacking_limit))
    end

    local cur_result = assess_retreat_position(qw.map_pos)
    -- Our current location can't significantly improve.
    if cur_result and cur_result.num_attacking <= 1 then
        if debug_channel("retreat") then
            dsay("Can't improve retreat position over current location with "
                .. tostring(cur_result.num_attacking) .. " attacking monster(s)")
        end

        return cur_result
    end

    -- We never retreat further than our closest flee position, if one is
    -- available.
    local radius
    local flee_move = best_move_towards_positions(qw.flee_positions)
    if flee_move then
        radius = max(qw.los_radius, flee_move.dist + 1)
    else
        radius = const.gxm
    end

    local best_result = cur_result
    local retreat = { keys = { "num_blocking", "num_attacking", "dist" },
                      reversed = { num_blocking = true, num_attacking = true,
                          dist = true } }
    local i = 1
    for pos in radius_iter(qw.map_pos, radius) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched block " .. tostring(i / 1000)
                    .. " of potential retreat positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        if supdist(pos) <= const.gxm
                and map_is_reachable_at(pos)
                and adjacent_floor_map[pos.x][pos.y] < 6
                and not map_has_adjacent_unseen_at(pos) then
            local result = assess_retreat_position(pos, attacking_limit, radius)
            if result_improves_retreat(retreat, result, best_result) then
                best_result = result
            end
        end

        -- We have a good enough result to stop searching. Any subsequent
        -- position can't have a meaningfully lower attacking count and can't
        -- have a lower blocking count or distance at all.
        if best_result
                and best_result.num_attacking <= 1
                and best_result.num_blocking == 0
                and best_result.dist
                    <= position_distance(pos, qw.map_pos) then
            break
        end

        i = i + 1
    end

    if debug_channel("retreat") then
        if best_result then
            dsay("Found best retreat position at "
                .. cell_string_from_map_position(best_result.map_pos)
                .. " with distance " .. tostring(best_result.dist)
                .. " and " .. tostring(best_result.num_blocking)
                .. " blocking monsters"
                .. " and " .. tostring(best_result.num_attacking)
                .. " monsters attacking at destination")
        else
            dsay("No valid retreat position found")
        end
    end

    -- We have no viable retreating position or our current one is rated best.
    if not best_result then
        return
    elseif best_result.dist == 0 then
        if debug_channel("retreat") then
            dsay("Already at best retreat position")
        end

        return best_result
    end

    local enemies = assess_enemies()
    local cutoff
    if cur_result then
        cutoff = (cur_result.num_attacking - best_result.num_attacking)
            * (enemies.threat - enemies.ranged_threat / 2)
            * (10 + enemies.move_delay - player_move_delay()) / 10
    end

    -- Don't try to retreat if we have multiple monsters in the way. Don't try
    -- to retreat too far if our position doesn't improve enough. If our
    -- current position is unsafe such that it is not a valid retreat position,
    -- allow retreating as far as we need to, although in that case, other
    -- plans like cloud tactical step might have acted.
    if best_result.num_blocking > 1
            or cutoff and best_result.dist > cutoff then
        if debug_channel("retreat") then
            if best_result.num_blocking > 1 then
                dsay("Too many monsters blocking retreat")
            else
                dsay("Retreat distance is over cutoff of " .. tostring(cutoff))
            end
        end

        return
    end

    return best_result
end

function best_retreat_position(attacking_limit)
    return turn_memo_args("best_retreat_position",
        function()
            return best_retreat_position_func(attacking_limit)
        end, attacking_limit)
end

function will_fight_extreme_threat()
    if not using_ranged_weapon() then
        return want_to_be_surrounded()
    end

    local result = best_retreat_position(2)
    if not result then
        return false
    end

    return result.dist == 0 or best_move_towards(result.map_pos)
end

function retreat_distance_at(pos)
    if not qw.danger_in_los or not using_ranged_weapon() then
        return const.inf_dist
    end

    local map_pos = position_sum(qw.map_pos, pos)

    local enemies = assess_enemies(const.duration.available)
    if enemies.threat >= const.extreme_threat then
        local result = best_retreat_position(2)
        if not result then
            return const.inf_dist
        elseif positions_equal(map_pos, result.map_pos) then
            return 0
        end

        local move = best_move_towards(result.map_pos, map_pos)
        if move then
            return move.dist + 1
        else
            return const.inf_dist
        end
    end

    local enemies = assess_enemies()
    local adjusted_threat = enemies.threat - enemies.ranged_threat / 2
    if adjusted_threat < const.moderate_threat then
        if debug_channel("retreat") then
            dsay("No retreat position needed for low adjusted threat of "
                .. tostring(adjusted_threat)
                .. " (total/ranged threat: " .. tostring(enemies.threat)
                .. "/" .. tostring(enemies.ranged_threat) .. ")")
        end

        return const.inf_dist
    end

    local result = best_retreat_position(4)
    if not result then
        return const.inf_dist
    elseif positions_equal(map_pos, result.map_pos) then
        return 0
    end

    local move = best_move_towards(result.map_pos, map_pos)
    if move then
        return move.dist + 1
    end

    return const.inf_dist
end
