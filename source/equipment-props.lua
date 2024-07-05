-------------------------------------
-- Equipment property evaluation.

-- Properties that don't have a linear progression of value at different
-- levels. The Str/Dex/Int in nonlinear_property can only recieve negative
-- utility, which happens when they are reduced to dangerous levels.
const.nonlinear_properties = { "Str", "Dex", "Int", "rF", "rC", "rElec",
    "rPois", "rN", "Will", "rCorr", "SInv", "Fly", "Faith", "Spirit",
    "Acrobat", "Reflect", "RMsl", "Clar", "-Tele", "Ponderous", "Harm",
    "^Fragile", "^Drain", "^Contam" }

const.no_swap_properties = { "^Fragile", "^Drain", "^Contam" }


-- These properties always provide the same benefit (or detriment) with each
-- point of the property.
const.linear_properties = { "Str", "Dex", "Slay", "AC", "EV", "SH", "Regen",
    "*Slow", "*Corrode", "*Tele", "*Rage" }

const.property_max_levels = {}
for _, prop in ipairs(const.nonlinear_properties) do
    local max_level
    if prop == "rF" or prop == "rC" or prop == "rN" then
        max_level = 3
    elseif not (prop == "Str"
            or prop == "Dex"
            or prop == "Int"
            or prop == "Will") then
        max_level = 1
    end
    const.property_max_levels[prop] = max_level
end

-- Returns the amount of an artprop granted by an item.
function item_property(prop, item)
    if not item then
        return 0
    end

    if item.artefact and item.artprops and item.artprops[prop] then
        return item.artprops[prop]
    else
        local name = item.name()
        local ego = item.ego()
        local subtype = item.subtype()
        if prop == "rF" then
            if name:find("fire dragon") then
                return 2
            elseif ego == "fire resistance"
                    or ego == "resistance"
                    or subtype == "ring of protection from fire"
                    or name:find("golden dragon")
                    or subtype == "ring of fire" then
                return 1
            elseif name:find("ice dragon") or subtype == "ring of ice" then
                return -1
            else
                return 0
            end
        elseif prop == "rC" then
            if name:find("ice dragon") then
                return 2
            elseif ego == "cold resistance" or ego == "resistance"
                     or subtype == "ring of protection from cold"
                     or name:find("golden dragon")
                     or subtype == "ring of ice" then
                return 1
            elseif name:find("fire dragon") or subtype == "ring of fire" then
                return -1
            else
                return 0
            end
        elseif prop == "rElec" then
            return name:find("storm dragon") and 1 or 0
        elseif prop == "rPois" then
            return (ego == "poison resistance"
                or subtype == "ring of poison resistance"
                or name:find("swamp dragon")
                or name:find("golden dragon")) and 1 or 0
        elseif prop == "rN" then
            return (ego == "positive energy"
                or subtype == "ring of positive energy"
                or name:find("pearl dragon")) and 1 or 0
        elseif prop == "Will" then
            return (ego == "willpower"
                or subtype == "ring of willpower"
                or name:find("quicksilver dragon")) and 1 or 0
        elseif prop == "rCorr" then
            return (subtype == "ring of resist corrosion"
                or name:find("acid dragon")) and 1 or 0
        elseif prop == "SInv" then
            return (ego == "see invisible"
                or subtype == "ring of see invisible") and 1 or 0
        elseif prop == "Fly" then
            return ego == "flying" and 1 or 0
        elseif prop == "Faith" then
            return subtype == "amulet of faith" and 1 or 0
        elseif prop == "Spirit" then
            return (ego == "spirit shield"
                    or subtype == "amulet of guardian spirit") and 1 or 0
        elseif prop == "Regen" then
             return (name:find("troll leather")
                     or subtype == "amulet of regeneration") and 1 or 0
        elseif prop == "Acrobat" then
             return subtype == "amulet of the acrobat" and 1 or 0
        elseif prop == "Reflect" then
             return (ego == "reflection" or subtype == "amulet of reflection")
                 and 1 or 0
        elseif prop == "*Dream" then
             return name:find("dreamshard necklace") and 1 or 0
        elseif prop == "RMsl" then
             return ego == "repulsion" and 1 or 0
        elseif prop == "Ponderous" then
             return ego == "ponderousness" and 1 or 0
        elseif prop == "Harm" then
             return ego == "harm" and 1 or 0
        elseif prop == "Str" then
            if subtype == "ring of strength" then
                return item.plus or 0
            elseif ego == "strength" then
                return 3
            end
        elseif prop == "Dex" then
            if subtype == "ring of dexterity" then
                return item.plus or 0
            elseif ego == "dexterity" then
                return 3
            end
        elseif prop == "Int" then
            if subtype == "ring of intelligence" then
                return item.plus or 0
            elseif ego == "intelligence" then
                return 3
            end
        elseif prop == "Slay" then
            return subtype == "ring of slaying" and item.plus or 0
        elseif prop == "AC" then
            if subtype == "ring of protection" then
                return item.plus or 0
            -- Wrong for weapons, but we scale things differently for weapons.
            elseif ego == "protection" then
                return 3
            elseif ego == "RevParry" then
                return 5
            end
        elseif prop == "EV" then
            return subtype == "ring of evasion"  and item.plus or 0
        elseif prop == "SH" then
            return subtype == "amulet of reflection" and 5 or 0
        end
    end

    return 0
