------------------
-- Plans specific to the Abyss.

function plan_go_to_abyss_portal()
    if unable_to_travel()
            or in_branch("Abyss")
            or goal_branch ~= "Abyss"
            or not branch_found("Abyss") then
        return false
    end

    magicfind("one-way gate to the infinite horrors of the Abyss")
    return true
end

function plan_enter_abyss()
    if view.feature_at(0, 0) == "enter_abyss"
            and goal_branch == "Abyss"
            and not unable_to_use_stairs() then
        go_downstairs(true, true)
        return true
    end

    return false
end

function plan_pick_up_abyssal_rune()
    if not in_branch("Abyss") or have_branch_runes("Abyss") then
        return false
    end

    local rune_pos = item_map_positions[branch_runes(where_branch, true)[1]]
    if rune_pos and positions_equal(qw.map_pos, rune_pos) then
        magic(",")
        return true
    end

    return false
end

function want_to_stay_in_abyss()
    return goal_branch == "Abyss" and not hp_is_low(50)
end

function plan_exit_abyss()
    if view.feature_at(0, 0) == branch_exit("Abyss")
            and not want_to_stay_in_abyss()
            and not unable_to_use_stairs() then
        go_upstairs()
        return true
    end

    return false
end

function plan_lugonu_exit_abyss()
    if not in_branch("Abyss")
            or want_to_stay_in_abyss()
            or you.god() ~= "Lugonu"
            or not can_invoke()
            or you.piety_rank() < 1
            or not can_use_mp(1) then
        return false
    end

    use_ability("Depart the Abyss")
    return true
end

function want_to_move_to_abyss_objective()
    return in_branch("Abyss") and not you.confused() and not hp_is_low(75)
end

function plan_move_towards_abyssal_feature()
    if not want_to_move_to_abyss_objective()
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    local feats = goal_travel_features()
    if feats then
        local result = best_move_towards_features(feats)
        if result then
            return move_towards_destination(result.move, result.dest, "goal")
        end
    end

    result = best_move_towards_features(feats, true)
    if result then
        return move_towards_destination(result.move, result.dest, "goal")
    end

    return false
end

function plan_go_down_abyss()
    if view.feature_at(0, 0) == "abyssal_stair"
            and want_to_move_to_abyss_objective()
            and goal_branch == "Abyss"
            and where_depth < goal_depth
            and not unable_to_use_stairs() then
        go_downstairs()
        return true
    end

    return false
end

function plan_abyss_wait_one_turn()
    if in_branch("Abyss") then
        wait_one_turn()
        return true
    end

    return false
end

function want_to_move_to_abyssal_rune()
    if not want_to_move_to_abyss_objective() or goal_branch ~= "Abyss" then
        return false
    end

    local rune_pos = item_map_positions[branch_runes(where_branch, true)[1]]
    return rune_pos and not positions_equal(qw.map_pos, rune_pos)
        or c_persist.sensed_abyssal_rune
end

function plan_move_towards_abyssal_rune()
    if not want_to_move_to_abyssal_rune()
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    local rune = branch_runes(where_branch, true)[1]
    local rune_pos = get_item_map_positions({ rune })
    if rune_pos then
        rune_pos = rune_pos[1]
    else
        return false
    end

    local result = best_move_towards(rune_pos, true)
    if result then
        return move_towards_destination(result.move, result.rune_pos, "goal")
    end

    result = best_move_towards_unexplored_near(rune_pos, true)
    if result then
        return move_towards_destination(result.move, result.dest, "goal")
    end

    return false
end

function plan_explore_near_runelights()
    if not want_to_move_to_abyss_objective()
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    local runelights = get_feature_map_positions({ "runelight" })
    if not runelights then
        return false
    end

    local result = best_move_towards_unexplored_near_positions(runelights)
    if result then
        return move_towards_destination(result.move, result.dest, "goal")
    end

    return false
end

function set_plan_abyss()
    plans.abyss = cascade {
        {plan_pick_up_abyssal_rune, "pick_up_abyssal_rune"},
        {plan_lugonu_exit_abyss, "lugonu_exit_abyss"},
        {plan_exit_abyss, "exit_abyss"},
        {plan_go_down_abyss, "go_down_abyss"},
        {plan_move_towards_abyssal_feature, "move_towards_abyssal_feature"},
        {plan_move_towards_abyssal_rune, "move_towards_abyssal_rune"},
        {plan_explore_near_runelights, "explore_near_runelights"},
    }
end
