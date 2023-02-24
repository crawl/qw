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

function move_to(pos)
    magic(delta_to_vi(pos) .. "YY")
end

function go_upstairs(confirm, keep_exclusions)
    if not keep_exclusions then
        remove_exclusions(level_is_temporary())
    end

    magic("<" .. confirm and "Y" or "")
end

function go_downstairs(confirm, keep_exclusions)
    if not keep_exclusions then
        remove_exclusions(level_is_temporary())
    end

    magic(">" .. confirm and "Y" or "")
end

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        magic("s")
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
    remove_exclusions(true)
    magic("X" .. control('e'))
    return true
end

function plan_stuck_dig_grate()
    local grate_offset = 20
    local grate_pos
    for pos in square_iter(origin) do
        if view.feature_at(pos.x, pos.y) == "iron_grate" then
            if abs(pos.x) + abs(pos.y) < grate_offset
                    and you.see_cell_solid_see(pos.x, pos.y) then
                grate_pos = pos
                grate_offset = abs(pos.x) + abs(pos.y)
            end
        end
    end

    if closest_grate < 20 then
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "r" .. vector_move(grate_pos) .. "\r")
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

function try_move(pos)
    if can_move_to(pos) then
        return delta_to_vi(pos)
    else
        return
    end
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

function is_swamp_end_cloud(pos)
    return (view.cloud_at(pos.x, pos.y) == "freezing vapour"
            or view.cloud_at(pos.x, pos.y) == "foul pestilence")
        and you.see_cell_no_trans(pos.x, pos.y)
        and not view.is_safe_square(pos.x, pos.y)
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

    local best_pos
    local best_dist = 11
    for pos in adjacent_iter(origin) do
        if can_move_to(pos) and view.is_safe_square(pos.x, pos.y) then
            for dpos in radius_iter(pos) do
                local dist = supdist({ x = dpos.x - pos.x,
                    y = dpos.y - pos.y })
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

function plan_stuck_move_to_next_destination()
    if moving_is_unsafe() then
        return false
    end

    local move, dest = get_move_towards_next_destination()
    if move then
        move_destination = dest
        move_reason = "travel"
        move_to(move)
        return true
    end

    return false
end

function plan_exclusion_move()
    if moving_is_unsafe() or not exclusion_map[0][0] then
        return false
    end

    local move, dest = get_move_towards_next_destination(true)
    if move then
        move_destination = dest
        move_reason = "travel"
        move_to(move)
        return true
    end

    local feats = level_stairs_features(gameplan_branch, gameplan_depth,
        DIR.UP)
    move = best_move_towards_features(feats, true)
    if move then
        move_to(move)
        return true
    end

    return false
end

function plan_stuck_move_towards_monster()
    if moving_is_unsafe() then
        return false
    end

    local mons_targets = {}
    for pos in square_iter(origin) do
        local monster =  monster.get_monster_at(pos.x, pos.y)
        if monster and Monster(monster):is_enemy() then
            table.insert(mons_targets,
                { x = pos.x + waypoint.x, y = pos.y + waypoint.y })
        end
    end
    local move, dest = best_move_towards(mons_targets)

    if move then
        move_destination = dest
        move_reason = "monster"
        move_to(move)
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
        {plan_exclusion_move, "exclusion_move"},
        {plan_attack, "attack"},
        {plan_rest, "rest"},
        {plan_pre_explore, "pre_explore"},
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
        {plan_stuck_move_to_next_destination, "stuck_move_to_next_destination"},
        {plan_stuck_move_to_monster, "stuck_move_to_monster"},
        {plan_stuck_clear_exclusions, "try_stuck_leave_exclusion"},
        {plan_stuck_dig_grate, "try_stuck_dig_grate"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_stuck_forget_map, "try_stuck_forget_map"},
        {plan_stuck_initial, "stuck_initial"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_stuck, "stuck"},
    }
end
