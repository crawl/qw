-------------------------------------
-- Equipment comparisons.

-- We assign a numerical value to all armour/weapon/jewellery, which
-- is used both for autopickup (so it has to work for unIDed items) and
-- for equipment selection. A negative value means we prefer an empty slot.

-- The valuation functions either return a pair of numbers - minimum
-- minimum and maximum potential value - or the current value. Here
-- value should be viewed as utility relative to not wearing anything in
-- that slot. For the current value calculation, we can specify an equipped
-- item and try to simulate not wearing it (for property values).

-- We pick up an item if its max value is greater than our currently equipped
-- item's min value. We swap to an item if it has a greater cur value.

-- if cur, return the current value instead of minmax
-- if it2, pretend we aren't equipping it2
-- if sit = "hydra", assume we are fighting a hydra at lowish XL
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

function base_equip_value(it)
    only_linear_properties = true
    local val1, val2 = equip_value(it)
    only_linear_properties = false
    return val1, val2
end

-- Is the first item going to be worse than the second item no matter what
-- other properties we have?
function property_dominated(it, it2)
    local bmin, bmax = base_equip_value(it)
    local bmin2, bmax2 = base_equip_value(it2)
    local diff = bmin2 - bmax
    if diff < 0 then
        return false
    end

    local vec = property_vec(it)
    local vec2 = property_vec(it2)
    for i = 1, #vec do
        if vec[i] > vec2[i] then
            diff = diff - (vec[i] - vec2[i])
        end
    end
    return diff >= 0
end

function armour_value(it, cur, it2)
    local name = it.name()
    local value = 0
    local val1, val2 = 0, 0
    if current_god_hates_item(it) then
        if cur then
            return -1, -1
        else
            val1 = -10000
        end
    elseif not cur and future_gods_hate_item(it) then
        val1 = -10000
    end

    local res_val1, res_val2 = total_property_value(it, cur, it2)
    val1 = val1 + res_val1
    val2 = val2 + res_val2

    local ego = it.ego()
    if it.artefact then
        if not it.fully_identified then -- could be good or bad
            val1 = val1 + (cur and 400 or -400)
            val2 = val2 + 400
        end

        -- Unrands
        if name:find("hauberk") then
            return -1, -1
        end

        if it.name():find("Mad Mage's Maulers") then
            if you.race() == "Djinni" or god_uses_mp() then
                if cur then
                    return -1, -1
                else
                    val1 = -10000
                end
            elseif not cur and future_gods_use_mp then
                val1 = -10000
            end

            value = value + 200
        elseif it.name():find("lightning scales") then
            value = value + 100
        end
    elseif name:find("runed") or name:find("glowing") or name:find("dyed")
            or name:find("embroidered") or name:find("shiny") then
        val1 = val1 + (cur and 400 or -200)
        val2 = val2 + 400
    end

    value = value + 50 * expected_armour_multiplier() * it.ac
    if it.plus then
        value = value + 50 * it.plus
    end
    local st = it.subtype()
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

    if good_slots[st] == "Boots" then
        local want_barding = you.race() == "Armataur" or you.race() == "Naga"
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

    val1 = val1 + value
    val2 = val2 + value
    return val1, val2
end

