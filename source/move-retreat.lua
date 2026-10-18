----------------------
-- Assessment of retreat positions

function position_component(target_pos, positions)
    local components = {}
    local target_ind
    local function merge_components(i, j)
        for _, pos in ipairs(components[j]) do
            table.insert(components[i], pos)
        end
        components[j] = nil
        if target_ind == j then
            target_ind = i
        end
    end
    for _, pos in ipairs(positions) do
        local current_ind
        for i, component in ipairs(components) do
            for _, cpos in ipairs(component) do
                if is_adjacent(pos, cpos) then
                    if current_ind then
                        merge_components(current_ind, i)
                    else
                        table.insert(component, pos)
                        current_ind = i
                    end

                    break
                end
            end
        end

        if not current_ind then
            table.insert(components, { pos })
            current_ind = #components
        end

        if not target_ind
                and (positions_equal(pos, target_pos)
                    or is_adjacent(pos, target_pos)) then
            target_ind = current_ind
        end
    end

    return components[target_ind]
end

function enemy_melee_score_at(enemy, target_pos, melee_enemies, factor)
    if enemy:threat() < 1 then
        if debug_channel("retreat-all") then
            dsay("Ignoring melee enemy: low threat")
        end

        return 0
    end

    if enemy:can_melee_at(target_pos) then
        local score = enemy:threat() * factor
        if debug_channel("retreat-all") then
            dsayf("Assigning enemy to its current position for melee score"
                    .. " of %.1f",
                score)
        end

        melee_enemies[enemy:pos().hash] = enemy
        return score
    end

    local search = enemy:melee_move_search(target_pos)
    if not search then
        if debug_channel("retreat-all") then
            dsay("Ignoring melee enemy: can't reach player")
        end

        return 0
    end

    local seed_pos = search.path[#search.path]
    if not melee_enemies[seed_pos.hash]
            and not get_monster_at(seed_pos)
            and enemy:can_traverse(seed_pos) then
        local score = enemy:threat() * factor
        if debug_channel("retreat-all") then
            dsayf("Assigning enemy to seed position %s for melee score of %.1f",
                cell_string_from_position(seed_pos),
                score)
        end

        melee_enemies[seed_pos.hash] = enemy
        return score
    end

    local positions = {}
    for pos in radius_iter(target_pos, enemy:melee_range()) do
        if enemy:can_traverse(pos)
                and positions_can_melee(pos,
                    target_pos, enemy:melee_range()) then
            table.insert(positions, pos)
        end
    end

    local component = position_component(seed_pos, positions)
    if not component then
        if debug_channel("retreat-all") then
            dsay("Ignoring melee enemy: No available melee position found")
        end

        return 0
    end

    for _, pos in ipairs(component) do
        if not melee_enemies[pos.hash] and not get_monster_at(pos) then
            local score = enemy:threat() * factor
            if debug_channel("retreat-all") then
                dsayf("Assigning enemy to destination component position %s"
                        .. " for melee score of %.1f",
                    cell_string_from_position(pos),
                    score)
            end

            melee_enemies[pos.hash] = enemy
            return score
        end
    end

    if debug_channel("retreat-all") then
        dsay("Ignoring melee enemy: No available melee position found")
    end

    return 0
end

function enemy_target_los_distance(enemy, start_pos, end_pos, target_pos)
    if not target_pos then
        target_pos = end_pos
    end

    if cell_see_cell(start_pos, target_pos) then
        local los_dist = position_distance(start_pos, target_pos)
        if debug_channel("retreat-all") then
            dsayf("Found LOS distance of %d for target position %s via LOS"
                    .. " when starting from %s",
                los_dist,
                cell_string_from_position(target_pos),
                cell_string_from_position(start_pos))
        end

        return los_dist
    end

    local search = enemy:melee_move_search(end_pos, start_pos)
    if not search then
        return
    end

    for _, pos in ipairs(search.path) do
        if cell_see_cell(pos, target_pos) then
            local los_dist = position_distance(pos, target_pos)
            if debug_channel("retreat-all") then
                dsayf("Found LOS distance of %d for target position %s via"
                        .. " move path from %s to %s",
                    los_dist,
                    cell_string_from_position(target_pos),
                    cell_string_from_position(start_pos),
                    cell_string_from_position(end_pos))
            end

            return los_dist
        end
    end

    return const.inf_dist
end

function enemy_los_score_at(enemy, target_pos, player_path, player_los_dist)
    if using_ranged_weapon()
        -- Creeping Frost is their only significant ranged attack and we
        -- won't usually move towards this monster if solid walls would
        -- become adjacent.
        or enemy:name() == "ironbound frostheart"
            and not enemy:has_line_of_fire(target_pos) then
        return 0
    end

    local range = enemy:player_melee_range()
    if cell_see_cell(enemy:pos(), target_pos) then
        return max(0, position_distance(enemy:pos(), target_pos) - range)
    end

    local player_los_score = 0
    if player_los_dist then
        player_los_score = max(0, player_los_dist - range)
    end

    if player_path and enemy:regains_los() then
        -- We start at the first position after our current position.
        for i = 2, #player_path do
            local pos = los_position(player_path[i])
            if not cell_see_cell(enemy:pos(), pos) then
                local firing_pos = enemy:choose_firing_pos(pos)
                if firing_pos then
                    if debug_channel("retreat-all") then
                        dsayf("Chose firing position of %s",
                            cell_string_from_position(firing_pos))
                    end

                    local los_dist = enemy_target_los_distance(enemy,
                        enemy:pos(), firing_pos, target_pos)
                    if los_dist and los_dist < const.inf_dist then
                        return max(player_los_score, los_dist - range)
                    end

                    if los_dist then
                        los_dist = enemy_target_los_distance(enemy, firing_pos,
                            target_pos)
                        if los_dist then
                            return max(player_los_score, los_dist - range)
                        end
                    end

                    break
                end

                break
            end
        end
    end

    local los_dist = enemy_target_los_distance(enemy, enemy:pos(), target_pos)
    if los_dist then
        return max(player_los_score, los_dist - range)
    end

    return player_los_score
end

function enemy_ranged_score_at(enemy, target_pos, player_path, player_los_dist)
    if not enemy:is_ranged() then
        return 0
    end

    if enemy:threat() == 0 then
        return 0
    end

    local los_score = enemy_los_score_at(enemy, target_pos, player_path,
        player_los_dist)

    -- The player movement and enemy visibility components of ranged score
    -- don't apply for our current position, when player_path is nil. The
    -- LOS distance component still applies.
    local sight_score = 0
    local dist_score = 0
    if player_path then
        -- We skip the starting position.
        for i = 2, #player_path do
            local pos = los_position(player_path[i])
            if enemy:has_line_of_fire(pos) then
                sight_score = sight_score + 1
            elseif cell_see_cell(enemy:pos(), pos) then
                sight_score = sight_score + 0.75
            end
        end

        dist_score = 0.25 * player_move_delay() / enemy:move_delay()
            * (#player_path - 1)
    end

    local total_score = enemy:threat()
        * (player_move_delay() / 10 * (los_score + sight_score) + dist_score)

    if debug_channel("retreat-all") then
        dsayf("Ranged enemy final score: %.1f; LOS distance score: %.1f; Sight"
                .. " score: %.1f; Dist score: %.1f",
            total_score,
            los_score,
            sight_score,
            dist_score)
    end

    return total_score
end

function retreat_score_at(target_pos, player_path)
    local tree_score = 0
    local slimy_score = 0
    local player_los_dist
    if player_path then
        -- Skip the starting position.
        for i = 2, #player_path do
            local pos = los_position(player_path[i])
            if cell_see_cell(pos, target_pos) then
                player_los_dist = i - 1
            end

            -- We score the final position differently and even if we don't
            -- have a path.
            if i < #player_path then
                if qw.awaken_forest then
                    tree_score = tree_score + count_trees_at(pos)
                end

                slimy_score = slimy_score + count_slimy_walls_at(pos)
            end
        end
    end

    if qw.awaken_forest then
        tree_score = tree_score + 5 * count_trees_at(target_pos)
    end

    slimy_score = slimy_score + 5 * count_slimy_walls_at(target_pos)

    -- For fumbling melee attacks 37.5% of the time.
    local melee_factor = will_fumble_primary_attack_at(target_pos) and 1.6 or 1
    local melee_enemies = {}
    local melee_score = 0
    local dist_score = 0
    local ranged_score = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if debug_channel("retreat-all") then
            local props = { threat = "threat", melee_range = "melee range",
                move_delay = "move delay" }
            dsay("Assessing retreat score of " .. monster_string(enemy, props))
        end

        local score = enemy_melee_score_at(enemy, target_pos, melee_enemies, melee_factor)
        melee_score = melee_score + score
        local enemy_score = score

        if player_path and enemy:can_seek() and not enemy:is_ranged() then
            score = 0.1
                * enemy:threat()
                * player_move_delay()
                / enemy:move_delay()
                -- This is just the move distance.
                * (#player_path - 1)
            dist_score = dist_score + score
            enemy_score = enemy_score + score

            if debug_channel("retreat-all") then
                dsay("Distance score: " .. score)
            end
        end

        score = enemy_ranged_score_at(enemy, target_pos, player_path, player_los_dist)
        ranged_score = ranged_score + score
        enemy_score = enemy_score + score

        if debug_channel("retreat-all") then
            dsay("Total score for this enemy: " .. enemy_score)
        end
    end

    -- Ensure that we have an enemy to melee at the retreat position.
    if player_path and not using_ranged_weapon() then
        local can_melee = false
        for hash, enemy in pairs(melee_enemies) do
            if positions_can_melee(target_pos, position_from_hash(hash),
                    enemy:player_melee_range()) then
                can_melee = true
                break
            end
        end

        if not can_melee then
            if debug_channel("retreat-all") then
                dsay("Invalid retreat position: no enemy to melee")
            end

            return
        end
    end

    local trap_score = trap_score_at(target_pos)
    if not trap_score then
        trap_score = 0
    end

    local total_score = melee_score
        + dist_score
        + ranged_score
        + trap_score
        + tree_score
        + slimy_score

    if debug_channel("retreat-all") then
        dsayf("Final retreat score: %.1f; Player LOS distance: %s;"
                .. " Melee score: %.1f; Distance score: %.1f;"
                .. " Ranged score: %.1f; Trap score: %.1f;"
                .. " Tree score: %.1f; Slimy wall score: %.1f",
            total_score,
            -- Can be nil
            tostring(player_los_dist),
            melee_score,
            dist_score,
            ranged_score,
            trap_score,
            tree_score,
            slimy_score)
    end

    return total_score
end

function retreat_move_check_func(map_pos)
    if not map_is_safe_at(map_pos) then
        return false
    end

    local mons = get_monster_at(los_position(map_pos))
    if mons and not mons:player_can_swap() then
        return false
    end

    return true
end

function retreat_move_check(map_pos)
    return turn_memo_args(retreat_move_check_func, map_pos)
end

function assess_retreat_position(pos, dist)
    local result = { pos = pos, map_pos = map_position(pos), dist = dist }

    if dist == 0 and not is_safe_at(pos) then
        return
    end

    if debug_channel("retreat-all") then
        dsayf("Evaluating retreat position %s at distance %d",
            cell_string_from_position(pos),
            dist)
    end

    local player_path
    if dist > 0 then
        player_path = move_path(const.move.retreat, result.map_pos)
        if not player_path then
            if debug_channel("retreat-all") then
                dsay("Invalid retreat position: no valid retreat path")
            end

            return
        end
    end

    result.score = retreat_score_at(pos, player_path)
    if not result.score then
        return
    end

    return result
end

function best_retreat_result_func()
    if map_is_excluded_at(qw.map_pos) then
        return
    end

    -- The retreat location has become unreachable.
    if qw.retreat_result
            and not map_is_reachable_at(qw.map_pos,
                const.move.retreat, qw.retreat_result.map_pos) then
        qw.retreat_result = nil
        qw.retreat_turns = nil
    end

    if not qw.danger_in_los then
        if qw.retreat_result then
            if qw.turns - qw.retreat_turns > 10 then
                qw.retreat_result = nil
                qw.retreat_turns = nil
            else
                return qw.retreat_result
            end
        end

        return
    end

    local cur_result
    if is_safe_at(const.origin) then
        cur_result = assess_retreat_position(const.origin, 0)
    elseif debug_channel("retreat") then
        dsay("Current position is not safe")
    end

    -- We don't search for a new retreat position for at least 3 turns,
    -- unless our current position turns out to have a better score than the
    -- cached result.
    if qw.retreat_result then
        if qw.turns - qw.retreat_turns <= 3
                and (not cur_result
                    or qw.retreat_result.score < cur_result.score) then
            return qw.retreat_result
        else
            qw.retreat_result = nil
            qw.retreat_turns = nil
        end
    end

    local max_dist = qw.los_radius * 3
    if debug_channel("retreat") then
        local enemies = assess_enemies()
        dsayf("Calculating best retreat position; Max search radius: %d;"
                .. " Total threat: %.1f; Ranged threat: %.1f;"
                .. " Current position score: %s",
            max_dist,
            enemies.threat,
            enemies.ranged_threat,
            (cur_result and string.format("%.1f", cur_result.score) or "nil"))
    end

    local best_result = cur_result
    local i = 1
    for pos in radius_iter(qw.map_pos, max_dist) do
        local dist = move_distance(const.move.retreat, pos)
        if dist and dist < max_dist
                and not map_has_adjacent_unseen_at(pos)
                and retreat_move_check(pos) then
            local result = assess_retreat_position(los_position(pos), dist)
            if result and (not best_result or result.score < best_result.score) then
                best_result = result
            end
        end

        if qw.coroutine_throttle and i % 100 == 0 then
            if debug_channel("retreat-all") then
                dsayf("Searched block %d of potential retreat positions", i / 100)
            end

            coroutine.yield()
        end

        i = i + 1
    end

    if not best_result then
        if debug_channel("retreat") then
            dsay("Can't retreat: No safe retreat position found")
        end

        qw.retreat_result = nil
        qw.retreat_turns = nil
        return
    end

    if best_result.dist == 0 and debug_channel("retreat") then
        dsay("Can't retreat: Already at best retreat position")

        return
    end

    if debug_channel("retreat") then
        dsayf("Found new best retreat position with distance %d at %s with a"
                .. " retreat score of %.1f",
            best_result.dist,
            cell_string_from_position(best_result.pos),
            best_result.score)
    end

    qw.retreat_result = best_result
    qw.retreat_turns = qw.turns

    return best_result
end

function best_retreat_result()
    return turn_memo(best_retreat_result_func)
end

function will_fight_extreme_threat()
    if want_to_be_surrounded() then
        return true
    end

    return false
end

function retreat_distance_at(pos)
    local result = best_retreat_result()
    if result then
        local dist = move_distance(const.move.retreat, map_position(pos), result.map_pos)
        if dist then
            return dist
        else
            return const.inf_dist
        end
    else
        return const.inf_dist
    end
end
