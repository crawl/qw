-----------------------------------------
-- Attack setup and evaluation

const.attack = { "melee", "launcher", "throw", "evoke" }

-- Is the result from an attack on the first target better than the current
-- best result?
function result_improves_attack(attack, result, best_result)
    if not result then
        return false
    end

    if not best_result then
        return true
    end

    return compare_table_keys(result, best_result, attack.props,
        attack.reversed_props)
end

function score_enemy_hit(result, enemy, attack)
    if attack.check and not attack.check(enemy) then
        return
    end

    for _, prop in ipairs(attack.props) do
        local use_min = attack.min_props[prop]
        if not use_min and not result[prop] then
            result[prop] = 0
        end

        if prop == "hit" then
            result[prop] = result[prop] + 1
        elseif use_min then
            local value = enemy[prop](enemy)
            if not result[prop] or value < result[prop] then
                result[prop] = value
            end
        else
            local value = enemy[prop](enemy)
            if value == true then
                value = 1
            elseif value == false then
                value = 0
            end

            result[prop] = result[prop] + value
        end
    end
end

function assess_melee_target(attack, enemy)
    local result = { attack = attack, pos = enemy:pos() }
    score_enemy_hit(result, enemy, attack)
    return result
end

function make_melee_attack(weapons)
    local attack = {
        type = const.attack.melee,
        items = weapons,
        has_damage_rating = true,
        uses_finesse = true,
        uses_heroism = true,
        uses_berserk = true,
        uses_might = true
    }
    attack.props = { "los_danger", "distance", "is_constricting_you",
        "stabbability", "damage_level", "threat", "is_orc_priest_wizard" }
    -- We favor closer monsters.
    attack.reversed_props = { distance = true }
    attack.min_props = { distance = true }

    return attack
end

function make_primary_attack()
    local weapons
    local equip = inventory_equip(const.inventory.equipped)
    if equip then
        weapons = equip.weapon
    end

    if weapons and weapons[1].is_ranged then
        return make_launcher_attack(weapons)
    else
        return make_melee_attack(weapons)
    end
end

function get_primary_target()
    if using_ranged_weapon() then
        return get_launcher_target()
    else
        return get_melee_target()
    end
end


function get_melee_attack()
    local attack = get_attack(1)
    if not attack or attack.type ~= const.attack.melee then
        return
    end

    return attack
end

function get_melee_target_func(assume_flight)
    local attack = get_melee_attack()
    if not attack then
        return
    end

    local best_result
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:player_can_melee()
                or enemy:get_player_move_towards(assume_flight) then
            local result = assess_melee_target(attack, enemy)
            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
        end
    end

    return best_result
end

function get_melee_target(assume_flight)
    return turn_memo_args("get_melee_target",
        function()
            return get_melee_target_func(assume_flight)
        end, assume_flight)
end

function assess_explosion_position(attack, target_pos, second_pos)
    local result = { attack = attack, pos = target_pos, positions = {} }
    for pos in adjacent_iter(target_pos, true) do
        result.positions[hash_position(pos)] = true

        if positions_equal(target_pos, const.origin)
                and not attack.explosion_ignores_player then
            return
        end

        local mons
        if supdist(pos) <= qw.los_radius then
            mons = get_monster_at(pos)
        end
        if mons then
            if mons:attitude() > const.attitude.hostile
                    and not mons:ignores_player_projectiles() then
                return
            end

            if mons:is_enemy() then
                score_enemy_hit(result, mons, attack)
            end
        end
    end

    if not second_pos or result.positions[hash_position(second_pos)] then
        return result
    end
end

