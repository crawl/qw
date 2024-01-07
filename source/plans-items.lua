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

function zap_item(item, pos, aim_at_target)
    local cur_quiver = items.fired_item()
    local name = item.name()
    if not cur_quiver or name ~= cur_quiver.name() then
        magic("Q*" .. item_letter(item))
    end

    say("ZAPPING " .. name .. ".")
    return crawl.do_targeted_command("CMD_FIRE", pos.x, pos.y, aim_at_target)
end

function plan_wield_weapon()
    local weap = get_weapon()
    if is_weapon(weap)
            or weapon_skill() == "Unarmed Combat"
            or you.berserk()
            or transformed() then
        return false
    end

    for it in inventory() do
        if it and it.class(true) == "weapon" then
            if should_equip(it) then
                say("Wielding weapon " .. it.name() .. ".")
                magic("w" .. item_letter(it) .. "YY")
                -- this might have a 0-turn fail because of unIDed holy
                return nil
            end
        end
    end
    if weap and not is_melee_weapon(weap) then
        magic("w-")
        return true
    end

    return false
end

function plan_swap_weapon()
    local weapon = get_weapon()
    if you.race() == "Troll"
            or you.berserk()
            or transformed()
            or not weapon then
        return false
    end

    local sit
    local enemy_dist = qw.los_radius
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= 2 and string.find(enemy:desc(), "hydra") then
            sit = "hydra"
            break
        end
    end

    local twohands = true
    if items.equipped_at("Shield") and you.race() ~= "Formicid" then
        twohands = false
    end

    local it_old = get_weapon()
    local swappable = can_swap(it_old)
    if not swappable then
        return false
    end

    local max_val = weapon_value(it_old, true, it_old, sit)
    local max_it
    for it in inventory() do
        if it and it.class(true) == "weapon" and not it.equipped then
            if twohands or it.hands < 2 then
                local val2 = weapon_value(it, true, it_old, sit)
                if val2 > max_val then
                    max_val = val2
                    max_it = it
                end
            end
        end
    end
    if max_it then
        say("SWAPPING to " .. max_it.name() .. ".")
        magic("w" .. item_letter(max_it) .. "YY")
        return true
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

    local bestv = -1
    local minv, maxv, bestletter
    for it in inventory() do
        if equip_slot(it) == "Weapon" then
            minv, maxv = equip_value(it, true, nil, "bless")
            if minv > bestv then
                bestv = minv
                bestletter = item_letter(it)
            end
        end
    end
    if bestv > 0 then
        use_ability("Brand Weapon With Holy Wrath", bestletter .. "Y")
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

function plan_move_for_acquirement()
    if not can_read_acquirement()
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
    if c_persist.okawaru_weapon_gifted
            or you.god() ~= "Okawaru"
            or you.piety_rank() < 6
            or not contains_string_in("Receive Weapon", you.abilities())
            or not can_invoke() then
        return false
    end

    if use_ability("Receive Weapon") then
        c_persist.okawaru_weapon_gifted = true
        return true
    end

    return false
end

function plan_receive_okawaru_armour()
    if c_persist.okawaru_armour_gifted
            or you.god() ~= "Okawaru"
            or you.piety_rank() < 6
            or not contains_string_in("Receive Armour", you.abilities())
            or not can_invoke() then
        return false
    end

    if use_ability("Receive Armour") then
        c_persist.okawaru_armour_gifted = true
        return true
    end

    return false
end

function plan_maybe_pickup_acquirement()
    if acquirement_pickup then
        magic(",")
        acquirement_pickup = false
        return true
    end

    return false
end

function plan_upgrade_weapon()
    if acquirement_class == "Weapon" then
        acquirement_class = nil
    end

    if you.race() == "Troll" then
        return false
    end

    local twohands = not items.equipped_at("Shield")
        or you.race() == "Formicid"
    local it_old = get_weapon()
    swappable = can_swap(it_old, true)
    for it in inventory() do
        if it and it.class(true) == "weapon" and not it.equipped then
            if should_upgrade(it, it_old)
                    and swappable
                    and (twohands or it.hands < 2) then
                say("UPGRADING to " .. it.name() .. ".")
                magic("w" .. item_letter(it) .. "YY")
                return true
            elseif should_drop(it) then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. item_letter(it) .. "\r")
                return true
            end
        end
    end

    return false
