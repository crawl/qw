-------------------------------------
-- equipment valuation and autopickup

-- We assign a numerical value to all armour/weapon/jewellery, which
-- is used both for autopickup (so it has to work for unIDed items) and
-- for equipment selection. A negative value means we prefer an empty slot.

-- The valuation functions either return a pair of numbers - minimum
-- minimum and maximum potential value - or the current value. Here
-- value should be viewed as utility relative to not wearing anything in
-- that slot. For the current value calculation, we can specify an equipped
-- item and try to simulate not wearing it (for resist values).

-- We pick up an item if its max value is greater than our currently equipped
-- item's min value. We swap to an item if it has a greater cur value.

-- if cur, return the current value instead of minmax
-- if it2, pretend we aren't equipping it2
-- if sit = "hydra", assume we are fighting a hydra at lowish XL
--        = "extended", assume we are in (or about to enter) extended branches
--        if planning to convert to TSO, we need this weapon to be TSO-friendly
--        = "bless", assume we want to bless the weapon with TSO eventually
function equip_value(it, cur, it2, sit)
    if not it then
        return 0, 0
    end
    local class = it.class(true)
    if class == "armour" then
        return armour_value(it, cur, it2)
    elseif class == "weapon" then
        return weapon_value(it, cur, it2, sit)
    elseif class == "jewellery" then
        if equip_slot(it) == "Amulet" then
            return amulet_value(it, cur, it2)
        else
            return ring_value(it, cur, it2)
        end
    end
    return -1, -1
end

-- Returns the amount of an artprop granted by an item.
function item_resist(str, it)
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

-- Returns the player's intrinsic level of an artprop string.
function intrinsic_resist(str)
    if str == "rF" then
        return you.mutation("fire resistance")
    elseif str == "rC" then
        return you.mutation("cold resistance")
    elseif str == "rElec" then
        return you.mutation("electricity resistance")
    elseif str == "rPois" then
        if intrinsic_rpois() or you.mutation("poison resistance") > 0 then
            return 1
        else
            return 0
        end
    elseif str == "rN" then
        local val = you.mutation("negative energy resistance")
        if you.god() == "the Shining One" then
            val = val + math.floor(you.piety_rank() / 3)
        end
        return val
    elseif str == "Will" then
        return you.mutation("strong-willed") + (you.god() == "Trog" and 1 or 0)
    elseif str == "rCorr" then
        return 0
    elseif str == "SInv" then
        if intrinsic_sinv() or you.mutation("see invisible") > 0 then
            return 1
        else
            return 0
        end
    elseif str == "Fly" then
        return intrinsic_flight() and 1 or 0
    elseif str == "Spirit" then
        return you.race() == "Vine Stalker" and 1 or 0
    end

    return 0
end

-- Returns the current level of "resistance" to an artprop string. If an
-- item is provided, assume the item is equipped and try to pretend that
-- it is unequipped. Does not include some temporary effects.
function player_resist(str, it)
    local it_res = it and it.equipped and item_resist(str, it) or 0
    local stat
    if str == "Str" then
        stat, _ = you.strength()
        return stat - it_res
    elseif str == "Dex" then
        stat, _ = you.dexterity()
        return stat - it_res
    elseif str == "Int" then
        stat, _ = you.intelligence()
        return stat - it_res
    end
    local other_res = intrinsic_resist(str)
    for it2 in inventory() do
        if it2.equipped and slot(it2) ~= slot(it) then
            other_res = other_res + item_resist(str, it2)
        end
    end
    if str == "rF" or str == "rC" or str == "rN" or str == "Will" then
        return other_res
    else
        return other_res > 0 and 1 or 0
    end
end

function equip_slot(it)
    local class = it.class(true)
    if class == "armour" then
        return good_slots[it.subtype()]
    elseif class == "weapon" then
        return "Weapon"
    elseif class == "jewellery" then
        local sub = it.subtype()
        if sub and sub:find("amulet")
           or not sub and it.name():find("amulet") then
            return "Amulet"
        else
            return "Ring" -- not the actual slot name
        end
    end
    return
end