function assess_ranged_position(attack, target_pos, second_pos)
    if debug_channel("ranged") then
        dsay("Targeting " .. cell_string_from_position(target_pos))
    end

    if secondary_pos
            and attack.is_exploding
            and position_distance(target_pos, secondary_pos) > 2 then
        return
    end

    local positions = spells.path(attack.test_spell, target_pos.x,
        target_pos.y, 0, 0, false)
    local result = { attack = attack, pos = target_pos, positions = {} }
    local past_target, at_target_result
    for i, coords in ipairs(positions) do
        local pos = { x = coords[1], y = coords[2] }
        if position_distance(pos, const.origin) > attack.range then
            break
        end

        local hit_target = positions_equal(pos, target_pos)
        local mons = get_monster_at(pos)
        -- Non-penetrating attacks must reach the target before reaching any
        -- other enemy, otherwise they're considered blocked and unusable.
        if not attack.is_penetrating
                and not past_target
                and not hit_target
                and mons and not mons:ignores_player_projectiles() then
            if debug_channel("ranged") then
                dsay("Aborted target: blocking monster at "
                    .. cell_string_from_position(pos))
            end

            return
        end

        -- Never potentially hit non-enemy monsters that are allies, would get
        -- aggravated, or would cause penance. If at_target_result is defined,
        -- we'll be using '.', otherwise we abort this target.
        if mons and not mons:is_enemy()
                and not mons:is_harmless()
                and not mons:ignores_player_projectiles() then
            if debug_channel("ranged") then
                if at_target_result then
                    dsay("Using at-target key due to non-enemy monster at "
                        .. cell_string_from_position(pos))
                else
                    dsay("Aborted target: non-enemy monster at "
                        .. cell_string_from_position(pos))
                end
            end

            return at_target_result
        end

        -- Unless we're hitting our target right now, try to avoid losing ammo
        -- to destructive terrain at the end of our throw path by using '.'.
        if not hit_target
                and not attack.is_exploding
                and attack.type == const.attack.throw
                and attack.items[1].subtype() ~= "boomerang"
                and i == #positions
                and destroys_items_at(pos)
                and not destroys_items_at(target_pos) then
            if debug_channel("ranged") then
                dsay("Using at-target key due to destructive terrain at "
                    .. pos_string(pos))
            end

            return at_target_result
        end

        result.positions[hash_position(pos)] = true

        if mons and not mons:ignores_player_projectiles() then
            if attack.is_exploding then
                return assess_explosion_position(attack, target_pos,
                    second_pos)
            elseif mons:is_enemy()
                    -- Non-penetrating attacks only get the values from the
                    -- target.
                    and (attack.is_penetrating or hit_target) then
                score_enemy_hit(result, mons, attack)
                if debug_channel("ranged") then
                    dsay("Attack scores after enemy at " .. pos_string(pos)
                        .. ": " .. stringify_table(result))
                end
            end
        end

        -- We've reached the target, so make a copy of the results up to this
        -- point in case we later decide to use '.'.
        if hit_target
                and (not second_pos
                    or result.positions[hash_position(second_pos)]) then
            at_target_result = util.copy_table(result)
            at_target_result.aim_at_target = true
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

function assess_possible_explosion_positions(attack, target_pos, second_pos)
    local best_result
    for pos in adjacent_iter(target_pos, true) do
        local valid, mon
        if supdist(pos) <= qw.los_radius
                and (not attack.seen_pos or not attack.seen_pos[pos.x][pos.y])
                and (attack.explosion_ignores_player
                    or position_distance(pos, const.origin) > 1)
                -- If we have a second position, don't consider explosion
                -- centers that won't reach the position.
                and (not second_pos or position_distance(pos, second_pos) <= 1) then
            valid = true
            mon = get_monster_at(pos)
        end

        if valid and (positions_equal(target_pos, pos)
                or not mon
                or mon:ignores_player_projectiles()) then
            local result = assess_ranged_position(attack, pos, second_pos)
            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end

            if attack.seen_pos then
                attack.seen_pos[pos.x][pos.y] = true
            end
        end
    end
    return best_result
end

function attack_test_spell(attack)
end

function make_launcher_attack(weapons)
    local attack = {
        type = const.attack.launcher,
        items = weapons,
        has_damage_rating = true,
        uses_finesse = true,
        uses_heroism = true,
        range = qw.los_radius,
        can_target_empty = false,
        test_spell = "Quicksilver Bolt",
    }

    for _, weapon in ipairs(weapons) do
        if item_is_penetrating(weapon) then
            attack.is_penetrating = true
        end

        if item_is_exploding(weapon) then
            attack.is_exploding = true

            attack.explosion_ignores_player = true
            if not item_explosion_ignores_player(weapon) then
                attack.explosion_ignores_player = false
            end
        end
    end

    attack.props = { "los_danger", "hit", "distance", "is_constricting_you",
        "damage_level", "threat", "is_orc_priest_wizard" }
    attack.reversed_props = { distance = true }
    attack.min_props = { distance = true }
    return attack
