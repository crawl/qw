------------------
-- Emergency plans

function plan_teleport()
    if can_teleport() and want_to_teleport() then
        return teleport()
    end

    return false
end

-- Are we significantly stronger than usual thanks to a buff that we used?
function buffed()
    if hp_is_low(50)
            or transformed()
            or you.corrosion() >= 8 + qw.base_corrosion then
        return false
    end

    if you.god() == "Okawaru"
            and (have_duration("heroism") or have_duration("finesse")) then
        return true
    end

    if you.extra_resistant() then
        return true
    end

    return false
end

function use_ru_healing()
    use_ability("Draw Out Power")
end

function use_ely_healing()
    use_ability("Greater Healing")
end

function use_purification()
    use_ability("Purification")
end

function plan_brothers_in_arms()
    if can_brothers_in_arms() and want_to_brothers_in_arms() then
        return use_ability("Brothers in Arms")
    end

    return false
end

function plan_greater_servant()
    if can_greater_servant() and want_to_greater_servant() then
        return use_ability("Greater Servant of Makhleb")
    end

    return false
end

function plan_cleansing_flame()
    if can_cleansing_flame() and want_to_cleansing_flame() then
        return use_ability("Cleansing Flame")
    end

    return false
end

function plan_divine_warrior()
    if can_divine_warrior() and want_to_divine_warrior() then
        return use_ability("Summon Divine Warrior")
    end

    return false
end

function plan_recite()
    if can_recite()
            and qw.danger_in_los
            and not (qw.immediate_danger and hp_is_low(33)) then
        return use_ability("Recite", "", true)
    end

    return false
end

function plan_tactical_step()
    if not qw.tactical_step then
        return false
    end

    say("Stepping ~*~*~tactically~*~*~ (" .. qw.tactical_reason .. ").")
    return move_to(qw.tactical_step)
end

function plan_priority_tactical_step()
    if qw.tactical_reason == "cloud"
            or qw.tactical_reason == "sticky flame" then
        return plan_tactical_step()
    end

    return false
end

function plan_flee()
    if unable_to_move() or dangerous_to_move() or not want_to_flee() then
        return false
    end

    local result = best_move_towards_positions(qw.flee_positions)

    if not result and in_bad_form() then
        result = best_move_towards_unexplored(true)
        if result then
            qw.last_flee_turn = you.turns()
            say("FLEEEEING to unexplored (badform).")
            return move_to(result.move)
        end
    end

    if result then
        if not qw.danger_in_los then
            qw.last_flee_turn = you.turns()
        end

        say("FLEEEEING.")
        return move_to(result.move)
    end

    return false
end

-- XXX: This plan is broken due to changes to combat assessment.
function plan_grand_finale()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting
            or not can_grand_finale() then
        return false
    end

    local invo = you.skill("Invocations")
    -- fail rate potentially too high, need to add ability failure rate lua
    if invo < 10 or you.piety_rank() < 6 and invo < 15 then
        return false
    end
    local bestx, besty, best_info, new_info
    local flag_order = {"threat", "injury", "distance"}
    local flag_reversed = {false, true, true}
    local best_info, best_pos
    for _, enemy in ipairs(qw.enemy_list) do
        local pos = enemy:pos()
        if is_traversable_at(pos)
                and not cloud_is_dangerous(view.cloud_at(pos.x, pos.y)) then
            if new_info.safe == 0
                    and (not best_info
                        or compare_melee_targets(enemy, best_enemy, props, reversed)) then
                best_info = new_info
                best_pos = pos
            end
        end
    end
    if best_info then
        use_ability("Grand Finale", "r" .. vector_move(best_pos) .. "\rY")
        return true
    end
    return false
end

function plan_apocalypse()
    if can_apocalypse() and want_to_apocalypse() then
        return use_ability("Apocalypse")
    end

    return false
end