-- The current utility of having a given amount of an artprop.
function absolute_resist_value(str, n)
    if str == "Str" or str == "Int" or str == "Dex" then
        if n > 4 then
            return 0 -- handled by linear_resist_value()
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
        if str == "rF" then
            if branch_soon("Zot") then
                val = val * 2.5
            elseif branch_soon("Geh") then
                val = val * 1.5
            end
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
        -- We either don't use invocations much for these gods
        if you.god() == "Cheibriados"
                or you.god() == "Beogh"
                or you.god() == "Qazlal"
                or you.god() == "Hepliaklqana"
                or you.god() ~= "Ru"
                or you.god() ~= "Xom" then
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
    elseif str == "Fragile" then
        return -10000
    elseif str == "-Tele" then
        return you.race() == "Formicid" and 0 or -10000
    end
    return 0
end

function max_resist_value(str, d)
    if d <= 0 then
        return 0
    end

    local val = 0
    local ires = intrinsic_resist(str)
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
                or you.god() == "Hepliaklqana"
                or you.god() ~= "Ru"
                or you.god() ~= "Xom" then
            return 0
        else
            return 1000
        end
    elseif str == "Spirit" then
        return ires < 1 and not god_uses_mp() and 100 or 0
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
    elseif str == "Repulsion" then
        return 200
    end

    return 0
end

function min_resist_value(str, d)
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
            return 75 * d
        end
    -- Begin properties that are always bad.
    elseif d > 0 then
        if str == "Harm" then
            return -500
        elseif str == "Ponderous" then
            return -300
        elseif str == "Fragile" then
            return -10000
        elseif str == "-Tele" then
            return you.race() == "Formicid" and 0 or -10000
        end
    end

    return 0
end

function resist_value(str, it, cur, it2)
    local d = item_resist(str, it)
    if d == 0 then
        return 0, 0
    end
    if cur then
        local c = player_resist(str, it2)
        local diff = absolute_resist_value(str, c + d)
            - absolute_resist_value(str, c)
        return diff, diff
    else
        return min_resist_value(str, d), max_resist_value(str, d)
    end
end

function linear_resist_value(str)
    if str == "Regen" then
        return 100
    elseif str == "Slay" or str == "AC" or str == "EV" then
        return 50
    elseif str == "SH" then
        return 40
    elseif str == "Str" then
        return 30
    elseif str == "Dex" then
        return 20
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

-- Resistances and properties that don't have a linear progression of value at
-- different levels. The Str/Dex/Int in nonlinear_resists can only recieve
-- negative utility, which happens when they are reduced to dangerous levels.
local nonlinear_resists = { "Str", "Dex", "Int", "rF", "rC", "rElec", "rPois",
    "rN", "Will", "rCorr", "SInv", "Fly", "Faith", "Spirit", "Acrobat",
    "Reflect", "Repulsion", "-Tele", "Ponderous", "Harm", "Fragile" }
-- These properties always provide the same benefit (or detriment) with each
-- point/pip/instance of the property.
local linear_resists = { "Str", "Dex", "Slay", "AC", "EV", "SH", "Regen",
    "*Slow", "*Corrode", "*Tele", "*Rage" }

function total_resist_value(it, cur, it2)
    local val = 0
    for _, str in ipairs(linear_resists) do
        val = val + item_resist(str, it) * linear_resist_value(str)
    end

    local val1, val2 = val, val
    if not only_linear_resists then
        for _, str in ipairs(nonlinear_resists) do
            local a, b = resist_value(str, it, cur, it2)
            val1 = val1 + a
            val2 = val2 + b
        end
    end
    return val1, val2
end

function resist_vec(it)
    local vec = { }
    for _, str in ipairs(nonlinear_resists) do
        local a, b = resist_value(str, it)
        table.insert(vec, b > 0 and b or a)
    end
    return vec
end

function base_equip_value(it)
    only_linear_resists = true
    local val1, val2 = equip_value(it)
    only_linear_resists = false
    return val1, val2
end

