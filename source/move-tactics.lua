----------------------
-- Tactical steps and fleeing

function assess_square_enemies(a, pos)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers = false
    a.adjacent = 0
    a.kite_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(enemy_list) do
        local dist = enemy:distance()
        local see_cell = cell_see_cell(pos, enemy:pos())
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

            if (have_reaching() or have_ranged_weapon())
                    and not ranged
                    and enemy:speed() < player_speed() then
                a.kite_adjacent = a.kite_adjacent + 1
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
                and enemy:has_path_to_player() then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function assess_square(pos)
    a = {}

    -- Distance to current square
    a.supdist = supdist(pos)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_brothers_in_arms(3)
            + count_greater_servants(3)
            + count_divine_warriors(3) > 0
    end

    -- Can we move there?
    a.can_move = a.supdist == 0 or can_move_to(pos)
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
    a.bad_wall = qw.have_slimy_walls and count_adjacent_slimy_walls_at(pos) > 0

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

    -- Equal to const.inf_dist if the position has no move to any flee,
    -- otherwise equal to the minimum movement distance to a flee position.
    a.flee_distance = flee_distance_at(pos)

    a.retreat_distance = retreat_distance_at(pos)

    return a
end

function reason_to_flee()
    return can_retreat_upstairs and reason_to_rest(90)
        -- When we're at low XL and trying to go up, we want to flee to
        -- known stairs when autoexplore is disabled, instead of
        -- engaging in combat. This rule helps Delvers in particular
        -- avoid fights near their starting level that would get them
        -- killed.
        or you.xl() <= 8
            and disable_autoexplore
            and goal_travel.first_dir == const.dir.up
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   kiting      - kiting slower monsters with reaching or a ranged weapon
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
            and a2.flee_distance < a1.flee_distance
            and a1.enemy_distance < 10
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked. Unless we're stuck in a bad form, in which case
            -- running is still our best bet.
            and (a1.adjacent == 0 and a2.adjacent == 0 or bad_form)
            and reason_to_flee()
            and not buffed()
            and starting_spell ~= "Summon Small Mammal" then
        return "fleeing"
    elseif a2.retreat_distance < a1.retreat_distance then
        return "retreating"
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
    elseif a1.kite_adjacent > 0 and a2.adjacent == 0 and a2.ranged == 0 then
        return "kiting"
    elseif want_to_be_surrounded() then
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
    elseif reason == "retreating" and best_reason ~= "retreating" then
        return true
    elseif best_reason == "retreating" and reason ~= "retreating" then
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
    elseif want_to_be_surrounded() and a2.ranged < a1.ranged then
        return true
    elseif want_to_be_surrounded() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif reason == "fleeing" and a2.flee_distance < a1.flee_distance then
        return true
    elseif reason == "fleeing" and a2.flee_distance > a1.flee_distance then
        return false
    elseif reason == "retreating"
            and a2.retreat_distance < a1.retreat_distance then
        return true
    elseif reason == "retreating"
            and a2.retreat_distance > a1.retreat_distance then
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
    qw.tactical_step = nil
    qw.tactical_reason = "none"
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
            and a0.kite_adjacent == 0
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end

    local best_pos, best_reason, besta
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
    end
    if besta then
        qw.tactical_step = delta_to_vi(best_pos)
        qw.tactical_reason = best_reason
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
        local gpos = position_sum(qw.map_pos, enemy:pos())
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
        local pdist = dist_map.excluded_map[qw.map_pos.x][qw.map_pos.y]
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

function best_flee_position_at(pos)
    local map_pos = position_sum(qw.map_pos, pos)
    local best_pos, best_dist
    local is_origin = position_is_origin(pos)
    for _, flee_pos in ipairs(flee_positions) do
        local dist_map = get_distance_map(flee_pos)
        local dist = dist_map.excluded_map[map_pos.x][map_pos.y]
        if dist and (not best_dist or dist < best_dist) then
            best_pos = flee_pos
            best_dist = dist
        end
    end
    return best_pos, best_dist
end

function flee_distance_at(pos)
    local flee_pos, flee_dist = best_flee_position_at(pos)
    if flee_pos then
        return flee_dist
    end

    return const.inf_dist
end