end

function plan_remove_terrible_jewellery()
    if you.berserk() or transformed() then
        return false
    end
    for it in inventory() do
        if it and it.equipped and it.class(true) == "jewellery"
                    and not it.cursed
                    and should_remove(it) then
            say("REMOVING " .. it.name() .. ".")
            magic("P" .. item_letter(it) .. "YY")
            return true
        end
    end
    return false
end

function plan_maybe_upgrade_amulet()
    if acquirement_class ~= "Amulet" then
        return false
    end

    acquirement_class = nil
    return plan_upgrade_amulet()
end

function plan_upgrade_amulet()
    local it_old = items.equipped_at("Amulet")
    swappable = can_swap(it_old, true)
    for it in inventory() do
        if it and equip_slot(it) == "Amulet" and not it.equipped then
            local equip = false
            local drop = false
            if should_upgrade(it, it_old) then
                equip = true
            elseif should_drop(it) then
                drop = true
            end
            if equip and swappable then
                say("UPGRADING to " .. it.name() .. ".")
                magic("P" .. item_letter(it) .. "YY")
                return true
            end
            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. item_letter(it) .. "\r")
                return true
            end
        end
    end
    return false
end

function plan_maybe_upgrade_rings()
    if acquirement_class ~= "Ring" then
        return false
    end

    acquirement_class = nil
    return plan_upgrade_rings()
end

function plan_upgrade_rings()
    local it_rings = ring_list()
    local empty = empty_ring_slots() > 0
    for it in inventory() do
        if it and equip_slot(it) == "Ring" and not it.equipped then
            local equip = false
            local drop = false
            local swap
            if empty then
                if should_equip(it) then
                    equip = true
                end
            else
                for _, it_old in ipairs(it_rings) do
                    if not equip
                            and not it_old.cursed
                            and should_upgrade(it, it_old) then
                        equip = true
                        swap = it_old
                    end
                end
            end
            if not equip and should_drop(it) then
                drop = true
            end
            if equip then
                local letter = item_letter(it)
                say("UPGRADING to " .. it.name() .. ".")
                if swap then
                    items.swap_slots(swap.slot, letter_slot('Y'), false)

                    if letter == 'Y' then
                        letter = item_letter(swap)
                    end
                end
                magic("P" .. letter .. "YY")
                return true
            end
            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. item_letter(it) .. "\r")
                return true
            end
        end
    end
    return false
end

function plan_maybe_upgrade_armour()
    local acquire = false
    if acquirement_class ~= nil then
        for _, s in pairs(good_slots) do
            if acquirement_class == s then
                acquire = true
                break
            end
        end
    end

    if not upgrade_phase and not acquire then
        return false
    end

    if acquire then
        acquirement_class = nil
    end

    return plan_upgrade_armour()
end