-- Is the first item going to be worse than the second item no matter what
-- other resists we have?
function resist_dominated(it, it2)
    local bmin, bmax = base_equip_value(it)
    local bmin2, bmax2 = base_equip_value(it2)
    local diff = bmin2 - bmax
    if diff < 0 then
        return false
    end

    local vec = resist_vec(it)
    local vec2 = resist_vec(it2)
    for i = 1, #vec do
        if vec[i] > vec2[i] then
            diff = diff - (vec[i] - vec2[i])
        end
    end
    return diff >= 0
end

function easy_runes()
    local branches = {"Swamp", "Snake", "Shoals", "Spider"}
    local count = 0
    for _, br in ipairs(branches) do
        if have_branch_runes(br) then
            count = count + 1
        end
    end
    return count
end

-- A list of armour slots, this is used to normalize names for them and also to
-- iterate over the slots
good_slots = {cloak="Cloak", helmet="Helmet", gloves="Gloves", boots="Boots",
    body="Body Armour", shield="Shield"}

function armour_value(it, cur, it2)
    local name = it.name()
    local value = 0
    local val1, val2 = total_resist_value(it, cur, it2)
    local ego = it.ego()
    if it.artefact then
        if not it.fully_identified then -- could be good or bad
            val2 = val2 + 400
            val1 = val1 + (cur and 400 or -400)
        end

        -- Unrands
        if name:find("hauberk") then
            return -1, -1
        end
        if it.name():find("Mad Mage's Maulers") then
            if god_uses_mp() then
                return -1, -1
            else
                value = value + 200
            end
        elseif it.name():find("lightning scales") then
            if you.god() == "Cheibriados" then
                return -1, -1
            else
                value = value + 100
            end
        end
    elseif name:find("runed") or name:find("glowing") or name:find("dyed")
            or name:find("embroidered") or name:find("shiny") then
        val2 = val2 + 400
        val1 = val1 + (cur and 400 or -200)
    end

    value = value + 50 * expected_armour_multiplier() * it.ac
    if it.plus then
        value = value + 50 * it.plus
    end
    st, _ = it.subtype()
    if good_slots[st] == "Shield" then
        if it.encumbrance == 0 then
            if not want_buckler() then
                return -1, -1
            end
        elseif (not want_shield()) and (have_two_hander()
                or you.base_skill("Shields") == 0) then
            return -1, -1
        end
    end
    -- name always starts with {boots armour} here
    -- ^ is no longer true I think?
    if good_slots[st] == "Boots" then
        local want_barding = you.race() == "Palentonga" or you.race() == "Naga"
        local is_barding = name:find("barding") or name:find("lightning scales")
        if want_barding and not is_barding
                or not want_barding and is_barding then
            return -1, -1
        end
    end
    if good_slots[st] == "Body Armour" then
        if unfitting_armour() then
            value = value - 25 * it.ac
        end
        evp = it.encumbrance
        ap = armour_plan()
        if ap == "heavy" or ap == "large" then
            if evp >= 20 then
                value = value - 100
            elseif name:find("pearl dragon") then
                value = value + 100
            end
        elseif ap == "dodgy" then
            if evp > 11 then
                return -1, -1
            elseif evp > 7 then
                value = value - 100
            end
        else
            if evp > 7 then
                return -1, -1
            elseif evp > 4 then
                value = value - 100
            end
        end
    end
    return value + val1, value + val2
end

