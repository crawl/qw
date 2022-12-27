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

function plan_cloud_step()
    if tactical_reason == "cloud" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_water_step()
    if tactical_reason == "water" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_coward_step()
    if tactical_reason == "hiding" or tactical_reason == "stealth" then
        if tactical_reason == "hiding" then
            hiding_turn_count = you.turns()
        end
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_flee_step()
    if tactical_reason == "fleeing" then
        say("FLEEEEING.")
        set_stair_target(tactical_step)
        last_flee_turn = you.turns()
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_other_step()
    if tactical_reason ~= "none" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function move_to(x, y)
    magic(delta_to_vi(x, y) .. "YY")
end

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        magic("s")
        return true
    end

    local dx, dy
    local count = 0
    for x, y in adjacent_iter(0, 0) do
        if can_move_to(x, y) then
            count = count + 1
            if crawl.one_chance_in(count) then
                dx = x
                dy = y
            end
        end
    end
    if count > 0 then
        say("Stepping randomly (" .. reason .. ").")
        move_to(dx, dy)
        return true
    else
        say("Standing still (" .. reason .. ").")
        magic("s")
        return true
    end
end

function plan_disturbance_random_step()
    if crawl.messages(5):find("There is a strange disturbance nearby!") then
        return random_step("disturbance")
    end
    return false
end

function plan_wait()
    rest()
    return true
end

function plan_stuck()
    stuck_turns = stuck_turns + 1
    return random_step("stuck")
end

function plan_stuck_initial()
    if stuck_turns <= 50 then
        return plan_stuck()
    end

    return false
end

function plan_stuck_clear_exclusions()
    local n = clear_exclusion_count[where] or 0
    if n > 20 then
        return false
    end
    clear_exclusion_count[where] = n + 1
    magic("X" .. control('e'))
    return true
end

function plan_stuck_dig_grate()
    local closest_grate = 20
    local cx, cy
    for dx = -los_radius, los_radius do
        for dy = -los_radius, los_radius do
            if view.feature_at(dx, dy) == "iron_grate" then
                if abs(dx) + abs(dy) < closest_grate
                        and you.see_cell_solid_see(dx, dy) then
                    cx = dx
                    cy = dy
                    closest_grate = abs(dx) + abs(dy)
                end
            end
        end
    end

    if closest_grate < 20 then
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "r" .. vector_move(cx, cy) .. "\r")
            return true
        end
    end

    return false
end

function plan_stuck_forget_map()
    if not cloudy
            and not danger
            and (at_branch_end("Slime") and not have_branch_runes("Slime")
                or at_branch_end("Geh") and not have_branch_runes("Geh")) then
        magic("X" .. control('f'))
        return true
    end
    return false
end

function plan_stuck_cloudy()
    if cloudy and not hp_is_low(50) and not you.mesmerised() then
        return random_step("cloudy")
    end
    return false
end

function plan_stuck_teleport()
    if can_teleport() then
        return teleport()
    end
    return false
end

function try_move(dx, dy)
    if can_move_to(dx, dy) then
        return delta_to_vi(dx, dy)
    else
        return nil
    end
end

