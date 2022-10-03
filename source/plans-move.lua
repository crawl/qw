function cloud_is_dangerous(cloud)
    if cloud == "flame" or cloud == "fire" then
        return (you.res_fire() < 1)
    elseif cloud == "noxious fumes" then
        return (not meph_immune())
    elseif cloud == "freezing vapour" then
        return (you.res_cold() < 1)
    elseif cloud == "poison gas" then
        return (you.res_poison() < 1)
    elseif cloud == "calcifying dust" then
        return (you.race() ~= "Gargoyle")
    elseif cloud == "foul pestilence" then
        return (not miasma_immune())
    elseif cloud == "seething chaos" or cloud == "mutagenic fog" then
        return true
    end
    return false
end

function assess_square(x, y)
    a = {}

    -- Distance to current square
    a.supdist = supdist(x, y)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_bia(3) + count_sgd(3)
            + count_divine_warrior(3) > 0
    end

    -- Can we move there?
    a.can_move = (a.supdist == 0)
                  or not view.withheld(x, y)
                      and not monster_in_way(x, y)
                      and is_traversable(x, y)
                      and not is_solid(x, y)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_monsters(a, x, y)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish(x, y)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and not intrinsic_amphibious_or_flight()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = view.is_safe_square(x, y)
    cloud = view.cloud_at(x, y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil) or a.safe
                                 or danger and not cloud_is_dangerous(cloud)

    -- Equal to 10000 if the move is not closer to any stair in
    -- good_stair_list, otherwise equal to the (min) dist to such a stair
    a.stair_closer = stair_improvement(x, y)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   reaching    - kiting slower monsters with reaching
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from a square adjacent to multiple monsters
--                 (when not cleaving)
--   fleeing     - moving towards stairs
function step_reason(a1, a2)
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow) and a1.cloud_safe then
        return false
    elseif not a1.near_ally
            and a2.stair_closer < 10000
            and a1.stair_closer > 0
            and a1.enemy_distance < 10
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked.
            and a1.adjacent == 0
            and a2.adjacent == 0
            and (reason_to_rest(90) or you.xl() <= 8 and disable_autoexplore)
            and not buffed()
            and (no_spells or starting_spell() ~= "Summon Small Mammal") then
        return "fleeing"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require some close threats that try to say adjacent to us before
        -- we'll try to move out of water. We also require that we are no worse
        -- in at least one of ranged threats or enemy distance at the new
        -- position.
        if a1.followers_to_land
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return false
        end
    elseif have_reaching() and a1.slow_adjacent > 0 and a2.adjacent == 0
                 and a2.ranged == 0 then
        return "reaching"
    elseif cleaving() then
        return false
    elseif a1.adjacent == 1 then
        return false
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2 then
        return "outnumbered"
    else
        return false
    end
end

-- determines whether moving a0->a2 is an improvement over a0->a1
-- assumes that these two moves have already been determined to be better
-- than not moving, with given reasons
function step_improvement(bestreason, reason, a1, a2)
    if reason == "fleeing" and bestreason ~= "fleeing" then
        return true
    elseif bestreason == "fleeing" and reason ~= "fleeing" then
        return false
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.adjacent + a2.ranged < a1.adjacent + a1.ranged then
        return true
    elseif a2.adjacent + a2.ranged > a1.adjacent + a1.ranged then
        return false
    elseif cleaving() and a2.ranged < a1.ranged then
        return true
    elseif cleaving() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif reason == "fleeing" and a2.stair_closer < a1.stair_closer then
        return true
    elseif reason == "fleeing" and a2.stair_closer > a1.stair_closer then
        return false
    elseif a2.enemy_distance < a1.enemy_distance then
        return true
    elseif a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.stair_closer < a1.stair_closer then
        return true
    elseif a2.stair_closer > a2.stair_closer then
        return false
    elseif a1.cornerish and not a2.cornerish then
        return true
    else
        return false
    end
end

