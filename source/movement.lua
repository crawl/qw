----------------------
-- Movement evaluation

function can_move_to(pos)
    return is_traversable_at(pos)
        and not view.withheld(pos.x, pos.y)
        and not monster_in_way(pos)
end

-- XXX: This needs to run before update_map() and hence before traversal_map is
-- updated, so we have to do an uncached check. Ideally we'd use the traversal
-- map, but this requires separating the traversal map update to its own path
-- and somehow retaining information about the per-cell changes so update_map()
-- can propagate updates to adjacent cells.
function traversable_square(pos)
    return feature_is_traversable(view.feature_at(pos.x, pos.y))
end

function flight_traversable_square(pos)
    return feature_is_traversable(view.feature_at(pos.x, pos.y), true)
end

function tabbable_square(pos)
    return view.feature_at(pos.x, pos.y) ~= "unseen"
        and view.is_safe_square(pos.x, pos.y)
        and (not monster_map[pos.x][pos.y]
            or monster_map[pos.x][pos.y]:is_firewood())
end

function flight_tabbable_square(pos)
    return view.feature_at(pos.x, pos.y) ~= "unseen"
        and view.is_safe_square(pos.x, pos.y, true)
        and (not monster_map[pos.x][pos.y]
            or monster_map[pos.x][pos.y]:is_firewood())
end

-- Should only be called for adjacent squares.
function monster_in_way(pos)
    local mons = monster_map[pos.x][pos.y]
    local feat = view.feature_at(0, 0)
    return mons and (mons:attitude() <= enum_att_neutral
            and not branch_step_mode
        or mons:attitude() > enum_att_neutral
            and (mons:is_constricted()
                or mons:is_caught()
                or mons:status("petrified")
                or mons:status("paralysed")
                or mons:status("constricted by roots")
                or mons:is("sleeping")
                or not mons:can_traverse(origin)
                or feat  == "trap_zot"))
end

function assess_square_enemies(a, pos)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers_to_land = false
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

            if not liquid_bound
                    and not ranged
                    and enemy:reach_range() < 2 then
                a.followers_to_land = true
            end

            if have_reaching()
                    and not ranged
                    and enemy:reach_range() < 2
                    and enemy:speed() < player_speed() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (dist == 2
                        and (enemy:is_fast() or enemy:reach_range() >= 2)
                    or ranged) then
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

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and not intrinsic_amphibious()
        and not intrinsic_flight()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = view.is_safe_square(pos.x, pos.y)
    cloud = view.cloud_at(pos.x, pos.y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil)
        or a.safe
        or danger and not cloud_is_dangerous(cloud)

    -- Equal to INF_DIST if the move is not closer to any position in
    -- flee_positions, otherwise equal to the (min) dist to such a stair
    a.flee_distance = stairs_improvement(pos)

    return a
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
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow) and a1.cloud_safe then
        return false
    elseif not a1.near_ally
            and a2.flee_distance < INF_DIST
            and a1.flee_distance > 0
            and a1.enemy_distance < 10
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked.
            and a1.adjacent == 0
            and a2.adjacent == 0
            -- At low XL, we want to flee to known stairs when autoexplore is
            -- disabled, instead of engaging in combat. Since autoexplore is
            -- disabled, we don't want to explore the current level and will be
            -- taking stairs to some new destination, which is usually a level
            -- above us. This rule makes Delvers to climb upwards if they
            -- can, instead of fighting dangerous monsters.
            and (reason_to_rest(90) or you.xl() <= 8 and disable_autoexplore)
            and not buffed()
            and (no_spells or starting_spell() ~= "Summon Small Mammal") then
        return "fleeing"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require some close threats that try to stay adjacent to us before
        -- we'll try to move out of water. We also require that we are no worse
        -- in at least one of ranged threats or enemy distance at the new
        -- position.
        if a1.followers_to_land
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
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
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2 then
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
    if you.confused()
            or you.berserk()
            or you.constricted()
            or not can_move()
            or in_branch("Slime")
            or you.status("spiked") then
        return
    end
    local a0 = assess_square(origin)
    if a0.cloud_safe
            and not (a0.fumble and sense_danger(3))
            and (not have_reaching() or a0.slow_adjacent == 0)
            and (a0.adjacent <= 1 or cleaving())
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end
    local best_pos, best_reason, besta
    for pos in adjacent_iter(origin) do
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
    end
    if besta then
        tactical_step = delta_to_vi(best_pos)
        tactical_reason = best_reason
    end
