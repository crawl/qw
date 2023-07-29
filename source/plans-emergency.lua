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
            or you.corrosion() >= 2 + base_corrosion then
        return false
    end

    if you.god() == "Okawaru"
            and (you.status("heroic") or you.status("finesse-ful")) then
        return true
    end

    if you.extra_resistant() then
        return true
    end

    return false
end

function berserk()
    use_ability("Berserk")
end

function heroism()
    use_ability("Heroism")
end

function recall()
    if you.god() == "Yredelemnul" then
        use_ability("Recall Undead Slaves", "", true)
    else
        use_ability("Recall Orcish Followers", "", true)
    end
end

function recall_ancestor()
    use_ability("Recall Ancestor", "", true)
end

function finesse()
    use_ability("Finesse")
end

function slouch()
    use_ability("Slouch")
end

function drain_life()
    use_ability("Drain Life")
end

function trogs_hand()
    use_ability("Trog's Hand")
end

function ru_healing()
    use_ability("Draw Out Power")
end

function ely_healing()
    use_ability("Greater Healing")
end

function purification()
    use_ability("Purification")
end

function recite()
    use_ability("Recite", "", true)
end

function brothers_in_arms()
    use_ability("Brothers in Arms")
end

function greater_servant()
    use_ability("Greater Servant of Makhleb")
end

function cleansing_flame()
    use_ability("Cleansing Flame")
end

function divine_warrior()
    use_ability("Summon Divine Warrior")
end

function apocalypse()
    use_ability("Apocalypse")
end

function plan_brothers_in_arms()
    if can_brothers_in_arms() and want_to_brothers_in_arms() then
        brothers_in_arms()
        return true
    end
    return false
end

function plan_greater_servant()
    if can_greater_servant() and want_to_greater_servant() then
        greater_servant()
        return true
    end
    return false
end

function plan_cleansing_flame()
    if can_cleansing_flame() and want_to_cleansing_flame() then
        cleansing_flame()
        return true
    end
    return false
end

function plan_divine_warrior()
    if can_divine_warrior() and want_to_divine_warrior() then
        divine_warrior()
        return true
    end
    return false
end

function plan_recite()
    if can_recite() and danger
            and not (immediate_danger and hp_is_low(33)) then
        recite()
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

function plan_wall_step()
    if tactical_reason == "wall" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_coward_step()
    if (tactical_reason == "hiding" or tactical_reason == "stealth")
            and (not want_to_move_to_abyss_objective()
                or should_rest()) then
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
    if tactical_reason ~= "fleeing" then
        return false
    end

    local best_pos = best_flee_destination_at(vi_to_delta(tactical_step))
    if not best_pos then
        return false
    end

    target_flee_position = best_pos
    last_flee_turn = you.turns()
    say("FLEEEEING.")
    magic(tactical_step .. "Y")
    return true
end

function plan_other_step()
    if tactical_reason ~= "none" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

-- XXX: This plan is broken due to changes to combat assessment.
function plan_grand_finale()
    if not danger
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
    for _, enemy in ipairs(enemy_list) do
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
        apocalypse()
        return true
    end
    return false
end

function plan_hydra_destruction()
    if not can_destruction()
            or you.skill("Invocations") < 8
            or count_greater_servants(4) > 0
            or hydra_weapon_status(items.equipped_at("Weapon")) > -1
            or you.xl() >= 20 then
        return false
    end

    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= 5 and string.find(enemy:desc(), "hydra") then
            say("invoking major destruction")
            for letter, abil in pairs(you.ability_table()) do
                if abil == "Major Destruction" then
                    magic("a" .. letter .. "r"
                        .. vector_move(enemy.pos.x, enemy.pos.y) .. "\r")
                    return true
                end
            end
        end
    end
    return false
end

function fiery_armour()
    use_ability("Fiery Armour")
end

function plan_resistance()
    if want_resistance() then
        return drink_by_name("resistance")
    end

    return false
end

function plan_magic_points()
    if not you.teleporting() and want_magic_points() then
        return drink_by_name("magic")
    end

    return false
end

function plan_trogs_hand()
    if can_trogs_hand() and want_to_trogs_hand() and not you.teleporting() then
        trogs_hand()
        return true
    end

    return false
end

function prefer_ru_healing()
    return drain_level() <= 1
end

function prefer_ely_healing()
    if you.god() ~= "Elyvilon" or you.piety_rank() < 4 then
        return false
    end
    return true
