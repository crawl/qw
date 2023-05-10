------------------
-- Plans specifically for the Abyss.

function plan_go_to_abyss_portal()
    if in_branch("Abyss")
            or not want_to_stay_in_abyss()
            or not branch_found("Abyss")
            or position_is_cloudy then
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

function want_to_move_to_abyssal_rune()
    return in_branch("Abyss")
        and want_to_stay_in_abyss()
        and (item_map_positions[abyssal_rune]
            and not positions_equal(global_pos,
                item_map_positions[abyssal_rune]))
-- XXX: Re-enable this when abyssal rune sensing works.
--          or c_persist.sensed_abyssal_rune)
end

function get_reachable_runelights()
    if not feature_map_positions["runelight"] then
        return
    end

    local runelights = {}
    for _, pos in ipairs(feature_map_positions["runelight"]) do
        if get_runelight(pos).los == FEAT_LOS.REACHABLE then
            table.insert(runelights, pos)
        end
    end
    if #runelights > 0 then
        return runelights
    end
end

function want_to_move_to_runelight()
    return in_branch("Abyss")
        and want_to_stay_in_abyss()
        and get_reachable_runelights()
end

function want_to_move_to_abyss_exit()
    return in_branch("Abyss")
        and not want_to_stay_in_abyss()
        and get_branch_stairs_state(where_branch, where_depth, where_branch,
            DIR.UP).los >= FEAT_LOS.REACHABLE
end

function want_to_move_to_abyssal_stairs()
    if not in_branch("Abyss")
            or not want_to_stay_in_abyss()
            or where_depth >= gameplan_depth then
        return false
    end

    for _, state in pairs(c_persist.abyssal_stairs) do
        if state.los >= FEAT_LOS.REACHABLE then
            return true
        end
    end
    return false
end

function want_to_move_to_abyss_objective()
    return in_branch("Abyss")
        and (want_to_move_to_abyss_exit()
            or want_to_move_to_abyssal_stairs()
            or want_to_move_to_runelight()
            or want_to_move_to_abyssal_rune())
        and not reason_to_rest(0.66)
end

function plan_go_to_abyssal_stairs()
    if want_to_move_to_abyssal_stairs() then
        magic("X>\r")
        return true
    end

    return false
end

function plan_go_down_abyss()
    if view.feature_at(0, 0) == "abyssal_stair"
            and want_to_stay_in_abyss()
            and where_depth < gameplan_depth then
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

function plan_lugonu_exit_abyss()
    if not in_branch("Abyss")
            or want_to_stay_in_abyss()
            or you.god() ~= "Lugonu"
            or not can_invoke()
            or you.piety_rank() < 1
            or you.mp() < 1 then
        return false
    end

    use_ability("Depart the Abyss")
    return true
end

function plan_stuck_abyss_wait_one_turn()
    if in_branch("Abyss") then
        wait_one_turn()
        return true
    end

    return false
end

function plan_pickup_abyssal_rune()
    if item_map_positions[abyssal_rune]
            and positions_equal(global_pos,
                item_map_positions[abyssal_rune]) then
        magic(",")
        return true
    end

    return false
end

function plan_move_towards_abyssal_rune()
    if not in_branch("Abyss")
            or not want_to_stay_in_abyss()
            or not item_map_positions[abyssal_rune]
-- XXX: Re-enable this when abyssal rune sensing works.
--              and not c_persist.sensed_abyssal_rune then
        return false
    end

    local move, dest = best_move_towards_items({ abyssal_rune })
    if move then
        move_towards_destination(move, dest, "rune")
        return true
    end

    local rune_pos = item_map_positions[rune]
    if not rune_pos then
        return false
    end

    move, dest = get_move_towards_unreachable_map_position(rune_pos)
    if move then
        move_towards_destination(move, dest, "rune")
        return true
    end

    return false
end

function plan_move_towards_runelight()
    if not want_to_move_to_runelight() then
        return false
    end

    local runelights = get_reachable_runelights()
    if not runelights then
        return false
    end

    local move, dest = best_move_towards_map_positions(runelights)
    if move then
        move_towards_destination(move, dest, "runelight")
        return true
    end

    return false
end