end

function make_throwing_attack(missile, prefer_melee)
    if not missile then
        return
    end

    local attack = {
        type = const.attack.throw,
        items = { missile },
        has_damage_rating = true,
        prefer_melee = prefer_melee,
        uses_finesse = true,
        uses_heroism = true,
        range = qw.los_radius,
        is_penetrating = item_is_penetrating(missile),
        can_target_empty = true,
        test_spell = "Quicksilver Bolt",
    }
    attack.props = { "los_danger", "hit", "distance", "is_constricting_you",
        "damage_level", "threat", "is_orc_priest_wizard" }
    attack.reversed_props = { distance = true }
    attack.min_props = { distance = true }
    return attack
end

function assess_ranged_target(attack, pos, second_pos)
    if position_distance(pos, const.origin) > attack.range
            or not you.see_cell_solid_see(pos.x, pos.y) then
        return
    end

    local result
    if attack.is_exploding and attack.can_target_empty then
        result = assess_possible_explosion_positions(attack, pos, second_pos)
    else
        result = assess_ranged_position(attack, pos, second_pos)
    end

    return result
end

function get_ranged_attack_target(attack)
    if not attack then
        return
    end

    local melee_target
    if attack.prefer_melee then
        melee_target = get_melee_target()
        if melee_target
                and get_monster_at(melee_target.pos):player_can_melee() then
            return
        end
    end

    if attack.is_exploding then
        attack.seen_pos = {}
        for i = -qw.los_radius, qw.los_radius do
            attack.seen_pos[i] = {}
        end
    end

    local best_result
    for _, enemy in ipairs(qw.enemy_list) do
        -- If we have and prefer a melee target and there's a ranged monster,
        -- we'll abort whenever there's a monster we could move towards
        -- instead, since this is how the melee movement plan works.
        if melee_target and enemy:is_ranged() and enemy:get_player_move_towards() then
            return
        end

        local pos = enemy:pos()
        if enemy:distance() <= attack.range
                and you.see_cell_solid_see(pos.x, pos.y) then
            local result
            if attack.is_exploding and attack.can_target_empty then
                result = assess_possible_explosion_positions(attack, pos)
            else
                result = assess_ranged_position(attack, pos)
            end

            if result_improves_attack(attack, result, best_result) then
                best_result = result
            end
        end
    end
    if best_result then
        return best_result
    end
end

function get_best_throwing_attack()
    local attack = get_attack(2)
    if not attack or attack.type ~= const.attack.throw then
        return
    end

    return attack
end

function get_secondary_throwing_attack()
    local attack = get_attack(3)
    if not attack or attack.type ~= const.attack.throw then
        return
    end

    return attack
end

function get_high_threat_target()
    local result = assess_enemies(const.duration.ignore_buffs)
    if not result.scary_enemy then
        return
    end

    local attack = result.scary_enemy:best_player_attack()
    if not attack then
        return
    end

    local pos = result.scary_enemy:pos()
    local primary_target = get_primary_target()
    if attack.type == const.attack.melee then
        if positions_equal(primary_target.pos, pos) then
            return primary_target
        else
            return
        end
    end

    local secondary_pos
    if primary_target and not positions_equal(primary_target.pos, pos) then
        secondary_pos = primary_target.pos
    end

    return assess_ranged_target(attack, pos, secondary_pos)
end

function get_throwing_target_func()
    local target = get_high_threat_target()
    if target then
        if target.attack.type ~= const.attack.throw then
            return
        end

        return target
    end

    local result = assess_enemies()
    if result.threat < const.moderate_threat
            and qw.incoming_monsters_turn == you.turns() then
        return
    end

    local attack = get_secondary_throwing_attack()
    if not attack then
        return
    end

    return get_ranged_attack_target(attack)
end

function get_throwing_target()
    return turn_memo("get_throwing_target", get_throwing_target_func)
end

function get_evoke_target()
    return turn_memo("get_evoke_target",
        function()
            local target = get_high_threat_target()
            if target and target.attack.type == const.attack.evoke then
                return target
            end
        end)
end

function get_launcher_target()
    return turn_memo("get_launcher_target",
        function() return get_ranged_attack_target(get_attack(1)) end)
end