function plan_hydra_destruction()
    if not can_destruction()
            or you.skill("Invocations") < 8
            or check_greater_servants(4) then
        return false
    end

    local hydra_dist = dangerous_hydra_distance()
    if not hydra_dist or hydra_dist > 5 then
        return false
    end

    return use_ability("Major Destruction",
        "r" .. vector_move(enemy:x_pos(), enemy:y_pos()) .. "\r")
end

function fiery_armour()
    use_ability("Fiery Armour")
end

function plan_resistance()
    if can_drink() and want_resistance() then
        return drink_by_name("resistance")
    end

    return false
end

function plan_magic_points()
    if can_drink() and want_magic_points() then
        return drink_by_name("magic")
    end

    return false
end

function plan_trogs_hand()
    if can_trogs_hand() and want_to_trogs_hand() then
        return use_ability("Trog's Hand")
    end

    return false
end

function plan_cure_bad_poison()
    if not qw.danger_in_los then
        return false
    end

    if you.poison_survival() <= you.hp() - 60 then
        if drink_by_name("curing") then
            say("(to cure bad poison)")
            return true
        end

        if can_purification() then
            return use_purification()
        end
    end

    return false
end

function plan_cancellation()
    if not qw.danger_in_los or not can_drink() or you.teleporting() then
        return false
    end

    if you.petrifying()
            or you.corrosion() >= 16 + qw.base_corrosion
            or you.corrosion() >= 12 + qw.base_corrosion and hp_is_low(70)
            or in_bad_form() then
        return drink_by_name("cancellation")
    end

    return false
end

function plan_blinking()
    if not in_branch("Zig") or not qw.danger_in_los or not can_read() then
        return false
    end

    local para_danger = false
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:name() == "floating eye"
                or enemy:name() == "starcursed mass" then
            para_danger = true
        end
    end
    if not para_danger then
        return false
    end

    if count_item("scroll", "blinking") == 0 then
        return false
    end

    local cur_count = 0
    for pos in adjacent_iter(const.origin) do
        local mons = get_monster_at(pos)
        if mons and mons:name() == "floating eye" then
            cur_count = cur_count + 3
        elseif mons and mons:name() == "starcursed mass" then
            cur_count = cur_count + 1
        end
    end
    if cur_count >= 2 then
        return false
    end

    local best_count = 0
    local best_pos
    for pos in square_iter(const.origin) do
        if is_traversable_at(pos)
                and not is_solid_at(pos)
                and not get_monster_at(pos)
                and is_safe_at(pos)
                and not view.withheld(pos.x, pos.y)
                and you.see_cell_no_trans(pos.x, pos.y) then
            local count = 0
            for dpos in adjacent_iter(pos) do
                if supdist(dpos) <= qw.los_radius then
                    local mons = get_monster_at(dpos)
                    if mons and mons:is_enemy()
                            and mons:name() == "floating eye" then
                        count = count + 3
                    elseif mons
                            and mons:is_enemy()
                            and mons:name() == "starcursed mass" then
                        count = count + 1
                    end
                end
            end
            if count > best_count then
                best_count = count
                best_pos = pos
            end
        end
    end
    if best_count >= cur_count + 2 then
        local scroll = find_item("scroll", "blinking")
        return read_scroll(scroll,  vector_move(best_x, best_y) .. ".")
    end
    return false
end

function can_drink_heal_wounds()
    if not can_drink()
            or not find_item("potion", "heal wounds")
            or you.mutation("no potion heal") > 1 then
        return false
    end

    local armour = get_slot_item("body")
    if armour and armour:name():find("NoPotionHeal") then
        return false
    end

    return true
end

function heal_general()
    if can_ru_healing() and drain_level() <= 1 then
        return use_ru_healing()
    end

    if can_ely_healing() then
        return use_ely_healing()
    end

    if can_drink_heal_wounds() then
        if drink_by_name("heal wounds") then
            return true
        elseif not item_type_is_ided("potion", "heal wounds")
                and quaff_unided_potion() then
            return true
        end
    end

    if can_ru_healing() then
        return use_ru_healing()
    end

    if can_ely_healing() then
        return use_ely_healing()
    end

    return false
end

