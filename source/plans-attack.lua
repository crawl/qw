------------------
-- Attack plans
--

-- Is the first attack result better than the second?
function compare_attack_results(attack, first, second)
    if not first then
        return false
    end

    if not second then
        return true
    end

    for _, prop in ipairs(attack.props) do
        local val1 = first[prop]
        local val2 = second[prop]
        local if_greater_val =
            not attack.reversed_props[prop] and true or false
        if val1 > val2 then
            return if_greater_val
        elseif val1 < val2 then
            return not if_greater_val
        end
    end
    return false
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

function get_melee_target()
    local best_result
    local attack = {}
    attack.props = { "player_can_melee", "distance", "constricting_you",
        "very_stabbable", "damage_level", "threat", "is_orc_priest_wizard" }
    attack.reversed_props = { }
    attack.reversed_props.distance = true
    -- We favor closer monsters.
    reversed.distance = true
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        if not failed_moves[hash_position(pos)]
                and enemy:player_can_move_to_melee() then
            result = assess_melee_target(attack, pos)
                and compare_target(attack, result, best_result) then
            best_result = result
        end
    end
    return best_enemy
end

function melee_attack()
    local success = false
    failed_move = { }
    while not success do
        local enemy = get_melee_target()
        if enemy == nil then
            return false
        end
        success = make_attack(enemy)
    end
    return true
end
function assess_explosion(attack, target)
    local result = { pos = target }
    for pos in adjacent_iter(target, true) do
        -- Never hit ourselves.
        if pos.x == 0 and pos.y == 0 then
            return
        end

        local mons = monster_array[epos.x][epos.y]
        if mons then
            if mons:is_friendly()
                and not mons:ignores_player_projectiles() then
            return

            if mons:is_enemy() then
                add_enemy_hit_props(result, mons, attack.props)
            end
        end
    end
    return result
end

function assess_ranged_target(attack, target)
    local positions = spells.path(attack.test_spell, target.x, target.y, false)
    local result = { pos = target }
    local past_target, at_target_result
    for i, pos in ipairs(positions) do
        local hit_target = pos.x == target.x and pos.y == target.y
        local mons = monster_array[pos.x][pos.y]
        -- Non-penetrating attacks must reach the target before reaching any
        -- other monster, otherwise they're considered blocked and unusable.
        if not attack.is_penetrating
                and not past_target
                and not hit_target
                and mons
                and not mons:ignores_player_projectiles() then
            return
        end

        -- Never potentially hit friendlies. If at_target_result is defined,
        -- we'll be using '.', otherwise we haven't yet reached our target and
        -- the attack is unusable.
        if mons and mons:is_friendly()
                and not mons:ignores_player_projectiles() then
            return at_target_result
        end

        -- Try to avoid losing ammo to destructive terrain at the end of our
        -- throw path by using '.'.
        if not hit_target
                and not attack.is_explosion
                and attack.uses_ammunition
                and i == #positions
                and not destroys_items_at(attack.target)
                and destroys_items_at(pos) then
            return at_target_result
        end

        if mons and not mons:ignores_player_projectiles() then
            if attack.is_explosion then
                return assess_explosion(attack, target)
            elseif mons:is_enemy()
                    -- Non-penetrating attacks only get the values from the
                    -- target.
                    and (attack.is_penetrating or hit_target) then
                add_enemy_hit_props(result, mons, attack.props)
            end
        end

        -- We've reached the target, so make a copy of the results up to this
        -- point in case we later decide to use '.'.
        if hit_target then
            at_target_result = util.copy(result)
            at_target_result.stop_at_target = true
            past_target = true
        end
    end
    return result
end

function assess_explosion_targets(attack, target)
    local best_result
    for _, pos in adjacent_iter(target, true) do
        if not attack.seen_pos[target.x][target.y] then
            local result = assess_ranged_target(attack, pos)
            if compare_attack_results(attack, result, best_result) then
                best_result = result
            end
            attack.seen_pos[pos.x][pos.y] = true
        end
    end
    return best_result
end

function get_ranged_target()
    local weapon = items.fired_item()
    local attack = {}
    attack.range = weapon_range(weapon)
    attack.is_penetrating = is_penetrating_weapon(weapon)
    attack.is_explosion = is_exploding_weapon(weapon)
    attack.test_spell = weapon_test_spell(weapon)
    attack.props = { "hit", "distance", "constricting_you", "damage_level",
        "threat", "is_orc_priest_wizard" }
    attack.reversed = {}
    attack.reversed.distance = true

    if explosion then
        attack.seen_pos = {}
        for i = -los_radius, los_radius do
            attack.seen_pos[i] = {}
        end
    end

    reversed.distance = true
    local best_result
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        if enemy:distance() <= attack.range
                and you.see_cell_solid_see(pos.x, pos.y) then
            local result
            if explosion then
                result = assess_explosion_targets(attack, pos)
            else
                result = assess_ranged_target(attack, pos)
            end

            if compare_attack_results(attack, result, best_result) then
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
