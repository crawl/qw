------------------
-- Plans for using items, including the acquirement plan cascade.

function read_scroll(item, etc)
    if not etc then
        etc = ""
    end

    say("READING " .. item.name() .. ".")
    magic("r" .. item_letter(item) .. etc)
end

function read_scroll_by_name(name, etc)
    local item = find_item("scroll", name)
    if item then
        read_scroll(item, etc)
        return true
    end

    return false
end

function drink_potion(item)
    say("DRINKING " .. item.name() .. ".")
    magic("q" .. item_letter(item))
end

function drink_by_name(name)
    local potion = find_item("potion", name)
    if potion then
        drink_potion(potion)
        return true
    end

    return false
end

function teleport()
    return read_scroll_by_name("teleportation")
end

function dangerous_hydra_distance()
    if you.xl() >= 18 or hydra_melee_value() > 0 then
        return
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:is_real_hydra() then
            return enemy:distance()
        end
    end
end

function best_hydra_swap_weapon()
    local best_weapon, best_value
    local cur_weapons = inventory_equip(const.inventory.equipped).weapon
    for weapon in inventory_slot_iter("weapon") do
        if equip_letter_for_item(weapon, "weapon") then
            local value = equip_value(weapon, true, cur_weapons, "hydra")
            if value > 0 and (not best_value or value > best_value) then
                best_weapon = weapon
                best_value = value
            end
        end
    end
    return best_weapon
end

function plan_wield_weapon()
    if unable_to_swap_weapons() then
        return false
    end

    local hydra_dist = dangerous_hydra_distance()
    if hydra_dist and hydra_dist <= 2 then
        return equip_item(best_hydra_swap_weapon(), "weapon")
    end

    local best_equip = best_equip_set()
    for weapon in equip_set_slot_iter(best_equip, "weapon") do
        if equip_item(weapon, "weapon", best_equip) then
            return true
        end
    end

    return false
end

function plan_bless_weapon()
    if you.god() ~= "the Shining One"
            or you.one_time_ability_used()
            or you.piety_rank() < 6
            or not can_invoke() then
        return false
    end

    local cur_equip = inventory_equip(const.inventory.equipped)
    local best_weapon, best_value
    for weapon in inventory_slot_iter("weapon") do
        local value = equip_value(weapon, true, cur_equip, "bless")
        if value > 0 and (not best_value or value > best_value) then
            best_weapon = item
            best_value = value
        end
    end

    if best_weapon then
        use_ability("Brand Weapon With Holy Wrath", item_letter(best_weapon))
        return true
    end

    return false
end

function can_receive_okawaru_weapon()
    return not c_persist.okawaru_weapon_gifted
        and you.god() == "Okawaru"
        and you.piety_rank() >= 6
        and contains_string_in("Receive Weapon", you.abilities())
        and can_invoke()
end

function can_receive_okawaru_armour()
    return not c_persist.okawaru_armour_gifted
        and you.god() == "Okawaru"
        and you.piety_rank() >= 6
        and contains_string_in("Receive Armour", you.abilities())
        and can_invoke()
end

function can_read_acquirement()
    return find_item("scroll", "acquirement") and can_read()
end

function can_invent_gizmo()
    return not c_persist.invented_gizmo
        and you.xl() >= 14
        and contains_string_in("Invent Gizmo", you.abilities())
end

function plan_move_for_acquirement()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_read_acquirement()
                and not can_receive_okawaru_weapon()
                and not can_receive_okawaru_armour()
            or not destroys_items_at(const.origin)
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    for pos in radius_iter(const.origin, qw.los_radius) do
        local map_pos = position_sum(qw.map_pos, pos)
        if map_is_reachable_at(map_pos) and not destroys_items_at(pos) then
            local result = best_move_towards(map_pos)
            if result and move_to(result.move) then
                return true
            end
        end
    end

    return false
end

function plan_receive_okawaru_weapon()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_receive_okawaru_weapon() then
        return false
    end

    if use_ability("Receive Weapon") then
        c_persist.okawaru_weapon_gifted = true
        return true
    end

    return false
end

function plan_receive_okawaru_armour()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_receive_okawaru_armour() then
        return false
    end

    if use_ability("Receive Armour") then
        c_persist.okawaru_armour_gifted = true
        return true
    end

    return false
end

