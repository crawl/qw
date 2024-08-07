----------------------
-- Assessment of fleeing positions

function update_flee_positions()
    qw.flee_positions = {}

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
    if not positions then
        return
    end

    for i, pos in ipairs(positions) do
        local state
        if feats[i] == "escape_hatch_up" then
            state = get_map_escape_hatch(where_branch, where_depth, pos)
        end
        if (not state or state.safe)
                and map_is_reachable_at(pos) then
            if debug_channel("flee") then
                dsay("Adding flee position #"
                    .. tostring(#qw.flee_positions + 1) .. " at "
                    .. cell_string_from_map_position(pos))
            end

            table.insert(qw.flee_positions, pos)
        end
    end
end

function check_following_melee_enemies(radius)
    return check_enemies(radius,
        function(mons)
            return mons:can_melee_player() and mons:can_seek()
        end)
end

function want_to_flee()
    if not qw.can_flee_upstairs then
        return false
    end

    -- If we're stuck in danger a bad form or berserked with a non-melee
    -- weapon, fleeing is our best bet.
    if (qw.danger_in_los or options.autopick_on)
            and (in_bad_form() or you.berserk() and using_ranged_weapon()) then
        return true
    end

    if not qw.danger_in_los then
        if qw.last_flee_turn and you.turns() >= qw.last_flee_turn + 10 then
            qw.last_flee_turn = nil
        end

        if not qw.last_flee_turn then
            return false
        end

        return not buffed() and reason_to_rest(90)
    end

    -- Don't flee from a place were we'll be opportunity attacked, and don't
    -- flee when we have allies close by.
    if check_following_melee_enemies(2) or check_allies(3) then
        return false
    end

    -- When we're at low XL and trying to go up, we want to flee to known
    -- stairs when autoexplore is disabled, instead of engaging in combat. This
    -- rule helps Delvers in particular avoid fights near their starting level
    -- that would get them killed.
    if you.xl() <= 8
            and disable_autoexplore
            and goal_travel.first_dir == const.dir.up
            and not goal_travel.stairs_dir then
        return true
    end

    local enemy = get_scary_enemy(const.duration.available)
    if enemy and enemy:threat(const.duration.available) >= 5
            and enemy:name():find("slime creature")
            and enemy:name() ~= "slime creature" then
        return true
    end

    if have_extreme_threat() then
        return not will_fight_extreme_threat()
    end

    if will_kite() then
        return false
    end

    return not buffed()
        and reason_to_rest(90)
        and qw.starting_spell ~= "Summon Small Mammal"
end

function enemy_can_flee_attack(enemy, flee_dist)
    local dist_to_player = enemy:melee_move_distance(const.origin)
    if not dist_to_player then
        if debug_channel("flee-all") then
            local props = { is_ranged = "ranged", reach_range = "reach",
                move_delay = "move delay" }
            dsay("Ignoring monster that can't reach us: "
                .. monster_string(enemy, props))
        end

        return false
    end

    local closing_dist = dist_to_player
        - (enemy:is_ranged(true) and 4 or 0)
    local dist_gain = flee_dist
        * (player_move_delay() - enemy:move_delay())
        / enemy:move_delay()

    if debug_channel("flee-all") then
        local props = { is_ranged = "ranged", reach_range = "reach",
            move_delay = "move delay" }
        dsay("Evaluating " .. monster_string(enemy, props)
            .. " with a closing distance of "
            .. tostring(closing_dist)
            .. " compared to a distance gain of "
            .. tostring(dist_gain))
    end

    return closing_dist < dist_gain
end

function flee_function(map_pos)
    local pos = position_difference(map_pos, qw.map_pos)
    if view.withheld(pos.x, pos.y) or not is_safe_at(pos) then
        return false
    end

    if supdist(pos) > qw.los_radius then
        return true
    end

    local mons = get_monster_at(pos)
    if mons and not mons:is_friendly() then
        return false
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:can_melee_at(pos) then
            return false
        end
    end

    return true
end

function can_flee_to_destination(pos)
    local search = distance_map_search(qw.map_pos, pos, flee_function, 0)
    if not search then
        if debug_channel("flee") then
            dsay("Unable to find move to flee position at "
                .. cell_string_from_map_position(pos))
        end

        return false
    end

    if debug_channel("flee") then
        dsay("Evaluating flee position at "
            .. cell_string_from_map_position(pos) .. " with distance "
            .. tostring(search.dist))
    end

    local extreme_threat = have_extreme_threat()
    local flee_attackers = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy_can_flee_attack(enemy, search.dist) then
            flee_attackers = flee_attackers + 1
        end

        if flee_attackers > 2 or not extreme_threat and flee_attackers > 0 then
            if debug_channel("flee") then
                dsay("Not fleeing to " .. cell_string_from_map_position(pos)
                    .. " due to "  .. tostring(flee_attackers)
                    .. " or more attackers gaining distance")
            end

            return false
        end
    end

    if debug_channel("flee") then
        dsay("Able to flee to " .. cell_string_from_map_position(pos))
    end

    return true
end

function get_flee_move()
    if in_bad_form() then
        result = best_move_towards_positions(qw.flee_positions, true)

        if debug_channel("flee") then
            if result then
                dsay("Found bad form flee move to "
                    .. cell_string_from_position(result.move)
                    .. " towards destination "
                    .. cell_string_from_map_position(result.dest))
            else
                dsay("No bad form flee move found towards any destination")
            end
        end

        if not result then
            result = best_move_towards_unexplored(true)
        end

        if debug_channel("flee") then
            if result then
                dsay("Found bad form flee move to "
                    .. cell_string_from_position(result.move)
                    .. " towards destination near unexplored areas at "
                    .. cell_string_from_map_position(result.dest))
            else
                dsay("No bad form flee move found towards unexplored areas")
            end
        end

        return result
    end

    local valid_dests = {}
    for _, pos in ipairs(qw.flee_positions) do
        if can_flee_to_destination(pos) then
            table.insert(valid_dests, pos)
        end
    end

    local result = best_move_towards_positions(valid_dests)

    if debug_channel("flee") then
        if result then
            dsay("Found flee move to "
                .. cell_string_from_position(result.move)
                .. " towards destination "
                .. cell_string_from_map_position(result.dest))
        else
            dsay("No move found towards any flee destination")
        end
    end

    return result
end

function will_flee()
    if not want_to_flee() or unable_to_move() or dangerous_to_move() then
        return false
    end

    return get_flee_move()
end
