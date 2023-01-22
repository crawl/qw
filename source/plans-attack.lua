------------------
-- Attack plans
--

function plan_flail_at_invis()
    if not invis_sigmund then
        return false
    end

    invis_sigmund_count = invis_sigmund_count + 1
    for pos in adjacent_iter(origin) do
        if supdist(pos) > 0 and view.invisible_monster(pos.x, pos.y) then
            magic(control(delta_to_vi(pos)))
            return true
        end
    end

    if sigmund_pos.x ~= 0 or sigmund_pos. ~= 0 then
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
        if (pos.x ~= 0 or pos.y ~= 0)
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
    if melee_target then
        return melee_target
    end

    local attack = {}
    attack.props = { "player_can_melee", "distance", "constricting_you",
        "very_stabbable", "damage_level", "threat", "is_orc_priest_wizard" }
    attack.reversed_props = {}
    attack.reversed_props.distance = true
    -- We favor closer monsters.
    reversed.distance = true

    local best_result
    for _, enemy in ipairs(enemy_list) do
        if enemy:player_can_melee() or enemy:get_player_move_towards() then
            local result = assess_melee_target(attack, enemy:pos())
            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
        end
    end
    melee_target = best_result.pos
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
    if not danger or melee_is_unsafe() then
        return false
    end

    melee_target = get_melee_target()
    if not melee_target then
        return false
    end

    local enemy = monster_array[melee_target.x][melee_target.y]
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

function get_ranged_target(weapon)
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

function throw_missile(missile, pos)
    local cur_missile = items.fired_item()
    if not cur_missile or missile.name() ~= cur_missile.name() then
        magic("Q*" .. letter(missile))
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y)
end

function plan_throw()
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

function do_wait()
    last_wait = you.turns()
    wait_count = wait_count + 1
    magic("s")
end

function plan_wait_for_enemy()
    if melee_target and melee_is_unsafe() then
        do_wait()
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
        do_wait()
        return true
    end

    local need_wait = false
    for _, enemy in ipairs(enemy_list) do
        if enemy:is_ranged() then
            wait_count = 0
            return false
        end

        if not need_wait and enemy:can_move_to_melee_player() then
            need_wait = true
        end
    end
    if not need_wait then
        return false
    end

    do_wait()
    return true
end

function plan_poison_spit()
    if not danger
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

function plan_use_flight()
    if melee_enemy then
        return false
    end
end

function plan_move_towards_enemy()
    local target = get_melee_target()
    if not target then
        return false
    end

    local move = monster_array[target.x][target.y]:get_player_move_towards()
    magic(delta_to_vi(move))
    return true
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
    }
end
