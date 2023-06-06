------------------
-- Attack plans
--

function plan_flail_at_invis()
    if not invis_monster or weapon_is_ranged() or dangerous_to_melee() then
        return false
    end

    local can_ctrl = not you.confused()
    if invis_monster_pos then
        if is_adjacent(invis_monster_pos)
                and not is_solid_at(invis_monster_pos) then
            attack_melee(invis_monster_pos, can_ctrl)
            return true
        end

        if invis_monster_pos.x == 0 then
            local apos = { x = 0, y = sign(invis_monster_pos.y) }
            if not is_solid_at(apos) then
                attack_melee(apos, can_ctrl)
                return true
            end
        end

        if invis_monster_pos.y == 0 then
            local apos = { x = sign(invis_monster_pos.x), y = 0 }
            if not is_solid_at(apos) then
                attack_melee(apos, can_ctrl)
                return true
            end
        end
    end

    local tries = 0
    while tries < 100 do
        local pos = { x = -1 + crawl.random2(3), y = -1 + crawl.random2(3) }
        tries = tries + 1
        if supdist(pos) > 0 and not is_solid_at(pos) then
            attack_melee(pos, can_ctrl)
            return true
        end
    end

    return false
end

function plan_shoot_at_invis()
    if not invis_monster or not weapon_is_ranged() or dangerous_to_shoot() then
        return false
    end

    local can_ctrl = not you.confused()
    if invis_monster_pos then
        if not is_solid_at(invis_monster_pos)
                and have_line_of_fire(invis_monster_pos)then
            shoot_launcher(invis_monster_pos)
            return true
        end

        if invis_monster_pos.x == 0 then
            local apos = { x = 0, y = sign(invis_monster_pos.y) }
            if not is_solid_at(apos) and have_line_of_fire(apos)then
                shoot_launcher(apos)
                return true
            end
        end

        if invis_monster_pos.y == 0 then
            local apos = { x = sign(invis_monster_pos.x), y = 0 }
            if not is_solid_at(apos) and have_line_of_fire(apos)then
                shoot_launcher(apos)
                return true
            end
        end
    end

    local tries = 0
    while tries < 100 do
        local pos = { x = -1 + crawl.random2(3), y = -1 + crawl.random2(3) }
        tries = tries + 1
        if supdist(pos) > 0
                and not is_solid_at(pos)
                and have_line_of_fire(pos) then
            shoot_launcher(pos)
            return true
        end
    end

    return false
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
    if memos["melee_target"] then
        return memos["melee_target"]
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
        memos["melee_target"] = best_result.pos
    end
    return memos["melee_target"]
end

function attack_melee(pos, use_control)
    if use_control or you.confused() and you.transform() == "tree" then
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

    local enemy = get_monster_at(target)
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
        if position_is_origin(pos) then
            return
        end

        local mons = get_monster_at(pos)
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
    if debug_channel("ranged") then
        dsay("Targeting " .. pos_string(target))
    end
    local positions = spells.path(attack.test_spell, target.x, target.y, false)
    local result = { pos = target }
    local past_target, at_target_result
    if debug_channel("ranged") then
        dsay("Targeting " .. pos_string(target))
    end
    for i, coords in ipairs(positions) do
        pos = { x = coords[1], y = coords[2] }
        local hit_target = positions_equal(pos, target)
        local enemy = get_monster_at(pos)
        -- Non-penetrating attacks must reach the target before reaching any
        -- other enemy, otherwise they're considered blocked and unusable.
        if not attack.is_penetrating
                and not past_target
                and not hit_target
                and enemy
                and not enemy:ignores_player_projectiles() then
            if debug_channel("ranged") then
                dsay("Aborted target: blocking monster at " .. pos_string(pos))
            end
            return
        end

        -- Never potentially hit friendlies. If at_target_result is defined,
        -- we'll be using '.', otherwise we haven't yet reached our target and
        -- the attack is unusable.
        if enemy and enemy:is_friendly()
                and not enemy:ignores_player_projectiles() then
            if debug_channel("ranged") then
                dsay("Aborted target: blocking monster at " .. pos_string(pos))
            end
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
            if debug_channel("ranged") then
                dsay("Using at-target key due to destructive terrain at "
                    .. pos_string(pos))
            end
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
                if debug_channel("ranged") then
                    dsay("Attack scores after enemy at " .. pos_string(pos)
                        .. ": " .. stringify_table(result))
                end
            end
        end

        -- We've reached the target, so make a copy of the results up to this
        -- point in case we later decide to use '.'.
        if hit_target then
            at_target_result = util.copy_table(result)
            at_target_result.stop_at_target = true
            past_target = true
        end
    end

    -- We never hit anything, so make sure we return nil. This can happen in
    -- rare cases like an eldritch tentacle residing in its portal feature,
    -- which is solid terrain.
    if not result.hit or result.hit == 0 then
        return
    end

    return result
