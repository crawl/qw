-------------------------------------
-- General equipment manipulation.

const.acquire = { scroll = 1, okawaru_weapon = 2, okawaru_armour = 3 }

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

-- A list of armour slots, this is used to normalize names for them and also to
-- iterate over the slots
good_slots = {cloak="Cloak", helmet="Helmet", gloves="Gloves", boots="Boots",
    body="Body Armour", shield="Shield"}

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
        if it.class(true) == "weapon"
                and it.weap_skill == weapon_skill()
                and it.hands == 2 then
            return true
        end
    end

    return false
end

function get_weapon(allow_melded)
    local weapon = items.equipped_at("Weapon")
    if not allow_melded and weapon.is_melded then
        return
    end

    return weapon
end

function use_ranged_weapon()
    return turn_memo("use_ranged_weapon",
        function()
            return weapon_skill() == "Ranged Weapons"
        end)
end

function have_ranged_weapon()
    return turn_memo("have_ranged_weapon",
        function()
            local weapon = get_weapon()
            return weapon and not weapon.is_melded and weapon.is_ranged
        end)
end

function reach_range()
    local wp = get_weapon()
    return wp and not wp.is_melded and wp.reach_range or 1
end

function have_reaching()
    local wp = get_weapon()
    return wp and wp.reach_range >= 2 and not wp.is_melded
end

function weapon_min_delay(weapon)
    local delay = weapon.delay

    -- The maxes used in this function are used to cover cases like Dark Maul
    -- and Sniper, which have high base delays that can't reach the usual min
    -- delays.
    if contains_string_in(weapon.subtype(), { "crossbow", "arbalest" }) then
        return max(10, weapon.delay - 13.5)
    end

    if weapon.weap_skill == "Short Blades" then
        return 5
    end

    if contains_string_in(weapon.subtype(), { "demon whip", "scourge" }) then
        return 5
    end

    if contains_string_in(weapon.subtype(),
            { "demon blade", "eudemon blade", "trishula", "dire flail" }) then
        return 6
    end

    return max(7, weapon.delay - 13.5)
end

function weapon_delay(weapon, duration_level)
    if not durations then
        durations = {}
    end

    local skill = you.skill(weapon.weap_skill)
    if not have_duration("heroism", duration_level)
            and duration_active("heroism") then
        skill = skill - min(27 - skill, 5)
    elseif have_duration("heroism", duration_level)
            and not duration_active("heroism") then
        skill = skill + min(27 - skill, 5)
    end

    local delay = weapon.delay - skill / 2
    delay = max(weapon_min_delay(weapon), delay)

    local ego = weapon:ego()
    if ego == "speed" then
        delay = delay * 2 / 3
    elseif ego == "heavy" then
        delay = delay * 1.5
    end

    if have_duration("finesse", duration_level) then
        delay = delay / 2
    elseif not weapon.is_ranged
            and not weapon.class(true) == "missile"
            and have_duration("berserk", duration_level) then
        delay = delay * 2 / 3
    elseif have_duration("haste", duration_level) then
        delay = delay * 2 / 3
    end

    if have_duration("slow", duration_level) then
        delay = delay * 3 / 2
    end

    return delay
end

function min_delay_skill()
    local weapon = get_weapon()
    -- Unarmed combat.
    if not weapon then
        return 27
    end

    return 2 * (weapon.delay - weapon_min_delay(weapon))
end

function at_min_delay()
    return you.base_skill(weapon_skill()) >= min(27, min_delay_skill())
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

function can_swap(it, upgrade)
    if not it then
        return true
    end

    if it.name():find("obsidian axe") and you.status("mesmerised")
            or not upgrade and it.artefact and it.artprops["^Fragile"]
            or not upgrade
                and it.ego() == "distortion"
                and you.god() ~= "Lugonu" then
        return false
    end

    local feat = view.feature_at(0, 0)
    if you.flying()
            and (feat == "deep_water" and not intrinsic_amphibious()
                or feat == "lava" and not intrinsic_flight())
            and player_property("Fly", it) == 0 then
        return false
    end

    return true
end