function plan_upgrade_armour()
    if position_is_cloudy or you.mesmerised() then
        return false
    end

    for it in inventory() do
        if it and it.class(true) == "armour" and not it.equipped then
            local st, _ = it.subtype()
            local equip = false
            local drop = false
            local swappable
            local it_old = items.equipped_at(good_slots[st])
            local swappable = can_swap(it_old, true)
            if should_upgrade(it, it_old) then
                equip = true
            elseif should_drop(it) then
                drop = true
            end

            if good_slots[st] == "Helmet"
                   -- Proper helmet items restricted by one level of these
                   -- muts.
                   and (it.ac == 1
                           and (you.mutation("horns") > 0
                               or you.mutation("beak") > 0
                               or you.mutation("antennae") > 0)
                       -- All helmet slot items restricted by level three of
                       -- these muts.
                       or you.mutation("horns") >= 3
                       or you.mutation("antennae") >= 3) then
                equip = false
                drop = true
            elseif good_slots[st] == "Cloak"
                    and you.mutation("weakness stinger") >= 3 then
                equip = false
                drop = true
            elseif good_slots[st] == "Boots"
                    and (you.mutation("float") > 0
                        or you.mutation("talons") >= 3
                        or you.mutation("hooves") >= 3) then
                equip = false
                drop = true
            elseif good_slots[st] == "Boots"
                    and you.mutation("mertail") > 0
                    and (view.feature_at(0, 0) == "shallow_water"
                        or view.feature_at(0, 0) == "deep_water") then
                equip = false
                drop = false
            elseif good_slots[st] == "Gloves"
                    and (you.mutation("claws") >= 3
                        or you.mutation("demonic touch") >= 3) then
                equip = false
                drop = true
            end

            if equip and swappable then
                say("UPGRADING to " .. it.name() .. ".")
                magic("W" .. item_letter(it) .. "YN")
                upgrade_phase = true
                return true
            end

            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. item_letter(it) .. "\r")
                return true
            end
        end
    end
    for it in inventory() do
        if it and it.equipped
                and it.class(true) == "armour"
                and not it.cursed
                and should_remove(it) then
            say("REMOVING " .. it.name() .. ".")
            magic("T" .. item_letter(it) .. "YN")
            return true
        end
    end
    return false
end

function plan_unwield_weapon()
    if weapon_skill() ~= "Unarmed Combat"
           or not items.equipped_at("Weapon") then
        return false
    end

    magic("w-")
    return true
end

function body_armour_is_great(arm)
    local name = arm.name()
    local ap = armour_plan()
    if ap == "heavy" then
        return (name:find("gold dragon") or name:find("crystal plate")
                        or name:find("plate armour of fire")
                        or name:find("pearl dragon"))
    elseif ap == "large" then
        return name:find("dragon scales")
    elseif ap == "dodgy" then
        return arm.encumbrance <= 11 and name:find("dragon scales")
    else
        return name:find("dragon scales") or name:find("robe of resistance")
    end
end

function body_armour_is_good(arm)
    if in_branch("Zot") then
        return true
    end

    local name = arm.name()
    local ap = armour_plan()
    if ap == "heavy" then
        return name:find("plate") or name:find("dragon scales")
    elseif ap == "large" then
        return false
    elseif ap == "dodgy" then
        return name:find("ring mail") or name:find("robe of resistance")
    else
        return name:find("robe of resistance")
            or name:find("robe of fire resistance")
            or name:find("troll leather armour")
    end
end

-- Do we want to keep this brand?
function brand_is_great(brand)
    if brand == "speed"
            or brand == "spectralizing"
            or brand == "holy wrath" then
        return true
    -- The best that brand weapon can give us for ranged weapons.
    elseif brand == "heavy" and use_ranged_weapon() then
        return true
    -- The best that brand weapon can give us for melee weapons. No longer as
    -- good once we have the ORB. XXX: Nor if we're only doing undead or demon
    -- branches from now on.
    elseif brand == "vampirism" then
        return not have_orb
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

    local weapon = get_weapon()
    -- Prefer enchanting our wielded weapon.
    if weapon and weapon.is_enchantable then
        return weapon
    end

    if not unknown then
        return
    end

    for item in inventory() do
        if item.class(true) == "weapon" and item.is_enchantable then
            return item
        end
    end
end

function get_brandable_weapon(unknown)
    if unknown == nil then
        unknown = true
    end

    local weapon = get_weapon()
    -- Prefer enchanting our wielded weapon.
    if weapon
            and not weapon.artefact
            and not brand_is_great(weapon.ego()) then
        return weapon
    end

    if not unknown then
        return
    end

    for item in inventory() do
        if item.class(true) == "weapon"
                and not item.artefact
                and not brand_is_great(item.ego()) then
            return item
        end
    end
end

