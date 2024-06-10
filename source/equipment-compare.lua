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
function equip_value(item, cur, ignore_equip, sit, only_linear)
    if not item then
        return -1, -1
    end

    local slot = equip_slot(item)
    if const.armour_equip_names[slot] then
        return armour_value(item, cur, ignore_equip, only_linear)
    elseif slot == "weapon" then
        return weapon_value(item, cur, ignore_equip, sit, only_linear)
    elseif slot == "amulet" then
        return amulet_value(item, cur, ignore_equip, only_linear)
    elseif slot == "ring" then
        return ring_value(item, cur, ignore_equip, only_linear)
    elseif slot == "gizmo" then
        return gizmo_value(item, ignore_equip, only_linear)
    end

    return -1, -1
end

function equip_set_value(equip, ignore_item)
    if ignore_item then
        new_equip = {}
        local found_equip = false
        for slot, item in equip_set_iter(equip) do
            if item.slot ~= ignore_item.slot then
                if not new_equip[slot] then
                    new_equip[slot] = {}
                end

                table.insert(new_equip[slot], item)
                found_equip = true
            end
        end

        if not found_equip then
            return 0
        end

        equip = new_equip
    end

    local total_value, weapon_delay, weapon_count = 0, 0, 0
    for slot, item in equip_set_iter(equip) do
        local value = 0
        if slot == "weapon" then
            weapon_delay = weapon_delay + weapon_min_delay(item)
            weapon_count = weapon_count + 1
        elseif const.armour_equip_names[slot] then
            value = armour_base_value(item, true)
        elseif slot == "amulet" then
            value = amulet_base_value(item, true)
        elseif slot == "gizmo" then
            value = gizmo_base_value(item)
        end

        if value < 0 then
            return value
        end

        for _, prop in ipairs(const.linear_properties) do
            value = value
                + item_property(prop, item) * linear_property_value(prop)
        end

        total_value = total_value + value
    end

    if weapon_count > 0 then
        weapon_delay = weapon_delay / weapon_count
        local skill = weapon_skill()
        for weapon in equip_set_slot_iter(equip, "weapon") do
            local value = weapon_base_value(weapon, true)
            if value < 0 then
                return value
            end

            value = value + weapon_damage_value(weapon, weapon_delay)

            if weapon.weap_skill ~= skill then
                value = value / 10
            end

            total_value = total_value + value
        end
    end

    local cur_equip = inventory_equip(const.inventory.equipped)
    for _, prop in ipairs(const.nonlinear_properties) do
        local level = 0
        for _, item in equip_set_iter(equip) do
            level = level + item_property(prop, item)
        end

        local player_level = player_property(prop, cur_equip)
        total_value = total_value
            + absolute_property_value(prop, player_level + level)
            - absolute_property_value(prop, player_level)
    end

    return total_value
end

function best_inventory_equip(extra_item)
    local extra_slot = equip_slot(extra_item)
    if extra_item and (not extra_slot or equip_is_dominated(extra_item)) then
        return
    end

    local inventory = inventory_equip(const.inventory.value)
    if not inventory then
        if not extra_item then
            return
        end

        inventory = {}
    end

    local best_equip
    local iter_count = 1
    for equip in equip_combo_iter(inventory, extra_item) do
        equip.value = equip_set_value(equip)

        if debug_channel("items") then
            dsay("Iteration #" .. tostring(iter_count) .. ": "
                .. equip_set_string(equip) .. "; value: "
                .. tostring(equip.value))
        end

        if equip.value > 0
                and (not best_equip or equip.value > best_equip.value) then
            best_equip = equip
        end

        iter_count = iter_count + 1
    end

    if debug_channel("items") then
        if best_equip then
            dsay("Best equip set: " .. equip_set_string(best_equip)
                .. "; value: " .. tostring(best_equip.value))
        else
            dsay("No best equip set found")
        end
    end

    return best_equip
end

function best_equip_from_c_persist()
    if not c_persist.best_equip or not c_persist.best_equip.value then
        return
    end

    local equip = { value = c_persist.best_equip.value }
    c_persist.best_equip.value = nil
    for letter, name in pairs(c_persist.best_equip) do
        local item = get_item(letter)
        if not item or item.name() ~= name then
            return
        end

        local slot = equip_slot(item)
        if not equip[slot] then
            equip[slot] = {}
        end

        table.insert(equip[slot], item)
    end
    c_persist.best_equip.value = equip.value
    return equip
end

function equip_set_value_search(equip, filter, min_value)
    local best_item, best_value
    for slot, item in equip_set_iter(equip) do
        if not filter or filter(item) then
            local value = equip.value - equip_set_value(equip, item)
            if not best_value
                    or min_value and value < best_value
                    or not min_value and value > best_value then
                best_item = item
                best_value = value
            end
        end
    end
    return best_item, best_value