function plan_invent_gizmo()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_invent_gizmo() then
        return false
    end

    if use_ability("Invent Gizmo") then
        c_persist.invented_gizmo = true
        return true
    end

    return false
end

function plan_maybe_pickup_acquirement()
    if qw.acquirement_pickup then
        magic(",")
        qw.acquirement_pickup = false
        return true
    end

    return false
end

function plan_upgrade_weapon()
    if unable_to_wield_weapon() or you.race() == "Troll" then
        return false
    end

    local best_equip = best_equip_set()
    for weapon in equip_set_slot_iter(best_equip, "weapon") do
        if equip_item(weapon, "weapon", best_equip) then
            return true
        end
    end

    return false
end

function plan_remove_shield()
    if you.race() == "Felid" then
        return false
    end

    local best_equip = best_equip_set()
    for shield in equipped_slot_iter("shield") do
        if not item_in_equip_set(shield, best_equip)
                and unequip_item(shield) then
            return true
        end
    end

    return false
end

function plan_wear_shield()
    if you.race() == "Felid" then
        return false
    end

    local best_equip = best_equip_set()
    for shield in equip_set_slot_iter(best_equip, "shield") do
        if equip_item(shield, "shield", best_equip) then
            return true
        end
    end

    return false
end

function plan_remove_terrible_rings()
    if you.berserk()
            or (you.strength() > 0
                and you.intelligence() > 0
                and you.dexterity() > 0) then
        return false
    end

    local equip = best_equip_set()
    local worst_ring, worst_value = equip_set_value_search(equip,
        function(item)
            return item.equipped
                and equip_slot(item) == "ring"
                and can_swap_item(item, true)
        end, true)
    if not worst_ring or worst_value >= 0 then
        return false
    end

    say("REMOVING " .. worst_ring.name() .. ".")
    magic("R" .. item_letter(worst_ring))
    return true
end

function plan_upgrade_equipment()
    if qw.danger_in_los or not qw.position_is_safe then
        return false
    end

    local best_equip = best_equip_set()
    for slot, item in equip_set_iter(best_equip, const.upgrade_slots) do
        if equip_item(item, slot, best_equip) then
            return true
        end
    end

    return false
end

function plan_remove_equipment()
    if qw.danger_in_los or not qw.position_is_safe then
        return false
    end

    local best_equip = best_equip_set()
    for slot, item in equipped_slots_iter(const.upgrade_slots) do
        if not item_in_equip_set(item, best_equip)
                and unequip_item(item, slot) then
            return true
        end
    end

    return false
end

function plan_unwield_weapon()
    local best_equip = best_equip_set()
    for weapon in equipped_slot_iter("weapon") do
        if not item_in_equip_set(weapon, best_equip)
                and unequip_item(weapon, "weapon") then
            return true
        end
    end

    return false
end

-- Do we want to keep this brand?
function weapon_brand_is_great(weapon)
    local brand = weapon.ego()
    if brand == "speed"
            or brand == "spectralizing"
            or brand == "holy wrath"
                and (undead_or_demon_branch_soon() or future_tso) then
        return true
    -- The best that brand weapon can give us for ranged weapons.
    elseif brand == "heavy" and want_ranged_weapon() then
        return true
    -- The best that brand weapon can give us for melee weapons. No longer as
    -- good once we have the ORB. XXX: Nor if we're only doing undead or demon
    -- branches from now on.
    elseif brand == "vampirism" then
        return not qw.have_orb
    else
        return false
    end
end

function want_cure_mutations()
    return base_mutation("inhibited regeneration") > 0
            and you.race() ~= "Ghoul"
        or base_mutation("teleportitis") > 0
        or base_mutation("inability to drink after injury") > 0
        or base_mutation("inability to read after injury") > 0
        or base_mutation("deformed body") > 0
            and you.race() ~= "Naga"
            and you.race() ~= "Armataur"
            and (armour_plan() == "heavy"
                or armour_plan() == "large")
        or base_mutation("berserk") > 0
        or base_mutation("deterioration") > 1
        or base_mutation("frail") > 0
        or base_mutation("no potion heal") > 0
            and you.race() ~= "Vine Stalker"
        or base_mutation("heat vulnerability") > 0
            and (you.res_fire() < 0
                or you.res_fire() < 3
                    and (branch_soon("Zot") or branch_soon("Geh")))
        or base_mutation("cold vulnerability") > 0
            and (you.res_cold() < 0
                or you.res_cold() < 3 and branch_soon("Coc"))
