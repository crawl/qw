------------------
-- Attack plans
--
function compare_target_enemies(first, second, flag_order,
        flag_reversed)
    if not flag_order then
    end

    if not flag_reversed then
        flag_reversed = {}
        for _, flag in ipairs(flag_order) do
            table.insert(flag_reversed, false)
        end
    end

    for i, flag in ipairs(flag_order) do
        local if_greater_val = not flag_reversed[i] and true or false
        if first[flag] > second[flag] then
            return if_greater_val
        elseif first[flag] < second[flag] then
            return not if_greater_val
        end
    end
    return false
end

function get_melee_target_enemy()
    local best_enemy = nil
    for _, enemy in ipairs(enemy_list) do
        if not util.contains(failed_move, 20 * e.pos.x + e.pos.y)
                and player_can_move_to_melee_enemy(enemy, true) then
            update_melee_target_info(enemy)
            if not best_enemy
                    or compare_target_enemies(enemy, best_enemy) then
                best_enemy = enemy
            end
        end
    end
    return bestx, besty, best_info
end

function melee_attack()
    local success = false
    failed_move = { }
    while not success do
        local enemy = get_melee_target_enemy()
        if enemy == nil then
            return false
        end
        success = make_attack(enemy)
    end
    return true
end

function compare_ranged_target_enemies(first, second, flag_order,
        flag_reversed)
    update_melee_target_info(first)
    update_melee_target_info(second)

    if not flag_order then
        flag_order = { "player_can_range_attack", "distance",
            "constricting_you", "injury", "threat", "orc_priest_wizard" }
    end

    if not flag_reversed then
        flag_reversed = {}
        for _, flag in ipairs(flag_order) do
            table.insert(flag_reversed, false)
        end
    end

    for i, flag in ipairs(flag_order) do
        local if_greater_val = not flag_reversed[i] and true or false
        if first[flag] > second[flag] then
            return if_greater_val
        elseif first[flag] < second[flag] then
            return not if_greater_val
        end
    end
    return false
end

function get_ranged_target()
    local bestx, besty, best_info, new_info
    bestx = 0
    besty = 0
    best_info = nil
    for _, e in ipairs(enemy_list) do
        if not util.contains(failed_move, 20 * e.pos.x + e.pos.y) then
            if is_candidate_for_attack(e.pos.x, e.pos.y, true) then
                new_info = get_monster_info(e.pos.x, e.pos.y)
                if not best_info
                        or compare_enemy_ranged_info(new_info, best_info) then
                    bestx = e.pos.x
                    besty = e.pos.y
                    best_info = new_info
                end
            end
        end
    end
    return bestx, besty, best_info
end
function plan_throw()
    if melee_enemy or travel.is_excluded(0, 0) then
        return false
    end

    local missile = best_missile()
    if not missile then
        return false
    end

    for _, e in ipairs(enemy_list) do
        if crawl.do_targeted_command("CMD_FIRE", e.pos.x, e.pos.y) then
            return true
        end
    end

    return false
end

function plan_move_to_monster()
    if melee_enemy or travel.is_excluded(0, 0) then
        return false
    end

    for _, e in ipairs(enemy_list) do
        local move = best_move_towards({ { x = e.pos.x, y = e.pos.y } }, los_radius)
        if move then


    end
end

function plan_use_flight()
    if melee_enemy then
        return false
    end


end

function plan_cure_poison()
    if not you.poisoned() or you.poison_survival() > 1 then
        return false
    end

    if drink_by_name("curing") then
        say("(to cure poison)")
        return true
    end

    if can_trogs_hand() then
        trogs_hand()
        return true
    end

    if can_purification() then
        purification()
        return true
    end

    return false
end

function plan_check_incoming_melee_enemy()
    is_waiting = false
    if sense_danger(reach_range())
            or not options.autopick_on
            or you.berserk()
            or you.have_orb()
            or count_brothers_in_arms(los_radius) > 0
            or count_greater_servants(los_radius) > 0
            or count_divine_warriors(los_radius) > 0
            or not view.is_safe_square(0, 0)
            or view.feature_at(0, 0) == "shallow_water"
                and intrinsic_fumble()
                and not you.flying()
            or in_branch("Abyss") then
        wait_count = 0
        return false
    end

    if you.turns() >= last_wait + 10 then
        wait_count = 0
    end

    if not danger or wait_count >= 10 then
        return false
    end

    -- Hack to wait when we enter the Vaults end, so we don't move off stairs.
    if vaults_end_entry_turn and you.turns() <= vaults_end_entry_turn + 2 then
        is_waiting = true
        return false
    end

    local enemy_needs_wait = false
    for _, enemy in ipairs(enemy_list) do
        if is_ranged(enemy.m) then
            wait_count = 0
            return false
        end

        local melee_range = enemy.mons:reach_range()
        if supdist(enemy.pos.x, enemy.pos.y) <= melee_range then
            wait_count = 0
            return false
        end

        if not enemy_needs_wait and enemy_can_move_melee(enemy) then
            enemy_needs_wait = true
        end
    end
    if not enemy_needs_wait then
        return false
    end

    last_wait = you.turns()
    if plan_cure_poison() then
        return true
    end

    -- Don't actually wait yet, because we might use a ranged attack instead.
    is_waiting = true
    return false
