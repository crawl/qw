-------------------------------------
-- Equipment property evaluation.

-- Returns the amount of an artprop granted by an item.
function item_property(str, it)
    if not it then
        return 0
    end

    if it.artefact and it.artprops and it.artprops[str] then
        return it.artprops[str]
    else
        local name = it.name()
        local ego = it.ego()
        local subtype = it.subtype()
        if str == "rF" then
            if name:find("fire dragon") then
                return 2
            elseif ego == "fire resistance"
                    or ego == "resistance"
                    or subtype == "ring of protection from fire"
                    or name:find("gold dragon")
                    or subtype == "ring of fire" then
                return 1
            elseif name:find("ice dragon") or subtype == "ring of ice" then
                return -1
            else
                return 0
            end
        elseif str == "rC" then
            if name:find("ice dragon") then
                return 2
            elseif ego == "cold resistance" or ego == "resistance"
                     or subtype == "ring of protection from cold"
                     or name:find("gold dragon")
                     or subtype == "ring of ice" then
                return 1
            elseif name:find("fire dragon") or subtype == "ring of fire" then
                return -1
            else
                return 0
            end
        elseif str == "rElec" then
            return name:find("storm dragon") and 1 or 0
        elseif str == "rPois" then
            return (ego == "poison resistance"
                or subtype == "ring of poison resistance"
                or name:find("swamp dragon")
                or name:find("gold dragon")) and 1 or 0
        elseif str == "rN" then
            return (ego == "positive energy"
                or subtype == "ring of positive energy"
                or name:find("pearl dragon")) and 1 or 0
        elseif str == "Will" then
            return (ego == "willpower"
                or subtype == "ring of willpower"
                or name:find("quicksilver dragon")) and 1 or 0
        elseif str == "rCorr" then
            return (subtype == "ring of resist corrosion"
                or name:find("acid dragon")) and 1 or 0
        elseif str == "SInv" then
            return (ego == "see invisible"
                or subtype == "ring of see invisible") and 1 or 0
        elseif str == "Fly" then
            return ego == "flying" and 1 or 0
        elseif str == "Faith" then
            return subtype == "amulet of faith" and 1 or 0
        elseif str == "Spirit" then
            return (ego == "spirit shield"
                    or subtype == "amulet of guardian spirit") and 1 or 0
        elseif str == "Regen" then
             return (name:find("troll leather")
                     or subtype == "amulet of regeneration") and 1 or 0
        elseif str == "Acrobat" then
             return subtype == "amulet of the acrobat" and 1 or 0
        elseif str == "Reflect" then
             return (ego == "reflection" or subtype == "amulet of reflection")
                 and 1 or 0
        elseif str == "Repulsion" then
             return ego == "repulsion" and 1 or 0
        elseif str == "Ponderous" then
             return ego == "ponderousness" and 1 or 0
        elseif str == "Harm" then
             return ego == "harm" and 1 or 0
        elseif str == "Str" then
            if subtype == "ring of strength" then
                return it.plus or 0
            elseif ego == "strength" then
                return 3
            end
        elseif str == "Dex" then
            if subtype == "ring of dexterity" then
                return it.plus or 0
            elseif ego == "dexterity" then
                return 3
            end
        elseif str == "Int" then
            if subtype == "ring of intelligence" then
                return it.plus or 0
            elseif ego == "intelligence" then
                return 3
            end
        elseif str == "Slay" then
            return subtype == "ring of slaying" and it.plus or 0
        elseif str == "AC" then
            if subtype == "ring of protection" then
                return it.plus or 0
            -- Wrong for weapons, but we scale things differently for weapons.
            elseif ego == "protection" then
                return 3
            end
        elseif str == "EV" then
            return subtype == "ring of evasion"  and it.plus or 0
        elseif str == "SH" then
            return subtype == "amulet of reflection" and 5 or 0
        end
    end

    return 0
end

-- The current utility of having a given amount of an artprop.
function absolute_property_value(str, n)
    if str == "Str" or str == "Int" or str == "Dex" then
        if n > 4 then
            return 0 -- handled by linear_property_value()
        elseif n > 2 then
            return -100
        elseif n > 0 then
            return -250
        else
            return -10000
        end
    end
    if n == 0 then
        return 0
    end

    if branch_soon("Slime")
            and (str == "rF"
                or str == "rElec"
                or str == "rPois"
                or str == "rN"
                or str == "Will"
                or str == "SInv") then
        return 0
    end

    local val = 0
    if str == "rF" or str == "rC" then
        if n < 0 then
            val = -150
        elseif n == 1 then
            val = 125
        elseif n == 2 then
            val = 200
        elseif n >= 3 then
            val = 250
        end
        if str == "rF" and (branch_soon("Zot") or branch_soon("Geh")) then
            val = val * 2.5
        elseif str == "rC" then
            if branch_soon("Coc") then
                val = val * 2.5
            elseif branch_soon("Slime") then
                val = val * 1.5
            end
        end
        return val
    elseif str == "rElec" then
        return 75
    elseif str == "rPois" then
        return easy_runes() < 2 and 225 or 75
    elseif str == "rN" then
        return 25 * min(n, 3)
    elseif str == "Will" then
        local branch_factor = branch_soon("Vaults") and 1.5 or 1
        return min(100 * branch_factor * n, 300 * branch_factor)
    elseif str == "rCorr" then
        return branch_soon("Slime") and 1200 or 50
    elseif str == "SInv" then
        return 200
    elseif str == "Fly" then
        return 200
    elseif str == "Faith" then
        -- We don't use invocations enough for these gods to care about Faith.
        if you.god() == "Cheibriados"
                or you.god() == "Beogh"
                or you.god() == "Qazlal"
                or you.god() == "Hepliaklqana" then
        -- These gods gain little from Faith.
        elseif you.god() == "Ru" or you.god() == "Xom" then
            return 0
        -- Otherwise, we like Faith a lot.
        else
            return 1000
        end
    elseif str == "Spirit" then
        return god_uses_mp() and -150 or 100
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
    elseif str == "Repulsion" then
        return 200
    -- Begin properties we always assign a nonpositive value.
    elseif str == "Harm" then
        return -500
    elseif str == "Ponderous" then
        return -300
    elseif str == "-Tele" then
        return you.race() == "Formicid" and 0 or -10000
    end

    return 0