end

function assess_explosion_targets(attack, target)
    local best_result
    for _, pos in adjacent_iter(target, true) do
        if not attack.seen_pos[target.x][target.y] then
            local result = assess_ranged_target(attack, pos)
            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
            attack.seen_pos[pos.x][pos.y] = true
        end
    end
    return best_result
end

function weapon_test_spell(weapon)
    if weapon.class(true) == "missile" then
        if weapon:name():find("javelin") then
            return "Quicksilver Bolt"
        else
            return "Magic Dart"
        end
    else
        return "Magic Dart"
    end
end

function weapon_range(weapon)
    local class = weapon.class(true)
    if class == "missile" or class == "weapon" and weapon.is_ranged then
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

function get_ranged_target(weapon, prefer_melee)
    local attack = {}
    attack.range = weapon_range(weapon)
    attack.is_penetrating = is_penetrating_weapon(weapon)
    attack.is_explosion = is_exploding_weapon(weapon)
    attack.test_spell = weapon_test_spell(weapon)
    attack.props = { "hit", "distance", "is_constricting_you", "damage_level",
        "threat", "is_orc_priest_wizard" }
    attack.reversed_props = { distance = true }

    if explosion then
        attack.seen_pos = {}
        for i = -los_radius, los_radius do
            attack.seen_pos[i] = {}
        end
    end

    local best_result
    for _, enemy in ipairs(enemy_list) do
        -- If we prefer melee and have any ranged enemy that we could move
        -- towards, don't try to get a ranged target. We prefer to try to move
        -- towards the biggest threat.
        if prefer_melee
                and enemy:is_ranged()
                and enemy:get_player_move_towards() then
            return
        end

        local pos = enemy:pos()
        if enemy:distance() <= attack.range
                and you.see_cell_solid_see(pos.x, pos.y)
                -- If we prefer melee, don't try this ranged attack when we
                -- have a reachable ranged monster or are just outside of their
                -- melee range.
                and not (prefer_melee
                    and enemy:distance() == reach_range() + 1
                    and enemy:get_player_move_towards()) then
            local result
            if explosion then
                result = assess_explosion_targets(attack, pos)
            else
                result = assess_ranged_target(attack, pos)
            end

            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
        end
    end
    if best_result then
        return best_result.pos
    end
end

function plan_launcher()
    if not danger
            or not weapon_is_ranged()
            or unable_to_shoot()
            or dangerous_to_attack() then
        return false
    end

    local target = get_ranged_target(get_weapon())
    if not target then
        return false
    end

    return shoot_launcher(target)
end

function throw_missile(missile, pos)
    local cur_missile = items.fired_item()
    if not cur_missile or missile.name() ~= cur_missile.name() then
        magic("Q*" .. letter(missile))
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y)
end

function shoot_launcher(pos)
    local weapon = get_weapon()
    local cur_missile = items.fired_item()
    if not cur_missile or weapon.name() ~= cur_missile.name() then
        magic("Q*" .. letter(weapon))
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y)
end

function plan_throw()
    if not danger or unable_to_throw() or dangerous_to_attack() then
        return false
    end

    local missile = best_missile()
    if not missile then
        return false
    end

    local target = get_ranged_target(missile, true)
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

function plan_melee_wait_for_enemy()
    if not danger or weapon_is_ranged() then
        return false
    end

    if unable_to_move() or dangerous_to_move() then
        wait_combat()
        return true
    end

    if dangerous_to_attack()
            or position_is_cloudy
            or not options.autopick_on
            or view.feature_at(0, 0) == "shallow_water"
                and intrinsic_fumble()
                and not you.flying()
            or in_branch("Abyss")
            or wait_count >= 10 then
        wait_count = 0
        return false
    end

    if you.turns() >= last_wait + 10 then
        wait_count = 0
    end

    -- Hack to wait when we enter the Vaults end, so we don't move off stairs.
    if vaults_end_entry_turn and you.turns() <= vaults_end_entry_turn + 2 then
        wait_combat()
        return true
    end

    local target = get_melee_target()
    local want_wait = false
    for _, enemy in ipairs(enemy_list) do
        -- We prefer to wait for a target monster to reach us over moving
        -- towards it. However if there exists monsters with ranged attacks, we
        -- prefer to move closer to our target over waiting. This way we are
        -- hit with fewer ranged attacks over time.
        if target and enemy:is_ranged() then
            wait_count = 0
            return false
        end

        if not want_wait and enemy:can_move_to_player_melee() then
            want_wait = true

            -- If we don't have a target, we'll never abort from waiting due to
            -- ranged monsters, since we can't move towards one anyhow.
            if not target then
                break
            end
        end
    end
    if want_wait then
        wait_combat()
        return true
    end

    return false