end

function remove_equip_set_item(item, equip)
    local slot = equip_slot(item)
    if not equip[slot] then
        return
    end

    for i, set_item in ipairs(equip[slot]) do
        if equip[slot][i].slot == item.slot then
            if #equip[slot] == 1 then
                equip[slot] = nil
            else
                table.remove(equip[slot], i)
            end

            return
        end
    end
end

function best_equip_set()
    if qw.best_equip then
        return qw.best_equip
    end

    qw.best_equip = best_equip_from_c_persist()
    if qw.best_equip then
        return qw.best_equip
    end

    local equip = best_inventory_equip()
    if not equip then
        c_persist.best_equip = nil
        return
    end

    repeat
        local worst_item, worst_value = equip_set_value_search(equip,
            nil, true)

        if worst_value and worst_value <= 0 then
            if debug_channel("items") then
                dsay("Removing best equip set item " .. worst_item.name()
                    .. " with value " .. tostring(worst_value))
            end

            remove_equip_set_item(worst_item, equip)
            equip.value = equip.value - worst_value
        end
    until not worst_value or worst_value > 0
    qw.best_equip = equip

    if debug_channel("items") then
        dsay("Final best equip set: " .. equip_set_string(qw.best_equip)
            .. "; value: " .. tostring(qw.best_equip.value))
    end

    c_persist.best_equip = {}
    for _, item in equip_set_iter(qw.best_equip) do
        c_persist.best_equip[item_letter(item)] = item.name()
    end
    c_persist.best_equip.value = qw.best_equip.value

    return qw.best_equip
end

-- Is the first item going to be worse than the second item no matter what
-- other properties we have?
function property_dominated(item1, item2)
    local bmin1, bmax1 = equip_value(item1, false, nil, nil, true)
    local bmin2, bmax2 = equip_value(item2, false, nil, nil, true)
    local diff = bmin2 - bmax1
    if diff < 0 then
        return false
    end

    local props1 = property_array(item1)
    local props2 = property_array(item2)
    for i = 1, #props1 do
        if props1[i] > props2[i] then
            diff = diff - (props1[i] - props2[i])
        end
    end
    return diff >= 0
end

function armour_base_value(item, cur)
    local value = 0
    local min_val, max_val = 0, 0

    if current_god_hates_item(item) then
        if cur then
            return -1, -1
        else
            min_val = -10000
        end
    elseif not cur and future_gods_hate_item(item) then
        min_val = -10000
    end

    local name = item.name()
    if item.artefact then
        -- Unrands
        if name:find("hauberk") then
            return -1, -1
        end

        if you.race() ~= "Djinni" and item.name():find("Mad Mage's Maulers") then
            if you.god() ~= "No God" and qw.always_need_mp_for_gods then
                return -1, -1
            elseif god_uses_mp() then
                if cur then
                    return -1, -1
                else
                    min_val = -10000
                end
            elseif not cur and qw.future_gods_use_mp then
                min_val = -10000
            end

            value = value + 200
        elseif item.name():find("lightning scales") then
            value = value + 100
        end
    end

    value = value + 50 * expected_armour_multiplier() * item.ac
    if item.plus then
        value = value + 50 * item.plus
    end

    local slot = equip_slot(item)
    if slot == "shield" and not want_shield() then
        return -1, -1
    end

    if slot == "boots" then
        local want_barding = you.race() == "Armataur" or you.race() == "Naga"
        local is_barding = name:find("barding") or name:find("lightning scales")
        if want_barding and not is_barding
                or not want_barding and is_barding then
            return -1, -1
        end
    end

    if slot == "body" then
        if unfitting_armour() then
            value = value - 25 * item.ac
        end

        evp = item.encumbrance
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

    return min_val + value, max_val + value
end

function armour_value(item, cur, ignore_equip, only_linear)
    local min_val, max_val = armour_base_value(item, cur)

    if cur and min_val < 0 or max_val < 0 then
        return min_val, max_val
    end

    -- Subtype is known and has given us a reasonable value range. We adjust
    -- this range based on the fact that the unknown properties could be good
    -- or bad.
    if not cur and equip_is_valuable_unidentified(item) then
        min_val = min_val + (item.artefact and -400 or -200)
        max_val = max_val + 400
    end

    local res_min, res_max = total_property_value(item, cur, ignore_equip,
        only_linear)
    min_val = min_val + res_min
    max_val = max_val + res_max

    return min_val, max_val
end

function weapons_match_skill(skill)
    for weapon in equipped_slot_iter("weapon") do
        if weapon.weap_skill ~= skill then
            return false
        end
    end

    return true
end

function weapons_have_antimagic()
    for weapon in equipped_slot_iter("weapon") do
        if weapon.ego() == "antimagic" then
            return true
        end
    end

    return false
end