end

function max_property_value(str, d)
    if d <= 0 then
        return 0
    end

    local val = 0
    local ires = intrinsic_property(str)
    if str == "rF" or str == "rC" then
        if d == 1 then
            val = 125
        elseif d == 2 then
            val = 200
        elseif d == 3 then
            val = 250
        end

        if str == "rF" then
            val = val * 2.5
        elseif str == "rC" then
            if planning_cocytus then
                val = val * 2.5
            elseif planning_slime then
                val = val * 1.5
            end
        end
        return val
    elseif str == "rElec" then
        return ires < 1 and 75 or 0
    elseif str == "rPois" then
        return ires < 1 and (easy_runes() < 2 and 225 or 75) or 0
    elseif str == "rN" then
        return ires < 3 and 25 * d or 0
    elseif str == "Will" then
        local branch_factor = planning_vaults and 1.5 or 1
        return min(100 * branch_factor * d, 300 * branch_factor)
    elseif str == "rCorr" then
        return ires < 1 and (planning_slime and 1200 or 50) or 0
    elseif str == "SInv" then
        return ires < 1 and 200 or 0
    elseif str == "Fly" then
        return ires < 1 and 200 or 0
    elseif str == "Faith" then
        if you.god() == "Cheibriados"
                or you.god() == "Beogh"
                or you.god() == "Qazlal"
                or you.god() == "Hepliaklqana" then
            return -10000
        elseif you.god() == "Ru" or you.god() == "Xom" then
            return 0
        else
            return 1000
        end
    elseif str == "Spirit" then
        return ires < 1
            and (not (god_uses_mp() and future_gods_use_mp)) and 0
                or 100
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
    elseif str == "Repulsion" then
        return 100
    end

    return 0
end

function min_property_value(str, d)
    if d < 0 then
        if str == "rF" then
            return -450
        elseif str == "rC" then
            if planning_cocytus then
                return -450
            elseif planning_slime then
                return -225
            end

            return -150
        elseif str == "Will" then
            return -75 * d
        end
    -- Begin properties that are always bad.
    elseif d > 0 then
        if str == "Harm" then
            return -500
        elseif str == "Ponderous" then
            return -300
        elseif str == "-Tele" then
            return you.race() == "Formicid" and 0 or -10000
        end
    end

    return 0
end

function property_value(str, it, cur, it2)
    if str == "^Fragile" then
        local bad_for_hydra = it
            and it.class(true) == "weapon"
            and you.xl() < 18
            and hydra_weapon_value(it) < 0
        return bad_for_hydra and -500 or 0, 0
    end

    local d = item_property(str, it)
    if d == 0 then
        return 0, 0
    end

    if cur then
        local c = player_property(str, it2)
        local diff = absolute_property_value(str, c + d)
            - absolute_property_value(str, c)
        return diff, diff
    else
        return min_property_value(str, d), max_property_value(str, d)
    end
end

function linear_property_value(str)
    local skill = weapon_skill()
    dex_weapon = skill == "Long Blades"
        or skill == "Short Blades"
        or skill == "Ranged Weapons"
    if str == "Regen" then
        return 200
    elseif str == "Slay" or str == "AC" or str == "EV" then
        return 50
    elseif str == "SH" then
        return 40
    elseif str == "Str" then
        return dex_weapon and 10 or 35
    elseif str == "Dex" then
        return dex_weapon and 55 or 15
    -- Begin negative properties.
    elseif str == "*Tele" then
        return you.race() == "Formicid" and 0 or -300
    elseif str == "*Rage" then
        return (intrinsic_undead() or you.race() == "Formicid")
            and 0 or -300
    elseif str == "*Slow" then
        return you.race() == "Formicid" and 0 or -100
    elseif str == "*Corrode" then
        return -100
    end

    return 0
end

-- Properties that don't have a linear progression of value at different
-- levels. The Str/Dex/Int in nonlinear_property can only recieve negative
-- utility, which happens when they are reduced to dangerous levels.
local nonlinear_properties = { "Str", "Dex", "Int", "rF", "rC", "rElec", "rPois",
    "rN", "Will", "rCorr", "SInv", "Fly", "Faith", "Spirit", "Acrobat",
    "Reflect", "Repulsion", "-Tele", "Ponderous", "Harm", "^Fragile" }
-- These properties always provide the same benefit (or detriment) with each
-- point/pip/instance of the property.
local linear_properties = { "Str", "Dex", "Slay", "AC", "EV", "SH", "Regen",
    "*Slow", "*Corrode", "*Tele", "*Rage" }

function total_property_value(it, cur, it2)
    local val = 0
    for _, str in ipairs(linear_properties) do
        val = val + item_property(str, it) * linear_property_value(str)
    end

    local val1, val2 = val, val
    if not only_linear_properties then
        for _, str in ipairs(nonlinear_properties) do
            local a, b = property_value(str, it, cur, it2)
            val1 = val1 + a
            val2 = val2 + b
        end
    end
    return val1, val2
end

function property_vec(it)
    local vec = {}
    for _, str in ipairs(nonlinear_properties) do
        local a, b = property_value(str, it)
        table.insert(vec, b > 0 and b or a)
    end
    return vec
end