function plan_heal_wounds()
    if want_to_heal_wounds() then
        return heal_general()
    end

    return false
end

function can_haste()
    return can_drink()
        and not you.berserk()
        and you.god() ~= "Cheibriados"
        and you.race() ~= "Formicid"
        and find_item("potion", "haste")
end

function plan_haste()
    if can_haste() and want_to_haste() then
        return drink_by_name("haste")
    end

    return false
end

function can_might()
    return can_drink() and find_item("potion", "might")
end

function want_to_might()
    if not danger
            or dangerous_to_attack()
            or you.mighty()
            or you.teleporting() then
        return false
    end

    local result = assess_enemies()
    if result.threat >= const.high_threat then
        return true
    elseif result.scary_enemy then
        attack = result.scary_enemy:best_player_attack()
        return attack and attack.uses_might
    end

    return false
end

function plan_might()
    if can_might() and want_to_might() then
        return drink_by_name("might")
    end

    return false
end

function attraction()
    if you.status("attractive") then
        return false
    end

    return drink_by_name("attraction")
end

function plan_berserk()
    if can_berserk() and want_to_berserk() then
        return use_ability("Berserk")
    end

    return false
end

function plan_heroism()
    if can_heroism() and want_to_heroism() then
        return use_ability("Heroism")
    end

    return false
end

function plan_recall()
    if can_recall() and want_to_recall() then
        if you.god() == "Yredelemnul" then
            use_ability("Recall Undead Slaves", "", true)
        else
            use_ability("Recall Orcish Followers", "", true)
        end
    end

    return false
end

function plan_recall_ancestor()
    if can_recall_ancestor() and check_elliptic(qw.los_radius) then
        return use_ability("Recall Ancestor", "", true)
    end

    return false
end

function plan_finesse()
    if can_finesse() and want_to_finesse() then
        return use_ability("Finesse")
    end

    return false
end

function plan_slouch()
    if can_slouch() and want_to_slouch() then
        return use_ability("Slouch")
    end

    return false
end

function plan_drain_life()
    if can_drain_life() and want_to_drain_life() then
        return use_ability("Drain Life")
    end

    return false
end

function plan_fiery_armour()
    if can_fiery_armour() and want_to_fiery_armour() then
        return use_ability("Fiery Armour")
    end

    return false
end

function want_to_brothers_in_arms()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting()
            or check_brothers_in_arms(4) then
        return false
    end

    -- If threat is too high even with any available buffs like berserk.
    local result = assess_enemies(const.duration.available)
    if result.threat >= 15 then
        return true
    end

    return false
end

function want_to_slouch()
    return qw.danger_in_los
        and not dangerous_to_attack()
        and not you.teleporting()
        and you.piety_rank() == 6
        and estimate_slouch_damage() >= 6
end

function want_to_drain_life()
    return qw.danger_in_los
        and not dangerous_to_attack()
        and not you.teleporting()
        and count_enemies(qw.los_radius,
            function(mons) return mons:res_draining() == 0 end)
end

function want_to_greater_servant()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting()
            or you.skill("Invocations") < 12
            or check_greater_servants(4) then
        return false
    end

    if hp_is_low(50) and qw.immediate_danger then
        return true
    end

    local result = assess_enemies()
    if result.threat >= 15 then
        return true
    end

    return false
end

function want_to_cleansing_flame()
    if not qw.danger_in_los or dangerous_to_attack() then
        return false
    end

    local result = assess_enemies(const.duration.active, 2,
        function(mons) return mons:res_holy() <= 0 end)
    if result.scary_enemy and not result.scary_enemy:player_can_attack(1)
            or result.threat >= const.high_threat and result.count >= 3 then
        return true
    end

    if hp_is_low(50) and qw.immediate_danger then
        local flame_restore_count = count_enemies(2, mons_tso_heal_check)
        return flame_restore_count > count_enemies(1, mons_tso_heal_check)
            and flame_restore_count >= 4
    end

    return false
end