function get_enchantable_armour(unknown)
    if unknown == nil then
        unknown = true
    end

    -- Prefer enchanting body armour if it's of sufficient quality.
    local body_armour = items.equipped_at("Body Armour")
    if body_armour
            and body_armour.is_enchantable
            and body_armour_is_great(body_armour) then
        return body_armour
    end

    -- This item will not be what we'd prefer to enchant, but we'll use this
    -- target if we read-id the scroll.
    for _, slotname in pairs(good_slots) do
        local armour = items.equipped_at(slotname)

        -- We prefer not to enchant shields, but will use one as a fallback if
        -- we're using a shield.
        if unknown
                and not fallback_armour
                and slotname == "Shield"
                and armour
                and armour.is_enchantable then
            fallback_armour = armour
        end

        if armour and armour.is_enchantable
                and slotname ~= "Body Armour"
                and slotname ~= "Shield" then
            -- Prefer not to enchant items with negative enchant.
            if armour.plus >= 0 then
                return armour
            elseif unknown and not fallback_armour then
                fallback_armour = armour
            end

            if slotname == "Boots" and armour.name():find("barding") then
                if armour.plus >= 0 then
                    return armour
                elseif unknown and not fallback_armour then
                    fallback_armour = armour
                end
            end
        end
    end

    if body_armour
            and body_armour.is_enchantable
            and body_armour_is_good(body_armour) then
        return body_armour
    end

    if not unknown then
        return
    end

    if fallback_armour then
        return fallback_armour
    end

    for item in inventory() do
        if item.is_enchantable then
            return item
        end
    end
end

function plan_use_good_consumables()
    local read_ok = can_read()
    local drink_ok = can_drink()
    for it in inventory() do
        if read_ok and it.class(true) == "scroll" then
            if it.name():find("acquirement")
                    and not destroys_items_at(const.origin) then
                read_scroll(it)
                return true
            elseif it.name():find("enchant weapon")
                    and get_enchantable_weapon(false) then
                read_scroll(it)
                return true
            elseif it.name():find("brand weapon")
                    and get_brandable_weapon(false) then
                read_scroll(it)
                return true
            elseif it.name():find("enchant armour")
                    and get_enchantable_armour(false) then
                read_scroll(it)
                return true
            end
        elseif drink_ok and it.class(true) == "potion" then
            if it.name():find("experience") then
                drink_potion(it)
                return true
            end

            if it.name():find("mutation") and want_cure_mutations() then
                drink_potion(it)
                return true
            end
        end
    end

    return false
end

function plan_drop_other_items()
    upgrade_phase = false
    for it in inventory() do
        if it.class(true) == "missile" and not want_missile(it)
                or it.class(true) == "wand" and not want_wand(it)
                or it.class(true) == "potion" and not want_potion(it)
                or it.class(true) == "scroll" and not want_scroll(it) then
            say("DROPPING " .. it.name() .. ".")
            magic("d" .. item_letter(it) .. "\r")
            return true
        end
    end

    return false
end

function quaff_unided_potion(min_quantity)
    for it in inventory() do
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
    if not can_drink() then
        return false
    end

    return quaff_unided_potion(2)
end

function read_unided_scroll()
    for item in inventory() do
        if item.class(true) == "scroll" and not item.fully_identified then
            read_scroll(item, ".Y")
            return true
        end
    end

    return false
end

function plan_read_unided_scrolls()
    if not can_read() then
        return false
    end

    return read_unided_scroll()
end

function plan_use_identify_scrolls()
    if not can_read() then
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
    if view.feature_at(0, 0) ~= "enter_shop" or free_inventory_slots() == 0 then
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
                magic("<//" .. slot_letter(n - 1) .. "\ry")
                return
            -- Should in theory also work in Bazaar, but doesn't make much
            -- sense (since we won't really return or acquire money and travel
            -- back here)
            elseif not on_list
                 and not in_branch("Bazaar") and not branch_soon("Zot") then
                say("SHOPLISTING " .. it.name() .. " (" .. price .. " gold"
                 .. ", have " .. wealth .. ").")
                magic("<//" .. string.upper(slot_letter(n - 1)))
                return
            end
        elseif on_list then
            -- We no longer want the item. Remove it from shopping list.
            magic("<//" .. string.upper(slot_letter(n - 1)))
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

    magic("$" .. slot_letter(which_item - 1))
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
        {plan_move_for_acquirement, "move_for_acquirement"},
        {plan_receive_okawaru_weapon, "receive_okawaru_weapon"},
        {plan_receive_okawaru_armour, "receive_okawaru_armour"},
        {plan_maybe_pickup_acquirement, "try_pickup_acquirement"},
        {plan_maybe_upgrade_armour, "maybe_upgrade_armour"},
        {plan_maybe_upgrade_amulet, "maybe_upgrade_amulet"},
        {plan_maybe_upgrade_rings, "maybe_upgrade_rings"},
    }
