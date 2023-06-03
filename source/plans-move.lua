------------------
-- The normal plan cascade: choosing a move for a normal turn (not in the Abyss
-- or on the Orb run).

function plan_quit()
    if stuck_turns > QUIT_TURNS or select(2, you.hp()) == 1 then
        magic(control('q') .. "yes\r")
        return true
    end

    return false
end

function move_to(pos)
    magic(delta_to_vi(pos) .. "YY")
end

function move_towards_destination(pos, dest, reason)
    move_destination = dest
    move_reason = reason
    move_to(pos)
end

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        wait_one_turn()
        return true
    end

    local new_pos
    local count = 0
    for pos in adjacent_iter(origin) do
        if can_move_to(pos) then
            count = count + 1
            if crawl.one_chance_in(count) then
                new_pos = pos
            end
        end
    end
    if count > 0 then
        say("Stepping randomly (" .. reason .. ").")
        move_to(new_pos)
        return true
    else
        say("Standing still (" .. reason .. ").")
        wait_one_turn()
        return true
    end
end

function plan_disturbance_random_step()
    if crawl.messages(5):find("There is a strange disturbance nearby!") then
        return random_step("disturbance")
    end
    return false
end

function plan_swamp_clear_exclusions()
    if not at_branch_end("Swamp") then
        return false
    end

    magic("X" .. control('e'))
    return true
end

function plan_swamp_go_to_rune()
    if not at_branch_end("Swamp") or have_branch_runes("Swamp") then
        return false
    end

    if last_swamp_fail_count
            == c_persist.plan_fail_count.try_swamp_go_to_rune then
        swamp_rune_reachable = true
    end

    last_swamp_fail_count = c_persist.plan_fail_count.try_swamp_go_to_rune
    magicfind("@" .. branch_runes("Swamp")[1] .. " rune")
    return true
end

function is_swamp_end_cloud(pos)
    return (view.cloud_at(pos.x, pos.y) == "freezing vapour"
            or view.cloud_at(pos.x, pos.y) == "foul pestilence")
        and you.see_cell_no_trans(pos.x, pos.y)
        and not is_safe_at(pos)
end

function plan_swamp_clouds_hack()
    if not at_branch_end("Swamp") then
        return false
    end

    if have_branch_runes("Swamp") and can_teleport() then
        return teleport()
    end

    if swamp_rune_reachable then
        say("Waiting for clouds to move.")
        wait_one_turn()
        return true
    end

    local best_pos
    local best_dist = 11
    for pos in adjacent_iter(origin) do
        if can_move_to(pos) and is_safe_at(pos) then
            for dpos in radius_iter(pos) do
                local dist = supdist(position_difference(dpos, pos))
                if is_swamp_end_cloud(dpos) and dist < best_dist then
                    best_pos = pos
                    best_dist = dist
                end
            end
        end
    end

    if best_pos then
        magic(delta_to_vi(best_pos) .. "Y")
        return true
    end

    for pos in square_iter(origin) do
        if (view.cloud_at(pos.x, pos.y) == "freezing vapour"
                    or view.cloud_at(pos.x, pos.y) == "foul pestilence")
                and you.see_cell_no_trans(pos.x, pos.y) then
            return random_step(where)
        end
    end

    return plan_stuck_teleport()
end

function set_plan_move()
    plan_move = cascade {
        {plan_quit, "quit"},
        {plan_ancestor_identity, "try_ancestor_identity"},
        {plan_join_beogh, "join_beogh"},
        {plan_shop, "shop"},
        {plan_pick_up_abyssal_rune, "pick_up_abyssal_rune"},
        {plan_lugonu_exit_abyss, "lugonu_exit_abyss"},
        {plan_exit_abyss, "exit_abyss"},
        {plan_stairdance_up, "stairdance_up"},
        {plan_emergency, "emergency"},
        {plan_attack, "attack"},
        {plan_rest, "rest"},
        {plan_pre_explore, "pre_explore"},
        {plan_explore, "explore"},
        {plan_pre_explore2, "pre_explore2"},
        {plan_explore2, "explore2"},
        {plan_tomb_go_to_final_hatch, "try_tomb_go_to_final_hatch"},
        {plan_tomb_go_to_hatch, "try_tomb_go_to_hatch"},
        {plan_tomb_use_hatch, "tomb_use_hatch"},
        {plan_swamp_clear_exclusions, "try_swamp_clear_exclusions"},
        {plan_swamp_go_to_rune, "try_swamp_go_to_rune"},
        {plan_swamp_clouds_hack, "swamp_clouds_hack"},
        {plan_stuck, "stuck"},
    }
end
