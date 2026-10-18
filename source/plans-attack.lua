------------------
-- Attack plans
--

function can_attack_invis_at(pos)
    return not is_solid_at(pos) and not get_monster_at(pos)
end

function plan_flail_at_invis()
    if not invis_monster or using_ranged_weapon() or dangerous_to_melee() then
        return false
    end

    local can_ctrl = not you.confused()
    if invis_monster_pos then
        if is_adjacent(invis_monster_pos)
                and can_attack_invis_at(invis_monster_pos) then
            do_melee_attack(invis_monster_pos, can_ctrl)
            return true
        end

        if invis_monster_pos.x == 0 then
            local apos = new_position(0, sign(invis_monster_pos.y))
            if can_attack_invis_at(apos) then
                do_melee_attack(apos, can_ctrl)
                return true
            end
        end

        if invis_monster_pos.y == 0 then
            local apos = new_position(sign(invis_monster_pos.x), 0)
            if can_attack_invis_at(apos) then
                do_melee_attack(apos, can_ctrl)
                return true
            end
        end
    end

    local tries = 0
    while tries < 100 do
        local pos = new_position(-1 + crawl.random2(3), -1 + crawl.random2(3))
        tries = tries + 1
        if supdist(pos) > 0 and can_attack_invis_at(pos) then
            do_melee_attack(pos, can_ctrl)
            return true
        end
    end

    return false
end

function plan_shoot_at_invis()
    if not invis_monster
            or not using_ranged_weapon()
            or unable_to_shoot()
            or dangerous_to_shoot() then
        return false
    end

    local can_ctrl = not you.confused()
    if invis_monster_pos then
        if player_has_line_of_fire(invis_monster_pos) then
            return shoot_launcher(invis_monster_pos)
        end

        if invis_monster_pos.x == 0 then
            local apos = new_position(0, sign(invis_monster_pos.y))
            if player_has_line_of_fire(apos) then
                return shoot_launcher(apos)
            end
        end

        if invis_monster_pos.y == 0 then
            local apos = new_position(sign(invis_monster_pos.x), 0)
            if player_has_line_of_fire(apos) then
                return shoot_launcher(apos)
            end
        end
    end

    local tries = 0
    while tries < 100 do
        local pos = new_position(-1 + crawl.random2(3), -1 + crawl.random2(3))
        tries = tries + 1
        if supdist(pos) > 0 and player_has_line_of_fire(pos) then
            return shoot_launcher(pos)
        end
    end

    return false
end

function do_melee_attack(pos, use_control)
    if use_control or you.confused() and you.transform() == "tree" then
        magic(control(delta_to_vi(pos)) .. "Y")
        return
    end

    magic(delta_to_vi(pos) .. "Y")
end

-- This gets stuck if netted, confused, etc
function do_reach_attack(pos)
    magic("vr" .. vector_move(pos) .. ".")
end

function plan_melee()
    if not qw.danger_in_los
            or using_ranged_weapon()
            or unable_to_melee()
            or dangerous_to_melee() then
        return false
    end

    local target = best_melee_target()
    if not target then
        return false
    end

    local enemy = get_monster_at(target.pos)
    if not enemy:player_can_melee() then
        return false
    end

    if enemy:distance() == 1 then
        do_melee_attack(enemy:pos())
    else
        do_reach_attack(enemy:pos())
    end

    return true
end

function plan_launcher()
    if not qw.danger_in_los
            or not using_ranged_weapon()
            or unable_to_shoot()
            or dangerous_to_attack() then
        return false
    end

    local target = best_launcher_target()
    if not target then
        return false
    end

    return shoot_launcher(target.pos, target.aim_at_target)
end

function throw_missile(missile, pos, aim_at_target)
    local cur_missile = items.fired_item()
    if not cur_missile or missile.name() ~= cur_missile.name() then
        magic("Q*" .. item_letter(missile))
        qw.do_dummy_action = false
        coroutine.yield()
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y, aim_at_target)
end

