-------------------------------------
-- General equipment manipulation.

const.acquire = { scroll = 1, okawaru_weapon = 2, okawaru_armour = 3,
    gizmo = 4 }

-- A table mapping of armour slots. Used for iteration and to map simple slot
-- names to the full name needed by the items library.
const.armour_slots = { "shield", "body", "cloak", "helmet", "gloves", "boots" }
const.armour_equip_names = { shield="Shield", body="Body Armour", cloak="Cloak",
    helmet="Helmet", gloves="Gloves", boots="Boots" }


const.all_slots = { "weapon", "shield", "body", "helmet", "cloak", "gloves",
    "boots", "amulet", "ring", "gizmo" }
const.all_equip_names = { weapon="Weapon", shield="Shield", body="Body Armour", cloak="Cloak",
    helmet="Helmet", gloves="Gloves", boots="Boots", amulet="Amulet", gizmo="Gizmo" }

const.upgrade_slots = { "body", "helmet", "cloak", "gloves", "boots", "amulet",
    "ring" }

const.inventory = { "all", "value", "equipped" }

const.missile_delays = { dart=10, boomerang=13, javelin=15, ["large rock"]=20 }

function get_slot_item_func(slot, allow_melded)
    local slot_name = const.all_equip_names[slot]
    if not slot_name then
        return
    end

    local item = items.equipped_at(slot_name)
    if not item
            or item.is_melded and not allow_melded
            or equip_slot(item) ~= slot then
        return
    end

    return item
end

function get_slot_item(slot, allow_melded)
    return turn_memo_args("get_slot_item",
        function() return get_slot_item_func(slot, allow_melded) end,
        slot, allow_melded)
end

function get_weapon(allow_melded)
    return get_slot_item("weapon", allow_melded)
end

function get_shield(allow_melded)
    return get_slot_item("shield", allow_melded)
end

function equip_slot(item)
    if not item then
        return
    end

    local class = item.class(true)
    if class == "weapon" then
        return "weapon"
    elseif class == "armour" then
        return item.subtype()
    elseif class == "jewellery" then
        local sub = item.subtype()
        if sub and sub:find("amulet")
               or not sub and item.name():find("amulet") then
            return "amulet"
        else
            return "ring" -- not the actual slot name
        end
    elseif class == "gizmo" then
        return "gizmo"
    end
end

function want_ranged_weapon()
    return turn_memo("want_ranged_weapon",
        function()
            return weapon_skill() == "Ranged Weapons"
        end)
end

function using_ranged_weapon(allow_melded)
    local weapon = get_weapon(allow_melded)
    return weapon and weapon.is_ranged
end

function weapon_allows_shield(weapon)
    return weapon.hands == 1
        or you.race() == "Formicid" and not weapon.subtype():find("giant.* club")
end

function using_two_handed_weapon(allow_melded)
    local weapon = get_weapon(allow_melded)
    return weapon and weapon.hands == 2
end

function using_two_one_handed_weapons(allow_melded)
    return turn_memo_args("using_two_one_handed_weapons",
        function()
            local one_handers = 0
            for weapon in equipped_slot_iter("weapon", allow_melded) do
                if weapon.hands == 1 then
                    one_handers = one_handers + 1
                end

                if one_handers > 1 then
                    return true
                end
            end

            return false
        end, allow_melded)
end

function using_cleave(allow_melded)
    return turn_memo_args("using_cleave",
        function()
            for weapon in equipped_slot_iter("weapon", allow_melded) do
                if weapon.weap_skill == "Axes" then
                    return true
                end
            end
        end, allow_melded)
end

-- Would we ever want to use a two-handed weapon? This returns true when we
-- prefer 1h weapons if we haven't yet found a shield.
function want_two_handed_weapon()
    local sp = you.race()
    if sp == "Felid" or sp == "Coglin" then
        return false
    -- Formicids always use two-handed weapons since they can use them with shields.
    elseif sp == "Formicid" then
        return true
    end

    return want_ranged_weapon() or not (get_shield(true) and qw.shield_crazy)