end

function plan_cure_bad_poison()
    if not danger then
        return false
    end

    if you.poison_survival() <= you.hp() - 60 then
        if drink_by_name("curing") then
            say("(to cure bad poison)")
            return true
        end
        if can_purification() then
            purification()
            return true
        end
    end

    return false
end

function plan_cancellation()
    if not danger or not can_drink() or you.teleporting() then
        return false
    end

    if you.petrifying()
            or you.corrosion() >= 4 + base_corrosion
            or you.corrosion() >= 3 + base_corrosion and hp_is_low(70)
            or you.transform() == "pig"
            or you.transform() == "wisp"
            or you.transform() == "bat" then
        if drink_by_name("cancellation") then
            return true
        end
    end

    return false
end

function plan_blinking()
    if not in_branch("Zig") or not danger or not can_read() then
        return false
    end

    local para_danger = false
    for _, enemy in ipairs(enemy_list) do
        if enemy:name() == "floating eye"
                or enemy:name() == "starcursed mass" then
            para_danger = true
        end
    end
    if not para_danger then
        return false
    end

    if count_item("scroll", "of blinking") == 0 then
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
        local c = find_item("scroll", "blinking")
        return read(letter(c),  vector_move(best_x, best_y) .. ".")
    end
    return false
end

function can_drink_heal_wounds()
    return you.mutation("no potion heal") < 2
        and not (items.equipped_at("Body Armour")
            and items.equipped_at("Body Armour"):name():find("NoPotionHeal"))
end

function heal_general()
    if can_ru_healing() and prefer_ru_healing() then
        ru_healing()
        return true
    end

    if can_ely_healing() and prefer_ely_healing() then
        ely_healing()
        return true
    end

    if can_drink_heal_wounds() and drink_by_name("heal wounds") then
        return true
    end

    if can_ru_healing() then
        ru_healing()
        return true
    end

    if can_ely_healing() then
        ely_healing()
        return true
    end

    return false
end

function plan_heal_wounds()
    if want_to_heal_wounds() then
        return heal_general()
    end

    return false
end

function plan_haste()
    if want_to_serious_buff() then
        return haste()
    end
    return false
end

function plan_might()
    if not have_ranged_weapon() and want_to_serious_buff() then
        return might()
    end
    return false
end

function haste()
    if you.hasted() or you.race() == "Formicid"
            or you.god() == "Cheibriados" then
        return false
    end

    return drink_by_name("haste")
end

function might()
    if you.mighty() then
        return false
    end

    return drink_by_name("might")
end

function attraction()
    if you.status("attractive") then
        return false
    end

    return drink_by_name("attraction")
end

function plan_berserk()
    if can_berserk() and want_to_berserk() then
        berserk()
        return true
    end
    return false
end

function plan_heroism()
    if can_heroism() and want_to_heroism() then
        heroism()
        return true
    end
    return false
end

function plan_recall()
    if can_recall() and want_to_recall() then
        recall()
        return true
    end
    return false
end

function plan_recall_ancestor()
    if can_recall_ancestor() and want_to_recall_ancestor() then
        recall_ancestor()
        return true
    end
    return false
end

function plan_finesse()
    if can_finesse() and want_to_finesse() then
        finesse()
        return true
    end
    return false
end

function plan_slouch()
    if can_slouch() and want_to_slouch() then
        slouch()
        return true
    end
    return false
end

function plan_drain_life()
    if can_drain_life() and want_to_drain_life() then
        drain_life()
        return true
    end
    return false
end

function plan_fiery_armour()
    if can_fiery_armour() and want_to_fiery_armour() then
        fiery_armour()
        return true
    end

    return false
end

function want_to_brothers_in_arms()
    if not danger or dangerous_to_attack() or you.teleporting() then
        return false
    end

    -- Always BiA this list of monsters.
    if (check_enemies_in_list(qw.los_radius, brothers_in_arms_necessary_monsters)
                -- If piety as high, we can also use BiA as a fallback for when
                -- we'd like to berserk, but can't, or if when we see nasty
                -- monsters.
                or you.piety_rank() > 4
                    and (want_to_berserk() and not can_berserk()
                        or check_enemies_in_list(qw.los_radius, nasty_monsters)))
            and count_brothers_in_arms(4) == 0 then
        return true
    end

    return false
end

