function plan_teleport()
    if can_teleport() and want_to_teleport() then
        -- return false
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
    if you.god() == "Okawaru" and
         (you.status("heroic") or you.status("finesse-ful")) then
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

function hand()
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

function bia()
    use_ability("Brothers in Arms")
end

function sgd()
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

function plan_bia()
    if can_bia() and want_to_bia() then
        bia()
        return true
    end
    return false
end

function plan_sgd()
    if can_sgd() and want_to_sgd() then
        sgd()
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

function plan_grand_finale()
    if not danger or not can_grand_finale() then
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
    best_info = nil
    for _, e in ipairs(enemy_list) do
        if is_traversable(e.x, e.y)
                and not cloud_is_dangerous(view.cloud_at(e.x, e.y)) then
            new_info = get_monster_info(e.x, e.y)
            if new_info.safe == 0
                    and (not best_info
                        or compare_monster_info(new_info, best_info,
                            flag_order, flag_reversed)) then
                best_info = new_info
                bestx = e.x
                besty = e.y
            end
        end
    end
    if best_info then
        use_ability("Grand Finale", "r" .. vector_move(bestx, besty) .. "\rY")
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
            or count_sgd(4) > 0
            or hydra_weapon_status(items.equipped_at("Weapon")) > -1
            or you.xl() >= 20 then
        return false
    end

    for _, e in ipairs(enemy_list) do
        if supdist(e.x, e.y) <= 5 and string.find(e.m:desc(), "hydra") then
            say("INVOKING MAJOR DESTRUCTION")
            for letter, abil in pairs(you.ability_table()) do
                if abil == "Major Destruction" then
                    magic("a" .. letter .. "r" .. vector_move(e.x, e.y) ..
                        "\r")
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
    if not you.extra_resistant() and not you.teleporting()
         and want_resistance() then
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

function plan_hand()
    if can_hand() and want_to_hand() and not you.teleporting() then
        hand()
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
    if you.poison_survival() <= chp() - 60 then
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
    for _, e in ipairs(enemy_list) do
        if e.m:name() == "floating eye" or e.m:name() == "starcursed mass" then
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
    local best_count = 0
    local m, count, best_x, best_y
    for x, y in adjacent_iter(0, 0) do
        m = monster_array[x][y]
        if m and m:name() == "floating eye" then
            cur_count = cur_count + 3
        elseif m and m:name() == "starcursed mass" then
            cur_count = cur_count + 1
        end
    end
    if cur_count >= 2 then
        return false
    end

    for x, y in square_iter(0, 0) do
        if is_traversable(x, y)
                and not is_solid(x, y)
                and monster_array[x][y] == nil
                and view.is_safe_square(x, y)
                and not view.withheld(x, y)
                and you.see_cell_no_trans(x, y) then
            count = 0
            for dx, dy in adjacent_iter(x, y) do
                if abs(dx) <= los_radius and abs(dy) <= los_radius then
                    m = monster_array[dx][dy]
                    if m and m:name() == "floating eye" then
                        count = count + 3
                    elseif m and m:name() == "starcursed mass" then
                        count = count + 1
                    end
                end
            end
            if count > best_count then
                best_count = count
                best_x = x
                best_y = y
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
    if want_to_serious_buff() then
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

function want_to_bia()
    if not danger then
        return false
    end

    -- Always BiA this list of monsters.
    if (check_monster_list(los_radius, bia_necessary_monsters)
                -- If piety as high, we can also use BiA as a fallback for when
                -- we'd like to berserk, but can't, or if when we see nasty
                -- monsters.
                or you.piety_rank() > 4
                    and (want_to_berserk() and not can_berserk()
                        or check_monster_list(los_radius, nasty_monsters)))
            and count_bia(4) == 0
            and not you.teleporting() then
        return true
    end
    return false
end

function want_to_finesse()
    if danger
            and in_branch("Zig")
            and hp_is_low(80)
            and count_monsters_near(0, 0, los_radius) >= 5 then
        return true
    end
    if danger and check_monster_list(los_radius, nasty_monsters)
            and not you.teleporting() then
        return true
    end
    return false
