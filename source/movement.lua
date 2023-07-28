----------------------
-- Movement evaluation

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

-- Should only be called for adjacent squares.
function monster_in_way(pos, ignore_hostiles)
    local mons = get_monster_at(pos)
    if not mons then
        return false
    end

    local feat = view.feature_at(0, 0)
    local attitude = mons:attitude()
    return mons:name() == "orb of destruction"
        or not ignore_hostiles and attitude == const.attitude.hostile
        -- Attacking neutrals causes penance under the good gods.
        or attitude == const.attitude.neutral
            and mons:attacking_causes_penance()
        -- Strict neutral and up will swap with us, but we have to check that
        -- they can. We assume we never want to attack these.
        or attitude > const.attitude.neutral
            and (mons:is_constricted()
                or mons:is_caught()
                or mons:status("petrified")
                or mons:status("paralysed")
                or mons:status("constricted by roots")
                or mons:is("sleeping")
                or not mons:can_traverse(const.origin)
                or feat  == "trap_zot")
end

function assess_square_enemies(a, pos)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers = false
    a.adjacent = 0
    a.slow_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(enemy_list) do
        local dist = enemy:distance()
        local see_cell = view.cell_see_cell(pos.x, pos.y, enemy:x_pos(),
            enemy:y_pos())
        local ranged = enemy:is_ranged()
        local liquid_bound = enemy:is_liquid_bound()

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound and not ranged then
                a.followers = true
            end

            if have_reaching()
                    and not ranged
                    and enemy:speed() < player_speed() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (ranged or dist == 2 and enemy:is_fast()) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (enemy:is("wandering")
                    or enemy:is("sleeping")
                    or enemy:is("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (enemy:is("wandering")
                    or enemy:is("sleeping")
                    or enemy:is("dormant")
                    or enemy:is("dumb")
                    or liquid_bound
                    or enemy:is_stationary())
                and enemy:can_move_to_player_melee() then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function distance_to_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end

function distance_to_tabbable_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist
                and enemy:can_move_to_player_melee() then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end

function assess_square(pos)
    a = {}

    -- Distance to current square
    a.supdist = supdist(pos)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_brothers_in_arms(3) + count_greater_servants(3)
            + count_divine_warriors(3) > 0
    end

    -- Can we move there?
    a.can_move = a.supdist == 0
        or not view.withheld(pos.x, pos.y)
            and not monster_in_way(pos)
            and is_traversable_at(pos)
            and not is_solid_at(pos)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_enemies(a, pos)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish_at(pos)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the wall next to us dangerous?
    a.bad_wall = count_adjacent_slimy_walls_at(pos) > 0

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and not intrinsic_amphibious()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = is_safe_at(pos)
    cloud = view.cloud_at(pos.x, pos.y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil)
        or a.safe
        or danger and not cloud_is_dangerous(cloud)

    -- Equal to const.inf_dist if the move is not closer to any flee position
    -- in flee_positions, otherwise equal to the (min) dist to such a position.
    a.flee_distance = flee_improvement(pos)

    return a
end

function reason_to_flee()
    return (in_branch("Abyss") and not want_to_stay_in_abyss()
        or not in_branch("Abyss") and reason_to_rest(90)
        -- When we're at low XL and trying to go up, we want to flee to
        -- known stairs when autoexplore is disabled, instead of
        -- engaging in combat. This rule helps Delvers in particular
        -- avoid fights near their starting level that would get them
        -- killed.
        or you.xl() <= 8
            and disable_autoexplore
            and goal_travel.first_dir == const.dir.up)
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   reaching    - kiting slower monsters with reaching
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from a square adjacent to multiple monsters
--                 (when not cleaving)
--   fleeing     - moving towards stairs
function step_reason(a1, a2)
    local bad_form = in_bad_form()
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow or a2.bad_wall) and a1.cloud_safe then
        return false
    elseif not a1.near_ally
            and a2.flee_distance < const.inf_dist
            and a1.flee_distance > 0
            and a1.enemy_distance < 10
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked. Unless we're stuck in a bad form, in which case
            -- running is still our best bet.
            and (a1.adjacent == 0 and a2.adjacent == 0 or bad_form)
            and reason_to_flee()
            and not buffed()
            and starting_spell ~= "Summon Small Mammal" then
        return "fleeing"
    elseif not have_ranged_weapon()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not have_ranged_weapon()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require a ranged target or some close threats we want to melee
        -- that try to stay adjacent to us before we'll try to move
        -- out of water. We also require that we are no worse in at least one
        -- of ranged threats or enemy distance at the new position.
        if (have_ranged_target() or a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return false
        end
    elseif a1.bad_wall then
        -- Same conditions for dangerous walls as for water.
        if (have_ranged_target() or a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "wall"
        else
            return false
        end
    elseif have_reaching() and a1.slow_adjacent > 0 and a2.adjacent == 0
                 and a2.ranged == 0 then
        return "reaching"
    elseif cleaving() then
        return false
    elseif a1.adjacent == 1 then
        return false
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2
            -- We also need to be sure that any monsters we're stepping away
            -- from can eventually reach us, otherwise we'll be stuck in a loop
            -- constantly stepping away and then towards them.
            and incoming_melee_turn == you.turns() then
        return "outnumbered"
    else
        return false
    end
end

-- determines whether moving a0->a2 is an improvement over a0->a1
-- assumes that these two moves have already been determined to be better
-- than not moving, with given reasons
function step_improvement(best_reason, reason, a1, a2)
    if reason == "fleeing" and best_reason ~= "fleeing" then
        return true
    elseif best_reason == "fleeing" and reason ~= "fleeing" then
        return false
    elseif reason == "water" and best_reason == "water"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "water" and best_reason == "water"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif reason == "wall" and best_reason == "wall"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "wall" and best_reason == "wall"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.adjacent + a2.ranged < a1.adjacent + a1.ranged then
        return true
    elseif a2.adjacent + a2.ranged > a1.adjacent + a1.ranged then
        return false
    elseif cleaving() and a2.ranged < a1.ranged then
        return true
    elseif cleaving() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif reason == "fleeing" and a2.flee_distance < a1.flee_distance then
        return true
    elseif reason == "fleeing" and a2.flee_distance > a1.flee_distance then
        return false
    elseif a2.enemy_distance < a1.enemy_distance then
        return true
    elseif a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.flee_distance < a1.flee_distance then
        return true
    elseif a2.flee_distance > a2.flee_distance then
        return false
    elseif a1.cornerish and not a2.cornerish then
        return true
    else
        return false
    end
end

function choose_tactical_step()
    tactical_step = nil
    tactical_reason = "none"
    if unable_to_move()
            or you.confused()
            or you.berserk()
            or you.constricted()
            or you.status("spiked") then
        return
    end

    local a0 = assess_square(const.origin)
    if a0.cloud_safe
            and not (a0.fumble and sense_danger(3))
            and not (a0.bad_wall and sense_danger(3))
            and (not have_reaching() or a0.slow_adjacent == 0)
            and (a0.adjacent <= 1 or cleaving())
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end

    local best_pos, best_reason, besta
    local count = 1
    for pos in adjacent_iter(const.origin) do
        local a = assess_square(pos)
        local reason = step_reason(a0, a)
        if reason then
            if besta == nil
                    or step_improvement(best_reason, reason, besta, a) then
                best_pos = pos
                besta = a
                best_reason = reason
            end
        end

        count = count + 1
    end
    if besta then
        tactical_step = delta_to_vi(best_pos)
        tactical_reason = best_reason
    end
end

function distance_map_minimum_enemy_distance(dist_map, pspeed)
    -- We ignore enemy distance in bad forms, since fleeing is always one of
    -- our best options regardless of how close monsters are.
    if in_bad_form() then
        return
    end

    local min_dist
    for _, enemy in ipairs(enemy_list) do
        local gpos = position_sum(global_pos, enemy:pos())
        local dist = dist_map.excluded_map[gpos.x][gpos.y]
        if dist then
            local speed_diff = enemy:speed() - pspeed
            if speed_diff > 1 then
                dist = dist / 2
            elseif speed_diff > 0 then
                dist = dist / 1.5
            end

            -- In bad forms we need to try to run even if we take ranged
            -- damage.
            if not in_bad_form() and enemy:is_ranged() then
                dist = dist - 4
            end

            if not min_dist or dist < min_dist then
                min_dist = dist
            end
        end
    end
    return min_dist
end

function update_flee_positions()
    flee_positions = {}

    if unable_to_move() then
        return
    end

    local stairs_feats = level_stairs_features(where_branch, where_depth,
        const.dir.up)
    local search_feats = {}
    -- Only retreat to safe stairs with a safe destination.
    for _, feat in ipairs(stairs_feats) do
        local state = get_stairs(where_branch, where_depth, feat)
        local dest_state = get_destination_stairs(where_branch, where_depth,
            feat)
        if (not state or state.safe)
                and (not dest_state or dest_state.safe) then
            table.insert(search_feats, feat)
        end
    end

    local positions, feats = get_feature_map_positions(search_feats)
    if #positions == 0 then
        return
    end

    local safe_positions = {}
    for i, pos in ipairs(positions) do
        local state
        if feats[i] == "escape_hatch_up" then
            state = get_map_escape_hatch(where_branch, where_depth, pos)
        end
        if not state or state.safe then
            table.insert(safe_positions, pos)
        end
    end

    local pspeed = player_speed()
    for _, pos in ipairs(safe_positions) do
        local dist_map = get_distance_map(pos, true)
        local pdist = dist_map.excluded_map[global_pos.x][global_pos.y]
        local edist = distance_map_minimum_enemy_distance(dist_map, pspeed)
        if pdist and (not edist or pdist < edist) then
            if debug_channel("flee") then
                dsay("Adding flee position #" .. tostring(#flee_positions + 1)
                    .. " at " .. cell_string_from_map_position(pos))
            end

            table.insert(flee_positions, pos)
        end
    end
end

function best_flee_destination_at(pos)
    local best_dist, best_pos
    local is_origin = position_is_origin(pos)
    for _, flee_pos in ipairs(flee_positions) do
        local dist_map = get_distance_map(flee_pos)
        local map_pos = position_sum(global_pos, pos)
        local dist = dist_map.excluded_map[map_pos.x][map_pos.y]
        local current_dist = is_origin and dist
            or dist_map.excluded_map[global_pos.x][global_pos.y]
        if dist and (is_origin or not current_dist or dist < current_dist)
                and (not best_dist or dist < best_dist) then
            best_dist = dist
            best_pos = flee_pos
        end
    end
    return best_pos, best_dist
end

function flee_improvement(pos)
    local flee_pos, flee_dist = best_flee_destination_at(pos)
    if flee_pos then
        return flee_dist
    end

    return const.inf_dist
end

function get_move_closer(positions)
    local best_dist, best_move, best_dest
    for apos in adjacent_iter(const.origin) do
        local traversable = is_traversable_at(apos)
        for _, pos in ipairs(positions) do
            local dist = supdist(position_difference(pos, apos))
            if traversable and (not best_dist or dist < best_dist) then
                best_move = apos
                best_dest = pos
                best_dist = dist
            end
        end
    end

    return best_move, best_dest, best_dist
end

function move_search(search, current)
    local diff = position_difference(search.target, current)
    if supdist(diff) <= search.min_dist then
        search.result = position_difference(search.first_pos, search.center)
        return true
    end

    local function search_from(pos)
        if search.attempted[pos.x] and search.attempted[pos.x][pos.y]
                -- Our search should never leave LOS.
                or supdist(pos) > qw.los_radius then
            return false
        end

        if positions_equal(current, search.center) then
            search.first_pos = nil
        end

        if search.square_func(pos) then
            if not search.first_pos then
                search.first_pos = pos
            end

            if not search.attempted[pos.x] then
                search.attempted[pos.x] = {}
            end
            search.attempted[pos.x][pos.y] = true

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

function get_move_towards(center, target, square_func, min_dist)
    if not min_dist then
        min_dist = 0
    end

    if supdist(position_difference(center, target)) <= min_dist then
        return
    end

    search = {
        center = center, target = target, square_func = square_func,
        min_dist = min_dist
    }
    search.attempted = { [center.x] = { [center.y] = true } }

    if move_search(search, center) then
        return search.result
    end
end

function monster_can_move_to_player_melee(mons)
    local player_range = reach_range()
    -- The monster is already in range.
    if mons:distance() <= player_range then
        return true
    end

    local name = mons:name()
    if mons:is_stationary()
            or name == "wandering mushroom"
            or name:find("vortex")
            or mons:is("fleeing")
            or mons:status("paralysed")
            or mons:status("confused")
            or mons:status("petrified") then
        return false
    end

    local tab_func = function(pos)
        return mons:can_traverse(pos)
    end
    return get_move_towards(mons:pos(), const.origin, tab_func,
            mons:reach_range())
        -- If the monster can reach attack and we can't, be sure we can
        -- close the final 1-square gap.
        and (mons:reach_range() < 2
            or player_range > 1
            or get_move_closer({ mons:pos() }))
end

function best_move_towards(map_pos, ignore_exclusions)
    local dist_map = get_distance_map(map_pos)
    local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
    local current_dist = map[global_pos.x][global_pos.y]
    if current_dist == 0 then
        return
    end

    local result
    local safe_result
    for pos in adjacent_iter(global_pos) do
        local los_pos = position_difference(pos, global_pos)
        local dist = map[pos.x][pos.y]
        local better_dist = dist and (not current_dist or dist < current_dist)
        if better_dist
                and can_move_to(los_pos)
                and is_safe_at(pos)
                and (not safe_result or dist < safe_result.dist) then
            safe_result = { move = los_pos, dest = map_pos, dist = dist }
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
        local result = best_move_towards(pos)
        if result and (not best_result or result.dist < best_result.dist) then
            best_result = result
        end
    end
    return best_result
end

function update_reachable_position()
    for _, dist_map in pairs(distance_maps) do
        if dist_map.excluded_map[global_pos.x][global_pos.y] then
            reachable_position = dist_map.pos
            return
        end
    end

    reachable_position = global_pos
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
                hash_position(pos), { feat = const.feat_state.reachable })
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
    return best_move_towards_positions(positions, ignore_exclusions)
end

function best_move_towards_items(item_names, ignore_exclusions)
    local positions = get_item_map_positions(item_names)
    return best_move_towards_positions(positions, ignore_exclusions)
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
        local los_pos = position_difference(apos, global_pos)
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
    return best_move_towards_unexplored_near(global_pos, allow_unsafe)
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
    for pos in radius_iter(global_pos, const.gxm) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched for safety in block " .. tostring(i / 1000)
                    .. " of map positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        local los_pos = position_difference(pos, global_pos)
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
    if not move_destination then
        move_reason = nil
        return
    end

    local clear = false
    if move_reason == "goal" and want_goal_update then
        clear = true
    elseif move_reason == "monster" and danger then
        clear = true
    elseif positions_equal(global_pos, move_destination) then
        if move_reason == "unexplored"
                and autoexplored_level(where_branch, where_depth)
                and position_is_safe then
            reset_autoexplore(where)
        end

        clear = true
    end

    if clear then
        if debug_channel("explore") then
            dsay("Clearing move destination "
                .. cell_string_from_map_position(move_destination))
        end

        local dist_map = distance_maps[hash_position(move_destination)]
        if dist_map and not dist_map.permanent then
            distance_map_remove(dist_map)
        end

        move_destination = nil
        move_reason = nil
    end
end

function best_position_near(map_pos)
    if map_is_reachable_at(map_pos) then
        return pos
    end

    local best_dist, best_pos
    for pos in adjacent_iter(map_pos) do
        local dist = supdist(position_difference(pos, global_pos))
        if map_is_reachable_at(pos)
                and (not best_dist or dist < best_dist) then
            best_dist = dist
            best_pos = pos
        end
    end

    return best_pos
end
