------------------
-- Attack plans
--

function plan_flail_at_invis()
    if not invis_sigmund or dangerous_to_melee() then
        return false
    end

    invis_sigmund_count = invis_sigmund_count + 1
    for pos in adjacent_iter(origin) do
        if supdist(pos) > 0 and view.invisible_monster(pos.x, pos.y) then
            magic(control(delta_to_vi(pos)))
            return true
        end
    end

    if supdist(sigmund_pos) > 0 then
        if is_adjacent(sigmund_pos) and is_traversable(sigmund_pos) then
            magic(control(delta_to_vi(sigmund_pos)))
            return true
        end

        if sigmund_pos.x == 0 then
            local apos = { x = 0, y = sign(sigmund_pos.y) }
            if is_traversable(apos) then
                magic(delta_to_vi())
                return true
            end
        end

        if sigmund_pos.y == 0 then
            local apos = { x = sign(sigmund_pos.x), y = 0 }
            if is_traversable(apos) then
                magic(delta_to_vi())
                return true
            end
        end
    end

    local success = false
    local tries = 0
    while not success and tries < 100 do
        local pos = { x = -1 + crawl.random2(3), y = -1 + crawl.random2(3) }
        tries = tries + 1
        if supdist(pos) > 0
                and is_traversable_at(pos)
                and not is_solid_at(pos) then
            success = true
        end
    end
    if not success then
        return false
    end

    magic(control(delta_to_vi(pos)))
    return true
end

-- Is the result from an attack on the first target better than the current
-- best result?
function result_improves_attack(attack, result, best_result)
    if not result then
        return false
    end

    if not best_result then
        return true
    end

    for _, prop in ipairs(attack.props) do
        local val1 = result[prop]
        local val2 = best_result[prop]
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

function score_enemy_hit(result, enemy, props)
    for _, prop in ipairs(props) do
        if not result[prop] then
            result[prop] = 0
        end

        local value
        if prop == "hit" then
            value = 1
        else
            value = enemy[prop](enemy)
            if value == true then
                value = 1
            elseif value == false then
                value = 0
            end
        end
        result[prop] = result[prop] + value
    end
end

function assess_melee_target(attack, enemy)
    local result = { pos = enemy:pos() }
    score_enemy_hit(result, enemy, attack.props)
    return result
end

function get_melee_target(assume_flight)
    if melee_target then
        return melee_target
    end

    local attack = {}
    attack.props = { "player_can_melee", "distance", "is_constricting_you",
        "stabbability", "damage_level", "threat", "is_orc_priest_wizard" }
    -- We favor closer monsters.
    attack.reversed_props = { distance = true }

    local best_result
    for _, enemy in ipairs(enemy_list) do
        if enemy:player_can_melee()
                or enemy:get_player_move_towards(assume_flight) then
            local result = assess_melee_target(attack, enemy)
            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
        end
    end

    if best_result then
        melee_target = best_result.pos
    end
    return melee_target
end

function attack_melee(pos)
    if you.confused() and you.transform() == "tree" then
        magic(control(delta_to_vi(pos)) .. "Y")
        return
    end

    magic(delta_to_vi(pos) .. "Y")
end

-- This gets stuck if netted, confused, etc
function attack_reach(pos)
    magic('vr' .. vector_move(pos) .. '.')
end

function plan_melee()
    if not danger or dangerous_to_melee() then
        return false
    end

    local target = get_melee_target()
    if not target then
        return false
    end

    local enemy = monster_map[target.x][target.y]
    if not enemy:player_can_melee() then
        return false
    end

    if enemy:distance() == 1 then
        attack_melee(enemy:pos())
    else
        attack_reach(enemy:pos())
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

        local mons = monster_map[epos.x][epos.y]
        if mons then
            if mons:is_friendly()
                and not mons:ignores_player_projectiles() then
                return
            end

            if mons:is_enemy() then
                score_enemy_hit(result, mons, attack.props)
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
        local enemy = monster_map[pos.x][pos.y]
        -- Non-penetrating attacks must reach the target before reaching any
        -- other enemyter, otherwise they're considered blocked and unusable.
        if not attack.is_penetrating
                and not past_target
                and not hit_target
                and enemy
                and not enemy:ignores_player_projectiles() then
            return
        end

        -- Never potentially hit friendlies. If at_target_result is defined,
        -- we'll be using '.', otherwise we haven't yet reached our target and
        -- the attack is unusable.
        if enemy and enemy:is_friendly()
                and not enemy:ignores_player_projectiles() then
            return at_target_result
        end

        -- Try to avoid losing ammo to destructive terrain at the end of our
        -- throw path by using '.'.
        if not hit_target
                and not attack.is_explosion
                and attack.uses_ammunition
                and i == #positions
                and destroys_items_at(pos)
                and not destroys_items_at(attack.target) then
            return at_target_result
        end

        if enemy and not enemy:ignores_player_projectiles() then
            if attack.is_explosion then
                return assess_explosion(attack, target)
            elseif enemy:is_enemy()
                    -- Non-penetrating attacks only get the values from the
                    -- target.
                    and (attack.is_penetrating or hit_target) then
                score_enemy_hit(result, enemy, attack.props)
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