function weapon_value(it, cur, it2, sit)
    if it.class(true) ~= "weapon" then
        return -1, -1
    end

    local hydra_swap = sit == "hydra"
    local extended = sit == "extended"
    local tso = you.god() == "the Shining One"
        or planning_undead_demon_branches and planning_tso
        or you.god() == "Elyvilon"
        or you.god() == "Zin"
        or you.god() == "No God" and might_be_good
    local name = it.name()
    local value = 1000
    local weap = items.equipped_at("Weapon")
    -- The evaluating weapon doesn't match our desired skill...
    if it.weap_skill ~= wskill()
            -- ...and our current weapon already matches our desired skill or
            -- we use UC or the evaluating weapon is not a melee weapon
            and (weap and weap.weap_skill == wskill()
                or wskill() == "Unarmed Combat"
                or it.weap_skill == "Ranged Weapons")
            -- ...and we either don't need a hydra swap weapon or the
            -- evaluating weapon isn't a hydra swap weapon for our desired
            -- skill.
            and (not hydra_swap
                or not (it.weap_skill == "Maces & Flails"
                            and wskill() == "Axes"
                        or it.weap_skill == "Short Blades"
                            and wskill() == "Long Blades")) then
        return -1, -1
    end

    if it.hands == 2 and want_buckler() then
        return -1, -1
    end

    if sit == "bless" then
        local val1, val2 = 0, 0
        if it.artefact then
            return -1, -1
        elseif name:find("runed") or name:find("glowing")
                     or name:find("enchanted")
                     or it.ego() and not it.fully_identified then
            val2 = val2 + 150
            val1 = val1 + (cur and 150 or -150)
        end
        if it.plus then
            value = value + 30 * it.plus
        end
        delay_estimate = min(7, math.floor(it.delay / 2))
        if it.weap_skill == "Short Blades" and delay_estimate > 5 then
            delay_estimate = 5
        end
        value = value + 1200 * it.damage / delay_estimate
        return value + val1, value + val2
    end

    if tso and name:find("demon") and not name:find("eudemon") then
        return -1, -1
    end

    if (intrinsic_evil() or you.god() == "Yredelemnul")
            and name:find("holy") then
        return -1, -1
    end

    if name:find("obsidian axe") then
        if tso then
            return -1, -1
        -- This is much less good when it can't make friendly demons.
        elseif you.mutation("hated by all") or you.god() == "Okawaru" then
            value = value - 200
        -- XXX: De-value this on certain levels or give qw better strats
        -- while mesmerized.
        else
            value = value + 200
        end
    end

    local val1, val2 = total_resist_value(it, cur, it2)
    if it.artefact and not it.fully_identified
            or name:find("runed")
            or name:find("glowing") then
        val2 = val2 + 500
        val1 = val1 + (cur and 500 or -250)
    end

    if hydra_swap then
        local hydra_quality = hydra_weapon_status(it)
        if hydra_quality == -1 then
            return -1, -1
        elseif hydra_quality == 1 then
            value = value + 500
        end
    end

    local ego = it.ego()
    if ego then -- names are mostly in weapon_brands_verbose[]
        if ego == "distortion" then
            return -1, -1
        elseif ego == "holy wrath" then
            if intrinsic_evil() or you.god() == "Yredelemnul" then
                return -1, -1
            end

            if extended then
                value = value + 500
            end
        elseif ego == "vampirism" then
            if tso then
                return -1, -1
            end

            if extended then
                value = value - 400
            end

             -- This is what we want.
            value = value + 500
        elseif ego == "speed" then
            if you.god() == "Cheibriados" then
                return -1, -1
            end

            -- This is good too
            value = value + 300
        elseif ego == "spectralizing" then
            value = value + 200
        elseif ego == "electrocution" then
            value = value + 150
        elseif ego == "draining" then
            if tso then
                return -1, -1
            end

            if not extended then
                value = value + 75
            end
        elseif ego == "flaming" or ego == "freezing" or ego == "vorpal" then
            value = value + 75
        elseif ego == "protection" then
            value = value + 50
        elseif ego == "venom" and not extended then
            value = value + 50
        elseif ego == "antimagic" then
            if you.race() == "Vine Stalker" then
                value = value - 300
            else
                value = value + 75
            end
        elseif ego == "pain" and (tso or you.god() == "Trog") then
            return -1, -1
        elseif ego == "chaos" and (tso or you.god() == "Cheibriados") then
            return -1, -1
        end
    end

    if it.plus then
        value = value + 30 * it.plus
    end

    delay_estimate = min(7, math.floor(it.delay / 2))
    if it.weap_skill == "Short Blades" and delay_estimate > 5 then
        delay_estimate = 5
    end
    -- We might be delayed by a shield or not yet at min delay, so add a little.
    delay_estimate = delay_estimate + 1
    value = value + 1200 * it.damage / delay_estimate

    -- Subtract a bit for very slow weapons because of how much skill they
    -- require to reach min delay.
    if it.delay > 17 then
        value = value - 120 * (it.delay - 17)
    end

    if it.weap_skill ~= wskill() then
        value = value / 10
        val1 = val1 / 10
        val2 = val2 / 10
    end

    return value + val1, value + val2
