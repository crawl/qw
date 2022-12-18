function get_target()
    local bestx, besty, best_info, new_info
    bestx = 0
    besty = 0
    best_info = nil
    for _, e in ipairs(enemy_list) do
        if not util.contains(failed_move, 20 * e.x + e.y) then
            if is_candidate_for_attack(e.x, e.y, true) then
                new_info = get_monster_info(e.x, e.y)
                if not best_info
                        or compare_monster_info(new_info, best_info) then
                    bestx = e.x
                    besty = e.y
                    best_info = new_info
                end
            end
        end
    end
    return bestx, besty, best_info
end

function attack()
    local bestx, besty, best_info
    local success = false
    failed_move = { }
    while not success do
        bestx, besty, best_info = get_target()
        if best_info == nil then
            return false
        end
        success = make_attack(bestx, besty, best_info)
    end
    return true
end

function plan_wait_for_melee()
    is_waiting = false
    if sense_danger(reach_range())
            or not options.autopick_on
            or you.berserk()
            or you.have_orb()
            or count_bia(los_radius) > 0
            or count_sgd(los_radius) > 0
            or count_divine_warrior(los_radius) > 0
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

    local monster_needs_wait = false
    for _, e in ipairs(enemy_list) do
        if is_ranged(e.m) then
            wait_count = 0
            return false
        end

        local melee_range = e.m:reach_range()
        if supdist(e.x, e.y) <= melee_range then
            wait_count = 0
            return false
        end

        local tab_func = function(x, y)
            return e.m:can_traverse(x, y)
        end
        if not monster_needs_wait
                and not (e.m:name() == "wandering mushroom"
                    or e.m:name():find("vortex")
                    or e.m:desc():find("fleeing")
                    or e.m:status("paralysed")
                    or e.m:status("confused")
                    or e.m:status("petrified"))
                and will_tab(e.x, e.y, 0, 0, tab_func, melee_range)
                -- If the monster can reach attack and we can't, be sure we can
                -- close the final 1-square gap.
                and (melee_range < 2
                    or have_reaching()
                    or can_move_closer(e.x, e.y)) then
            monster_needs_wait = true
        end
    end
    if not monster_needs_wait then
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
    local cur_e = none
    for _, e in ipairs(enemy_list) do
        local dist = supdist(e.x, e.y)
        if dist < best_dist and e.m:res_poison() < 1 then
            best_dist = dist
            cur_e = e
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
                "r" .. vector_move(cur_e.x, cur_e.y) .. "\r") then
            return true
        end
    end
    return false
end

function plan_wait_throw()
    if not is_waiting then
        return false
    end

    if distance_to_enemy(0, 0) < 3 then
        return false
    end

    local missile
    _, missile = best_missile()
    if missile then
        local cur_missile = items.fired_item()
        if cur_missile and missile.name() == cur_missile.name() then
            magic("ff")
        else
            magic("Q*" .. letter(missile) .. "ff")
        end
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

function plan_attack()
    if danger and attack() then
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
        if count_bia(1) > 0
                or count_sgd(1) > 0
                or count_divine_warrior(1) > 0 then
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