end

-- The current utility of having a given level of an artprop.
function absolute_property_value(prop, level)
    if prop == "Str" or prop == "Int" or prop == "Dex" then
        if level > 4 then
            -- Handled by linear_property_value()
            return 0
        elseif level > 2 then
            return -100
        elseif level > 0 then
            return -250
        else
            return -10000
        end
    end

    if level == 0 then
        return 0
    end

    if branch_soon("Slime")
            and (prop == "rF"
                or prop == "rElec"
                or prop == "rPois"
                or prop == "rN"
                or prop == "SInv") then
        return 0
    end

    if prop == "rF" or prop == "rC" then
        local value
        -- The value of negative levels is a bit worse than the corresponding
        -- value of the corresponding positive level. This way we'll not value
        -- items that e.g. take us up one level of rC+ yet also down one level
        -- of rF- when we're at rF0 or less.
        if level <= -3 then
            value = -275
        elseif level == -2 then
            value = -225
        elseif level == -1 then
            value = -150
        elseif level == 1 then
            value = 125
        elseif level == 2 then
            value = 200
        else
            value = 250
        end

        if prop == "rF" and (branch_soon("Zot") or branch_soon("Geh")) then
            value = value * 2.5
        elseif prop == "rC" then
            if branch_soon("Coc") then
                value = value * 2.5
            elseif branch_soon("Slime") then
                value = value * 1.5
            end
        end

        return value
    elseif prop == "rElec" then
        return 75
    elseif prop == "rPois" then
        return easy_runes() < 2 and 225 or 75
    elseif prop == "rN" then
        return 25 * min(level, 3)
    elseif prop == "Will" then
        local branch_factor = branch_soon("Vaults") and 1.5 or 1
        return min(100 * branch_factor * level, 300 * branch_factor)
    elseif prop == "rCorr" then
        return branch_soon("Slime") and 1200 or 50
    elseif prop == "SInv" then
        return 200
    elseif prop == "Fly" then
        return 200
    elseif prop == "Faith" then
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
    elseif prop == "Spirit" then
        if you.race() == "Djinni" then
            return 0
        else
            return god_uses_mp() and -150 or 100
        end
    elseif prop == "Acrobat" then
        return 100
    elseif prop == "Reflect" then
        return 20
    elseif prop == "RMsl" then
        return 200
    elseif prop == "*Dream" then
        return 100
    elseif prop == "Clar" then
        return you.race() == "Mummy" and 100 or 20
    elseif prop == "Rampage" then
        return using_ranged_weapon() and -50 or 20
    -- Begin properties we always assign a nonpositive value.
    elseif prop == "Harm" then
        return -500
    elseif prop == "Ponderous" then
        return -300
    elseif prop == "-Tele" then
        return you.race() == "Formicid" and 0 or -10000
    end

    return 0
end