function shoot_launcher(pos, aim_at_target)
    local weapon = get_weapon()
    local cur_missile = items.fired_item()
    if not cur_missile or weapon.name() ~= cur_missile.name() then
        magic("Q*" .. item_letter(weapon))
        qw.do_dummy_action = false
        coroutine.yield()
    end

    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y, aim_at_target)
end

function plan_throw()
    if not qw.danger_in_los or unable_to_throw() or dangerous_to_attack() then
        return false
    end

    local target = best_throwing_target()
    if not target then
        return false
    end

    return throw_missile(target.attack.items[1], target.pos,
        target.aim_at_target)
end

function wait_combat()
    qw.last_wait = qw.turns
    qw.wait_count = qw.wait_count + 1
    wait_one_turn()
end

function plan_melee_wait_for_enemy()
    if not qw.danger_in_los or using_ranged_weapon() then
        return false
    end

    if unable_to_move() or dangerous_to_move(true) then
        wait_combat()
        return true
    end

    if dangerous_to_attack()
            or qw.position_is_cloudy
            or not options.autopick_on
            or will_fumble_primary_attack_at(const.origin)
            or in_branch("Abyss")
            or qw.wait_count >= 10 then
        qw.wait_count = 0
        return false
    end

    if qw.turns >= qw.last_wait + 10 then
        qw.wait_count = 0
    end

    -- Hack to wait when we enter the Vaults end, so we don't move off stairs.
    if vaults_end_entry_turn and qw.turns <= vaults_end_entry_turn + 2 then
        wait_combat()
        return true
    end

    local target = best_melee_target()
    local want_wait = false
    for _, enemy in ipairs(qw.enemy_list) do
        -- We prefer to wait for a target monster to reach us over moving
        -- towards it. However if there exists monsters with ranged attacks or
        -- summons, we prefer to move closer to our target over waiting. This
        -- way we are hit with fewer ranged attacks and summons over the entire
        -- fight.
        if target and enemy:has_line_of_fire(const.origin) then
            qw.wait_count = 0
            return false
        end

        if not want_wait and enemy:player_can_wait_for_melee() then
            want_wait = true

            -- If we don't have a target, we'll never abort from waiting due
            -- to ranged monsters, since we can't move towards one anyhow.
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
    if not qw.danger_in_los or not using_ranged_weapon() then
        return false
    end

    if unable_to_move() or dangerous_to_move() then
        wait_combat()
        return true
    end

    if dangerous_to_attack()
            or qw.position_is_cloudy
            or not options.autopick_on
            or in_branch("Abyss")
            or qw.wait_count >= 10 then
        qw.wait_count = 0
        return false
    end

    if qw.turns >= qw.last_wait + 10 then
        qw.wait_count = 0
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:player_can_wait_for_melee() then
            wait_combat()
            return true
        end
    end

    return false
end

function plan_poison_spit()
    local mut_level = you.mutation("spit poison")
        if not qw.danger_in_los
            or dangerous_to_attack()
            or you.xl() > 11
            or mut_level < 1
            or you.breath_timeout()
            or you.berserk()
            or you.confused() then
        return false
    end

    local range = 5
    local ability = "Spit Poison"
    if mut_level > 1 then
        range = 6
        ability = "Breathe Poison Gas"
    end

    local target = best_ranged_attack_target(poison_spit_attack())
    if not target then
        return false
    end

    return use_ability(ability,
        "r" .. vector_move(target.pos)
            .. (target.aim_at_target and "." or "\r"))
end

function evoke_targeted_item(item, pos, aim_at_target)
    local cur_quiver = items.fired_item()
    local name = item.name()
    if not cur_quiver or name ~= cur_quiver.name() then
        magic("Q*" .. item_letter(item))
        qw.do_dummy_action = false
        coroutine.yield()
    end

    say("EVOKING " .. name .. " at " .. cell_string_from_position(pos) .. ".")
    magic("fr" .. vector_move(pos) .. (aim_at_target and "." or "\r"))
    -- Currently broken when no monsters are available for autotargeting.
    -- return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y,
    -- aim_at_target)