function want_to_divine_warrior()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting()
            or you.skill("Invocations") < 8
            or check_divine_warriors(4) then
        return false
    end

    if hp_is_low(50) and qw.immediate_danger then
        return true
    end

    local result = assess_enemies()
    if result.threat >= 15 then
        return true
    end
end

function want_to_fiery_armour()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.status("fiery-armoured") then
        return false
    end

    if hp_is_low(50) and qw.immediate_danger then
        return true
    end

    local result = assess_enemies()
    if result.scary_enemy or result.threat >= const.high_threat then
        return true
    end

    return false
end

function want_to_apocalypse()
    if not qw.danger_in_los or dangerous_to_attack() or you.teleporting() then
        return false
    end

    local dlevel = drain_level()
    local result = assess_enemies()
    if dlevel == 0
                and (result.scary_enemy or result.threat >= const.high_threat)
            or dlevel <= 2 and hp_is_low(50) then
        return true
    end

    return false
end

function bad_corrosion()
    if you.corrosion() == qw.base_corrosion then
        return false
    elseif in_branch("Slime") then
        return you.corrosion() >= 24 + qw.base_corrosion and hp_is_low(70)
    else
        return you.corrosion() >= 12 + qw.base_corrosion and hp_is_low(50)
            or you.corrosion() >= 16 + qw.base_corrosion and hp_is_low(70)
    end
end

function want_to_teleport()
    if you.teleporting() or in_branch("Zig") then
        return false
    end

    if in_bad_form() and not will_flee() then
        return true
    end

    if qw.have_orb and hp_is_low(33) and sense_danger(2) then
        return true
    end

    if count_hostile_summons(qw.los_radius) > 0 and you.xl() < 21 then
        hostile_summons_timer = you.turns()
        return true
    end

    if qw.immediate_danger and bad_corrosion()
            or qw.immediate_danger and hp_is_low(25) then
            return true
    end

    if will_flee() then
        return false
    end

    local enemies = assess_enemies(const.duration.available)
    if enemies.scary_enemy
            and enemies.scary_enemy:threat(const.duration.available) >= 5
            and enemies.scary_enemy:name():find("slime creature")
            and enemies.scary_enemy:name() ~= "slime creature" then
        return true
    end

    if enemies.threat >= const.extreme_threat then
        return not will_fight_or_retreat()
    end

    return false
end

function want_to_heal_wounds()
    if want_to_orbrun_heal_wounds() then
        return true
    end

    if not qw.danger_in_los then
        return false
    end

    if can_ely_healing() and hp_is_low(50) and you.piety_rank() >= 5 then
        return true
    end

    return hp_is_low(25)
end

function want_resistance()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting()
            or you.extra_resistant() then
        return false
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if (enemy:has_path_to_melee_player() or enemy:is_ranged(true))
                and (monster_in_list(enemy, fire_resistance_monsters)
                        and you.res_fire() < 3
                    or monster_in_list(enemy, cold_resistance_monsters)
                        and you.res_cold() < 3
                    or monster_in_list(enemy, elec_resistance_monsters)
                        and you.res_shock() < 1
                    or monster_in_list(enemy, pois_resistance_monsters)
                        and you.res_poison() < 1
                    or in_branch("Zig")
                        and monster_in_list(enemy, acid_resistance_monsters)
                        and not you.res_corr()) then
            return true
        end
    end

    return false
end

function want_to_haste()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.hasted()
            or you.teleporting() then
        return false
    end

    local result = assess_enemies()
    if result.threat >= const.high_threat then
        return not duration_active("finesse") or you.slowed()
    elseif result.scary_enemy then
        local attack = result.scary_enemy:best_player_attack()
        return attack
            -- We can always use haste if we're slowed().
            and (you.slowed()
                -- Only primary attacks are allowed to use haste.
                or attack.index == 1
                    -- Don't haste if we're already benefiting from Finesse.
                    and not (attack.uses_finesse and duration_active("finesse")))
    end

    return false
end