function want_to_finesse()
    if not danger or dangerous_to_attack() then
        return false
    end

    if in_branch("Zig")
            and hp_is_low(80)
            and count_enemies(qw.los_radius) >= 5 then
        return true
    end

    if not you.teleporting()
            and check_enemies_in_list(qw.los_radius, nasty_monsters) then
        return true
    end

    return false
end

function want_to_slouch()
    return danger
        and not dangerous_to_attack()
        and not you.teleporting()
        and you.piety_rank() == 6
        and estimate_slouch_damage() >= 6
end

function want_to_drain_life()
    return danger
        and not dangerous_to_attack()
        and not you.teleporting()
        and count_enemies(qw.los_radius,
            function(mons) return mons:res_draining() == 0 end)
end

function want_to_greater_servant()
    if you.skill("Invocations") >= 12
            and (check_enemies_in_list(qw.los_radius, nasty_monsters)
                or hp_is_low(50) and immediate_danger) then
        if count_greater_servants(4) == 0 and not you.teleporting() then
            return true
        end
    end
    return false
end

function want_to_cleansing_flame()
    if not danger or dangerous_to_attack() then
        return false
    end

    local holy_check = function(mons)
            return mons:is_holy_vulnerable()
        end
    if not check_enemies_in_list(1, scary_monsters, holy_check)
                and check_enemies_in_list(2, scary_monsters, holy_check)
            or count_enemies(2, holy_check) > 8 then
        return true
    end

    local filter = function(mons)
        return mons:is_holy_vulnerable() and not mons:is_summoned()
    end
    if hp_is_low(50) and immediate_danger then
        local flame_restore_count = count_enemies(2, filter)
        return flame_restore_count > count_enemies(1, filter)
            and flame_restore_count >= 4
    end

    return false
end

function want_to_divine_warrior()
    return danger
        and not dangerous_to_attack()
        and not you.teleporting()
        and you.skill("Invocations") >= 8
        and (check_enemies_in_list(qw.los_radius, nasty_monsters)
            or hp_is_low(50) and immediate_danger)
        and count_divine_warriors(4) == 0
end

function want_to_fiery_armour()
    return danger
        and not dangerous_to_attack()
        and (hp_is_low(50)
            or count_enemies_in_list(qw.los_radius, scary_monsters) >= 2
            or check_enemies_in_list(qw.los_radius, nasty_monsters)
            or count_enemies(qw.los_radius) >= 6)
end

function want_to_apocalypse()
    if not danger or dangerous_to_attack() or you.teleporting() then
        return false
    end

    local dlevel = drain_level()
    return dlevel == 0 and check_enemies_in_list(qw.los_radius, scary_monsters)
        or dlevel <= 2
            and (danger and hp_is_low(50)
                or check_enemies_in_list(qw.los_radius, nasty_monsters))
end

function bad_corrosion()
    if you.corrosion() == base_corrosion then
        return false
    elseif in_branch("Slime") then
        return you.corrosion() >= 6 + base_corrosion and hp_is_low(70)
    else
        return you.corrosion() >= 3 + base_corrosion and hp_is_low(50)
            or you.corrosion() >= 4 + base_corrosion and hp_is_low(70)
    end
end

function want_to_teleport()
    if in_branch("Zig") then
        return false
    end

    if want_to_orbrun_teleport() then
        return true
    end

    if in_bad_form()
            and not find_item("potion", "cancellation")
            and sense_danger(1) then
        return true
    end

    if count_hostile_summons(qw.los_radius) > 0 and you.xl() < 21 then
        hostile_summons_timer = you.turns()
        return true
    end

    if in_branch("Pan")
            and (count_enemies_by_name(qw.los_radius, "hellion") >= 3
                or count_enemies_by_name(qw.los_radius, "daeva") >= 3) then
        dislike_pan_level = true
        return true
    end

    if you.xl() <= 17
            and not can_berserk()
            and count_big_slimes(qw.los_radius) > 0 then
        return true
    end

    return immediate_danger and bad_corrosion()
            or immediate_danger and hp_is_low(25)
            or count_nasty_hell_monsters(qw.los_radius) >= 9
end

function want_to_heal_wounds()
    if have_orb then
        return want_to_orbrun_heal_wounds()
    end

    if danger and can_ely_healing()
            and hp_is_low(50)
            and you.piety_rank() >= 5 then
        return true
    end

    return danger and hp_is_low(25)
end