end

function want_to_slouch()
    if danger and you.piety_rank() == 6 and not you.teleporting()
            and estimate_slouch_damage() >= 6 then
        return true
    end
    return false
end

function want_to_drain_life()
    if not danger then
        return false
    end
    return count_monsters(los_radius, function(m) return m:res_draining() == 0 end)
end

function want_to_sgd()
    if you.skill("Invocations") >= 12
            and (check_monster_list(los_radius, nasty_monsters)
                or hp_is_low(50) and immediate_danger) then
        if count_sgd(4) == 0 and not you.teleporting() then
            return true
        end
    end
    return false
end

function want_to_cleansing_flame()
    if not check_monster_list(1, scary_monsters, mons_is_holy_vulnerable)
            and check_monster_list(2, scary_monsters, mons_is_holy_vulnerable)
        or count_monsters(2, mons_is_holy_vulnerable) > 8 then
        return true
    end

    local filter = function(m)
        local holiness = m:holiness()
        return not m:desc():find("summoned")
            and (holiness == "undead"
                or holiness == "demonic"
                or holiness == "evil")
    end
    if hp_is_low(50) and immediate_danger then
        local flame_restore_count = count_monsters(2, filter)
        return flame_restore_count > count_monsters(1, filter)
            and flame_restore_count >= 4
    end

    return false
end

function want_to_divine_warrior()
    return you.skill("Invocations") >= 8
        and (check_monster_list(los_radius, nasty_monsters)
            or hp_is_low(50) and immediate_danger)
        and count_divine_warrior(4) == 0
        and not you.teleporting()
end

function want_to_fiery_armour()
    return danger
        and (hp_is_low(50)
            or count_monster_list(los_radius, scary_monsters) >= 2
            or check_monster_list(los_radius, nasty_monsters)
            or count_monsters_near(0, 0, los_radius) >= 6)
end

function want_to_apocalypse()
    local dlevel = drain_level()
    return dlevel == 0 and check_monster_list(los_radius, scary_monsters)
        or dlevel <= 2
            and (danger and hp_is_low(50)
                or check_monster_list(los_radius, nasty_monsters))
end

function bad_corrosion()
    if you.corrosion() == base_corrosion then
        return false
    elseif in_branch("Slime") then
        return you.corrosion() >= 6 + base_corrosion and hp_is_low(70)
    else
        return (you.corrosion() >= 3 + base_corrosion and hp_is_low(50)
            or you.corrosion() >= 4 + base_corrosion and hp_is_low(70))
    end
end

function want_to_teleport()
    if in_branch("Zig") then
        return false
    end

    if count_hostile_sgd(los_radius) > 0 and you.xl() < 21 then
        sgd_timer = you.turns()
        return true
    end

    if in_branch("Pan")
            and (count_monster_by_name(los_radius, "hellion") >= 3
                or count_monster_by_name(los_radius, "daeva") >= 3) then
        dislike_pan_level = true
        return true
    end

    if you.xl() <= 17
            and not can_berserk()
            and count_big_slimes(los_radius) > 0 then
        return true
    end

    return immediate_danger and bad_corrosion()
            or immediate_danger and hp_is_low(25)
            or count_nasty_hell_monsters(los_radius) >= 9
end

function want_to_heal_wounds()
    if danger and can_ely_healing()
            and hp_is_low(50)
            and you.piety_rank() >= 5 then
        return true
    end

    return danger and hp_is_low(25)
end

function count_nasty_hell_monsters(r)
    if not in_hell_branch() then
        return 0
    end

    -- We're most concerned with hell monsters that aren't vulnerable to any
    -- holy wrath we might have (either from TSO Cleansing Flame or the weapon
    -- brand).
    local have_holy_wrath = you.god() == "the Shining One"
        or items.equipped_at("weapon")
            and items.equipped_at("weapon").ego() == "holy wrath"
    local filter = function(m)
        return not (have_holy_wrath and mons_is_holy_vulnerable(m))
    end
    return count_monster_list(r, nasty_monsters, filter)