end

-- Would we ever want a shield?
function want_shield()
    local sp = you.race()
    if sp == "Felid" then
        return false
    elseif sp == "Coglin" then
        return not using_two_one_handed_weapons(true)
    end

    return true
end

function player_reach_range()
    return turn_memo("player_reach_range",
        function()
            local range = 1
            for weapon in equipped_slot_iter("weapon") do
                if weapon.reach_range > range then
                    range = weapon.reach_range
                end
            end

            return range
        end)
end

function weapon_min_delay(weapon)
    local max_delay
    if weapon.delay then
        max_delay = weapon.delay
    elseif weapon.class(true) == "missile" then
        max_delay = const.missile_delays[weapon.subtype()]
    end

    -- The maxes used in this function are used to cover cases like Dark Maul
    -- and Sniper, which have high base delays that can't reach the usual min
    -- delays.
    if contains_string_in(weapon.subtype(), { "crossbow", "arbalest", "cannon" }) then
        return max(10, max_delay - 13.5)
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

    return max(7, max_delay - 13.5)
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

    local delay
    if weapon.delay then
        delay = weapon.delay
    elseif weapon.class(true) == "missile" then
        delay = const.missile_delays[weapon.subtype()]
    end

    delay = max(weapon_min_delay(weapon), delay - skill / 2)

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
    local max_level
    for weapon in equipped_slot_iter("weapon") do
        local level = min(27, 2 * (weapon.delay - weapon_min_delay(weapon)))
        if not max_level or level > max_level then
            max_level = level
        end
    end

    if max_level then
        return max_level
    -- Unarmed combat
    else
        return 27
    end
end

function at_min_delay()
    return you.base_skill(weapon_skill()) >= min_delay_skill()
end

function armour_evp()
    local armour = get_slot_item("body", true)
    if armour then
        return armour.encumbrance
    else
        return 0
    end
end

function base_ac()
    local ac = 0
    for slot, item in equipped_slots_iter(const.armour_slots, true) do
        if slot ~= "shield" then
            ac = ac + item.ac
        end
    end
    return ac
end

function item_is_unswappable(item)
    for _, prop in ipairs(const.no_swap_properties) do
        if item_property(prop, item) > 0 then
            return true
        end
    end

    return item.ego() == "distortion" and you.god() ~= "Lugonu"
end

function can_swap_item(item, upgrade)
    if not item then
        return true
    end

    if item.is_melded
            or item.name():find("obsidian axe") and you.status("mesmerised")
            or not upgrade and item_is_unswappable(item) then
        return false
    end

    local feat = view.feature_at(0, 0)
    if you.flying()
            and (feat == "deep_water" and not intrinsic_amphibious()
                or feat == "lava")
            and player_property("Fly",
                { [equip_slot(item)] = { item } }) == 0 then
        return false
    end

    return true
end

function equip_set_string(equip)
    local item_letters = {}
    local item_counts = {}
    local slots = {}
    for slot, item in equip_set_iter(equip) do
        if item_counts[slot] then
            item_counts[slot] = item_counts[slot] + 1
        else
            item_counts[slot] = 1
        end

        table.insert(slots, slot)
        table.insert(item_letters, item.slot and item_letter(item) or "?")
        table.insert(item_counts, tostring(item_counts[slot]))
    end

    local entries = {}
    for i, slot in ipairs(slots) do
        local max_items = slot_max_items(slot)
        table.insert(entries, slot .. (max_items > 1 and item_counts[i] or "")
            .. ":" .. item_letters[i])
    end

    return "(" .. table.concat(entries, ", ") .. ")"
end