function count_nasty_hell_monsters(radius)
    if not in_hell_branch() then
        return 0
    end

    -- We're most concerned with hell monsters that aren't vulnerable to any
    -- holy wrath we might have (either from TSO Cleansing Flame or the weapon
    -- brand).
    local have_holy_wrath = you.god() == "the Shining One"
        or items.equipped_at("weapon")
            and items.equipped_at("weapon").ego() == "holy wrath"
    local filter = function(mons)
        return not (have_holy_wrath and mons:is_holy_vulnerable())
    end
    return count_enemies_in_list(radius, nasty_monsters, filter)
end

function want_to_serious_buff()
    if not danger or dangerous_to_attack() then
        return false
    end

    if have_orb then
        return want_to_orbrun_buff()
    end

    if in_branch("Zig")
            and hp_is_low(50)
            and count_enemies(qw.los_radius) >= 5 then
        return true
    end

    -- These gods have their own buffs.
    if you.god() == "Okawaru" or you.god() == "Trog" then
        return false
    end

    -- None of these uniques exist early.
    if you.num_runes() < 3 then
        return false
    end

    -- Don't waste a potion if we are already leaving.
    if you.teleporting() then
        return false
    end

    if check_enemies_in_list(qw.los_radius, ridiculous_uniques) then
        return true
    end

    if count_nasty_hell_monsters(qw.los_radius) >= 5 then
        return true
    end

    return false
end

function want_resistance()
    return danger
        and not dangerous_to_attack()
        and not you.teleporting()
        and not you.extra_resistant()
        and (check_enemies_in_list(qw.los_radius, fire_resistance_monsters)
                and you.res_fire() < 3
            or check_enemies_in_list(qw.los_radius, cold_resistance_monsters)
                and you.res_cold() < 3
            or check_enemies_in_list(qw.los_radius, elec_resistance_monsters)
                and you.res_shock() < 1
            or check_enemies_in_list(qw.los_radius, pois_resistance_monsters)
                and you.res_poison() < 1
            or in_branch("Zig")
                and check_enemies_in_list(qw.los_radius, acid_resistance_monsters)
                and not you.res_corr())
end

function want_magic_points()
    local mp, mmp = you.mp()
    return danger
        and not dangerous_to_attack()
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
    local hp, mhp = you.hp()
    return in_branch("Abyss") and mhp - hp >= 30
        or not dangerous_to_attack()
            and check_enemies_in_list(qw.los_radius, hand_monsters)
end

function want_to_berserk()
    return danger
        and not dangerous_to_melee()
        and (hp_is_low(50) and sense_danger(2, true)
            or check_enemies_in_list(2, scary_monsters)
            or invis_monster and nasty_invis_caster)
end

function want_to_heroism()
    return danger
        and not dangerous_to_attack()
        and (have_orb and want_to_orbrun_buff()
            or hp_is_low(70)
            or check_enemies_in_list(qw.los_radius, scary_monsters)
            or count_enemies(0, 0, qw.los_radius) >= 4)
end

function want_to_recall()
    if immediate_danger and hp_is_low(66) then
        return false
    end

    local mp, mmp = you.mp()
    return mp == mmp
end

function want_to_recall_ancestor()
    return count_elliptic(qw.los_radius) == 0
end

function plan_continue_flee()
    if you.turns() >= last_flee_turn + 10 or not target_flee_position then
        return false
    end

    if danger or not reason_to_flee()
            or unable_to_move()
            or you.confused()
            or you.berserk()
            or you.status("spiked")
            or count_brothers_in_arms(3) > 0
            or count_greater_servants(3) > 0
            or count_divine_warriors(3) > 0
            or buffed() then
        return false
    end

    for pos in adjacent_iter(const.origin) do
        if can_move_to(pos) and not is_solid_at(pos) and is_safe_at(pos) then
            local map = get_distance_map(target_flee_position).excluded_map
            local dist = map[global_pos.x + pos.x][global_pos.y + pos.y]
            if dist and dist < map[global_pos.x][global_pos.y] then
                dsay("STILL FLEEEEING.")
                return move_to(pos)
            end
        end
    end

    return false
end

function plan_full_inventory_panic()
    if FULL_INVENTORY_PANIC and free_inventory_slots() == 0 then
        panic("Inventory is full!")
    else
        return false
    end
end