function move_towards(dx, dy)
    if not can_move()
            or you.confused()
                and (count_brothers_in_arms(1) > 0
                    or count_greater_servants(1) > 0
                    or count_divine_warriors(1) > 0) then
        magic("s")
        return true
    end
    local move = nil
    if abs(dx) > abs(dy) then
        if abs(dy) == 1 then move = try_move(sign(dx), 0) end
        if move == nil then move = try_move(sign(dx), sign(dy)) end
        if move == nil then move = try_move(sign(dx), 0) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = try_move(sign(dx), 1) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = try_move(sign(dx), -1) end
        if move == nil then move = try_move(0, sign(dy)) end
    elseif abs(dx) == abs(dy) then
        move = try_move(sign(dx), sign(dy))
        if move == nil then move = try_move(sign(dx), 0) end
        if move == nil then move = try_move(0, sign(dy)) end
    else
        if abs(dx) == 1 then move = try_move(0, sign(dy)) end
        if move == nil then move = try_move(sign(dx), sign(dy)) end
        if move == nil then move = try_move(0, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = try_move(1, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = try_move(-1, sign(dy)) end
        if move == nil then move = try_move(sign(dx), 0) end
    end
    if move == nil or move_count >= 10 then
        add_ignore(dx, dy)
        table.insert(failed_move, 20 * dx + dy)
        return false
    else
        if (abs(dx) > 1 or abs(dy) > 1) and not branch_step_mode
             and view.feature_at(dx, dy) ~= "closed_door" then
            did_move = true
            if monster_array[dx][dy] or did_move_towards_monster > 0 then
                local move_x, move_y = vi_to_delta(move)
                target_memory_x = dx - move_x
                target_memory_y = dy - move_y
                did_move_towards_monster = 2
            end
        end
        if branch_step_mode then
            local move_x, move_y = vi_to_delta(move)
            if view.feature_at(move_x, move_y) == "shallow_water" then
                return false
            end
        end
        magic(move .. "Y")
        return true
    end
end

function plan_step_towards_branch()
    if (stepped_on_lair
            or not branch_found("Lair"))
                and (at_branch_end("Crypt")
                    or stepped_on_tomb
                    or not branch_found("Tomb")) then
        return false
    end

    for x, y in square_iter(0, 0, los_radius, true) do
        local feat = view.feature_at(x, y)
        if (feat == "enter_lair" or feat == "enter_tomb")
                and you.see_cell_no_trans(x, y) then
            if x == 0 and y == 0 then
                if feat == "enter_lair" then
                    stepped_on_lair = true
                else
                    stepped_on_tomb = true
                end
                return false
            else
                branch_step_mode = true
                local result = move_towards(x, y)
                branch_step_mode = false
                return result
            end
        end
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
    magicfind("@" .. branch_rune("Swamp") .. " rune")
    return true
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
        magic("s")
        return true
    end

    local bestx, besty
    local bestdist = 11
    for x, y in adjacent_iter(0, 0) do
        if can_move_to(x, y) and view.is_safe_square(x, y) then
            for dx, dy in radius_iter(x, y) do
                local dist = supdist(dx - x, dy - y)
                if (view.cloud_at(dx, dy) == "freezing vapour"
                            or view.cloud_at(dx, dy) == "foul pestilence")
                        and you.see_cell_no_trans(dx, dy)
                        and not view.is_safe_square(dx, dy)
                        and dist < bestdist then
                    bestx = x
                    besty = y
                    bestdist = dist
                end
            end
        end
    end

    if bestx then
        magic(delta_to_vi(bestx, besty) .. "Y")
        return true
    end

    for x, y in square_iter(0, 0) do
        if (view.cloud_at(x, y) == "freezing vapour"
                    or view.cloud_at(x, y) == "foul pestilence")
                and you.see_cell_no_trans(x, y) then
            return random_step(where)
        end
    end

    return plan_stuck_teleport()
end

function plan_stuck_move_to_target()
    local move
    if gameplan_travel.first_dir then
        if gameplan_travel.first_dir == DIR.UP then
            move = best_move_towards_features(upstairs_features)
        else
            move = best_move_towards_features(downstairs_features)
        end
    elseif gameplan_travel.first_branch then
        move = best_move_towards_features(
            branch_entrance(gameplan_travel.first_branch))
    elseif gameplan_status:find("^God:") then
        local god = gameplan_god(gameplan_status)
        move = best_move_to_features(god_altar(god))
    end

    if not move then
        local wx, wy = travel.waypoint_delta(waypoint_parity)
        local mons_targets = {}
        for x, y in square_iter(0, 0) do
            if has_dangerous_monster(x, y)
                    and not you.see_cell_no_trans(x, y) then
                table.insert(mons_targets, { x = x + wx, y = y + wy })
            end
        end
        move = best_move_towards(mons_targets)
    end

    if move then
        move_to(move.x, move.y)
        return true
    end

    return false
end

function set_plan_move()
    plan_move = cascade {
        {plan_quit, "quit"},
        {plan_ancestor_identity, "try_ancestor_identity"},
        {plan_join_beogh, "join_beogh"},
        {plan_shop, "shop"},
        {plan_stairdance_up, "stairdance_up"},
        {plan_emergency, "emergency"},
        {plan_recall, "recall"},
        {plan_recall_ancestor, "try_recall_ancestor"},
        {plan_recite, "try_recite"},
        {plan_wait_for_melee, "wait_for_melee"},
        {plan_starting_spell, "try_starting_spell"},
        {plan_wait_spit, "try_wait_spit"},
        {plan_wait_throw, "try_wait_throw"},
        {plan_wait_wait, "wait_wait"},
        {plan_attack, "attack"},
        {plan_cure_poison, "cure_poison"},
        {plan_flail_at_invis, "try_flail_at_invis"},
        {plan_rest, "rest"},
        {plan_pre_explore, "pre_explore"},
        {plan_step_towards_branch, "step_towards_branch"},
        {plan_continue_tab, "continue_tab"},
        {plan_unwield_weapon, "unwield_weapon"},
        {plan_explore, "explore"},
        {plan_pre_explore2, "pre_explore2"},
        {plan_explore2, "explore2"},
        {plan_tomb_go_to_final_hatch, "try_tomb_go_to_final_hatch"},
        {plan_tomb_go_to_hatch, "try_tomb_go_to_hatch"},
        {plan_tomb_use_hatch, "tomb_use_hatch"},
        {plan_swamp_clear_exclusions, "try_swamp_clear_exclusions"},
        {plan_swamp_go_to_rune, "try_swamp_go_to_rune"},
        {plan_swamp_clouds_hack, "swamp_clouds_hack"},
        {plan_stuck_move_to_target, "stuck_move_to_target"},
        {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
        {plan_stuck_dig_grate, "try_stuck_dig_grate"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_stuck_forget_map, "try_stuck_forget_map"},
        {plan_stuck_initial, "stuck_initial"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_stuck, "stuck"},
    }
end