function want_magic_points()
    if you.race() == "Djinni" then
        return false
    end

    local mp, mmp = you.mp()
    return qw.danger_in_los
        and not dangerous_to_attack()
        and not you.teleporting()
        -- Don't bother restoring MP if our max MP is low.
        and mmp >= 20
        -- No point trying to restore MP with ghost moths around.
        and count_enemies_by_name(qw.los_radius, "ghost moth") == 0
        -- We want and could use these abilities if we had more MP.
        and (can_cleansing_flame(true)
                and not can_cleansing_flame()
                and want_to_cleansing_flame()
            or can_divine_warrior(true)
                and not can_divine_warrior()
                and want_to_divine_warrior())
end

function want_to_trogs_hand()
    if you.regenerating() or you.teleporting() then
        return false
    end

    local hp, mhp = you.hp()
    return in_branch("Abyss") and mhp - hp >= 30
        or not dangerous_to_attack()
            and check_enemies_in_list(qw.los_radius, hand_monsters)
end

function check_berserkable_enemies()
    local filter = function(enemy, moveable)
        return enemy:player_has_path_to_melee()
    end
    return check_enemies(2, filter)
end

function want_to_berserk()
    if not qw.danger_in_los or dangerous_to_melee() or you.berserk() then
        return false
    end

    if hp_is_low(50) and check_berserkable_enemies()
            or invis_monster and nasty_invis_caster then
        return true
    end

    local result = assess_enemies(const.duration.available, 2)
    if result.scary_enemy then
        local attack = result.scary_enemy:best_player_attack()
        if attack and attack.uses_berserk then
            return true
        end
    end

    if result.threat >= const.high_threat then
        return true
    end

    return false
end

function want_to_finesse()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or you.teleporting()
            or duration_active("finesse") then
        return false
    end

    local result = assess_enemies()
    if result.threat >= const.high_threat then
        return true
    elseif result.scary_enemy then
        attack = result.scary_enemy:best_player_attack()
        return attack and attack.uses_finesse
    end

    return false
end

function want_to_heroism()
    if not qw.danger_in_los
            or dangerous_to_attack()
            or duration_active("heroism")
            or you.teleporting() then
        return false
    end

    local result = assess_enemies()
    if result.threat >= const.high_threat then
        return true
    elseif result.scary_enemy then
        local attack = result.scary_enemy:best_player_attack()
        return attack and attack.uses_heroism
    end

    return false
end

function want_to_recall()
    if qw.immediate_danger and hp_is_low(66) then
        return false
    end

    if you.race() == "Djinni" then
        local hp, mhp = you.hp()
        return hp == mhp
    else
        local mp, mmp = you.mp()
        return mp == mmp
    end
end

function plan_full_inventory_panic()
    if qw.danger_in_los or not qw.position_is_safe then
        return false
    end

    if qw_full_inventory_panic and free_inventory_slots() == 0 then
        panic("Inventory is full!")
    else
        return false
    end
end

function plan_cure_confusion()
    if not you.confused()
            or not can_drink()
            or not (qw.danger_in_los
                or options.autopick_on
                or qw.position_is_cloudy)
            or view.cloud_at(0, 0) == "noxious fumes"
                and not meph_immune() then
        return false
    end

    if drink_by_name("curing") then
        say("(to cure confusion)")
        return true
    end

    if can_purification() then
        return use_purification()
    end

    if not item_type_is_ided("potion", "curing") then
        return quaff_unided_potion()
    end

    return false
end

-- This plan is necessary to make launcher qw try to escape from the net so
-- that it can resume attacking instead of trying post-attack plans. It should
-- come after any emergency plans that we could still execute while caught.
function plan_escape_net()
    if not qw.danger_in_los or not you.caught() then
        return false
    end

    -- Can move in any direction to escape nets, regardless of what's there.
    return move_to({ x = 0, y = 1 })
end

function plan_wait_confusion()
    if not you.confused() or not (qw.danger_in_los or options.autopick_on) then
        return false
    end

    wait_one_turn()
    return true
end