end

function c_choose_acquirement()
    local acq_items = items.acquirement_items(const.acquire.scroll)

    -- These categories should be in order of preference.
    local wanted = {"weapon", "armour", "jewellery", "gold"}
    local item_ind = {}
    for _, c in ipairs(wanted) do
        item_ind[c] = 0
    end

    for i, item in ipairs(acq_items) do
        if debug_channel("items") then
            dsay("Offered " .. item.name(), true)
        end

        local class = item.class(true)
        if item_ind[class] ~= nil then
            item_ind[class] = i
        end
    end

    for _, c in ipairs(wanted) do
        local ind = item_ind[c]
        if ind > 0 then
            local item = acq_items[ind]
            if autopickup(item, item.name()) then
                say("ACQUIRING " .. item.name())
                acquirement_class = equip_slot(item)
                acquirement_pickup = true
                return ind
            end
        end
    end

    -- If somehow we didn't find anything, pick the first item and move on.
    say("GAVE UP ACQUIRING")
    return 1
end

function c_choose_okawaru_weapon()
    local best_val = -1000
    local best_ind, best_item
    local cur_weapon = get_weapon()
    local acq_items = items.acquirement_items(const.acquire.okawaru_weapon)
    for i, item in ipairs(acq_items) do
        local val = equip_value(item, true, cur_weapon)

        if debug_channel("items") then
            dsay("Offered " .. item.name() .. " with value " .. tostring(val),
                true)
        end

        if val > best_val then
            best_val = val
            best_ind = i
            best_item = item
        end
    end

    -- If somehow we didn't find anything, pick the first item and move on.
    if not best_ind then
        say("GAVE UP ACQUIRING OKAWARU WEAPON")
        return 1
    end

    say("ACQUIRING " .. best_item.name())
    acquirement_class = equip_slot(best_item)
    acquirement_pickup = true
    return best_ind
end

function equip_value_difference(item, cur_vals)
    local subtype = item.subtype()
    local cur_item = items.equipped_at(good_slots[subtype])
    local val = equip_value(item, true, cur_item)
    if val < 0 then
        return
    end

    if not cur_vals[subtype] then
        local cur_val = 0
        if cur_item then
            cur_val = equip_value(cur_item, true, cur_item)
        end
        cur_vals[subtype] = cur_val
    end

    return val - cur_vals[subtype]
end

function c_choose_okawaru_armour()
    local cur_vals = {}
    local best_diff, best_int, best_item
    local acq_items = items.acquirement_items(const.acquire.okawaru_armour)
    for i, item in ipairs(acq_items) do
        local diff = equip_value_difference(item, cur_vals)

        if debug_channel("items") then
            dsay("Offered " .. item.name() .. " with value difference "
                .. tostring(diff), true)
        end

        if diff and (not best_diff or diff > best_diff) then
            best_diff = diff
            best_ind = i
            best_item = item
        end
    end

    -- If somehow we didn't find anything, pick the first item and move on.
    if not best_ind then
        say("GAVE UP ACQUIRING OKAWARU ARMOUR")
        return 1
    end

    say("ACQUIRING " .. best_item.name())
    acquirement_class = equip_slot(best_item)
    acquirement_pickup = true
    return best_ind
end

function get_unidentified_item()
    local id_item
    for item in inventory() do
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

function c_choose_controlled_blink()
end
