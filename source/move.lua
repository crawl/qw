----------------------
-- General movement calculations

function can_move_to(to_pos, from_pos, allow_hostiles)
    return not view.withheld(to_pos.x, to_pos.y)
        and (supdist(to_pos) > qw.los_radius
            or not monster_in_way_at(to_pos, from_pos, allow_hostiles))
end

function player_can_swap_mons_to(mons, pos)
    return mons:player_can_swap()
        and mons:can_traverse(pos)
        and feature_at(pos) ~= "trap_zot"
end

function monster_in_way_at(to_pos, from_pos, allow_hostiles)
    local mons = get_monster_at(to_pos)
    if not mons then
        return false
    end

    -- Assume this is a blink move. We can't ever blink onto any kind of
    -- monster.
    if position_distance(to_pos, from_pos) > 1 then
        return true
    end

    return not (player_can_swap_mons_to(mons, from_pos)
        or allow_hostiles and mons:player_can_attack())
end

function get_move_closer(pos)
    local best_move, best_dist
    for apos in adjacent_iter(const.origin) do
        local dist = position_distance(pos, apos)
        if is_safe_at(pos) and (not best_dist or dist < best_dist) then
            best_move = apos
            best_dist = dist
        end
    end

    return best_move, best_dist
end

function update_move_destination()
    if not qw.move_destination then
        qw.move_reason = nil
        return
    end

    local clear = false
    if qw.move_reason == "goal" and qw.want_goal_update then
        clear = true
    elseif qw.move_reason == "monster" and have_target() then
        clear = true
    elseif positions_equal(qw.map_pos, qw.move_destination) then
        if qw.move_reason == "unexplored"
                and autoexplored_level(where_branch, where_depth)
                and qw.position_is_safe then
            reset_autoexplore(where_branch, where_depth)
        end

        clear = true
    end

    if clear then
        if debug_channel("move") then
            dsay("Clearing move destination "
                .. cell_string_from_map_position(qw.move_destination))
        end

        qw.move_destination = nil
        qw.move_reason = nil
    end
end

function move_to(pos, cloud_waiting)
    if cloud_waiting == nil then
        cloud_waiting = true
    end

    if cloud_waiting
            and not qw.position_is_cloudy
            and not is_excluded_at(pos)
            and cloud_is_dangerous_at(pos) then
        wait_one_turn()
        return true
    end

    local mons = get_monster_at(pos)
    if mons and monster_in_way_at(pos, const.origin, true) then
        if mons:player_can_attack() then
            return shoot_launcher(pos)
        else
            return false
        end
    end

    magic(delta_to_vi(pos) .. "YY")
    return true
end

function move_towards_destination(pos, dest, reason)
    if move_to(pos) then
        qw.move_destination = dest
        qw.move_reason = reason
        return true
    end

    return false
end