end

function plan_wait_spit()
    if not is_waiting then
        return false
    end
    if you.mutation("spit poison") < 1 then
        return false
    end
    if you.berserk() or you.confused() or you.breath_timeout() then
        return false
    end
    if you.xl() > 11 then
        return false
    end
    local best_dist = 10
    local target = none
    for _, enemy in ipairs(enemy_list) do
        local dist = supdist(enemy.pos.x, enemy.pos.y)
        if dist < best_dist and enemy.mons:res_poison() < 1 then
            best_dist = dist
            target = enemy
        end
    end
    ab_range = 6
    ab_name = "Spit Poison"
    if you.mutation("spit poison") > 2 then
        ab_range = 7
        ab_name = "Breathe Poison Gas"
    end
    if best_dist <= ab_range then
        if use_ability(ab_name,
                "r" .. vector_move(target.pos.x, target.pos.y) .. "\r") then
            return true
        end
    end
    return false
end

function throw_missile(missile)
    local cur_missile = items.fired_item()
    if cur_missile and missile.name() == cur_missile.name() then
        magic("ff")
    else
        magic("Q*" .. letter(missile) .. "ff")
    end
end

function plan_wait_throw()
    if not is_waiting then
        return false
    end

    if distance_to_enemy(0, 0) < 3 then
        return false
    end

    local missile = best_missile()
    if missile then
        return true
    else
        return false
    end
end

function plan_wait_wait()
    if not is_waiting then
        return false
    end
    magic("s")
    return true
end

function plan_melee()
    if danger and melee_attack() then
        return true
    end
    return false
end

function plan_continue_tab()
    if did_move_towards_monster == 0 then
        return false
    end
    if supdist(target_memory_x, target_memory_y) == 0 then
        return false
    end
    if not options.autopick_on then
        return false
    end
    return move_towards(target_memory_x, target_memory_y)
end

-- This gets stuck if netted, confused, etc
function attack_reach(x, y)
    magic('vr' .. vector_move(x, y) .. '.')
end

function attack_melee(x, y)
    if you.confused() then
        if count_brothers_in_arms(1) > 0
                or count_greater_servants(1) > 0
                or count_divine_warriors(1) > 0 then
            magic("s")
            return
        elseif you.transform() == "tree" then
            magic(control(delta_to_vi(x, y)) .. "Y")
            return
        end
    end
    if monster_array[x][y]:attitude() == enum_att_neutral then
        if you.god() == "the Shining One" or you.god() == "Elyvilon"
             or you.god() == "Zin" then
            magic("s")
        else
            magic(control(delta_to_vi(x, y)))
        end
    end
    magic(delta_to_vi(x, y) .. "Y")
end

function make_attack(x, y, info)
    if info.attack_range == 0 then
        return move_towards(x, y)
    end

    if info.attack_range == 1 then
        attack_melee(x, y)
    else
        attack_reach(x, y)
    end
    return true
end

function hit_closest()
    startstop()
end

function plan_flail_at_invis()
    if options.autopick_on then
        invisi_count = 0
        invis_sigmund = false
        return false
    end
    if invisi_count > 100 then
        say("Invisible monster not found???")
        invisi_count = 0
        invis_sigmund = false
        magic(control('a'))
        return true
    end

    invisi_count = invisi_count + 1
    for x, y in adjacent_iter(0, 0) do
        if supdist(x, y) > 0 and view.invisible_monster(x, y) then
            magic(control(delta_to_vi(x, y)))
            return true
        end
    end

    if invis_sigmund and (sigmund_dx ~= 0 or sigmund_dy ~= 0) then
        x = sigmund_dx
        y = sigmund_dy
        if adjacent(x, y) and is_traversable(x, y) then
            magic(control(delta_to_vi(x, y)))
            return true
        elseif x == 0 and is_traversable(0, sign(y)) then
            magic(delta_to_vi(0, sign(y)))
            return true
        elseif y == 0 and is_traversable(sign(x),0) then
            magic(delta_to_vi(sign(x),0))
            return true
        end
    end

    local success = false
    local tries = 0
    while not success and tries < 100 do
        x = -1 + crawl.random2(3)
        y = -1 + crawl.random2(3)
        tries = tries + 1
        if (x ~= 0 or y ~= 0) and is_traversable(x, y)
             and view.feature_at(x, y) ~= "closed_door"
             and not view.feature_at(x, y):find("runed") then
            success = true
        end
    end
    if tries >= 100 then
        magic("s")
    else
        magic(control(delta_to_vi(x, y)))
    end
    return true
end

function set_plan_attack()
    plan_attack = cascade {
        {plan_wait_for_melee, "wait_for_melee"},
        {plan_starting_spell, "try_starting_spell"},
        {plan_wait_spit, "try_wait_spit"},
        {plan_wait_throw, "try_wait_throw"},
        {plan_wait_wait, "wait_wait"},
        {plan_melee, "attack"},
        {plan_cure_poison, "cure_poison"},
        {plan_flail_at_invis, "try_flail_at_invis"},
    }
end