end

function want_to_serious_buff()
    if danger and in_branch("Zig")
            and hp_is_low(50)
            and count_monsters_near(0, 0, los_radius) >= 5 then
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

    if check_monster_list(los_radius, ridiculous_uniques) then
        return true
    end

    if count_nasty_hell_monsters(los_radius) >= 5 then
        return true
    end

    return false
end

function want_resistance()
    return check_monster_list(los_radius, fire_resistance_monsters)
            and you.res_fire() < 3
        or check_monster_list(los_radius, cold_resistance_monsters)
            and you.res_cold() < 3
        or check_monster_list(los_radius, elec_resistance_monsters)
            and you.res_shock() < 1
        or check_monster_list(los_radius, pois_resistance_monsters)
            and you.res_poison() < 1
        or in_branch("Zig")
            and check_monster_list(los_radius, acid_resistance_monsters)
            and not you.res_corr()
end

function want_magic_points()
    -- No point trying to restore MP with ghost moths around.
    return count_monster_by_name(los_radius, "ghost moth") == 0
            and (hp_is_low(50) or you.have_orb() or in_extended())
        -- We want and could use these abilities if we had more MP.
        and (can_cleansing_flame(true)
                and not can_cleansing_flame()
                and want_to_cleansing_flame()
            or can_divine_warrior(true)
                and not can_divine_warrior()
                and want_to_divine_warrior())
end

function want_to_hand()
    return check_monster_list(los_radius, hand_monsters)
end

function want_to_berserk()
    return (hp_is_low(50) and sense_danger(2, true)
        or check_monster_list(2, scary_monsters)
        or invis_sigmund and not options.autopick_on)
end

function want_to_heroism()
    return danger
        and (hp_is_low(70)
            or check_monster_list(los_radius, scary_monsters)
            or count_monsters_near(0, 0, los_radius) >= 4)
end

function want_to_recall()
    if immediate_danger and hp_is_low(66) then
        return false
    end

    local mp, mmp = you.mp()
    return mp == mmp
end

function want_to_recall_ancestor()
    return count_elliptic(los_radius) == 0
end

function plan_continue_flee()
    if you.turns() >= last_flee_turn + 10 or not target_stair then
        return false
    end

    if danger
            or not (reason_to_rest(90)
                or you.xl() <= 8 and disable_autoexplore)
            or you.transform() == "tree"
            or count_bia(3) > 0
            or count_sgd(3) > 0
            or count_divine_warrior(3) > 0
            or you.status("spiked")
            or you.confused()
            or buffed() then
        return false
    end

    local num = waypoint_parity
    local wx, wy = travel.waypoint_delta(num)
    local val
    for x, y in adjacent_iter(0, 0) do
        if is_traversable(x, y)
                and not is_solid(x, y)
                and not monster_in_way(x, y)
                and view.is_safe_square(x, y)
                and not view.withheld(x, y) then
            val = stair_dists[num][target_stair][wx + x][wy + y]
            if val and val < stair_dists[num][target_stair][wx][wy] then
                dsay("STILL FLEEEEING.")
                magic(delta_to_vi(x, y) .. "YY")
                return true
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

function plan_cure_confusion()
    if you.confused() and (danger or not options.autopick_on) then
        if view.cloud_at(0, 0) == "noxious fumes" and not meph_immune() then
            if you.god() == "Beogh" then
                magic("s") -- avoid Beogh penance
                return true
            end
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
        if you.god() == "Beogh" then
            magic("s") -- avoid Beogh penance
            return true
        end
    end
    return false
end

-- curing poison/confusion with purification is handled elsewhere
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

