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
    if view.feature_at(0, 0) == "exit_abyss"
            and not want_to_stay_in_abyss()
            and not you.mesmerised()
            and can_move() then
        go_upstairs()
        return true
    end

    return false
end

function plan_abyss_rest()
    local hp, mhp = you.hp()
    if you.confused() or you.slowed() or
         you.berserk() or you.teleporting() or you.silencing() or
         transformed() or hp < mhp and you.regenerating() then
        rest()
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

function set_plan_abyss_rest()
    plan_abyss_rest = cascade {
        {plan_go_to_abyss_exit, "try_go_to_abyss_exit"},
        {plan_abyss_hand, "abyss_hand"},
        {plan_abyss_rest, "rest"},
        {plan_go_down_abyss, "go_down_abyss"},
        {plan_go_to_abyss_downstairs, "try_go_to_abyss_downstairs"},
    }
end

function set_plan_abyss_move()
    plan_abyss_move = cascade {
        {plan_lugonu_exit_abyss, "lugonu_exit_abyss"},
        {plan_exit_abyss, "exit_abyss"},
        {plan_emergency, "emergency"},
        {plan_recall_ancestor, "try_recall_ancestor"},
        {plan_recite, "try_recite"},
        {plan_attack, "attack"},
        {plan_cure_poison, "cure_poison"},
        {plan_flail_at_invis, "try_flail_at_invis"},
        {plan_abyss_rest, "abyss_rest"},
        {plan_pre_explore, "pre_explore"},
        {plan_autoexplore, "try_autoexplore"},
        {plan_pre_explore2, "pre_explore2"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_wait, "wait"},
    }
end