function poison_spit_attack()
    local poison_gas = you.mutation("spit poison") > 1
    local attack = {
        range = poison_gas and 6 or 5,
        is_penetrating = poison_gas,
        prefer_melee = not using_ranged_weapon(),
        test_spell = "Quicksilver Bolt",
        props = { "los_danger", "hit", "distance", "is_constricting_you",
            "damage_level", "threat", "is_orc_priest_wizard" },
        reversed_props = { distance = true },
        min_props = { distance = true },
        check = function(mons) return mons:res_poison() < 1 end,
    }
    return attack
end

function make_wand_attack(wand_type)
    local wand = find_item("wand", wand_type)
    if not wand then
        return
    end

    local attack = {
        type = const.attack.evoke,
        items = { wand },
        range = item_range(wand),
        is_penetrating = item_is_penetrating(wand),
        is_exploding = item_is_exploding(wand),
        can_target_empty = item_can_target_empty(wand),
        explosion_ignores_player = item_explosion_ignores_player(wand),
        damage_is_hp = wand_type == "paralysis",
        test_spell = "Quicksilver Bolt",
        props = { "los_danger", "hit", "distance", "is_constricting_you",
            "damage_level", "threat", "is_orc_priest_wizard" },
        reversed_props = { distance = true },
        min_props = { distance = true },
    }
    return attack
end

function get_attacks()
    if qw.attacks then
        return qw.attacks
    end

    local attack = make_primary_attack()
    attack.index = 1
    qw.attacks = { attack }

    attack = make_throwing_attack(best_missile(missile_damage))
    if attack then
        table.insert(qw.attacks, attack)
        attack.index = #qw.attacks
    end

    attack = make_throwing_attack(best_missile(missile_quantity), true)
    if attack then
        table.insert(qw.attacks, attack)
        attack.index = #qw.attacks
    end

    for _, wand_type in ipairs(const.wand_types) do
        attack = make_wand_attack(wand_type)
        if attack then
            table.insert(qw.attacks, attack)
            attack.index = #qw.attacks
        end
    end

    return qw.attacks
end

function get_attack(index)
    local attacks = get_attacks()
    return attacks[index]
end

function get_ranged_target()
    return turn_memo("get_ranged_target",
        function()
            if you.berserk() then
                return false
            end

            local target = get_evoke_target()
            if target then
                return target
            end

            target = get_throwing_target()
            if target then
                return target
            end

            if using_ranged_weapon() then
                return get_launcher_target()
            end
        end)
end

function have_target()
    if get_primary_target() then
        return true
    end

    return get_throwing_target()
end

function get_ranged_attack()
    if using_ranged_weapon() then
        return get_attack(1)
    end

    return get_best_throwing_attack()
end

function make_damage_func(resist, chance, add, damage_mult)
    return function(mons, damage)
        local res_level = 0
        local prop = const.monster_resist_props[resist]
        if prop then
            res_level = mons[prop](mons)
        end

        return damage
            + chance * monster_percent_unresisted(resist, res_level, true)
            * (add + damage_mult * damage)
    end
end

function initialize_ego_damage()
    const.ego_damage_funcs = {
        ["flaming"] = make_damage_func("rF", 1, 0, 0.25),
        ["freezing"] = make_damage_func("rC", 1, 0, 0.25),
        ["electrocution"] = make_damage_func("rElec", 0.25, 14, 0),
        ["venom"] = make_damage_func("rN", 0.5, 3, 0.25),
        ["draining"] = make_damage_func("rN", 0.5, 3, 0.25),
        ["vampirism"] = make_damage_func("rN", 0.6, 0, 0),
        ["holy wrath"] = make_damage_func("rHoly", 1, 0, 0.75),
    }
end

function rated_attack_average_damage(mons, attack, duration_level)
    if not attack.items then
        local damage = you.unarmed_damage_rating()
        damage = (1 + damage) / 2

        local damage_func = const.ego_damage_funcs[you.unarmed_ego()]
        if damage_func then
            damage = damage_func(mons, damage)
        end

        return damage
    end

    local total_damage = 0
    for _, item in ipairs(attack.items) do
        local damage = item.damage_rating()
        damage = (1 + damage) / 2

        if attack.uses_berserk and have_duration("berserk", duration_level) then
            damage = damage + 5.5
        elseif attack.uses_might and have_duration("might", duration_level) then
            damage = damage + 5.5
        end

        if attack.uses_might and have_duration("weak", duration_level) then
            damage = 0.75 * damage
        end

        local damage_func = const.ego_damage_funcs[item.ego()]
        if damage_func then
            damage = damage_func(mons, damage)
        end

        if attack.type == const.attack.melee
                and you.xl() < 18
                and mons:is_real_hydra() then
            local value = hydra_weapon_value(item)
            damage = damage * math.pow(2, value)
        end

        total_damage = total_damage + damage * mons:weapon_accuracy(item)
    end
    return total_damage