end

function amulet_value(it, cur, it2)
    local name = it.name()
    if name:find("macabre finger necklace") then
        return -1, -1
    end

    if not it.fully_identified then
        if cur then
            return 800, 800
        else
            return -1, 1000
        end
    end

    local val1, val2 = total_resist_value(it, cur, it2)
    return val1, val2
end

function ring_value(it, cur, it2)
    if not it.fully_identified then
        if cur then
            return 5000, 5000
        else
            return -1, 5000
        end
    end

    local val1, val2 = total_resist_value(it, cur, it2)
    return val1, val2
end

function count_charges(wand_type, ignore_it)
    local count = 0
    for it in inventory() do
        if it.class(true) == "wand"
                and (not ignore_it or slot(it) ~= slot(ignore_it))
                and it.subtype() == wand_type then
            count = count + it.plus
        end
    end
    return count
end

function want_wand(it)
    if you.mutation("inability to use devices") > 0 then
        return false
    end

    local sub = it.subtype()
    if sub and sub == "digging" then
        return true
    end
end

function want_potion(it)
    sub = it.subtype()
    if sub == nil then
        return true
    end

    wanted = { "curing", "heal wounds", "haste", "resistance",
        "experience", "might", "mutation", "cancellation" }

    if planning_god_uses_mp then
        table.insert(wanted, "magic")
    end

    if planning_undead_demon_branches then
        table.insert(wanted, "lignification")
        table.insert(wanted, "attraction")
    end

    return util.contains(wanted, sub)
end

function want_scroll(it)
    sub = it.subtype()
    if sub == nil then
        return true
    end

    wanted = { "acquirement", "brand weapon", "enchant armour",
        "enchant weapon", "identify", "teleportation"}

    if will_zig then
        table.insert(wanted, "blinking")
        table.insert(wanted, "fog")
    end

    return util.contains(wanted, sub)
end

-- This doesn't handle rings correctly at the moment, but right now we are
-- only using this for weapons anyway.
-- Also maybe this should check resist_dominated too?
function item_is_sit_dominated(it, sit)
    local slotname = equip_slot(it)
    local minv, maxv = equip_value(it, nil, nil, sit)
    if maxv <= 0 then
        return true
    end
    for it2 in inventory() do
        if equip_slot(it2) == slotname and slot(it2) ~= slot(it) then
            local minv2, maxv2 = weapon_value(it2, nil, nil, sit)
            if minv2 >= maxv and not
                 (slotname == "Weapon" and you.base_skill("Shields") > 0
                    and it.hands == 1 and it2.hands == 2) then
                return true
            end
        end
    end
    return false
end

function item_is_dominated(it)
    local slotname = equip_slot(it)
    if slotname == "Weapon" and you.xl() < 18
            and not item_is_sit_dominated(it, "hydra") then
        return false
    elseif planning_undead_demon_branches
            and slotname == "Weapon"
            and not item_is_sit_dominated(it, "extended") then
        return false
    elseif slotname == "Weapon"
                and (you.god() == "the Shining One"
                        and not you.one_time_ability_used()
                    or planning_tso)
                and not item_is_sit_dominated(it, "bless") then
        return false
    end
    local minv, maxv = equip_value(it)
    if maxv <= 0 then
        return true
    end
    local num_slots = 1
    if slotname == "Ring" then
        num_slots = max_rings()
    end
    for it2 in inventory() do
        if equip_slot(it2) == slotname and slot(it2) ~= slot(it) then
            local minv2, maxv2 = equip_value(it2)
            if minv2 >= maxv
                    or minv2 >= minv
                    and maxv2 >= maxv
                    and resist_dominated(it, it2) then
                num_slots = num_slots - 1
                if num_slots == 0 then
                    return true
                end
            end
        end
    end
    return false
end

function should_drop(it)
    return item_is_dominated(it)
end

-- Assumes old_it is equipped.
function should_upgrade(it, old_it, sit)
    if not old_it then
        return should_equip(it, sit)
    end

    if not it.fully_identified and not should_drop(it) then
        if equip_slot(it) == "Weapon" and it.weap_skill ~= wskill() then
            return true
        end

        -- Don't like to swap Faith.
        return item_resist("Faith", old_it) == 0
    end

    return equip_value(it, true, old_it, sit)
        > equip_value(old_it, true, old_it, sit)
