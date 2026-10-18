----------------------
-- Assessment of fleeing positions

function get_flee_positions()
    if qw.flee_positions then
        if #qw.flee_positions == 0 then
            return
        else
            return qw.flee_positions
        end
    end

    qw.flee_positions = {}
    local stairs_feats = level_stairs_features(where_branch, where_depth,
        const.dir.up)
    local search_feats = {}
    -- Only retreat to safe stairs with a safe destination.
    for _, feat in ipairs(stairs_feats) do
        local state = get_stairs_state(where_branch, where_depth, feat)
        local dest_state = get_destination_stairs_state(where_branch, where_depth,
            feat)
        if (not state or state.safe)
                and (not dest_state or dest_state.safe) then
            table.insert(search_feats, feat)
        end
    end

    local positions = get_feature_positions(search_feats)
    if not positions then
        return
    end

    local best_dist
    for _, pos in ipairs(positions) do
        if not can_flee_to(pos) then
            goto continue
        end

        if not best_dist or dist < best_dist then
            qw.flee_positions = { pos }
            best_dist = dist
        elseif dist == best_dist then
            table.insert(qw.flee_positions, pos)
        end

        ::continue::
    end

    if #qw.flee_positions == 0 then
        return
    else
        return qw.flee_positions
    end
end

function check_following_melee_enemies(radius)
    return check_enemies(radius,
        function(mons)
            return mons:can_melee_player() and mons:can_seek()
        end)
end

function want_to_flee_scary_enemy(duration)
    local enemies = assess_enemies(duration, nil, nil, true)
    local enemy = enemies.scary_enemy
    if enemy and enemy:threat() >= 5
            and enemy:name():find("slime creature")
            and enemy:name() ~= "slime creature" then
        return true
    end
end

function level_is_dangerous()
    return qw.danger_in_los
        or not autoexplored_level(where_branch, where_depth)
end

function was_recently_marked()
    return you.status("marked")
        or qw.last_marked_turns and qw.turns - qw.last_marked_turns < 40
end

function want_to_flee()
    if not qw.can_flee_upstairs then
        return false
    end

    -- If we're stuck in danger a bad form or berserked with a non-melee
    -- weapon, fleeing is our best bet.
    if (qw.danger_in_los or not options.autopick_on)
            and (in_bad_form() or you.berserk() and using_ranged_weapon()) then
        return true
    end

    if level_is_dangerous()
            -- Fleeing to stairs on Vaults:5 is often counterproductive.
            and not at_branch_end("Vaults")
            and was_recently_marked() then
        return true
    end

    -- We limit fleeing without danger in LOS to 10 turns in most cases.
    local escaping = goal_status == "Escape"
    if not qw.danger_in_los then
        if qw.last_flee_turn
                -- If we're escaping and we initiated fleeing to a hatch, we
                -- always continue fleeing until we leave the level, even if
                -- there's no danger. This is because a travel command wouldn't
                -- take us to this hatch, but to some staircase further away.
                and not (escaping and flee_destination_is_hatch())
                and qw.turns >= qw.last_flee_turn + 10 then
            qw.last_flee_turn = nil
        end

        if not qw.last_flee_turn then
            return false
        end

        return escaping or not buffed() and reason_to_rest(90)
    end

    -- Don't flee from a place were we'll be opportunity attacked, and don't
    -- flee when we have allies close by.
    if check_following_melee_enemies(2)
            or check_allies(3) and not escaping then
        return false
    end

    -- We generally prefer fleeing over fighting on the orb run.
    if escaping then
        return true
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

    if want_to_flee_scary_enemy(const.duration.ignore_buffs) then
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

function enemy_can_flee_attack(enemy, start_pos, flee_dist)
    local dist_to_player = enemy:melee_move_distance(start_pos)
    if not dist_to_player then
        if debug_channel("flee-all") then
            dsay("Ignoring monster that can't reach us: "
                .. monster_string(enemy))
        end

        return false
    end

    local closing_dist = dist_to_player - enemy:range()
    local dist_gain = flee_dist
        * (player_move_delay() - enemy:move_delay())
        / enemy:move_delay()

    if debug_channel("flee-all") then
        dsayf("Evaluating %s with a closing distance of %d compared to a"
                .. " distance gain of %d",
            monster_string(enemy), closing_dist, dist_gain)
    end

    return closing_dist < dist_gain
end

function flee_move_check_func(map_pos)
    local pos = los_position(map_pos)
    if not is_safe_at(pos) then
        return false
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

function flee_move_check(map_pos)
    return turn_memo_args(flee_move_check_func, map_pos)
end

function can_flee_to(dest_pos, start_pos)
    -- If start_pos is not the default of the player's position, we must map
    -- to dest_pos. Otherwise, if we're starting at the player's position, we
    -- can map there to check many flee destinations with one distance map.
    local dist_pos, dist_map_pos
    if start_pos then
        dist_pos = start_pos
        dist_map_pos = dest_pos
    else
        start_pos = qw.map_pos
        dist_pos = dest_pos
        dist_map_pos = start_pos
    end

    local dist = move_distance(const.move.flee, dist_pos, dist_map_pos)
    if not dist then
        if debug_channel("flee") then
            dsayf("Unable to find flee move from %s to %s",
                cell_string_from_map_position(start_pos),
                cell_string_from_map_position(dest_pos))
        end
        return false

    end

    if debug_channel("flee") then
        dsayf("Evaluating flee move from %s to %s with distance %d",
            cell_string_from_map_position(start_pos),
            cell_string_from_map_position(dest_pos),
            dist)
    end

    local extreme_threat = have_extreme_threat()
    local flee_attackers = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy_can_flee_attack(enemy, los_position(start_pos), dist) then
            flee_attackers = flee_attackers + 1
        end

        if flee_attackers > 2 or not extreme_threat and flee_attackers > 0 then
            if debug_channel("flee") then
                dsayf("Not fleeing to destination due to at least %d attackers"
                        .. " gaining distance",
                    flee_attackers)
            end

            return false
        end
    end

    if debug_channel("flee") then
        dsay("Able to flee to destination.")
    end

    return true
end

function best_flee_move()
    local flee_positions = get_flee_positions()
    if not flee_positions then
        return
    end

    if in_bad_form() then
        result = best_move_towards_positions(flee_positions)

        if debug_channel("flee") then
            if result then
                dsayf("Found bad form flee move to %s towards destination %s",
                    cell_string_from_position(result.move),
                    cell_string_from_map_position(result.dest_pos))
            else
                dsay("No bad form flee move found towards any destination")
            end
        end

        if not result then
            result = best_move_towards_unexplored(true)
        end

        if debug_channel("flee") then
            if result then
                dsayf("Found bad form flee move to %s towards unexplored areas"
                        .. " at %s",
                    cell_string_from_position(result.move),
                    cell_string_from_map_position(result.dest_pos))
            else
                dsay("No bad form flee move found towards unexplored areas")
            end
        end

        return result
    end

    local result = best_move_towards_positions(flee_positions)

    if debug_channel("flee") then
        if result then
            dsayf("Found flee move to %s towards destination %s",
                cell_string_from_position(result.move),
                cell_string_from_map_position(result.dest_pos))
        else
            dsay("No move found towards any flee destination")
        end
    end

    return result
end

function flee_destination_is_hatch()
    local move = best_flee_move()
    if not move then
        return false
    end

    return get_escape_hatch_state(where_branch, where_depth, move.dest_pos)
end

function will_flee()
    if not want_to_flee() or unable_to_move() or dangerous_to_move() then
        return false
    end

    return want_to_take_upstairs() or best_flee_move()
end