end

function get_move_closer(positions)
    local best_dist, best_move, best_dest
    for apos in adjacent_iter(origin) do
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

    return best_move, best_dest
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
                or supdist(pos) > los_radius then
            return false
        end

        if current.x == search.center.x and current.y == search.center.y  then
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
    if name == "wandering mushroom"
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
    return get_move_towards(mons:pos(), origin, tab_func, mons:reach_range())
        -- If the monster can reach attack and we can't, be sure we can
        -- close the final 1-square gap.
        and (mons:reach_range() < 2
            or player_range > 1
            or get_move_closer({ mons:pos() }))
end

function best_move_towards_map_positions(positions, ignore_exclusions, radius)
    local best_dist, best_dest
    local best_move = {}
    for _, pos in ipairs(positions) do
        local dist_map = get_distance_map(pos, radius)
        local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
        for dpos in adjacent_iter(global_pos) do
            local dist = map[dpos.x][dpos.y]
            if dist and (not best_dist or dist < best_dist) then
                best_dist = dist
                best_move = position_difference(dpos, global_pos)
                best_dest = pos
            end
        end
    end

    if best_dist then
        return best_move, best_dest
    end
end

function best_move_towards_map_position(pos, ignore_exclusions, radius)
    return best_move_towards_map_positions({ pos }, ignore_exclusions, radius)
end

function best_move_towards_features(feats, ignore_exclusions, radius)
    local positions = get_feature_map_positions(feats, radius)
    if #positions > 0 then
        return best_move_towards_map_positions(positions, ignore_exclusions,
            radius)
    end
end

function best_move_towards_items(item_names, ignore_exclusions, radius)
    local positions = get_item_map_positions(item_names, radius)
    if #positions > 0 then
        return best_move_towards_map_positions(positions, ignore_exclusions,
            radius)
    end
end

function destination_features()
    if gameplan_travel.first_dir then
        return level_stairs_features(where_branch, where_depth,
            gameplan_travel.first_dir)
    elseif gameplan_travel.first_branch then
        return { branch_entrance(gameplan_travel.first_branch) }
    else
        local god = gameplan_god(gameplan_status)
        if god then
            return { god_altar(god) }
        end
    end
end

function best_move_towards_destination(ignore_exclusions, radius)
    local feats = destination_features()
    if not feats then
        return
    end

    return best_move_towards_features(feats, ignore_exclusions, radius)
end

function map_position_has_adjacent_unseen(pos)
    for apos in adjacent_iter(pos) do
        if traversal_map[apos.x][apos.y] == nil then
            return true
        end
    end

    return false
end

function best_move_towards_unexplored()
    local reachable_positions
    if #flee_positions > 0 then
        reachable_positions = flee_positions
    else
        reachable_positions = { global_pos }
    end

    for pos in radius_iter(global_pos, GXM) do
        if map_is_traversable_at(pos)
                and map_position_has_adjacent_unseen(pos) then
            for _, reachable_pos in ipairs(reachable_positions) do
                local dist_map = get_distance_map(reachable_pos)
                if dist_map.map[pos.x][pos.y] then
                    return best_move_towards_map_position(pos, true)
                end
            end
        end
    end
end

function best_move_towards_unexcluded()
    local reachable_positions
    if #flee_positions > 0 then
        reachable_positions = flee_positions
    else
        reachable_positions = { global_pos }
    end

    for pos in radius_iter(global_pos, GXM) do
        if map_is_traversable_at(pos) and map_is_unexcluded_at(pos) then
            for _, reachable_pos in ipairs(reachable_positions) do
                local dist_map = get_distance_map(reachable_pos)
                if dist_map.map[pos.x][pos.y] then
                    return best_move_towards_map_position(pos, true)
                end
            end
        end
    end
end

function update_move_destination()
    if not move_destination then
        return
    end

    local monster = move_reason == "monster"
    if monster and danger then
        reset = true
    elseif monster then
        local pos = position_difference(move_destination, global_pos)
        if supdist(pos) <= los_radius
                and you.see_cell_no_trans(pos.x, pos.y) then
            reset = true
        end
    elseif global_pos.x == move_destination.x
            and global_pos.y == move_destination.y then
        reset = true
    end

    if reset then
        move_destination = nil
        move_reason = nil
    end
end