end

function get_enchantable_weapon(unknown)
    if unknown == nil then
        unknown = true
    end

    local best_equip = best_equip_set()
    local slay_value = linear_property_value("Slay")
    local enchantable_weapon
    for weapon in inventory_slot_iter("weapon") do
        if weapon.is_enchantable then
            local equip = best_inventory_equip(weapon)
            if equip and equip.value > 0
                    and (not best_equip
                        or equip.value + slay_value > best_equip.value) then
                best_equip = equip
            end

            if unknown then
                enchantable_weapon = weapon
            end
        end
    end

    if not best_equip then
        return enchantable_weapon
    end

    -- Because of Coglins, we want to find the best of what may be two
    -- enchantable weapons.
    return equip_set_value_search(best_equip,
        function(item)
            return equip_slot(item) == "weapon" and item.is_enchantable
        end)
end

function get_brandable_weapon(unknown)
    if unknown == nil then
        unknown = true
    end

    local best_equip = best_equip_set()
    if not best_equip or not best_equip.weapon then
        return
    end

    local best_weapon = equip_set_value_search(best_equip,
        function(item)
            return equip_slot(item) == "weapon"
                and not item.artefact
                and not weapon_brand_is_great(item)
        end)
    if not unknown then
        return best_weapon
    end

    best_equip = nil
    local fallback_weapon
    for weapon in inventory_slot_iter("weapon") do
        if not weapon.artefact then
            fallback_weapon = weapon

            local equip = best_inventory_equip(weapon)
            if equip and equip.value > 0
                    and (not best_equip or equip.value > best_equip.value) then
                best_equip = equip
            end
        end
    end
    if best_equip then
        return equip_set_value_search(best_equip,
            function(item)
                return equip_slot(item) == "weapon"
                    and not item.artefact
            end)
    end

    return fallback_weapon
end

function body_armour_is_great_to_enchant(armour)
    local name = armour.name("base")
    local ap = armour_plan()
    if ap == "heavy" then
        return name == "gold dragon scales"
            or name == "crystal plate armour"
            or name == "plate armour" and item_property("rF", armour) > 0
            or name == "pearl dragon scales"
    elseif ap == "large" then
        return name:find("dragon scales")
    elseif ap == "dodgy" then
        return armour.encumbrance <= 11 and name:find("dragon scales")
    else
        return name:find("dragon scales")
            or name == "robe" and item_property("rF", armour) > 0
    end
end

function body_armour_is_good_to_enchant(armour)
    local name = armour.name("base")
    local ap = armour_plan()
    if ap == "heavy" then
        return name == "plate armour" or name:find("dragon scales")
    elseif ap == "large" then
        return false
    elseif ap == "dodgy" then
        return name == "ring mail"
            or name == "robe" and armour.ego() == "resistance"
    else
        return name == "robe" and item_property("rF", armour) > 0
            or name == "troll leather armour"
    end
end

function get_enchantable_armour(scroll_unknown)
    if scroll_unknown == nil then
        scroll_unknown = true
    end

    local best_equip = best_equip_set()
    local ac_value = linear_property_value("AC")
    local fallback_armour, body_armour
    local best_armour = equip_set_value_search(best_equip,
        function(item)
            if item.class(true) ~= "armour" or not item.is_enchantable then
                return false
            end

            local slot = equip_slot(item)
            return slot ~= "shield"
                and (slot ~= "body"
                    or body_armour_is_great_to_enchant(item))
        end)
    if best_armour then
        return best_armour
    end

    local body_armour
    if best_equip.body then
        body_armour = best_equip.body[1]
    end
    if body_armour
            and body_armour.is_enchantable
            and body_armour_is_good_to_enchant(body_armour) then
        return body_armour
    end

    local shield
    if best_equip.shield then
        shield = best_equip.shield[1]
    end
    if shield and shield.is_enchantable then
        return shield
    end

    if not unknown then
        return
    end

    for slot, armour in inventory_slot_iter(const.armour_slots) do
        if armour.is_enchantable then
            return armour
        end
    end
end

