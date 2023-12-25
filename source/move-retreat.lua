----------------------
-- Tactics for repositioning, retreating, and fleeing.

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
    if not enemy:can_cause_retreat() then
        return
    end

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
        local map_pos = position_sum(pos, qw.map_pos)
        local dist = dist_map.excluded_map[map_pos.x][map_pos.y]
        if can_move_to(pos)
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
    local result = move_search_result(mons:pos(), pos, traversal_func,
        mons:reach_range())
    if result then
        return result.last_pos
    end
end

function destination_monster_count_at(pos)
    local occupied_positions = { size = 0 }
    local player_dest_pos
    for _, enemy in ipairs(enemy_list) do
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

function can_move_from_position_to(from_pos, to_pos)
    if view.withheld(from_pos.x, from_pos.y)
            or view.withheld(to_pos.x, to_pos.y) then
        return false
    end

    local mons = get_monster_at(to_pos)
    if not mons then
        return true
    end

    if positions_equal(from_pos, const.origin)
            and mons:name() == "orb of destruction" then
        return false
    end

    local attitude = mons:attitude()
    if attitude == const.attitude.neutral
            and mons:attacking_causes_penance() then
        return false
    end

    if attitude > const.attitude.neutral then
        return friendly_can_swap_to(mons, from_pos)
    end

    return true
end

function reverse_retreat_move_to(to_pos, dist_map)
    local to_los_pos = position_difference(to_pos, qw.map_pos)
    local map = dist_map.excluded_map
    local best_pos, best_has_mons
    local to_dist = map[to_pos.x][to_pos.y]
    for from_pos in adjacent_iter(to_pos) do
        local from_los_pos = position_difference(from_pos, qw.map_pos)
        -- Moving from from_pos to to_pos must make us closer to the player's
        -- position. We already know that to_pos is on the best path to the
        -- retreat position because we started there and are walking backwards
        -- to the player's position.
        local from_dist = map[from_pos.x][from_pos.y]
        if from_dist
                and from_dist < to_dist
                -- Once we're in the player's los, we start checking for
                -- los-related issues that prevent movement, such as
                -- non-hostile monsters we can't move past. Hostile monsters
                -- will be considered by the caller of this function.
                and (supdist(to_los_pos) > qw.los_radius
                        or can_move_from_position_to(from_los_pos,
                            to_los_pos)) then
            local mons = get_monster_at(from_los_pos)
            local has_mons = mons
                and mons:attitude() < const.attitude.peaceful
            -- We prefer a move that doesn't force dealing with a hostile
            -- monster, if one is available.
            if not best_pos or not has_mons and best_has_mons then
                best_pos = from_pos
                best_has_mons = has_mons
            end
        end
    end
    return best_pos, best_has_mons
end

function assess_retreat_position(map_pos, max_distance)
    local result = { pos = position_difference(map_pos, qw.map_pos),
        map_pos = map_pos, blocking_count = 0 }
    result.destination_count = destination_monster_count_at(result.pos)

    -- We want to return a result for our current position so we can compare
    -- destination counts to it.
    if positions_equal(map_pos, qw.map_pos) then
        result.distance = 0
        return result
    end

    -- Don't bother continuing calculations since we'll never accept this
    -- position.
    if result.destination_count > 4 then
        return
    end

    local dist_map = get_distance_map(qw.map_pos)
    result.distance = dist_map.excluded_map[map_pos.x][map_pos.y]
    if not result.distance
            or max_distance and result.distance > max_distance then
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

        result.blocking_count = result.blocking_count + (has_mons and 1 or 0)
        cur_pos = pos
    end
    return result
end

function result_improves_retreat(result, best_result)
    if not result or result.destination_count > 4 then
        return false
    end

    if not best_result then
        return true
    end

    local keys = { "blocking_count", "destination_count", "distance" }
    local reversed_keys = { blocking_count = true, destination_count = true,
        distance = true }
    return compare_table_keys(result, best_result, keys, reversed_keys)
end

function best_retreat_position_func()
    if not map_is_unexcluded_at(qw.map_pos) then
        return
    end

    local cur_result = assess_retreat_position(qw.map_pos)
    -- Our current location can't improve.
    if cur_result and cur_result.destination_count <= 1 then
        return
    end

    local flee_pos, flee_dist = best_flee_position_at(const.origin)
    local radius = flee_dist
    if not radius then
        radius = const.gxm
    end

    local best_result = cur_result
    local i = 1
    for pos in radius_iter(qw.map_pos, radius) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched block " .. tostring(i / 1000)
                    .. " of map positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        if supdist(pos) <= const.gxm
                and map_is_reachable_at(pos)
                and adjacent_floor_map[pos.x][pos.y] < 6
                and not map_has_adjacent_unseen_at(pos) then
            local result = assess_retreat_position(pos, radius)
            if result_improves_retreat(result, best_result) then
                best_result = result
            end
        end

        -- We have a good enough result to stop searching. Any subsequent
        -- position can't have a meaningfully lower destination count and can't
        -- have a lower blocking count or distance at all.
        if best_result
                and best_result.destination_count <= 1
                and best_result.blocking_count == 0
                and best_result.distance
                    <= position_distance(pos, qw.map_pos) then
            break
        end
    end

    if best_result then
        -- Our current position is rated best.
        if best_result.distance == 0 then
            return
        end

        -- Don't try to travel too far if our position doesn't improve enough.
        -- This formula assumes we're willing to travel two squares for each
        -- point of total threat we see.
        local enemies = assess_enemies()
        local cutoff = cur_result.destination_count
            - best_result.destination_count
        cutoff = cutoff * (enemies.threat - enemies.ranged_threat / 2)
        if best_result.distance > cutoff then
            return
        end

        if debug_channel("retreat") then
            dsay("Found retreat position at "
                .. cell_string_from_map_position(best_result.map_pos)
                .. " with " .. tostring(best_result.blocking_count)
                .. " blocking monsters"
                .. " and " .. tostring(best_result.destination_count)
                .. " monsters attacking at destination at distance "
                .. best_result.distance)
        end
        return best_result.map_pos
    end

    if flee_pos then
        if debug_channel("retreat") then
            dsay("Retreating to best flee position at "
                .. cell_string_from_map_position(flee_pos))
        end
        return flee_pos
    end
end

function best_retreat_position(los_only)
    return turn_memo_args("best_retreat_position", best_retreat_position_func,
        los_only)
end

function want_to_retreat()
    if you.berserk()
            or want_to_be_surrounded()
            or assess_retreat_position(qw.map_pos).destination_count <= 1 then
        return false
    end

    local result = assess_enemies()
    if result.threat - result.ranged_threat / 2 >= 5 then
        return true
    end

    return false
end