end

-- Assumes it is not equipped and an empty slot is available.
function should_equip(it, sit)
    return equip_value(it, true, nil, sit) > 0
end

-- Assumes it is equipped.
function should_remove(it)
    return equip_value(it, true, it) <= 0
end

function want_missile(it)
    local st = it.subtype()
    if st == "javelin"
            or st == "large rock"
                and (you.race() == "Troll" or you.race() == "Ogre")
            or st == "boomerang"
                and count_item("missile", "javelin") < 20 then
        return true
    end

    return false
end

function want_miscellaneous(it)
    local st = it.subtype()
    if st == "figurine of a ziggurat" then
        return planning_zig
    end

    return false
end


function autopickup(it, name)
    if not initialized then
        return
    end

    if name:find("rune of Zot")
            or (gameplan_status == "Orb" and name:find("Orb of Zot")) then
        return true
    end

    if it.is_useless then
        return false
    end
    local class = it.class(true)
    old_value = 0
    new_value = 0
    ring = false
    if class == "armour" or class == "weapon" or class == "jewellery" then
        return not item_is_dominated(it)
    elseif class == "gold" then
        return true
    elseif class == "potion" then
        return want_potion(it)
    elseif class == "scroll" then
        return want_scroll(it)
    elseif class == "wand" then
        return want_wand(it)
    elseif class == "missile" then
        return want_missile(it)
    elseif class == "misc" then
        return want_miscellaneous(it)
    else
        return false
    end
end

clear_autopickup_funcs()
add_autopickup_func(autopickup)

-----------------------------------------
-- item functions

function inventory()
    return iter.invent_iterator:new(items.inventory())
end

function at_feet()
    return iter.invent_iterator:new(you.floor_items())
end

function free_inventory_slots()
    local slots = 52
    for _ in inventory() do
        slots = slots - 1
    end
    return slots
end

function slot(x)
    if type(x) == "userdata" then
        return x.slot
    elseif type(x) == "string" then
        return items.letter_to_index(x)
    else
        return x
    end
end

function letter(x)
    if type(x) == "userdata" then
        return items.index_to_letter(x.slot)
    elseif type(x) == "number" then
        return items.index_to_letter(x)
    else
        return x
    end
end

function item(x)
    if type(x) == "number" then
        return items.inslot(x)
    elseif type(x) == "string" then
        return items.inslot(items.letter_to_index(x))
    else
        return x
    end
end

function ring_list()
    rings = {}
    if you.race() ~= "Octopode" then
        if items.equipped_at("Left Ring") then
            table.insert(rings, items.equipped_at("Left Ring"))
        end
        if items.equipped_at("Right Ring") then
            table.insert(rings, items.equipped_at("Right Ring"))
        end
        return rings
    end
    for it in inventory() do
        if it.equipped and equip_slot(it) == "Ring" then
            table.insert(rings, it)
        end
    end
    return rings
end

function empty_ring_slots()
    return max_rings() - table.getn(ring_list())
end

function have_two_hander()
    for it in inventory() do
        if it.class(true) == "weapon" and it.weap_skill == wskill()
             and it.hands == 2 then
            return true
        end
    end
    return false
end

function count_item(cls, name)
    local count = 0
    for it in inventory() do
        if it.class(true) == cls and it.name():find(name) then
            count = count + it.quantity
        end
    end
    return count
end

function find_item(cls, name)
    if cls == "wand" then return find_wand(name) end
    for it in inventory() do
        if it.class(true) == cls and it.name():find(name) then
            return items.index_to_letter(it.slot)
        end
    end
end

function have_item(cls, name)
    for it in inventory() do
        if it.class(true) == cls and it.name():find(name) then
            return true
        end
    end
end