function plan_cure_confusion()
    if not you.confused()
            or not (danger or options.autopick_on)
            or view.cloud_at(0, 0) == "noxious fumes"
                and not meph_immune() then
        return false
    end

    if drink_by_name("curing") then
        say("(to cure confusion)")
        return true
    end

    if can_purification() then
        purification()
        return true
    end

    return false
end

-- This plan is necessary to make launcher qw try to escape from the net so
-- that it can resume attacking instead of trying post-attack plans. It should
-- come after any emergency plans that we could still execute while caught.
function plan_escape_net()
    if not danger or not you.caught() then
        return false
    end

    -- Can move in any direction to escape nets, regardless of what's there.
    return move_to({ x = 0, y = 1 })
end

function plan_wait_confusion()
    if not you.confused() or not (danger or options.autopick_on) then
        return false
    end

    wait_one_turn()
    return true
end

function plan_non_melee_berserk()
    if not you.berserk() or not have_ranged_weapon() then
        return false
    end

    if unable_to_move() or dangerous_to_move() then
        wait_one_turn()
        return true
    end

    local best_pos = best_flee_destination_at(const.origin)
    if not best_pos then
        wait_one_turn()
        return true
    end

    local result = best_move_towards(best_pos)
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

    if you.slowed() or you.petrifying() then
        purification()
        return true
    end

    local str, mstr = you.strength()
    local int, mint = you.intelligence()
    local dex, mdex = you.dexterity()
    if str < mstr and (str < mstr - 5 or str < 3)
         or int < mint and int < 3
         or dex < mdex and (dex < mdex - 8 or dex < 3) then
        purification()
        return true
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
    local wand_letter = find_item("wand", "digging")
    if not wand_letter or not can_zap() then
        return false
    end

    for _, enemy in ipairs(enemy_list) do
        if not enemy:can_move_to_player_melee()
                and not map_is_reachable_at(enemy:map_pos())
                and enemy:should_dig_unreachable() then
            say("ZAPPING " .. item(wand_letter).name() .. ".")
            magic("V" .. wand_letter .. "r" .. vector_move(enemy:pos())
                .. "\r")
            return true
        end
    end

    return false
end

function set_plan_emergency()
    plans.emergency = cascade {
        {plan_stairdance_up, "stairdance_up"},
        {plan_non_melee_berserk, "non_melee_berserk"},
        {plan_special_purification, "special_purification"},
        {plan_cure_confusion, "cure_confusion"},
        {plan_teleport, "teleport"},
        {plan_cancellation, "cancellation"},
        {plan_remove_terrible_jewellery, "remove_terrible_jewellery"},
        {plan_cure_bad_poison, "cure_bad_poison"},
        {plan_blinking, "blinking"},
        {plan_drain_life, "drain_life"},
        {plan_heal_wounds, "heal_wounds"},
        {plan_tomb2_arrival, "tomb2_arrival"},
        {plan_tomb3_arrival, "tomb3_arrival"},
        {plan_cloud_step, "cloud_step"},
        {plan_trogs_hand, "trogs_hand"},
        {plan_haste, "haste"},
        {plan_resistance, "resistance"},
        {plan_magic_points, "magic_points"},
        {plan_escape_net, "escape_net"},
        {plan_wait_confusion, "wait_confusion"},
        {plan_zig_fog, "zig_fog"},
        {plan_continue_flee, "continue_flee"},
        {plan_flee_step, "flee_step"},
        {plan_wall_step, "wall_step"},
        {plan_water_step, "water_step"},
        {plan_coward_step, "coward_step"},
        {plan_other_step, "other_step"},
        {plan_cleansing_flame, "try_cleansing_flame"},
        {plan_brothers_in_arms, "brothers_in_arms"},
        {plan_greater_servant, "greater_servant"},
        {plan_divine_warrior, "divine_warrior"},
        {plan_apocalypse, "try_apocalypse"},
        {plan_slouch, "try_slouch"},
        {plan_hydra_destruction, "try_hydra_destruction"},
        {plan_grand_finale, "grand_finale"},
        {plan_fiery_armour, "fiery_armour"},
        {plan_dig_grate, "try_dig_grate"},
        {plan_wield_weapon, "wield_weapon"},
        {plan_swap_weapon, "swap_weapon"},
        {plan_heroism, "heroism"},
        {plan_finesse, "finesse"},
        {plan_might, "might"},
        {plan_berserk, "berserk"},
        {plan_recall, "recall"},
        {plan_recall_ancestor, "try_recall_ancestor"},
        {plan_recite, "try_recite"},
    }
end