function weapon_base_value(item, cur, sit)
    local value = 1000
    local min_val, max_val = 0, 0

    local hydra_swap = sit == "hydra"
    local weap_skill = weapon_skill()
    -- The evaluating weapon doesn't match our desired skill...
    if item.weap_skill ~= weap_skill
            -- ...and our current weapon already matches our desired skill or
            -- we use UC...
            and (weapons_match_skill(weap_skill)
                or weap_skill == "Unarmed Combat")
            -- ...and we either don't need a hydra swap weapon or the
            -- evaluating weapon isn't a hydra swap weapon for our desired
            -- skill.
            and (not hydra_swap
                or not (item.weap_skill == "Maces & Flails"
                            and weap_skill == "Axes"
                        or item.weap_skill == "Short Blades"
                            and weap_skill == "Long Blades")) then
        return -1, -1
    end

    local name = item.name()
    if sit == "bless" then
        if item.artefact then
            return -1, -1
        elseif not cur and equip_is_valuable_unidentified(item) then
            min_val = min_val - 150
            max_val = max_val + 150
        end

        if item.plus then
            value = value + 30 * item.plus
        end

        value = value + 1200 * item.damage / weapon_min_delay(item)
        return value + min_val, value + max_val
    end

    if current_god_hates_item(item) then
        if cur then
            return -1, -1
        else
            min_val = -10000
        end
    elseif not cur and future_gods_hate_item(item) then
        min_val = -10000
    end

    -- XXX: De-value this on certain levels or give qw better strats while
    -- mesmerised.
    if name:find("obsidian axe") then
        -- This is much less good when it can't make friendly demons.
        if you.mutation("hated by all") or you.god() == "Okawaru" then
            value = value - 200
        elseif qw.future_okawaru then
            min_val = min_val + (cur and 200 or -200)
            max_val = max_val + 200
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

    if item.hands == 2 and not want_two_handed_weapon() then
        return -1, -1
    end

    if hydra_swap then
        local hydra_value = hydra_weapon_value(item)
        if hydra_value < 0 then
            return -1, -1
        elseif hydra_value > 0 then
            value = value + 500
        end
    end

    -- Names are mostly in weapon_brands_verbose[].
    local undead_demon = undead_or_demon_branch_soon()
    local ego = item.ego()
    if ego then
        if ego == "distortion" then
            return -1, -1
        elseif ego == "holy wrath" then
            -- We can never use this.
            if intrinsic_evil() then
                return -1, -1
            end

            if undead_demon then
                min_val = min_val + (cur and 500 or 0)
                max_val = max_val + 500
            -- This will eventaully be good on the Orb run.
            else
                max_val = max_val + 500
            end
        -- Not good against demons or undead, otherwise this is what we want.
        elseif ego == "vampirism" then
            -- It may be good at some point if we go to non undead-demon places
            -- before the Orb. XXX: Determine this from goals and adjust this
            -- value based on the result.
            if undead_demon then
                max_val = max_val + 500
            else
                min_val = min_val + (cur and 500 or 0)
                max_val = max_val + 500
            end
        elseif ego == "speed" then
            -- This is good too
            value = value + 300
        elseif ego == "spectralizing" then
            value = value + 400
        elseif ego == "draining" then
            -- XXX: Same issue as for vampirism above.
            if undead_demon then
                max_val = max_val + 75
            else
                min_val = min_val + (cur and 75 or 0)
                max_val = max_val + 75
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
                max_val = max_val + 50
            else
                min_val = min_val + (cur and 50 or 0)
                max_val = max_val + 50
            end
        elseif ego == "antimagic" then
            if you.race() ~= "Djinni" then
                local new_mmp = select(2, you.mp())
                -- Swapping to antimagic reduces our max MP by 2/3.
                if not weapons_have_antimagic() then
                    new_mmp = math.floor(select(2, you.mp()) * 1 / 3)
                end
                if not enough_max_mp_for_god(new_mmp, you.god()) then
                    if cur then
                        return -1, -1
                    else
                        min_val = -10000
                    end
                elseif not cur and not future_gods_enough_max_mp(new_mmp) then
                    min_val = -10000
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
                    min_val = -10000
                end
            elseif not cur and qw.planning_slime then
                min_val = -10000
            end

            -- The best possible ranged brand aside from possibly holy wrath vs
            -- undead or demons. Keeping this value higher than 500 for now to
            -- make Punk more competitive than all well-enchanted longbows save
            -- those with speed or holy wrath versus demons and undead.
            value = value + 750
        end
    end

    if item.plus then
        value = value + 30 * item.plus
    end

    return min_val + value, max_val + value
end

function weapon_damage_value(item, delay)
    -- We might be delayed by a shield or not yet at min delay, so add a little.
    return 1200 * item.damage / (delay + 1)
end