function plan_non_melee_berserk()
    if not you.berserk() or not using_ranged_weapon() then
        return false
    end

    if unable_to_move() or dangerous_to_move() then
        wait_one_turn()
        return true
    end

    local result = best_move_towards_positions(qw.flee_positions)
    if result then
        return move_to(result.move)
    end

    wait_one_turn()
    return true
end

-- Curing poison/confusion with purification is handled elsewhere.
function plan_special_purification()
    if not can_purification() then
        return false
    end

    if you.slowed() and not qw.slow_aura or you.petrifying() then
        return use_purification()
    end

    local str, mstr = you.strength()
    local int, mint = you.intelligence()
    local dex, mdex = you.dexterity()
    if str < mstr
            and (str < mstr - 5 or str < 3)
                or int < mint and int < 3
                or dex < mdex and (dex < mdex - 8 or dex < 3) then
        return use_purification()
    end

    return false
end

function can_dig_to(pos)
    local positions = spells.path("Dig", pos.x, pos.y, false)
    local hit_grate = false
    for i, coords in ipairs(positions) do
        local dpos = { x = coords[1], y = coords[2] }
        if not hit_grate
                and view.feature_at(dpos.x, dpos.y) == "iron_grate" then
            hit_grate = true
        end

        if positions_equal(pos, dpos) then
            return hit_grate
        end
    end
    return false
end

function plan_dig_grate()
    local wand = find_item("wand", "digging")
    if not wand or not can_zap() then
        return false
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if not map_is_reachable_at(enemy:map_pos())
                and enemy:should_dig_unreachable() then
            return evoke_targeted_item(wand, enemy:pos())
        end
    end

    return false
end

function plan_retreat()
    if not want_to_retreat() or unable_to_move() or dangerous_to_move() then
        return false
    end

    local pos = best_retreat_position()
    if not pos then
        return false
    end

    local result = best_move_towards(pos)
    if result then
        say("RETREEEEATING.")
        return move_to(result.move)
    end

    return false
end

function set_plan_emergency()
    plans.emergency = cascade {
        {plan_stairdance_up, "stairdance_up"},
        {plan_special_purification, "special_purification"},
        {plan_cure_confusion, "cure_confusion"},
        {plan_cancellation, "cancellation"},
        {plan_teleport, "teleport"},
        {plan_remove_terrible_rings, "remove_terrible_rings"},
        {plan_cure_bad_poison, "cure_bad_poison"},
        {plan_blinking, "blinking"},
        {plan_drain_life, "drain_life"},
        {plan_heal_wounds, "heal_wounds"},
        {plan_trogs_hand, "trogs_hand"},
        {plan_escape_net, "escape_net"},
        {plan_priority_tactical_step, "priority_tactical_step"},
        {plan_wait_confusion, "wait_confusion"},
        {plan_zig_fog, "zig_fog"},
        {plan_flee, "flee"},
        {plan_retreat, "retreat"},
        {plan_tactical_step, "tactical_step"},
        {plan_tomb2_arrival, "tomb2_arrival"},
        {plan_tomb3_arrival, "tomb3_arrival"},
        {plan_magic_points, "magic_points"},
        {plan_cleansing_flame, "try_cleansing_flame"},
        {plan_divine_warrior, "divine_warrior"},
        {plan_brothers_in_arms, "brothers_in_arms"},
        {plan_greater_servant, "greater_servant"},
        {plan_apocalypse, "try_apocalypse"},
        {plan_slouch, "try_slouch"},
        {plan_hydra_destruction, "try_hydra_destruction"},
        {plan_grand_finale, "grand_finale"},
        {plan_fiery_armour, "fiery_armour"},
        {plan_dig_grate, "try_dig_grate"},
        {plan_wield_weapon, "wield_weapon"},
        {plan_resistance, "resistance"},
        {plan_finesse, "finesse"},
        {plan_heroism, "heroism"},
        {plan_haste, "haste"},
        {plan_might, "might"},
        {plan_recall, "recall"},
        {plan_recall_ancestor, "try_recall_ancestor"},
        {plan_recite, "try_recite"},
        {plan_berserk, "berserk"},
    }
end