function plan_dig_grate()
    local grate_mon_list
    local grate_count_needed = 3
    if in_branch("Zot") then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher"}
    elseif in_branch("Depths") and at_branch_end() then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher",
            "angel", "daeva", "lich", "eye"}
    elseif in_branch("Depths") then
        grate_mon_list = {"angel", "daeva", "lich", "eye"}
    elseif in_branch("Pan") or at_branch_end("Geh") then
        grate_mon_list = {"smoke demon"}
        grate_count_needed = 1
    elseif in_branch("Zig") then
        grate_mon_list = {""}
        grate_count_needed = 1
    else
        return false
    end

    for _, e in ipairs(enemy_list) do
        local name = e.m:name()
        if contains_string_in(name, grate_mon_list)
             and not will_tab(0, 0, e.x, e.y, tabbable_square) then
            local grate_count = 0
            local closest_grate = 20
            local gx, gy, cgx, cgy
            for dx = -1, 1 do
                for dy = -1, 1 do
                    gx = e.x + dx
                    gy = e.y + dy
                    if supdist(gx, gy) <= los_radius
                            and view.feature_at(gx, gy) == "iron_grate" then
                        grate_count = grate_count + 1
                        if abs(gx) + abs(gy) < closest_grate
                                and you.see_cell_solid_see(gx, gy) then
                            cgx = gx
                            cgy = gy
                            closest_grate = abs(gx) + abs(gy)
                        end
                    end
                end
            end
            if grate_count >= grate_count_needed and closest_grate < 20 then
                local c = find_item("wand", "digging")
                if c and can_zap() then
                    say("ZAPPING " .. item(c).name() .. ".")
                    magic("V" .. letter(c) .. "r" .. vector_move(cgx, cgy) ..
                        "\r")
                    return true
                end
            end
        end
    end

    return false
end

function plan_cure_poison()
    if you.poison_survival() <= 1 and you.poisoned() then
        if drink_by_name("curing") then
            say("(to cure poison)")
            return true
        end
    end
    if you.poison_survival() <= 1 and you.poisoned() then
        if can_hand() then
            hand()
            return true
        end
        if can_purification() then
            purification()
            return true
        end
    end
    return false
end

function set_plan_emergency()
    plan_emergency = cascade {
        {plan_special_purification, "special_purification"},
        {plan_cure_confusion, "cure_confusion"},
        {plan_coward_step, "coward_step"},
        {plan_flee_step, "flee_step"},
        {plan_remove_terrible_jewellery, "remove_terrible_jewellery"},
        {plan_teleport, "teleport"},
        {plan_cure_bad_poison, "cure_bad_poison"},
        {plan_cancellation, "cancellation"},
        {plan_drain_life, "drain_life"},
        {plan_heal_wounds, "heal_wounds"},
        {plan_tomb2_arrival, "tomb2_arrival"},
        {plan_tomb3_arrival, "tomb3_arrival"},
        {plan_cloud_step, "cloud_step"},
        {plan_hand, "hand"},
        {plan_haste, "haste"},
        {plan_resistance, "resistance"},
        {plan_magic_points, "magic_points"},
        {plan_heroism, "heroism"},
        {plan_cleansing_flame, "try_cleansing_flame"},
        {plan_bia, "bia"},
        {plan_sgd, "sgd"},
        {plan_divine_warrior, "divine_warrior"},
        {plan_apocalypse, "try_apocalypse"},
        {plan_slouch, "try_slouch"},
        {plan_hydra_destruction, "try_hydra_destruction"},
        {plan_grand_finale, "grand_finale"},
        {plan_wield_weapon, "wield_weapon"},
        {plan_swap_weapon, "swap_weapon"},
        {plan_water_step, "water_step"},
        {plan_zig_fog, "zig_fog"},
        {plan_finesse, "finesse"},
        {plan_fiery_armour, "fiery_armour"},
        {plan_dig_grate, "try_dig_grate"},
        {plan_might, "might"},
        {plan_blinking, "blinking"},
        {plan_berserk, "berserk"},
        {plan_continue_flee, "continue_flee"},
        {plan_other_step, "other_step"},
    }
end