function best_missile()
    local missiles = {"boomerang", "javelin", "large rock"}
    local best_rating = 0
    local best_item = nil
    local it, i, name
    for it in inventory() do
        local rating = 0
        if it.class(true) == "missile" then
            for i, name in ipairs(missiles) do
                if it.name():find(name) then
                    rating = i
                    if it.ego() then
                        rating = rating + 0.5
                    end
                    if rating > best_rating then
                        best_rating = rating
                        best_item = it
                    end
                end
            end
        end
    end
    return best_rating, best_item
end

function find_wand(name)
    for it in inventory() do
        if it.class(true) == "wand" and it.name():find(name) then
            return items.index_to_letter(it.slot)
        end
    end
end

function count_item(cls, name)
    f = find_item(cls, name)
    if f then
        return item(f).quantity
    end
    return 0
end

function have_reaching()
    local wp = items.equipped_at("weapon")
    return wp and wp.reach_range == 2 and not wp.is_melded
end

function body_size()
    if you.race() == "Kobold" then
        return -1
    elseif you.race() == "Spriggan" or you.race() == "Felid" then
        return -2
    elseif you.race() == "Troll" or you.race() == "Ogre"
            or you.race() == "Naga" or you.race() == "Palentonga" then
        return 1
    else
        return 0
    end
end

function shield_skill_utility()
    local shield = items.equipped_at("Shield")
    if not shield then
        return 0
    end

    local shield_factor = you.mutation("four strong arms") > 0 and -2
        or 2 * body_size()
    local shield_penalty = 2 * shield.encumbrance * shield.encumbrance
        * (27 - you.base_skill("Shields"))
        / (5 * (20 - 3 * shield_factor)) / 27
    return 0.25 + 0.5 * shield_penalty
end

function min_delay_skill()
    weap = items.equipped_at("Weapon")
    if not weap then
        return 27
    end
    if weap.weap_skill ~= wskill() then
        return last_min_delay_skill
    end
    if weap.weap_skill == "Short Blades" and weap.delay == 12 then
        last_min_delay_skill = 14
        return 14
    end
    local mindelay = math.floor(weap.delay / 2)
    if mindelay > 7 then
        mindelay = 7
    end
    last_min_delay_skill = 2 * (weap.delay - mindelay)
    return last_min_delay_skill
end

function at_min_delay()
    return you.base_skill(wskill()) >= min(27,
        min_delay_skill() + (you.god() == "Ru" and 1 or 0))
end

function cleaving()
    weap = items.equipped_at("Weapon")
    if weap and weap.weap_skill == "Axes" then
        return true
    end
    return false
end

function armour_ac()
    arm = items.equipped_at("Body Armour")
    if arm then
        return arm.ac
    else
        return 0
    end
end

function base_ac()
    local total = 0
    for _, slotname in pairs(good_slots) do
        if slotname ~= "Shield" then
            it = items.equipped_at(slotname)
            if it then
                total = total + it.ac
            end
        end
    end
    return total
end

function armour_evp()
    arm = items.equipped_at("Body Armour")
    if arm then
        return arm.encumbrance
    else
        return 0
    end
end

function can_swap(equip_slot)
    local it = items.equipped_at(equip_slot)
    if it and (it.cursed
                or it.name():find("obsidian axe")
                    and you.status("mesmerised")) then
        return false
    end

    local feat = view.feature_at(0, 0)
    if you.flying()
            and (feat == "deep_water" and not intrinsic_amphibious()
                or feat == "lava" and not intrinsic_flight())
            and player_resist("Fly", items.equipped_at("Weapon")) == 0 then
        return false
    end

    return true
end

-- plural form, e.g. "Scrolls"
-- or invoke with item_class="name_callback" and provide callback for name
function see_item(item_class, r, name_callback)
    for x = -r, r do
        for y = -r, r do
            -- crawl.mpr("(" .. x .. ", " .. y .. "): "
            --     .. view.feature_at(x, y) .."\r")
            local is = items.get_items_at(x, y)
            if (is ~= nil) and (#is > 0) and (you.see_cell(x, y)) then
                for ind, i in pairs(is) do
                    local iname = i.name()
                    if (i:class(true) == item_class)
                            or ((item_class == "name_callback")
                                and name_callback(iname)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function is_melee_weapon(it)
    return it
        and it.class(true) == "weapon"
        and it.weap_skill ~= "Ranged Weapons"
end
