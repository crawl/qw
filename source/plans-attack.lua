------------------
-- Attack plans
--

function get_melee_target()
    local best_enemy = nil
    local props = { "player_can_melee", "distance", "constricting_you",
        "very_stabbable", "damage_level", "threat", "is_orc_priest_wizard" }
    local reversed = { }
    -- We favor closer monsters.
    reversed.distance = true
    for _, enemy in ipairs(enemy_list) do
        if not util.contains(failed_move, 20 * enemy:x_pos() + enemy:y_pos())
                and enemy:player_can_move_to_melee()
                and (not best_enemy
                    or compare_target(enemy, best_enemy, props, reversed)) then
            best_enemy = enemy
        end
    end
    return best_enemy
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

function add_enemy_hit_props(result, enemy, props)
    for _, prop in ipairs(props) do
        if not result[prop] then
            result[prop] = 0
        end

        if prop == "hit" then
            result.hit = result.hit + 1
        else
            result[prop] = result[prop] + tonumber(enemy[prop]())
        end
    end
end

function assess_ranged_target(attack, target)
    local positions = spells.path(attack.test_spell, target.x, target.y, false)
    local result = { pos = target }
    local stop_target_result
    for i, pos in ipairs(positions) do
        local mons = monster_array[pos.x][pos.y]
        if attack.is_penetrating then
            -- If we haven't reached our target yet, stop_target_result will be
            -- nil. This correctly indicates that we can't use this target at
            -- all, since it hits a friendly even if we use '.'.
            if mons:is_friendly() then
                result = stop_target_result
                break
            end

            if mons:is_enemy() then
                add_enemy_hit_props(result, mons, props)
            end

            -- Prefer to use '.' if we'd destroy
            if i == #positions
                    and attack.uses_ammunition
                    and not destroys_items_at(attack.target)
                    and destroys_items_at(pos) then
                result = stop_target_result
            end
        elseif attack.is_explosion and mons then
            for epos in adjacent_iter(target, true) do
                -- Never hit ourselves.
                if epos.x == 0 and epos.y == 0 then
                    return
                end

                local emons = monster_array[epos.x][epos.y]
                if emons and emons:is_friendly() then
                    return
                end

                if emons and emons:is_enemy() then
                    add_enemy_hit_props(result, emons, props)
                end
            end
        else
            if mons and (pos.x ~= target.x or pos.y ~= target.y) then
                result = stop_target_result
        end

        -- We've reached the target, so make a copy in case we have to aim
        -- at the target with '.'.
        if pos.x == target.x and pos.y == target.y then
            target_stop_result = util.copy(result)
            target_stop_result.stop_at_target = true
        end
    end
    return result
end

function assess_ranged_explosion(attack, target, seen_pos)
        k

    end

end

function compare_ranged_targets(first, second, props, reversed)
    for _, prop in ipairs(props) do
        local val1 = tonumber(first[prop]())
        local val2 = tonumber(second[prop]())
        local if_greater_val = not reversed[prop] and true or false
        if val1 > val2 then
            return if_greater_val
        elseif val1 < val2 then
            return not if_greater_val
        end
    end
    return false
end

function get_ranged_target()
    local weapon = items.fired_item()
    local attack = {}
    attack.range = weapon_range(weapon)
    attack.is_penetrating = is_penetrating_weapon(weapon)
    attack.is_explosion = is_exploding_weapon(weapon)
    attack.test_spell = weapon_test_spell(weapon)

    local seen_pos
    if explosion then
        seen_pos = {}
        for i = -los_radius, los_radius do
            seen_pos[i] = {}
        end
    end

    local props = { "hit", "distance", "constricting_you", "damage_level",
        "threat", "is_orc_priest_wizard" }
    local reversed = {}
    reversed.distance = true
    local best_result
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        if enemy:distance() <= attack.range
                and you.see_cell_solid_see(pos.x, pos.y) then
            if explosion then
                for _, pos in adjacent_iter(target, true) do
                    if not seen_pos[target.x][target.y] then
                        result = assess_ranged_target(attack, pos, props)
                        seen_pos[target.x][target.y] = true
                        if compare_ranged_result(best_result, result, props, reversed) then
                            best_result = result
                        end
                    end
                end
            else
                result = assess_ranged_target(attack, pos, props)
            end

            if compare_ranged_result(best_result, result, props, reversed) then
                best_result = result
            end
        end
    end
    return best_result
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
        if enemy:is_ranged() then
            wait_count = 0
            return false
        end

        local melee_range = enemy:reach_range()
        if enemy:distance() <= melee_range then
            wait_count = 0
            return false
        end

        if not enemy_needs_wait and enemy:can_move_to_melee_player() then
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
        local dist = enemy:distance()
        if dist < best_dist and enemy:res_poison() < 1 then
            best_dist = dist
            target = enemy:pos()
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
                "r" .. vector_move(target) .. "\r") then
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
    if supdist(target_memory) == 0 then
        return false
    end
    if not options.autopick_on then
        return false
    end
    return move_towards(target_memory)
end

-- This gets stuck if netted, confused, etc
function attack_reach(pos)
    magic('vr' .. vector_move(pos) .. '.')
end

function attack_melee(pos)
    if you.confused() then
        if count_brothers_in_arms(1) > 0
                or count_greater_servants(1) > 0
                or count_divine_warriors(1) > 0 then
            magic("s")
            return
        elseif you.transform() == "tree" then
            magic(control(delta_to_vi(pos)) .. "Y")
            return
        end
    end
    if monster_array[pos.x][pos.y]:attitude() == enum_att_neutral then
        if you.god() == "the Shining One"
                or you.god() == "Elyvilon"
                or you.god() == "Zin" then
            magic("s")
        else
            magic(control(delta_to_vi(pos)))
        end
    end
    magic(delta_to_vi(pos) .. "Y")
end

function make_melee_attack(enemy)
    if not enemy:player_can_melee() then
        return move_towards(enemy:pos())
    end

    if enemy:distance() == 1 then
        attack_melee(enemy:pos())
    else
        attack_reach(enemy:pos())
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
    for pos in adjacent_iter(origin) do
        if supdist(pos) > 0 and view.invisible_monster(pos.x, pos.y) then
            magic(control(delta_to_vi(pos)))
            return true
        end
    end

    if invis_sigmund and (sigmund_pos.x ~= 0 or sigmund_pos. ~= 0) then
        if is_adjacent(sigmund_pos) and is_traversable(sigmund_pos) then
            magic(control(delta_to_vi(sigmund_pos)))
            return true
        elseif x == 0 and is_traversable(0, sign(y)) then
            magic(delta_to_vi({ x = 0, y = sign(y) }))
            return true
        elseif y == 0 and is_traversable(sign(x),0) then
            magic(delta_to_vi({ x = sign(x), y = 0 }))
            return true
        end
    end

    local success = false
    local tries = 0
    while not success and tries < 100 do
        local pos = { x = -1 + crawl.random2(3), y = -1 + crawl.random2(3) }
        tries = tries + 1
        if (pos.x ~= 0 or pos.y ~= 0) and is_traversable(pos)
             and view.feature_at(pos.x, pos.y) ~= "closed_door"
             and not feature_is_runed_door(view.feature_at(pos.x, pos.y)) then
            success = true
        end
    end
    if tries >= 100 then
        magic("s")
    else
        magic(control(delta_to_vi(pos)))
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