end

function plan_targeted_evoke()
    if not qw.danger_in_los or dangerous_to_attack() or unable_to_evoke() then
        return false
    end

    local target = best_evoke_target()
    if not target then
        return false
    end

    evoke_targeted_item(target.attack.items[1], target.pos, target.aim_at_target)
end

function plan_move_towards_enemy()
    if not qw.danger_in_los
            or using_ranged_weapon()
            or unable_to_move()
            or dangerous_to_attack()
            or dangerous_to_move(true) then
        return false
    end

    local target = best_melee_target()
    if not target then
        return false
    end

    local map_pos = map_position(target.pos)
    local result = best_move_towards(map_pos, false, true)
    if not result then
        return false
    end

    if move_to(result.move) then
        qw.enemy_memory_pos = result.dest_pos
        qw.enemy_memory_moves = 1
        return true
    end

    return false
end

function plan_continue_move_towards_enemy()
    if not qw.enemy_memory_pos
            or unable_to_move()
            or dangerous_to_attack()
            or dangerous_to_move() then
        return false
    end

    if positions_equal(qw.map_pos, qw.enemy_memory_pos) then
        qw.enemy_memory_pos = nil
        qw.enemy_memory_moves = nil
        return false
    end

    if qw.enemy_memory_moves < 3 then
        local result = best_move_towards(qw.enemy_memory_pos)
        if not result then
            return false
        end

        if move_to(result.move) then
            qw.enemy_memory_moves = qw.enemy_memory_moves + 1
            return true
        else
            return false
        end
    end

    qw.enemy_memory_moves = nil

    -- We've been unable to reach the same enemy melee position in 3 movement
    -- turns on two recent occasions. So just set this as a move destination so
    -- we can settle the matter.
    if qw.last_enemy_memory_pos
            and positions_equal(qw.last_enemy_memory_pos,
                qw.enemy_memory_pos) then
        local result = best_move_towards(qw.enemy_memory_pos)
        qw.enemy_memory_pos = nil
        if result then
            return move_towards_destination(result.move, result.dest_pos,
                "monster")
        end
    end

    qw.enemy_memory_pos = nil
    qw.last_enemy_memory_pos = qw.enemy_memory_pos
    qw.last_enemy_memory_turns = qw.turns
    return false
end

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        wait_one_turn()
        return true
    end

    local new_pos
    local count = 0
    for pos in adjacent_iter(const.origin) do
        if can_move_to(pos, const.origin) then
            count = count + 1
            if crawl.one_chance_in(count) then
                new_pos = pos
            end
        end
    end
    if count > 0 then
        say("Stepping randomly (" .. reason .. ").")
        return move_to(new_pos)
    else
        say("Standing still (" .. reason .. ").")
        wait_one_turn()
        return true
    end
end

function plan_disturbance_random_step()
    if crawl.messages(5):find("There is a strange disturbance nearby!") then
        return random_step("disturbance")
    end
    return false
end

function set_plan_attack()
    plans.attack = cascade({
        { plan_starting_spell, "starting_spell" },
        { plan_poison_spit, "poison_spit" },
        { plan_targeted_evoke, "attack_wand" },
        { plan_throw, "throw" },
        { plan_launcher, "launcher" },
        { plan_melee, "melee" },
        { plan_launcher_wait_for_enemy, "launcher_wait_for_enemy" },
        { plan_melee_wait_for_enemy, "melee_wait_for_enemy" },
        { plan_continue_move_towards_enemy, "continue_move_towards_enemy" },
        { plan_move_towards_enemy, "move_towards_enemy" },
        { plan_shoot_at_invis, "shoot_at_invis" },
        { plan_flail_at_invis, "flail_at_invis" },
        { plan_disturbance_random_step, "disturbance_random_step" },
    })
end
