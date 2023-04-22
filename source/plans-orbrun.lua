------------------
-- The orbrun plan cascade: choosing a move for a turn on the Orb run.

function plan_go_to_orb()
    if gameplan_status ~= "Orb" or not c_persist.found_orb or cloudy then
        return false
    end

    if stash_travel_attempts == 0 then
        stash_travel_attempts = 1
        magicfind("orb of zot")
        return
    end

    stash_travel_attempts = 0
    disable_autoexplore = false
    return false
end

function want_to_orbrun_divine_warrior()
    return danger
        and count_pan_lords(los_radius) > 0
        and count_divine_warriors(4) == 0
        and not you.teleporting()
end

function plan_orbrun_divine_warrior()
    if can_divine_warrior() and want_to_orbrun_divine_warrior() then
        divine_warrior()
        return true
    end
    return false
end

function want_to_orbrun_teleport()
    return hp_is_low(33) and sense_danger(2)
end

function want_to_orbrun_heal_wounds()
    if danger then
        return hp_is_low(25) or hp_is_low(50) and you.teleporting()
    else
        return hp_is_low(50)
    end
end

function plan_orbrun_heal_wounds()
    if want_to_orbrun_heal_wounds() then
        return heal_general()
    end

    return false
end

function want_to_orbrun_buff()
    return count_pan_lords(los_radius) > 0
        or check_enemies_in_list(los_radius, scary_monsters)
end

function plan_orbrun_haste()
    if want_to_orbrun_buff() and not you.status("finesse-ful") then
        return haste()
    end
    return false
end

function plan_orbrun_might()
    if want_to_orbrun_buff() then
        return might()
    end

    return false
end

function plan_orbrun_hand()
    local hp, mhp = you.hp()
    if mhp - hp >= 30 and can_trogs_hand() then
        trogs_hand()
        return true
    end

    return false
end

function plan_orbrun_heroism()
    if can_heroism() and want_to_orbrun_buff() then
        return heroism()
    end

    return false
end

function plan_orbrun_finesse()
    if can_finesse() and want_to_orbrun_buff() then
        return finesse()
    end

    return false
end

function plan_orbrun_rest()
    if dangerous_to_rest() then
        return false
    end

    if you.confused()
            or transformed()
            or you.slowed()
            or you.berserk()
            or you.teleporting()
            or you.status("spiked")
            or you.silencing() then
        long_rest()
        return true
    end

    return false
end

function plan_orbrun_teleport()
    if can_teleport() and want_to_orbrun_teleport() then
        return teleport()
    end

    return false
end

function plan_gd0()
    send_travel("D", 0)
    return true
end

function plan_go_up()
    local feat = view.feature_at(0, 0)
    if (feature_is_upstairs(feat) or feat == "escape_hatch_up")
            and can_use_stairs() then
        go_upstairs()
        return true
    end

    return false
end

function set_plan_orbrun_rest()
    plan_orbrun_rest = cascade {
        {plan_cure_poison, "cure_poison"},
        {plan_orbrun_rest, "orbrun_rest"},
        {plan_orbrun_hand, "orbrun_hand"},
    }
end

function plan_orbrun_exclusion_move()
    if dangerous_to_move() or map_is_unexcluded_at(global_pos) then
        return false
    end

    local feats = level_stairs_features(where_branch, where_depth, DIR.UP)
    if feats then
        table.insert("escape_hatch_up")
    else
        feats = { "escape_hatch_up" }
    end

    move = best_move_towards_features(feats, true)
    if move then
        move_to(move)
        return true
    end

    if move_destination and move_reason == "exclusion" then
        move = best_move_towards_map_position(move_destination, true)
        if move then
            move_to(move)
            return true
        end
    end

    move, dest = best_move_towards_unexcluded()
    if move then
        if debug_channel("explore") then
            dsay("Moving to unexcluded position at "
                .. cell_string_from_map_position(dest))
        end
        move_destination = dest
        move_reason = "unexplored"
        move_to(move)
        return true
    end

    return false
end

function set_plan_orbrun_emergency()
    plan_orbrun_emergency = cascade {
        {plan_special_purification, "special_purification"},
        {plan_cure_confusion, "cure_confusion"},
        {plan_cancellation, "cancellation"},
        {plan_flee_step, "flee_step"},
        {plan_orbrun_teleport, "orbrun_teleport"},
        {plan_orbrun_heal_wounds, "orbrun_heal_wounds"},
        {plan_cloud_step, "cloud_step"},
        {plan_orbrun_finesse, "orbrun_finesse"},
        {plan_orbrun_haste, "orbrun_haste"},
        {plan_orbrun_heroism, "orbrun_heroism"},
        {plan_cleansing_flame, "try_cleansing_flame"},
        {plan_brothers_in_arms, "brothers_in_arms"},
        {plan_greater_servant, "greater_servant"},
        {plan_orbrun_divine_warrior, "orbrun_divine_warrior"},
        {plan_trogs_hand, "trogs_hand"},
        {plan_resistance, "resistance"},
        {plan_magic_points, "magic_points"},
        {plan_wield_weapon, "wield_weapon"},
        {plan_orbrun_might, "orbrun_might"},
        {plan_continue_flee, "continue_flee"},
        {plan_recall, "recall"},
        {plan_recall_ancestor, "try_recall_ancestor"},
        {plan_recite, "try_recite"},
    }
end

function set_plan_orbrun_move()
    plan_orbrun_move = cascade {
        {plan_orbrun_emergency, "orbrun_emergency"},
        {plan_orbrun_exclusion_move, "orbrun_exclusion_move"},
        {plan_attack, "attack"},
        {plan_orbrun_rest, "orbrun_rest"},
        {plan_use_good_consumables, "use_good_consumables"},
        {plan_go_up, "go_up"},
        {plan_gd0, "try_gd0"},
        {plan_go_to_upstairs, "try_go_to_upstairs"},
        {plan_disturbance_random_step, "disturbance_random_step"},
        {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_autoexplore, "try_autoexplore"},
        {plan_stuck, "stuck"},
    }
end