function plan_use_good_consumables()
    if qw.danger_in_los then
        return false
    end

    local read_ok = can_read()
    local drink_ok = can_drink()
    for item in inventory_iter() do
        if read_ok and item.class(true) == "scroll" then
            if item.name():find("acquirement")
                    and not destroys_items_at(const.origin) then
                read_scroll(item)
                return true
            elseif item.name():find("enchant weapon")
                    and get_enchantable_weapon(false) then
                read_scroll(item)
                return true
            elseif item.name():find("brand weapon")
                    and get_brandable_weapon(false) then
                read_scroll(item)
                return true
            elseif item.name():find("enchant armour")
                    and get_enchantable_armour(false) then
                read_scroll(item)
                return true
            end
        elseif drink_ok and item.class(true) == "potion" then
            if item.name():find("experience") then
                drink_potion(item)
                return true
            end

            if item.name():find("mutation") and want_cure_mutations() then
                drink_potion(item)
                return true
            end
        end
    end

    return false
end

function want_drop_item(item)
    local class = item.class(true)
    if class == "missile" and not want_missile(item)
            or class == "wand" and not want_wand(item)
            or class == "potion" and not want_potion(item)
            or class == "scroll" and not want_scroll(item) then
        return true
    end

    return equip_slot(item)
        and equip_is_dominated(item)
        and (not item.equipped or can_swap_item(item, true))
end

function plan_drop_items()
    if qw.danger_in_los or not qw.position_is_safe then
        return false
    end

    for item in inventory_iter() do
        if want_drop_item(item) then
            say("DROPPING " .. item.name() .. ".")
            magic("d" .. item_letter(item) .. "\r")
            return true
        end
    end

    return false
end

function quaff_unided_potion(min_quantity)
    for it in inventory_iter() do
        if it.class(true) == "potion"
                and (not min_quantity or it.quantity >= min_quantity)
                and not it.fully_identified then
            drink_potion(it)
            return true
        end
    end
    return false
end

function plan_quaff_unided_potions()
    if qw.danger_in_los or not qw.position_is_safe or not can_drink() then
        return false
    end

    return quaff_unided_potion(2)
end

function read_unided_scroll()
    for item in inventory_iter() do
        if item.class(true) == "scroll" and not item.fully_identified then
            read_scroll(item, ".Y")
            return true
        end
    end

    return false
end

function plan_read_unided_scrolls()
    if qw.danger_in_los or not qw.position_is_safe or not can_read() then
        return false
    end

    return read_unided_scroll()
end

function plan_use_identify_scrolls()
    if qw.danger_in_los or not qw.position_is_safe or not can_read() then
        return false
    end

    local id_scroll = find_item("scroll", "identify")
    if not id_scroll then
        return false
    end

    if not get_unidentified_item() then
        return false
    end

    read_scroll(id_scroll)
    return true
end

function want_to_buy(it)
    local class = it.class(true)
    if class == "missile" then
        return false
    elseif class == "scroll" then
        local sub = it.subtype()
        if sub == "identify" and count_item("scroll", sub) > 9 then
            return false
        end
    end
    return autopickup(it, it.name())
end

function shop_item_sort(i1, i2)
    return crawl.string_compare(i1[1].name(), i2[1].name()) < 0
end

function plan_shop()
    if qw.danger_in_los
            or view.feature_at(0, 0) ~= "enter_shop"
            or free_inventory_slots() == 0 then
        return false
    end
    if you.berserk() or you.caught() or you.mesmerised() then
        return false
    end

    local it, price, on_list
    local sitems = items.shop_inventory()
    table.sort(sitems, shop_item_sort)
    for n, e in ipairs(sitems) do
        it = e[1]
        price = e[2]
        on_list = e[3]

        if want_to_buy(it) then
            -- We want the item. Can we afford buying it now?
            local wealth = you.gold()
            if price <= wealth then
                say("BUYING " .. it.name() .. " (" .. price .. " gold).")
                magic("<//" .. items.index_to_letter(n - 1) .. "\ry")
                return
            -- Should in theory also work in Bazaar, but doesn't make much
            -- sense (since we won't really return or acquire money and travel
            -- back here)
            elseif not on_list
                 and not in_branch("Bazaar") and not branch_soon("Zot") then
                say("SHOPLISTING " .. it.name() .. " (" .. price .. " gold"
                 .. ", have " .. wealth .. ").")
                magic("<//" .. string.upper(items.index_to_letter(n - 1)))
                return
            end
        elseif on_list then
            -- We no longer want the item. Remove it from shopping list.
            magic("<//" .. string.upper(items.index_to_letter(n - 1)))
            return
        end
    end
    return false
end