function weapon_value(it, cur, it2, sit)
    if it.class(true) ~= "weapon" then
        return -1, -1
    end

    local hydra_swap = sit == "hydra"
    local weap = get_weapon()
    local weap_skill = weapon_skill()
    -- The evaluating weapon doesn't match our desired skill...
    if it.weap_skill ~= weap_skill
            -- ...and our current weapon already matches our desired skill or
            -- we use UC...
            and (weap and weap.weap_skill == weap_skill
                or weap_skill == "Unarmed Combat")
            -- ...and we either don't need a hydra swap weapon or the
            -- evaluating weapon isn't a hydra swap weapon for our desired
            -- skill.
            and (not hydra_swap
                or not (it.weap_skill == "Maces & Flails"
                            and weap_skill == "Axes"
                        or it.weap_skill == "Short Blades"
                            and weap_skill == "Long Blades")) then
        return -1, -1
    end

    if it.hands == 2 and want_buckler() then
        return -1, -1
    end

    local name = it.name()
    local value = 1000
    local val1, val2 = 0, 0

    if sit == "bless" then
        if it.artefact then
            return -1, -1
        elseif name:find("runed")
                or name:find("glowing")
                or name:find("enchanted")
                or it.ego() and not it.fully_identified then
            val1 = val1 + (cur and 150 or -150)
            val2 = val2 + 150
        end

        if it.plus then
            value = value + 30 * it.plus
        end

        value = value + 1200 * it.damage / weapon_min_delay(it)
        return value + val1, value + val2
    end

    if current_god_hates_item(it) then
        if cur then
            return -1, -1
        else
            val1 = -10000
        end
    elseif not cur and future_gods_hate_item(it) then
        val1 = -10000
    end

    -- XXX: De-value this on certain levels or give qw better strats while
    -- mesmerised.
    if name:find("obsidian axe") then
        -- This is much less good when it can't make friendly demons.
        if you.mutation("hated by all") or you.god() == "Okawaru" then
            value = value - 200
        elseif future_okawaru then
            val1 = val1 + (cur and 200 or -200)
            val2 = val2 + 200
        else
            value = value + 200
        end
    elseif name:find("consecrated labrys") then
        value = value + 1000
    elseif name:find("storm bow") then
        value = value + 150
    elseif name:find("{damnation}") then
        value = value + 1000
    end

    local res_val1, res_val2 = total_property_value(it, cur, it2)
    val1 = val1 + res_val1
    val2 = val2 + res_val2

    if it.artefact and not it.fully_identified
            or name:find("runed")
            or name:find("glowing") then
        val1 = val1 + (cur and 500 or -250)
        val2 = val2 + 500
    end

    if hydra_swap then
        local hydra_value = hydra_weapon_value(it)
        if hydra_value == -1 then
            return -1, -1
        elseif hydra_value == 1 then
            value = value + 500
        end
    end

    local undead_demon = undead_or_demon_branch_soon()
    local ego = it.ego()
    if ego then -- names are mostly in weapon_brands_verbose[]
        if ego == "distortion" then
            return -1, -1
        elseif ego == "holy wrath" then
            -- We can never use this.
            if intrinsic_evil() then
                return -1, -1
            end

            if undead_demon then
                val1 = val1 + (cur and 500 or 0)
                val2 = val2 + 500
            -- This will eventaully be good on the Orb run.
            else
                val2 = val2 + 500
            end
        -- Not good against demons or undead, otherwise this is what we want.
        elseif ego == "vampirism" then
            -- It may be good at some point if we go to non undead-demon places
            -- before the Orb. XXX: Determine this from goals and adjust this
            -- value based on the result.
            if undead_demon then
                val2 = val2 + 500
            else
                val1 = val1 + (cur and 500 or 0)
                val2 = val2 + 500
            end
        elseif ego == "speed" then
            -- This is good too
            value = value + 300
        elseif ego == "spectralizing" then
            value = value + 400
        elseif ego == "draining" then
            -- XXX: Same issue as for vampirism above.
            if undead_demon then
                val2 = val2 + 75
            else
                val1 = val1 + (cur and 75 or 0)
                val2 = val2 + 75
            end
        elseif ego == "penetration" then
            value = value + 150
        elseif ego == "heavy" then
            value = value + 100
        elseif ego == "flaming"
                or ego == "freezing"
                or ego == "electrocution" then
            value = value + 75
        elseif ego == "protection" then
            value = value + 50
        elseif ego == "venom" and not undead_demon then
            -- XXX: Same issue as for vampirism above.
            if undead_demon then
                val2 = val2 + 50
            else
                val1 = val1 + (cur and 50 or 0)
                val2 = val2 + 50
            end
        elseif ego == "antimagic" then
            if you.race() ~= "Djinni" then
                local new_mmp = select(2, you.mp())
                -- Swapping to antimagic reduces our max MP by 2/3.
                if weap.ego() ~= "antimagic" then
                    new_mmp = math.floor(select(2, you.mp()) * 1 / 3)
                end
                if not enough_max_mp_for_god(new_mmp, you.god()) then
                    if cur then
                        return -1, -1
                    else
                        val1 = -10000
                    end
                elseif not cur and not future_gods_enough_max_mp(new_mmp) then
                    val1 = -10000
                end
            end

            if you.race() == "Vine Stalker" then
                value = value - 300
            else
                value = value + 75
            end
        elseif ego == "acid" then
            if branch_soon("Slime") then
                if cur then
                    return -1, -1
                else
                    val1 = -10000
                end
            elseif not cur and planning_slime then
                val1 = -10000
            end

            -- The best possible ranged brand aside from possibly holy wrath vs
            -- undead or demons. Keeping this value higher than 500 for now to
            -- make Punk more competitive than all well-enchanted longbows save
            -- those with speed or holy wrath versus demons and undead.
            value = value + 750
        end
    end

    if it.plus then
        value = value + 30 * it.plus
    end

    -- We might be delayed by a shield or not yet at min delay, so add a little.
    value = value + 1200 * it.damage / (weapon_min_delay(it) + 1)

    if it.weap_skill ~= weap_skill then
        value = value / 10
        if val1 > 0 then
            val1 = val1 / 10
        end
        val2 = val2 / 10
    end

    val1 = val1 + value
    val2 = val2 + value
    return val1, val2
end

function amulet_value(it, cur, it2)
    local name = it.name()
    if name:find("macabre finger necklace") then
        return -1, -1
    end

    local val1, val2 = 0, 0
    if current_god_hates_item(it) then
        if cur then
            return -1, -1
        else
            val1 = -10000
        end
    elseif not cur and future_gods_hate_item(it) then
        val1 = -10000
    end

    if not it.fully_identified then
        if cur then
            return 800, 800
        end

        if val1 > -1 then
            val1 = -1
        end
        val2 = 1000
    end

    local res_val1, res_val2 = total_property_value(it, cur, it2)
    val1 = val1 + res_val1
    val2 = val2 + res_val2
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

    local val1, val2 = total_property_value(it, cur, it2)
    return val1, val2
end

-- This doesn't handle rings correctly at the moment, but right now we are
-- only using this for weapons anyway.
-- Also maybe this should check property_dominated too?
function item_is_sit_dominated(it, sit)
    local slotname = equip_slot(it)
    local minv, maxv = equip_value(it, nil, nil, sit)
    if maxv <= 0 then
        return true
    end

    for it2 in inventory() do
        if equip_slot(it2) == slotname and it2.slot ~= it.slot then
            local minv2, maxv2 = weapon_value(it2, nil, nil, sit)
            if minv2 >= maxv
                    and not (slotname == "Weapon"
                        and you.base_skill("Shields") > 0
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
    elseif slotname == "Weapon"
                and (you.god() == "the Shining One"
                        and not you.one_time_ability_used()
                    or future_tso)
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
        if equip_slot(it2) == slotname and it2.slot ~= it.slot then
            local minv2, maxv2 = equip_value(it2)
            if minv2 >= maxv
                    or minv2 >= minv
                        and maxv2 >= maxv
                        and property_dominated(it, it2) then
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
        if equip_slot(it) == "Weapon" and it.weap_skill ~= weapon_skill() then
            return true
        end

        -- Don't like to swap Faith.
        return item_property("Faith", old_it) == 0
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