end

function evoked_attack_average_damage(mons, attack)
    -- Crawl doesn't have dual evoking, so for simplicity we assume one item.
    local item = attack.items[1]
    local damage = item.evoke_damage
    damage = damage:gsub(".-(%d+)d(%d+).*", "%1 %2")
    local dice, size = unpack(split(damage, " "))
    damage = dice * (1 + size) / 2

    local res_prop = const.monster_resist_props[attack.resist]
    if res_prop then
        local res_level = mons[res_prop](mons)
        damage = damage * (1 - attack.resistable
            + attack.resistable
            * monster_percent_unresisted(attack.resist, res_level))
    end

    return damage * mons:evoke_accuracy(item)
end

function player_attack_damage(mons, index, duration_level)
    if not duration_level then
        duration_level = const.duration.active
    end

    local attack = get_attack(index)
    if attack.has_damage_rating then
        return rated_attack_average_damage(mons, attack, duration_level)
    elseif attack.type == const.attack.evoke then
        local damage
        if attack.damage_is_hp then
            if mons:is("paralysed")
                    or mons:status("confused")
                    or mons:status("petrifying")
                    or mons:status("petrified") then
                return 0
            else
                damage = mons:hp()
            end
        else
            damage = evoked_attack_average_damage(mons, attack)
        end

        return damage
    end
end

function unarmed_attack_delay(duration_level)
    if not duration_level then
        duration_level = const.duration.active
    end

    local skill = you.skill("Unarmed Combat")

    if not have_duration("heroism", duration_level)
            and duration_active("heroism") then
        skill = skill - min(27 - skill, 5)
    elseif have_duration("heroism", duration_level)
            and not duration_active("heroism") then
        skill = skill + min(27 - skill, 5)
    end

    local delay = 10 - 10 * skill / 54

    if have_duration("finesse", duration_level) then
        delay = delay / 2
    elseif have_duration("berserk", duration_level) then
        delay = delay * 2 / 3
    elseif have_duration("haste", duration_level) then
        delay = delay * 2 / 3
    end

    if have_duration("slow", duration_level) then
        delay = delay * 3 / 2
    end

    return delay
end

function player_attack_delay_func(index, duration_level)
    if not duration_level then
        duration_level = const.duration.active
    end

    local attack = get_attack(index)
    if attack.items then
        if attack.has_damage_rating then
            local count = 0
            local delay = 0
            for _, weapon in ipairs(attack.items) do
                count = count + 1
                delay = delay + weapon_delay(weapon, duration_level)
            end
            return delay / count
        -- Evocable items.
        else
            local delay = 10

            if have_duration("haste", duration_level) then
                delay = delay * 2 / 3
            end

            if have_duration("slow", duration_level) then
                delay = delay * 3 / 2
            end

            return delay
        end
    else
        return unarmed_attack_delay(duration_level)
    end
end

function player_attack_delay(index, duration_level)
    return turn_memo_args("player_attack_delay",
        function()
            return player_attack_delay_func(index, duration_level)
        end, index, duration_level)
end

function monster_best_player_attack(mons)
    local base_threat = mons:threat()
    local base_damage = mons:player_attack_damage(1) / player_attack_delay(1)
    local best_attack, best_threat
    for i, attack in ipairs(get_attacks()) do
        if not attack.prefer_melee and mons:player_can_attack(i) then
            local damage = player_attack_damage(mons, i,
                    const.duration.available)
                / player_attack_delay(i, const.duration.available)
            local threat = base_threat * base_damage / damage
            if threat < 3 then
                return attack
            elseif not best_threat or threat < best_threat then
                best_attack = attack
                best_threat = threat
            end
        end
    end

    return best_attack
end
