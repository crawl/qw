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

function enemy_melee_score_at(enemy, target_pos, melee_enemies)
    if enemy:threat() < 1 then
        if debug_channel("retreat-enemy") then
            dsay("Ignoring melee enemy: low threat")
        end

        return 0
    end

    if positions_can_melee(enemy:pos(), target_pos, enemy:reach_range()) then
        if debug_channel("retreat-enemy") then
            dsay("Assigning melee enemy to its current position")
        end

        melee_enemies[hash_position(enemy:pos())] = enemy
        return enemy:threat()
    end

    local search = enemy:melee_move_search(target_pos)
    if not search then
        if debug_channel("retreat-enemy") then
            dsay("Ignoring melee enemy: can't reach player")
        end

        return 0
    end

    local seed_pos = search.path[#search.path]
    local seed_hash = hash_position(seed_pos)
    if not melee_enemies[seed_hash]
            and not get_monster_at(seed_pos)
            and enemy:can_traverse(seed_pos) then
        if debug_channel("retreat-enemy") then
            dsay("Assigning melee enemy to seed position "
                .. cell_string_from_position(seed_pos))
        end

        melee_enemies[seed_hash] = enemy
        return enemy:threat()
    end

    local positions = {}
    for pos in radius_iter(target_pos, enemy:reach_range()) do
        if enemy:can_traverse(pos)
                and positions_can_melee(pos, target_pos,
                    enemy:reach_range()) then
            table.insert(positions, pos)
        end
    end

    local component = position_component(seed_pos, positions)
    if not component then
        if debug_channel("retreat-enemy") then
            dsay("Ignoring melee enemy: No available melee position found")
        end

        return 0
    end

    for _, pos in ipairs(component) do
        local hash = hash_position(pos)
        if not melee_enemies[hash] and not get_monster_at(pos) then
            if debug_channel("retreat-enemy") then
                dsay("Assigning melee enemy to destination component position "
                    .. cell_string_from_position(pos))
            end

            melee_enemies[hash] = enemy
            return enemy:threat()
        end
    end

    if debug_channel("retreat-enemy") then
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
        if debug_channel("retreat-enemy") then
            dsay("Found LOS distance of " .. los_dist
                .. " for target position "
                .. cell_string_from_position(target_pos)
                .. " via LOS when starting from "
                .. cell_string_from_position(start_pos))
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
            if debug_channel("retreat-enemy") then
                dsay("Found LOS distance of " .. los_dist
                    .. " for target position "
                    .. cell_string_from_position(target_pos)
                    .. " via move search from "
                    .. cell_string_from_position(start_pos)
                    .. " to "
                    .. cell_string_from_position(end_pos))
            end

            return los_dist
        end
    end

    return const.inf_dist
end

function enemy_los_score_at(enemy, target_pos, player_search, player_los_dist)
    if using_ranged_weapon()
            -- Creeping Frost is their only significant ranged attack and we
            -- won't usually move towards this monster if solid walls would
            -- become adjacent.
            or enemy:name() == "ironbound frostheart"
                and not enemy:has_line_of_fire(target_pos) then
        return 0
    end

    local range = player_reach_range()
    if cell_see_cell(enemy:pos(), target_pos) then
        return max(0, position_distance(enemy:pos(), target_pos) - range)
    end

    local player_los_score = 0
    if player_los_dist then
        player_los_score = max(0, player_los_dist - range)
    end

    if player_search and enemy:regains_los() then
        -- The player search is in reverse, from the retreat destination to
        -- the player position, so we walk it in reverse and start from the
        -- first position after our current position.
        for i = #player_search.path - 1, 1, -1 do
            local pos = position_difference(player_search.path[i], qw.map_pos)
            if not cell_see_cell(enemy:pos(), pos) then
                local firing_pos = enemy:choose_firing_pos(pos)
                if firing_pos then
                    if debug_channel("retreat-enemy") then
                        dsay("Chose firing position of "
                            .. cell_string_from_position(firing_pos))
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

function enemy_ranged_score_at(enemy, target_pos, player_search,
        player_los_dist)
    if not enemy:is_ranged(true) then
        return 0
    end

    if enemy:threat() == 0 then
        return 0
    end

    local los_score = enemy_los_score_at(enemy, target_pos, player_search,
        player_los_dist)

    -- The player movement and enemy visibility components of ranged score
    -- don't apply for our current position, when player_search is nil. The
    -- LOS distance component still applies.
    local sight_score = 0
    local dist_score = 0
    if player_search then
        -- The player search starts from the retreat destination, so we walk
        -- backwards through the path, starting from the first from the first
        -- position after our current position.
        for i = #player_search.path - 1, 1, -1 do
            local pos = position_difference(player_search.path[i], qw.map_pos)
            -- Creeping Frost is their only significant ranged attack and
            -- doesn't depend on their approach.
            if enemy:name() == "ironbound frostheart" then
                sight_score = sight_score
                    + (enemy:has_line_of_fire(pos) and 1 or 0)
            elseif enemy:has_line_of_fire(pos) then
                sight_score = sight_score + 1
            elseif cell_see_cell(enemy:pos(), pos) then
                sight_score = sight_score + 0.75
            end
        end

        dist_score = 0.25 * player_move_delay() / enemy:move_delay()
            * player_search.dist
    end

    local score = enemy:threat()
        * (player_move_delay() / 10 * (los_score + sight_score) + dist_score)

    if debug_channel("retreat-enemy") then
        dsay("Ranged enemy final score: " .. score
            .. "; LOS distance score: " .. los_score
            .. "; sight score: " .. sight_score
            .. "; dist score: " .. dist_score)
    end

    return score
end

function retreat_score_at(target_pos, player_search)
    local player_los_dist
    local tree_score = 0
    local wall_score = 0
    if player_search then
        -- This starts from the map position of pos.
        for i = 2, #player_search.path do
            local pos = position_difference(player_search.path[i], qw.map_pos)
            if cell_see_cell(pos, target_pos) then
                player_los_dist = i - 1
            end

            if i < #player_search.path then
                if qw.awaken_forest then
                    tree_score = tree_score + count_trees_at(pos)
                end

                wall_score = wall_score + count_slimy_walls_at(pos)
            end
        end

        if debug_channel("retreat-pos") then
            dsay("Player LOS distance: " .. player_los_dist)
        end
    end

    if qw.awaken_forest then
        tree_score = 5 * count_trees_at(target_pos)

        if tree_score > 0 and debug_channel("retreat-pos") then
            dsay("Adding " .. tree_score .. " points for Awaken Forest")
        end
    end

    wall_score = 5 * count_slimy_walls_at(target_pos)

    if wall_score > 0 and debug_channel("retreat-pos") then
        dsay("Adding " .. wall_score .. " points for slimy walls")
    end

    local melee_enemies = {}
    local melee_score = 0
    local dist_score = 0
    local ranged_score = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if debug_channel("retreat-enemy") then
            local props = { threat = "threat", reach_range = "reach",
                move_delay = "move delay" }
            dsay("Assessing retreat score of " .. monster_string(enemy, props))
        end

        local score = enemy_melee_score_at(enemy, target_pos, melee_enemies)
        melee_score = melee_score + score

        if debug_channel("retreat-enemy") then
            dsay("Melee score: " .. score)
        end

        if player_search
                and enemy:can_seek()
                and not enemy:is_ranged(true) then
            local score = 0.1 * enemy:threat()
                * player_move_delay()
                    / enemy:move_delay()
                * player_search.dist

            if debug_channel("retreat-enemy") then
                dsay("Distance score: " .. score)
            end

            dist_score = dist_score + score
        end

        ranged_score = ranged_score
            + enemy_ranged_score_at(enemy, target_pos, player_search,
                player_los_dist)
    end

    -- Ensure that we have an enemy to melee at the retreat position.
    if player_search and not using_ranged_weapon() then
        local can_melee = false
        for hash, enemy in pairs(melee_enemies) do
            local pos = unhash_position(hash)
            if positions_can_melee(target_pos, pos, player_reach_range()) then
                can_melee = true
                break
            end
        end

        if not can_melee then
            if debug_channel("retreat-pos") then
                dsay("Invalid retreat position: no enemy to melee")
            end

            return
        end
    end

    if not using_ranged_weapon()
            and in_water_at(target_pos)
            and intrinsic_fumble() then
        -- For fumbling melee attacks 37.5% of the time.
        melee_score = melee_score * 1.6
    end

    local total_score = tree_score + wall_score + melee_score + dist_score
        + ranged_score

    if debug_channel("retreat-pos") then
        dsay("Final retreat score: " .. total_score)
    end

    return total_score
end

function retreat_move_check(map_pos)
    local pos = position_difference(map_pos, qw.map_pos)
    if not is_safe_at(pos) then
        return false
    end

    local mons = get_monster_at(pos)
    if mons and not mons:is_friendly() then
        return false
    end

    return true
end

function assess_retreat_position(map_pos, dist, cache)
    local pos = position_difference(map_pos, qw.map_pos)
    local result = { pos = pos, map_pos = map_pos }

    local is_origin = position_is_origin(pos)
    if is_origin then
        if not is_safe_at(pos) then
            return
        end

        result.dist = 0
    else
        result.dist = dist
    end

    if debug_channel("retreat-pos") then
        dsay("Evaluating retreat position "
            .. cell_string_from_map_position(map_pos)
            .. " at distance " .. result.dist)
    end

    local player_search
    if not is_origin then
        player_search = distance_map_search(map_pos, qw.map_pos,
            retreat_move_check, 0, false, cache)
        if not player_search then
            if debug_channel("retreat-pos") then
                dsay("Invalid retreat position: no valid retreat path")
            end

            return
        end

    end

    result.score = retreat_score_at(pos, player_search)
    if not result.score then
        return
    end

    return result
end

function best_retreat_result_func()
    if not map_is_unexcluded_at(qw.map_pos) then
        return
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

    local cache = {}
    local cur_result
    if is_safe_at(const.origin) then
        cur_result = assess_retreat_position(qw.map_pos, nil, cache)
    elseif debug_channel("retreat") then
        dsay("Current position is not safe")
    end

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

    -- We never retreat further than our closest flee position, if one is
    -- available.
    local max_dist = const.max_search_radius
    local flee_move = best_move_towards_positions(qw.flee_positions)
    if flee_move then
        max_dist = min(max_dist, max(qw.los_radius, flee_move.dist + 1))
    end

    local enemies = assess_enemies()
    if debug_channel("retreat") then
        local enemies = assess_enemies()
        dsay("Calculating best retreat position"
            .. " with max search radius of " .. max_dist
            .. " and threat of " .. enemies.threat
            .. " and ranged threat of " .. enemies.ranged_threat
            .. " and current retreat score of "
            .. (cur_result and cur_result.score or "nil"))
    end

    local best_result = cur_result
    local i = 1
    local dist_map = get_distance_map(qw.map_pos, max_dist)
    for pos in radius_iter(qw.map_pos, max_dist) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched block " .. i / 1000
                    .. " of potential retreat positions")
            end

            coroutine.yield()
        end

        local dist = dist_map.excluded_map[hash_position(pos)]
        if dist and dist < max_dist
                and not map_has_adjacent_unseen_at(pos)
                and retreat_move_check(pos) then
            local result = assess_retreat_position(pos, dist, cache)
            if result and (not best_result
                    or best_result.score > result.score) then
                best_result = result
            end
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
        dsay("Found new best retreat position with distance "
            .. best_result.dist .. " at "
            .. cell_string_from_map_position(best_result.map_pos)
            .. " with a retreat score of " .. best_result.score)
    end

    qw.retreat_result = best_result
    qw.retreat_turns = qw.turns

    return best_result
end

function best_retreat_result()
    return turn_memo("best_retreat_result", best_retreat_result_func)
end

function will_fight_extreme_threat()
    if want_to_be_surrounded() then
        return true
    end

    return false
end

function retreat_distance_at(pos)
    local map_pos = position_sum(qw.map_pos, pos)
    local result = best_retreat_result()
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