function weapon_test_spell(weapon)
    if weapon.class(true) == "missile" then
        if item:name():find("javelin") then
            return "Dispelling Breath"
        else
            return "Magic Dart"
        end
    end
end

function weapon_range(weapon)
    if weapon.class(true) == "missile" then
        return los_radius
    end
end

function is_exploding_weapon(weapon)
    return false
end

function is_penetrating_weapon(weapon)
    if weapon:name():find("javelin") then
        return true
    end

    return false
end

function get_ranged_target(weapon)
    local attack = {}
    attack.range = weapon_range(weapon)
    attack.is_penetrating = is_penetrating_weapon(weapon)
    attack.is_explosion = is_exploding_weapon(weapon)
    attack.test_spell = weapon_test_spell(weapon)
    attack.props = { "hit", "distance", "is_constricting_you", "damage_level",
        "threat", "is_orc_priest_wizard" }
    attack.reversed_props = {}
    attack.reversed_props.distance = true

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

function throw_missile(missile, pos)
    local cur_missile = items.fired_item()
    if not cur_missile or missile.name() ~= cur_missile.name() then
        magic("Q*" .. letter(missile))
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y)
end

function plan_throw()
    if not danger or dangerous_to_attack() then
        return false
    end

    local missile = best_missile()
    if not missile then
        return false
    end

    local target = get_ranged_target(missile)
    if not target then
        return false
    end

    return throw_missile(missile, target)
end

function wait_combat()
    last_wait = you.turns()
    wait_count = wait_count + 1
    wait_one_turn()
end

function plan_wait_for_enemy()
    if not danger or dangerous_to_attack() then
        return false
    end

    local target = get_melee_target()
    if target and dangerous_to_melee() then
        wait_combat()
        return true
    end

    if not options.autopick_on
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
        wait_combat()
        return true
    end

    local need_wait = false
    for _, enemy in ipairs(enemy_list) do
        if enemy:is_ranged() then
            wait_count = 0
            return false
        end

        if not need_wait and enemy:can_move_to_player_melee() then
            need_wait = true
        end
    end
    if need_wait then
        wait_combat()
        return true
    end

    return false
end

function plan_poison_spit()
    if not danger
        or dangerous_to_attack()
        or you.xl() > 11
        or you.mutation("spit poison") < 1
        or you.breath_timeout()
        or you.berserk()
        or you.confused() then
        return false
    end

    local range = 6
    local ability = "Spit Poison"
    if you.mutation("spit poison") > 2 then
        range = 7
        ability = "Breathe Poison Gas"
    end

    local target
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= range and enemy:res_poison() < 1 then
            target = enemy:pos()
        end
    end

    if target and use_ability(ability, "r" .. vector_move(target) .. "\r") then
        return true
    end

    return false
end

function plan_flight_move_towards_enemy()
    if not danger or dangerous_to_move() then
        return false
    end

    local slot = find_item("potion", "flight")
    if not slot then
        return false
    end

    local target = get_melee_target(true)
    if not target then
        return false
    end

    local move = monster_map[target.x][target.y]:get_player_move_towards(true)
    local feat = view.feature_at(move.x, move.y)
    -- Only quaff flight when we finally reach an impassable square.
    if (feat == "deep_water" or feat == "lava")
            and not feature_is_traversable(feat) then
        return drink_by_name("flight")
    else
        magic(delta_to_vi(move))
        return true
    end
end

function plan_move_towards_enemy()
    if not danger or dangerous_to_move() then
        return false
    end

    local target = get_melee_target()
    if not target then
        return false
    end

    local mons = monster_map[target.x][target.y]
    local move = mons:get_player_move_towards()
    enemy_memory = { x = mons:x_pos() - move.x,  y = mons:y_pos() - move.y }
    turns_left_moving_towards_enemy = 2
    magic(delta_to_vi(move))
    return true
end

function plan_continue_move_towards_enemy()
    if turns_left_moving_towards_enemy == 0
            or supdist(enemy_memory) == 0
            or not options.autopick_on then
        return false
    end

    return get_move_towards(origin, enemy_memory, tabbable_square)
end

function set_plan_attack()
    plan_attack = cascade {
        {plan_flail_at_invis, "try_flail_at_invis"},
        {plan_starting_spell, "try_starting_spell"},
        {plan_poison_spit, "try_poison_spit"},
        {plan_melee, "try_melee"},
        {plan_throw, "try_throw"},
        {plan_wait_for_enemy, "try_wait_for_enemy"},
        {plan_move_towards_enemy, "try_move_towards_enemy"},
        {plan_continue_move_towards_enemy, "try_continue_move_towards_enemy"},
        {plan_flight_move_towards_enemy, "try_flight_move_towards_enemy"},
        {plan_disturbance_random_step, "disturbance_random_step"},
    }
end