function equip_set_iter(equip, slots, item_only)
    if not slots then
        slots = const.all_slots
    end

    local slot_num = 1
    local slot = slots[slot_num]
    local slot_ind = 1
    return function()
        if not equip then
            return
        end

        while slot_num <= #slots do
            local slot_items = equip[slot]
            if slot_items and slot_ind <= #slot_items then
                local item = equip[slot][slot_ind]
                slot_ind = slot_ind + 1

                if item_only then
                    return item
                else
                    return slot, item
                end
            else
                slot_num = slot_num + 1
                slot = slots[slot_num]
                slot_ind = 1
            end
        end

        return
    end
end

function equip_set_slot_iter(equip, slot)
    return equip_set_iter(equip, { slot }, true)
end

function inventory_equip_func(inventory_type, ignore_melding)
    local equip = {}
    local found_equip = false
    for _, item in ipairs(items.inventory()) do
        local slot = equip_slot(item)
        if slot and (not item.is_useless or inventory_type == const.inventory.equipped)
                and (ignore_melding or not item.is_melded)
                and (inventory_type ~= const.inventory.equipped
                    or item.equipped)
                and (inventory_type ~= const.inventory.value
                    or slot == "gizmo"
                    or select(2, equip_value(item)) > 0) then
            if not equip[slot] then
                equip[slot] = {}
            end

            found_equip = true
            table.insert(equip[slot], item)
        end
    end
    if found_equip then
        return equip
    end
end

function inventory_equip(inventory_type, ignore_melding)
    return turn_memo_args("inventory_equip",
        function()
            return inventory_equip_func(inventory_type, ignore_melding)
        end, inventory_type, ignore_melding)
end

function inventory_slots_iter(slots, ignore_melding)
    return equip_set_iter(inventory_equip(const.inventory.all, ignore_melding),
        slots)
end

function inventory_slot_iter(slot, ignore_melding)
    return equip_set_slot_iter(inventory_equip(const.inventory.all,
        ignore_melding), slot)
end

function equipped_slots_iter(slots, ignore_melding)
    return equip_set_iter(inventory_equip(const.inventory.equipped,
        ignore_melding), slots)
end

function equipped_slot_iter(slot, ignore_melding)
    return equip_set_slot_iter(inventory_equip(const.inventory.equipped,
        ignore_melding), slot)
end

util.defclass("EquipmentCombinationIterator")

