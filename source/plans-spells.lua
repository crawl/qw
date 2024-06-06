function get_starting_spell()
    if you.xl() > 4 or you.god() == "Trog" then
        return
    end

    local spell_list = { "Foxfire", "Freeze", "Magic Dart", "Necrotise", "Sandblast",
        "Shock", "Sting", "Summon Small Mammal" }
    for _, sp in ipairs(spell_list) do
        if spells.memorised(sp) and spells.fail(sp) <= 25 then
            return sp
        end
    end
end

function spell_range(sp)
    if sp == "Summon Small Mammal" then
        return qw.los_radius
    elseif sp == "Beastly Appendage" then
        return 4
    elseif sp == "Sandblast" then
        return 4
    else
        return spells.range(sp)
    end
end

function spell_castable(sp)
    if you.silenced()
            or you.confused()
            or you.berserk()
            or in_bad_form()
            or can_use_mp(spells.mana_cost(sp)) then
        return false
    end

    if sp == "Beastly Appendage" then
        return transformed()
    elseif sp == "Summon Small Mammal" then
        local count = 0
        for pos in square_iter(const.origin) do
            local mons = get_monster_at(pos)
            if mons and mons:is_friendly() then
                count = count + 1
            end
        end
        if count >= 2 then
            return false
        end
    end

    return true
end

function distance_to_tabbable_enemy()
    local best_dist = 10
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:distance() < best_dist
                and (enemy:player_has_path_to_melee()
                    or enemy:player_can_wait_for_melee()) then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end

function plan_starting_spell()
    if not qw.starting_spell or not spell_castable(qw.starting_spell) then
        return false
    end

    local dist = distance_to_tabbable_enemy()
    if dist < 2 and weapon_skill() ~= "Unarmed Combat" then
        local weap = get_weapon()
        if weap and weap.weap_skill == weapon_skill() then
            return false
        end
    end

    if dist > spell_range(qw.starting_spell) then
        return false
    end

    say("CASTING " .. qw.starting_spell)
    if spells.range(qw.starting_spell) > 0 then
        magic("z" .. spells.letter(qw.starting_spell) .. "f")
    else
        magic("z" .. spells.letter(qw.starting_spell))
    end
    return true
end