function plan_shopping_spree()
    if unable_to_travel() or goal_status ~= "Shopping" then
        return false
    end

    which_item = can_afford_any_shoplist_item()
    if not which_item then
        -- Remove everything on shoplist.
        clear_out_shopping_list()
        -- Record that we are done shopping this game.
        c_persist.done_shopping = true
        update_goal()
        return false
    end

    magic("$" .. items.index_to_letter(which_item - 1))
    return true
end

-- Usually, this function should return `1` or `false`.
function can_afford_any_shoplist_item()

    local shoplist = items.shopping_list()

    if not shoplist then
        return false
    end

    local price
    for n, entry in ipairs(shoplist) do
        price = entry[2]
        -- Since the shopping list holds no reference to the item itself,
        -- we cannot check want_to_buy() until arriving at the shop.
        if price <= you.gold() then
            return n
        end
    end
    return false
end

-- Clear out shopping list if no affordable items are left before entering Zot
function clear_out_shopping_list()
    local shoplist = items.shopping_list()
    if not shoplist then
        return
    end

    say("CLEARING SHOPPING LIST")
    -- Press ! twice to toggle action to 'delete'
    local clear_shoplist_magic = "$!!"
    for n, it in ipairs(shoplist) do
        clear_shoplist_magic = clear_shoplist_magic .. "a"
    end
    magic(clear_shoplist_magic)
    qw.do_dummy_action = false
    coroutine.yield()
end

-- These plans will only execute after a successful acquirement.
function set_plan_acquirement()
    plans.acquirement = cascade {
        {plan_maybe_pickup_acquirement, "try_pickup_acquirement"},
        {plan_move_for_acquirement, "move_for_acquirement"},
        {plan_receive_okawaru_weapon, "receive_okawaru_weapon"},
        {plan_receive_okawaru_armour, "receive_okawaru_armour"},
        {plan_invent_gizmo, "invent_gizmo"},
    }
end

function choose_acquirement(acquire_type)
    local acq_items = items.acquirement_items(acquire_type)
    local cur_equip = inventory_equip(const.inventory.equipped)
    for _, item in ipairs(acq_items) do
        local min_val, max_val = equip_value(item)
        say("Offered " .. item.name() .. " with min/max values "
            .. tostring(min_val) .. "/" .. tostring(max_val))
    end

    local index = best_acquirement_index(acq_items)
    if index then
        if acquire_type ~= const.acquire.gizmo then
            qw.acquirement_pickup = true
        end

        say("ACQUIRING " .. acq_items[index].name())
        return index
    else
        say("GAVE UP ACQUIRING")
        return 1
    end
end

function c_choose_acquirement()
    return choose_acquirement(const.acquire.scroll)
end

function c_choose_okawaru_weapon()
    return choose_acquirement(const.acquire.okawaru_weapon)
end

function c_choose_okawaru_armour()
    return choose_acquirement(const.acquire.okawaru_armour)
end

function c_choose_coglin_gizmo()
    return choose_acquirement(const.acquire.gizmo)
end

function get_unidentified_item()
    local id_item
    for item in inventory_iter() do
        if item.class(true) == "potion"
                and not item.fully_identified
                -- Prefer identifying potions over scrolls and prefer
                -- identifying smaller stacks.
                and (not id_item
                    or id_item.class(true) ~= "potion"
                    or item.quantity < id_item.quantity) then
            id_item = item
        elseif item.class(true) == "scroll"
                and not item.fully_identified
                and (not id_item or id_item.class(true) ~= "potion")
                and (not id_item or item.quantity < id_item.quantity) then
            id_item = item
        end
    end

    return id_item
end

function c_choose_identify()
    local id_item = get_unidentified_item()
    if id_item then
        say("IDENTIFYING " .. id_item.name())
        return item_letter(id_item)
    end
end

function c_choose_brand_weapon()
    local weapon = get_brandable_weapon()
    if weapon then
        say("BRANDING " .. weapon:name() .. ".")
        return item_letter(weapon)
    end
end

function c_choose_enchant_weapon()
    local weapon = get_enchantable_weapon()
    if weapon then
        say("ENCHANTING " .. weapon:name() .. ".")
        return item_letter(weapon)
    end
end

function c_choose_enchant_armour()
    local armour = get_enchantable_armour()
    if armour then
        say("ENCHANTING " .. armour:name() .. ".")
        return item_letter(armour)
    end
end