function max_property_value(prop, level)
    if level <= 0 then
        return 0
    end

    local ires = intrinsic_property(prop)
    if prop == "rF" or prop == "rC" then
        local value
        if level == 1 then
            value = 125
        elseif level == 2 then
            value = 200
        elseif level == 3 then
            value = 250
        end

        if prop == "rF" then
            value = value * 2.5
        elseif prop == "rC" then
            if qw.planning_cocytus then
                value = value * 2.5
            elseif qw.planning_slime then
                value = value * 1.5
            end
        end
        return value
    elseif prop == "rElec" then
        return ires < 1 and 75 or 0
    elseif prop == "rPois" then
        return ires < 1 and (easy_runes() < 2 and 225 or 75) or 0
    elseif prop == "rN" then
        return ires < 3 and 25 * level or 0
    elseif prop == "Will" then
        local branch_factor = qw.planning_vaults and 1.5 or 1
        return min(100 * branch_factor * level, 300 * branch_factor)
    elseif prop == "rCorr" then
        return ires < 1 and (qw.planning_slime and 1200 or 50) or 0
    elseif prop == "SInv" then
        return ires < 1 and 200 or 0
    elseif prop == "Fly" then
        return ires < 1 and 200 or 0
    elseif prop == "Faith" then
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
    elseif prop == "Spirit" then
        if ires >= 1
                or you.race() == "Djinni"
                or qw.planned_gods_all_use_mp then
            return 0
        else
            return 100
        end
    elseif prop == "Acrobat" then
        return 100
    elseif prop == "Reflect" then
        return 20
    elseif prop == "RMsl" then
        return 100
    elseif prop == "*Dream" then
        return 200
    elseif prop == "Clar" then
        return you.race() == "Mummy" and 100 or 20
    elseif prop == "Rampage" then
        return using_range_weapon() and 0 or 20
    elseif prop == "Harm" then
        return -500
    elseif prop == "Ponderous" then
        return -300
    elseif prop == "-Tele" then
        return you.race() == "Formicid" and 0 or -10000
    end

    return 0
end

function min_property_value(prop, level)
    if level < 0 then
        if prop == "rF" then
            return -450
        elseif prop == "rC" then
            if qw.planning_cocytus then
                return -450
            elseif qw.planning_slime then
                return -225
            end

            return -150
        elseif prop == "Will" then
            return -75 * level
        end
    elseif level > 0 then
        -- This can only have its effect once, so we want to carry around our
        -- best backup amulet.
        if prop == "*Dream" then
            return -10000
        -- Begin properties that are always bad.
        elseif prop == "Harm" then
            return -500
        elseif prop == "Ponderous" then
            return -300
        elseif prop == "-Tele" then
            return you.race() == "Formicid" and 0 or -10000
        end
    end

    return 0
end

function property_value(prop, item, cur, ignore_equip)
    local item_val = item_property(prop, item)
    if item_val == 0 then
        return 0, 0
    end

    if util.contains(const.no_swap_properties, prop) then
        local bad_for_hydra = item
            and equip_slot(item) == "weapon"
            and you.xl() < 18
            and hydra_weapon_value(item) < 0
        return bad_for_hydra and -500 or 0, 0
    end

    if cur then
        if not ignore_equip and item.equipped then
            local slot = equip_slot(item)
            ignore_equip = { [slot] = { item } }
        end

        local player_val = player_property(prop, ignore_equip)
        local diff = absolute_property_value(prop, player_val + item_val)
            - absolute_property_value(prop, player_val)
        return diff, diff
    else
        return min_property_value(prop, item_val),
            max_property_value(prop, item_val)
    end
end

function linear_property_value(prop)
    local skill = weapon_skill()
    dex_weapon = skill == "Long Blades"
        or skill == "Short Blades"
        or skill == "Ranged Weapons"
    if prop == "Regen" then
        return 200
    elseif prop == "Slay" or prop == "AC" or prop == "EV" then
        return 50
    elseif prop == "SH" then
        return 40
    elseif prop == "Str" then
        return dex_weapon and 10 or 35
    elseif prop == "Dex" then
        return dex_weapon and 55 or 15
    -- Begin negative properties.
    elseif prop == "*Tele" then
        return you.race() == "Formicid" and 0 or -300
    elseif prop == "*Rage" then
        return (intrinsic_undead() or you.race() == "Formicid")
            and 0 or -300
    elseif prop == "*Slow" then
        return you.race() == "Formicid" and 0 or -100
    elseif prop == "*Corrode" then
        return -100
    end

    return 0
end

function total_property_value(item, cur, ignore_equip, only_linear)
    local value = 0
    for _, prop in ipairs(const.linear_properties) do
        value = value + item_property(prop, item) * linear_property_value(prop)
    end

    if only_linear then
        return value, value
    end

    local min_value, max_value = value, value
    for _, prop in ipairs(const.nonlinear_properties) do
        local prop_min, prop_max = property_value(prop, item, cur,
            ignore_equip)
        min_value = min_value + prop_min
        max_value = max_value + prop_max
    end

    return min_value, max_value
end

function property_array(item)
    local array = {}
    for _, prop in ipairs(const.nonlinear_properties) do
        local min_value, max_value = property_value(prop, item)
        table.insert(array, max_value > 0 and max_value or min_value)
    end
    return array
end
