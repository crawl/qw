function starting_spell()
    if you.god() == "Trog" or you.xl() > 9 then
        no_spells = true
        return
    end
    local spell_list = {"Shock", "Magic Dart", "Sandblast", "Foxfire",
        "Freeze", "Pain", "Summon Small Mammal", "Beastly Appendage", "Sting"}
    for _, sp in ipairs(spell_list) do
        if spells.memorised(sp) and spells.fail(sp) <= 25 then
            return sp
        end
    end
    no_spells = true
end

function spell_range(sp)
    if sp == "Summon Small Mammal" then
        return los_radius
    elseif sp == "Beastly Appendage" then
        return 4
    elseif sp == "Sandblast" then
        return 3
    else
        return spells.range(sp)
    end
end

function spell_castable(sp)
    if sp == "Beastly Appendage" then
        if transformed() then
            return false
        end
    elseif sp == "Summon Small Mammal" then
        local count = 0
        for x = -los_radius, los_radius do
            for y = -los_radius, los_radius do
                m = monster_array[x][y]
                if m and m:attitude() == enum_att_friendly then
                    count = count + 1
                end
            end
        end
        if count >= 4 then
            return false
        end
    elseif sp == "Sandblast" then
        if not have_item("missile", "stone") then
            return false
        end
    end
    return true
end

function plan_starting_spell()
    if no_spells then
        return false
    end
    if you.silenced() or you.confused() or you.berserk() then
        return false
    end
    local sp = starting_spell()
    if not sp then
        return false
    end
    if cmp() < spells.mana_cost(sp) then
        return false
    end
    if you.xl() > 4 and not is_waiting then
        return false
    end
    local dist = distance_to_tabbable_enemy(0, 0)
    if dist < 2 and wskill() ~= "Unarmed Combat" then
        local weap = items.equipped_at("Weapon")
        if weap and weap.weap_skill == wskill() then
            return false
        end
    end
    if dist > spell_range(sp) then
        return false
    end
    if not spell_castable(sp) then
        return false
    end
    say("CASTING " .. sp)
    if spells.range(sp) > 0 then
        magic("z" .. spells.letter(sp) .. "f")
    else
        magic("z" .. spells.letter(sp))
    end
    return true
end