end

function plan_launcher_wait_for_enemy()
    if not danger or not weapon_is_ranged() then
        return false
    end

    if unable_to_move() or dangerous_to_move() then
        wait_combat()
        return true
    end

    if dangerous_to_attack()
            or position_is_cloudy
            or not options.autopick_on
            or view.feature_at(0, 0) == "shallow_water"
                and intrinsic_fumble()
                and not you.flying()
            or in_branch("Abyss")
            or wait_count >= 10 then
        wait_count = 0
        return false
    end

    if you.turns() >= last_wait + 10 then
        wait_count = 0
    end

    local want_wait = false
    for _, enemy in ipairs(enemy_list) do
        if enemy:can_move_to_player_melee() then
            wait_combat()
            return true
        end
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
    if not danger
            or weapon_is_ranged()
            or unable_to_move()
            or dangerous_to_attack()
            or dangerous_to_move() then
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

    local move = get_monster_at(target):get_player_move_towards(true)
    local feat = view.feature_at(move.x, move.y)
    -- Only quaff flight when we finally reach an impassable square.
    if (feat == "deep_water" or feat == "lava")
            and not is_traversable_at(move) then
        return drink_by_name("flight")
    else
        move_to(move)
        return true
    end
end

function plan_move_towards_enemy()
    if not danger
            or weapon_is_ranged()
            or unable_to_move()
            or dangerous_to_attack()
            or dangerous_to_move() then
        return false
    end

    local target = get_melee_target()
    if not target then
        return false
    end

    local mons = get_monster_at(target)
    local move = mons:get_player_move_towards()
    if not move then
        return false
    end

    enemy_memory = position_difference(mons:pos(), move)
    enemy_map_memory = position_sum(global_pos, mons:pos())
    turns_left_moving_towards_enemy = 2
    move_to(move)
    return true
end

function plan_continue_move_towards_enemy()
    if not enemy_memory
            or not options.autopick_on
            or unable_to_move()
            or dangerous_to_attack()
            or dangerous_to_move() then
        return false
    end

    if enemy_memory and position_is_origin(enemy_memory) then
        enemy_memory = nil
        turns_left_moving_towards_enemy = 0
        enemy_map_memory = nil
        return false
    end

    if turns_left_moving_towards_enemy > 0 then
        local move = get_move_towards(origin, enemy_memory, tabbable_square,
            reach_range())
        if not move then
            return false
        end

        move_to(move)
        return true
    end

    enemy_memory = nil

    if last_enemy_map_memory
            and enemy_map_memory
            and positions_equal(last_enemy_map_memory, enemy_map_memory) then
        enemy_map_memory = nil

        local dest = best_map_position_near(last_enemy_map_memory)
        if not dest then
            return false
        end

        local move = best_move_towards_map_position(dest)
        if move then
            move_towards_destination(move, dest, "monster")
            return true
        end
    end

    last_enemy_map_memory = enemy_map_memory
    enemy_map_memory = nil
    return false
end

function set_plan_attack()
    plan_attack = cascade {
        {plan_starting_spell, "starting_spell"},
        {plan_poison_spit, "poison_spit"},
        {plan_launcher, "launcher"},
        {plan_melee, "melee"},
        {plan_throw, "throw"},
        {plan_launcher_wait_for_enemy, "launcher_wait_for_enemy"},
        {plan_melee_wait_for_enemy, "melee_wait_for_enemy"},
        {plan_continue_move_towards_enemy, "continue_move_towards_enemy"},
        {plan_move_towards_enemy, "move_towards_enemy"},
        {plan_flight_move_towards_enemy, "flight_move_towards_enemy"},
        {plan_shoot_at_invis, "shoot_at_invis"},
        {plan_flail_at_invis, "flail_at_invis"},
        {plan_disturbance_random_step, "disturbance_random_step"},
    }
end