function choose_tactical_step()
    tactical_step = nil
    tactical_reason = "none"
    if you.confused()
            or you.berserk()
            or you.constricted()
            or you.transform() == "tree"
            or you.transform() == "fungus"
            or in_branch("Slime")
            or you.status("spiked") then
        return
    end
    local a0 = assess_square(0, 0)
    if a0.cloud_safe
            and not (a0.fumble and sense_danger(3))
            and (not have_reaching() or a0.slow_adjacent == 0)
            and (a0.adjacent <= 1 or cleaving())
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end
    local bestx, besty, bestreason
    local besta = nil
    local x, y
    local a
    local reason
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 then
                a = assess_square(x, y)
                reason = step_reason(a0, a)
                if reason then
                    if besta == nil
                            or step_improvement(bestreason, reason, besta,
                                a) then
                        bestx = x
                        besty = y
                        besta = a
                        bestreason = reason
                    end
                end
            end
        end
    end
    if besta then
        tactical_step = delta_to_vi(bestx, besty)
        tactical_reason = bestreason
    end
end

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

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        magic("s")
        return true
    end

    local dx, dy
    local count = 0
    for i = -1, 1 do
        for j = -1, 1 do
            if not (i == 0 and j == 0)
                    and is_traversable(i, j)
                    and not view.withheld(i, j)
                    and not monster_in_way(i, j) then
                count = count + 1
                if crawl.one_chance_in(count) then
                    dx = i
                    dy = j
                end
            end
        end
    end
    if count > 0 then
        say("Stepping randomly (" .. reason .. ").")
        magic(delta_to_vi(dx, dy) .. "YY")
        return true
    else
        say("Standing still (" .. reason .. ").")
        magic("s")
        return true
    end
    -- return false
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

function move_towards(dx, dy)
    if you.transform() == "tree"
            or you.transform() == "fungus"
            or you.confused()
                and (count_bia(1) > 0
                    or count_sgd(1) > 0
                    or count_divine_warrior(1) > 0) then
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

    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            local feat = view.feature_at(x, y)
            if (feat == "enter_lair" or feat == "enter_tomb")
                 and you.see_cell_no_trans(x, y) then
                if x == 0 and y == 0 then
                    if where == "Crypt:3" then
                        stepped_on_tomb = true
                    else
                        stepped_on_lair = true
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

    if have_branch_runes("Swamp") and can_teleport() and teleport() then
        return true
    end

    if swamp_rune_reachable then
        say("Waiting for clouds to move.")
        magic("s")
        return true
    end

    local bestx, besty
    local dist
    local bestdist = 11
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and view.is_safe_square(x, y)
                 and not view.withheld(x, y) and not monster_in_way(x, y) then
                dist = 11
                for x2 = -los_radius, los_radius do
                    for y2 = -los_radius, los_radius do
                        if (view.cloud_at(x2, y2) == "freezing vapour"
                                or view.cloud_at(x2, y2) == "foul pestilence")
                             and you.see_cell_no_trans(x2, y2)
                             and (you.god() ~= "Qazlal"
                                 or not view.is_safe_square(x2, y2)) then
                            if supdist(x - x2, y - y2) < dist then
                                dist = supdist(x - x2, y - y2)
                            end
                        end
                    end
                end
                if dist < bestdist then
                    bestx = x
                    besty = y
                    bestdist = dist
                end
            end
        end
    end
    if bestdist < 11 then
        magic(delta_to_vi(bestx, besty) .. "Y")
        return true
    end
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            if (view.cloud_at(x, y) == "freezing vapour"
                    or view.cloud_at(x, y) == "foul pestilence")
                 and you.see_cell_no_trans(x, y) then
                return random_step(where)
            end
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
        {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
        {plan_stuck_dig_grate, "try_stuck_dig_grate"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_stuck_forget_map, "try_stuck_forget_map"},
        {plan_stuck_initial, "stuck_initial"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_stuck, "stuck"},
    }
end