function EquipmentCombinationIterator:new(inventory, extra_item)
    local iter = {}
    setmetatable(iter, self)

    iter.inventory = inventory

    if extra_item then
        iter.extra_item = extra_item

        -- We work off a copy so we can add our extra item without affecting
        -- our memoized data.
        iter.inventory = util.copy_table(iter.inventory)

        local slot = equip_slot(extra_item)
        if not iter.inventory[slot] then
            iter.inventory[slot] = {}
        end

        table.insert(iter.inventory[slot], extra_item)
    end

    iter.inventory_slots = {}
    iter.slot_max_items = {}
    iter.active_slots = {}
    iter.seen_slots = {}
    for _, slot in ipairs(const.all_slots) do
        if iter.inventory[slot] then
            iter.slot_max_items[slot] = slot_max_items(slot)
            iter.seen_slots[slot] = true
            iter.active_slots[slot] = true
            table.insert(iter.inventory_slots, slot)
        end
    end

    iter.first_iteration = true
    iter.equip_indices = {}
    for _, slot in ipairs(iter.inventory_slots) do
        iter.equip_indices[slot] = {}
        iter:reset_equip_indices(slot, 1)
    end

    if debug_channel("items") then
        local inv_counts = {}
        for _, slot in ipairs(iter.inventory_slots) do
            table.insert(inv_counts, slot .. ":"
                .. tostring(#iter.inventory[slot]))
        end
        dsay("Item counts for slots: " .. table.concat(inv_counts, ", "))

        if extra_item then
            dsay("Extra item: " .. qw.stringify(extra_item))
        end
    end

    return iter
end

function EquipmentCombinationIterator:set_equip_index(slot, slot_ind, item_ind)
    local inv = self.inventory[slot]
    local indices = self.equip_indices[slot]
    if slot == "weapon" then
        if self.seen_slots["shield"]
                and slot_ind == 1
                and weapon_allows_shield(inv[item_ind]) then
            self.active_slots["shield"] = true
        elseif not weapon_allows_shield(inv[item_ind]) or slot_ind == 2 then
            self.active_slots["shield"] = false
        end
    end

    if inv[item_ind] == self.extra_item then
        self.extra_used = true
    elseif indices[slot_ind] and inv[indices[slot_ind]] == self.extra_item then
        self.extra_used = false
    end

    indices[slot_ind] = item_ind
end

function EquipmentCombinationIterator:reset_equip_indices(slot, slot_ind)
    local inv = self.inventory[slot]
    local num_items = #inv
    local max_items = min(num_items, self.slot_max_items[slot])

    -- There are no remaining slots to reset.
    if slot_ind > max_items then
        return true
    end

    local item_ind = 1
    local indices = self.equip_indices[slot]
    -- The first slot is always reset to the first item, since when it's reset,
    -- we're resetting all slots to the initial configuration. For subsequent
    -- slots, we reset them to the first item after the one used by the
    -- previous slot.
    if slot_ind > 1 then
        item_ind = indices[slot_ind - 1] + 1
    end

    -- We have no more unused inventory items to put in slots.
    if item_ind > num_items then
        return false
    end

    for j = 0, max_items - slot_ind do
        self:set_equip_index(slot, slot_ind + j, item_ind + j)
    end

    return true
end

function EquipmentCombinationIterator:iterate_equip_slot(slot)
    if self.first_iteration then
        self.first_iteration = false
        return true
    end

    local indices = self.equip_indices[slot]
    local inv = self.inventory[slot]
    local num_items = #inv
    local max_items = min(num_items, self.slot_max_items[slot])
    for i = max_items, 1, -1 do
        if indices[i] < num_items - (max_items - i) then
            self:set_equip_index(slot, i, indices[i] + 1)

            -- Assign remaining items to subsequent slots of this type.
            if self:reset_equip_indices(slot, i + 1) then
                return true
            -- There aren't enough unused items left to assign to this slot, so
            -- we're done iterating it.
            else
                break
            end
        end
    end

    -- There are no more unused item combinations for this slot, so reset its
    -- indices to the starting set of items.
    self:reset_equip_indices(slot, 1)
    return false
end

function EquipmentCombinationIterator:slot_iterator(reverse)
    local index, last_index, increment
    if reverse then
        index = #self.inventory_slots
        last_index = 1
        increment = -1
    else
        index = 1
        last_index = #self.inventory_slots
        increment = 1
    end

    return function()
        if index == last_index + increment then
            return
        end

        for i = index, last_index, increment do
            index = i + increment

            if self.active_slots[self.inventory_slots[i]] then
                return self.inventory_slots[i]
            end
        end
    end
end

function EquipmentCombinationIterator:equip_set()
    local equip = {}
    for slot in self:slot_iterator() do
        local inv = self.inventory[slot]
        local indices = self.equip_indices[slot]
        equip[slot] = {}
        for _, ind in ipairs(indices) do
            table.insert(equip[slot], inv[ind])
        end
    end
    return equip
end

function EquipmentCombinationIterator:iterate()
    for slot in self:slot_iterator(true) do
        while self:iterate_equip_slot(slot) do
            if not self.extra_item or self.extra_used then
                return self:equip_set()
            end
        end
    end
end

function equip_combo_iter(inventory, extra_item)
    local iter = EquipmentCombinationIterator:new(inventory, extra_item)
    return function()
        return iter:iterate()
    end
end

function item_in_equip_set(item, equip)
    if not equip then
        return false
    end

    local slot = equip_slot(item)
    if not slot then
        return false
    end

    local name = item.name()
    for eq_item in equip_set_slot_iter(equip, slot) do
        if item.slot and item.slot == eq_item.slot
                or (not item.slot and name == eq_item.name()) then
            return true
        end
    end

    return false
end

function get_swappable_rings(upgrade)
    local swappable_rings = {}
    for _, ring in inventory_slot_iter("ring") do
        if can_swap_item(ring, upgrade) then
            table.insert(swappable_rings, ring)
        end
    end

    return swappable_rings
end

-- This only needs to give the max number of items that can be used for slots
-- the species can actually use.
function slot_max_items(slot)
    if slot == "weapon" then
        return you.race() == "Coglin" and 2 or 1
    elseif slot == "ring" then
        return you.race() == "Octopode" and 8 or 2
    else
        return 1
    end
end

function equip_letter_for_item(item, slot, keep_items, upgrade)
    if not item or item.equipped then
        return
    end

    local cur_equip = inventory_equip(const.inventory.equipped)
    if slot == "weapon"
            and item.hands == 2
            and cur_equip
            and cur_equip.shield then
        return
    end

    if slot == "boots"
            and you.mutation("mertail") > 0
            and (feat == "shallow_water" or feat == "deep_water") then
        return
    end

    if not cur_equip[slot] or #cur_equip[slot] < slot_max_items(slot) then
        return ""
    end

    for slot_item in equipped_slot_iter(slot) do
        if not item_in_equip_set(slot_item, keep_items)
                and can_swap_item(slot_item, upgrade) then
            return item_letter(slot_item)
        end
    end
end

function equip_item(item, slot, keep_items)
    local dest_letter = equip_letter_for_item(item, slot, keep_items, true)
    if not dest_letter then
        return false
    end

    local verb = "WEARING"
    local key = "W"
    if slot == "ring" or slot == "amulet" then
        key = "P"
    elseif slot == "weapon" then
        verb = "WIELDING"
        key = "w"
    end
    say(verb .. " " .. item.name())
    magic(key .. item_letter(item) .. dest_letter)
    return true
end

function unequip_item(item, slot)
    if not item or not item.equipped or not can_swap_item(item, true) then
        return false
    end

    local verb = "REMOVING"
    local key = "T"
    if slot == "ring" or slot == "amulet" then
        key = "R"
    end
    say(verb .. " " .. item.name())
    magic(key .. item_letter(item))
    return true
end

function reset_best_equip()
    c_persist.best_equip = nil
    qw.best_equip = nil
end

function update_equip_tracking()
    if not qw.inventory_equip then
        qw.inventory_equip = {}
    end

    local seen_counts = {}
    for _, item in inventory_slots_iter() do
        local name = item.name()
        local seen = seen_counts[name]
        if seen then
            seen = seen + 1
        else
            seen = 1
        end
        seen_counts[name] = seen

        local prev_count = qw.inventory_equip[name]
        if not prev_count or seen > prev_count then
            if debug_channel("items") then
                dsay("Resetting best equip due to new item: " .. name)
            end

            reset_best_equip()
        end
    end
    qw.inventory_equip = seen_counts

    local xl = you.xl()
    if qw.last_xl ~= xl then
        reset_best_equip()
    end
    qw.last_xl = xl

    update_skill_tracking()
end

function equip_is_valuable_unidentified(item)
    if item.fully_identified then
        return false
    elseif item.artefact then
        return true
    end

    local slot = equip_slot(item)
    if slot == "ring" or slot == "amulet" then
        return true
    end

    local name = item.name()
    if slot == "weapon" then
        return name:find("glowing") or name:find("runed")
    elseif slot == "body" then
        return name:find("glowing")
            or name:find("runed")
            or name:find("shiny")
            or name:find("dyed")
    else
        return name:find("glowing")
            or name:find("runed")
            or name:find("shiny")
            or name:find("embroidered")
    end
end
