------------------
-- Plans to try when qw is stuck with no viable plan to execute.

function plan_random_step()
    if unable_to_move() or dangerous_to_move() then
        return false
    end

    qw.stuck_turns = qw.stuck_turns + 1
    return random_step("stuck")
end

function plan_stuck_initial()
    if qw.stuck_turns <= 50 then
        return plan_random_step()
    end

    return false
end

function plan_stuck_take_escape_hatch()
    local dir = escape_hatch_type(view.feature_at(0, 0))
    if not dir or unable_to_use_stairs() then
        return false
    end

    if dir == const.dir.up then
        go_upstairs()
    else
        go_downstairs()
    end

    return true
end

function plan_stuck_move_towards_escape_hatch()
    if want_to_use_escape_hatches(const.dir.up) then
        return false
    end

    local hatch_dir
    if goal_travel.first_dir then
        hatch_dir = goal_travel.first_dir
    else
        hatch_dir = const.dir.up
    end
    local feat = const.escape_hatches[hatch_dir]

    local result = best_move_towards_features({ feat }, true)
    if result then
        return move_towards_destination(result.move, result.dest, "hatch")
    end

    feat = const.escape_hatches[-hatch_dir]
    result = best_move_towards_features({ feat }, true)
    if result then
        return move_towards_destination(result.move, result.dest, "hatch")
    end

    return false
end

function plan_clear_exclusions()
    local n = clear_exclusion_count[where] or 0
    if n > 20 then
        return false
    end

    clear_exclusion_count[where] = n + 1
    remove_exclusions(true)
    magic("X" .. control('e'))
    qw.do_dummy_action = false
    return true
end

function plan_stuck_dig_grate()
    local wand = find_item("wand", "digging")
    if not wand or not can_evoke() then
        return false
    end

    local grate_offset = 20
    local grate_pos
    for pos in square_iter(const.origin) do
        if view.feature_at(pos.x, pos.y) == "iron_grate" then
            if abs(pos.x) + abs(pos.y) < grate_offset
                    and you.see_cell_solid_see(pos.x, pos.y) then
                grate_pos = pos
                grate_offset = abs(pos.x) + abs(pos.y)
            end
        end
    end

    if grate_offset < 20 then
        return evoke_targeted_item(wand, grate_pos)
    end

    return false
end

function plan_forget_map()
    if not qw.position_is_cloudy
            and not qw.danger_in_los
            and (at_branch_end("Slime") and not have_branch_runes("Slime")
                or at_branch_end("Geh") and not have_branch_runes("Geh")) then
        magic("X" .. control('f'))
        return true
    end

    return false
end

function plan_stuck_teleport()
    if can_teleport() then
        return teleport()
    end

    return false
end

function set_plan_stuck()
    plans.stuck = cascade {
        {plan_abyss_wait_one_turn, "abyss_wait_one_turn"},
        {plan_stuck_take_escape_hatch, "stuck_take_escape_hatch"},
        {plan_stuck_move_towards_escape_hatch, "stuck_move_towards_escape_hatch"},
        {plan_clear_exclusions, "try_clear_exclusions"},
        {plan_stuck_dig_grate, "try_stuck_dig_grate"},
        {plan_forget_map, "try_forget_map"},
        {plan_stuck_initial, "stuck_initial"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_random_step, "random_step"},
    }
end
