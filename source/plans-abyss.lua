------------------
-- The abyss plan cascade: choosing a move for a turn in the Abyss.

function plan_go_to_abyss_portal()
    if in_branch("Abyss")
            or not want_to_stay_in_abyss()
            or not branch_found("Abyss")
            or cloudy then
        return false
    end

    if stash_travel_attempts == 0 then
        stash_travel_attempts = 1
        magicfind("one-way gate to the infinite horrors of the Abyss")
        return
    end

    stash_travel_attempts = 0
    disable_autoexplore = false
    return false
end

function plan_enter_abyss()
    if view.feature_at(0, 0) == "enter_abyss"
            and want_to_stay_in_abyss() then
        go_downstairs(true, true)
        return true
    end

    return false
end

function plan_go_to_abyss_downstairs()
    if in_branch("Abyss")
            and want_to_stay_in_abyss()
            and where_depth < gameplan_depth then
        magic("X>\r")
        return true
    end

    return false
end

function plan_go_down_abyss()
    if view.feature_at(0, 0) == "abyssal_stair"
            and want_to_stay_in_abyss()
            and where_depth < 3 then
        go_downstairs()
        return true
    end
    return false
end

function plan_go_to_abyss_exit()
    if want_to_stay_in_abyss() then
        return false
    end
    magic("X<\r")
    return true
end

function plan_exit_abyss()
    if view.feature_at(0, 0) == branch_exit("Abyss")
            and not want_to_stay_in_abyss()
            and not you.mesmerised()
            and can_move() then
        go_upstairs()
        return true
    end

    return false
end

function plan_abyss_long_rest()
    local hp, mhp = you.hp()
    if you.confused()
            or transformed()
            or you.slowed()
            or you.berserk()
            or you.teleporting()
            or you.silencing()
            or you.status("spiked")
            or hp < mhp and you.regenerating() then
        long_rest()
        return true
    end

    return false
end

function plan_abyss_hand()
    local hp, mhp = you.hp()
    if mhp - hp >= 30 and can_trogs_hand() then
        trogs_hand()
        return true
    end
    return false
end

function plan_lugonu_exit_abyss()
    if you.god() ~= "Lugonu"
            or you.berserk()
            or you.confused()
            or you.silenced()
            or you.piety_rank() < 1
            or you.mp() < 1 then
        return false
    end

    use_ability("Depart the Abyss")
    return true
end

function plan_abyss_wait_one_turn()
    wait_one_turn()
    return true
end

function plan_move_to_abyssal_rune()
    local rune = branch_runes("Abyss")[1]
    local rune_name = rune .. RUNE_SUFFIX
    if have_branch_runes(where_branch)
            or not c_persist.sensed_abyssal_rune
                and not c_persist.seen_items[where][rune_name] then
        return false
    end

    move = best_move_towards_items({ rune_name })
    if move then
        move_to(move)
        return true
    end

    return false
end

function plan_move_to_runelight()
    local rune = branch_runes("Abyss")[1]
    local rune_name = rune .. RUNE_SUFFIX
    if have_branch_runes(where_branch) then
        return false
    end
end

function set_plan_abyss_rest()
    plan_abyss_rest = cascade {
        {plan_go_to_abyss_exit, "try_go_to_abyss_exit"},
        {plan_abyss_hand, "abyss_hand"},
        {plan_cure_poison, "cure_poison"},
        {plan_abyss_long_rest, "rest"},
        {plan_go_down_abyss, "go_down_abyss"},
        {plan_go_to_abyss_downstairs, "try_go_to_abyss_downstairs"},
    }
end

function set_plan_abyss_move()
    plan_abyss_move = cascade {
        {plan_lugonu_exit_abyss, "lugonu_exit_abyss"},
        {plan_exit_abyss, "exit_abyss"},
        {plan_emergency, "emergency"},
        {plan_attack, "attack"},
        {plan_abyss_rest, "abyss_long_rest"},
        {plan_pre_explore, "pre_explore"},
        {plan_move_to_rune, "move_to_rune"}
        {plan_move_to_runelight, "move_to_runelight"}
        {plan_autoexplore, "try_autoexplore"},
        {plan_pre_explore2, "pre_explore2"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_abyss_wait_one_turn, "abyss_wait_one_turn"},
    }
end