function weapon_value(item, cur, ignore_equip, sit, only_linear)
    local min_val, max_val = weapon_base_value(item, cur, sit)

    if cur and min_val < 0 or max_val < 0 then
        return min_val, max_val
    end

    local damage_value = weapon_damage_value(item, weapon_min_delay(item))
    min_val = min_val + damage_value
    max_val = max_val + damage_value

    -- The utility from damage is worth much less without training in the skill.
    if item.weap_skill ~= weapon_skill() then
        if min_val > 0 then
            min_val = min_val / 10
        end

        max_val = max_val / 10
    end

    if not cur and equip_is_valuable_unidentified(item) then
        min_val = min_val - 250
        max_val = max_val + 500
    end

    local prop_min, prop_max = total_property_value(item, cur, ignore_equip,
        only_linear)
    return min_val + prop_min, max_val + prop_max
end

function amulet_base_value(item, cur)
    local name = item.name()
    if name:find("macabre finger necklace") then
        return -1, -1
    end

    local min_val, max_val = 0, 0
    if current_god_hates_item(item) then
        if cur then
            return -1, -1
        else
            min_val = -10000
        end
    elseif not cur and future_gods_hate_item(item) then
        min_val = -10000
    end

    if name:find("of the Air.*Innac") then
        min_val = min_val - 200
        max_val = max_val - 200
    end

    return min_val, max_val
end

function amulet_value(item, cur, ignore_equip, only_linear)
    local min_val, max_val = amulet_base_value(item, cur)

    if cur and min_val < 0 or max_val < 0 then
        return min_val, max_val
    end

    if not cur and equip_is_valuable_unidentified(item) then
        min_val = min_val - 250
        max_val = max_val + 1000
    end

    local prop_min, prop_max = total_property_value(item, cur, ignore_equip,
        only_linear)
    return min_val + prop_min, max_val + prop_max
end

function ring_value(item, cur, ignore_equip, only_linear)
    local min_val, max_val = 0, 0

    if not cur and equip_is_valuable_unidentified(item) then
        min_val = min_val - 250
        max_val = max_val + 500
    end

    local prop_min, prop_max= total_property_value(item, cur, ignore_equip,
        only_linear)
    return min_val + prop_min, max_val + prop_max
end

function gizmo_base_value(item)
    local value = 0
    local ego = item.ego()
    if ego == "Gadgeteer" then
        value = 20
    elseif ego == "AutoDazzle" then
        value = 100
    -- This gets additional value added from its AC property.
    elseif ego == "RevParry" then
        value = 20
    end
    return value
end

function gizmo_value(item, ignore_equip, only_linear)
    return gizmo_base_value(item)
        + total_property_value(item, true, ignore_equip, only_linear)
end

-- Maybe this should check property_dominated too?
function weapon_is_sit_dominated(item, sit)
    local max_val = select(2, weapon_value(item, false, nil, sit))
    if max_val < 0 then
        return true
    end

    for weapon in inventory_slot_iter("weapon") do
        if weapon.slot ~= item.slot
                    and (weapon.hands == 1 or want_two_handed_weapon())
                    and select(2, weapon_value(weapon, false, nil, sit))
                        >= max_val then
            return true
        end
    end

    return false
end

function equip_is_dominated(item)
    local slot = equip_slot(item)
    if you.race() ~= "Coglin"
                and slot == "weapon"
                and you.xl() < 18
                and not weapon_is_sit_dominated(item, "hydra")
            or slot == "weapon"
                and (you.god() == "the Shining One"
                        and not you.one_time_ability_used()
                    or qw.future_tso)
                and not weapon_is_sit_dominated(item, "bless")
            or slot == "gizmo" then
        return false
    end

    local min_val, max_val = equip_value(item)
    if max_val < 0 then
        return true
    end

    local slots_free = slot_max_items(slot)
    for item2 in inventory_slot_iter(slot) do
        if item2.slot ~= item.slot
                and not (want_shield()
                    and weapon_allows_shield(item)
                    and not weapon_allows_shield(item2)) then
            local min_val2, max_val2 = equip_value(item2)
            if min_val2 >= max_val
                    or min_val2 >= min_val
                        and max_val2 >= max_val
                        and property_dominated(item, item2) then
                slots_free = slots_free - 1

                if slots_free == 0 then
                    return true
                end
            end
        end
    end

    return false
end

function best_acquirement_index(acq_items)
    local best_index, gold_index
    local best_equip = best_equip_set()
    for i, item in ipairs(acq_items) do
        local equip = best_inventory_equip(item)
        if equip and (not best_equip or equip.value > best_equip.value) then
            best_equip = equip
            best_index = i
        end

        if item.class(true) == "gold" then
            gold_index = i
        end
    end

    if best_index then
        return best_index
    elseif gold_index then
        return gold_index
    end
end
