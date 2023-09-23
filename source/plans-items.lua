------------------
-- Plans for using items, including the acquirement plan cascade.

function read(c, etc)
    if not can_read() then
        return false
    end

    if not etc then
        etc = ""
    end
    say("READING " .. item(c).name() .. ".")
    magic("r" .. letter(c) .. etc)
    return true
end

function drink(c)
    if not can_drink() then
        return false
    end

    say("DRINKING " .. item(c).name() .. ".")
    magic("q" .. letter(c))
    return true
end

function selfzap(c)
    if not can_zap() then
        return false
    end
    say("ZAPPING " .. item(c).name() .. ".")
    magic("V" .. letter(c) .. ".")
    return true
end

function read_by_name(name)
    local c = find_item("scroll", name)
    if (c and read(c)) then
        return true
    end
    return false
end

function drink_by_name(name)
    local c = find_item("potion", name)
    if (c and drink(c)) then
        return true
    end
    return false
end

function selfzap_by_name(name)
    local c = find_item("wand", name)
    if (c and selfzap(c)) then
        return true
    end
    return false
end

function teleport()
    return read_by_name("teleportation")
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
                magic("w" .. items.index_to_letter(it.slot) .. "YY")
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

    local exploding_weapon = weapon_is_exploding(weapon)
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
        magic("w" .. items.index_to_letter(max_it.slot) .. "YY")
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
                bestletter = letter(it)
            end
        end
    end
    if bestv > 0 then
        use_ability("Brand Weapon With Holy Wrath", bestletter .. "Y")
        return true
    end

    return false
end

function plan_receive_weapon()
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

function plan_receive_armour()
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
                magic("w" .. items.index_to_letter(it.slot) .. "YY")
                return true
            elseif should_drop(it) then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. items.index_to_letter(it.slot) .. "\r")
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
            magic("P" .. letter(it) .. "YY")
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
                magic("P" .. items.index_to_letter(it.slot) .. "YY")
                return true
            end
            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. items.index_to_letter(it.slot) .. "\r")
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
            local swap = nil
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
                        swap = it_old.slot
                    end
                end
            end
            if not equip and should_drop(it) then
                drop = true
            end
            if equip then
                local l = items.index_to_letter(it.slot)
                say("UPGRADING to " .. it.name() .. ".")
                if swap then
                    items.swap_slots(swap, items.letter_to_index('Y'), false)
                    if l == 'Y' then
                        l = items.index_to_letter(swap)
                    end
                end
                magic("P" .. l .. "YY")
                return true
            end
            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. items.index_to_letter(it.slot) .. "\r")
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
                magic("W" .. items.index_to_letter(it.slot) .. "YN")
                upgrade_phase = true
                return true
            end

            if drop then
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. items.index_to_letter(it.slot) .. "\r")
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
            magic("T" .. items.index_to_letter(it.slot) .. "YN")
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
        return (name:find("plate") or name:find("dragon scales"))
    elseif ap == "large" then
        return false
    elseif ap == "dodgy" then
        return (name:find("ring mail") or name:find("robe of resistance"))
    else
        return name:find("robe of resistance")
            or name:find("robe of fire resistance")
    end
end

-- do we want to keep this brand?
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

function plan_use_good_consumables()
    for it in inventory() do
        if it.class(true) == "scroll" and can_read() then
            if it.name():find("acquirement")
                    and not destroys_items_at(const.origin) then
                if read(it) then
                    return true
                end
            elseif it.name():find("enchant weapon") then
                local weapon = items.equipped_at("weapon")
                if weapon and weapon.class(true) == "weapon"
                        and not weapon.artefact and weapon.plus < 9 then
                    local oldname = weapon.name()
                    if read(it, letter(weapon)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
            elseif it.name():find("brand weapon") then
                local weapon = items.equipped_at("weapon")
                if weapon and weapon.class(true) == "weapon"
                        and not weapon.artefact
                        and not brand_is_great(weapon.ego()) then
                    local oldname = weapon.name()
                    if read(it, letter(weapon)) then
                        say("BRANDING " .. oldname .. ".")
                        return true
                    end
                end
            elseif it.name():find("enchant armour") then
                local body = items.equipped_at("Body Armour")
                local ac = armour_ac()
                if body and not body.artefact
                        and body.plus < ac
                        and body_armour_is_great(body)
                        and not body.name():find("quicksilver") then
                    local oldname = body.name()
                    if read(it, letter(body)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
                for _, slotname in pairs(good_slots) do
                    if slotname ~= "Body Armour" and slotname ~= "Shield" then
                        local it2 = items.equipped_at(slotname)
                        if it2 and not it2.artefact
                                and it2.plus < 2
                                and it2.plus >= 0
                                and not it2.name():find("scarf") then
                            local oldname = it2.name()
                            if read(it, letter(it2)) then
                                say("ENCHANTING " .. oldname .. ".")
                                return true
                            end
                        end
                        if slotname == "Boots"
                                and it2
                                and it2.name():find("barding")
                                and not it2.artefact
                                and it2.plus < 4
                                and it2.plus >= 0 then
                            local oldname = it2.name()
                            if read(it, letter(it2)) then
                                say("ENCHANTING " .. oldname .. ".")
                                return true
                            end
                        end
                    end
                end
                if body and not body.artefact
                        and body.plus < ac
                        and body_armour_is_good(body)
                        and not body.name():find("quicksilver") then
                    local oldname = body.name()
                    if read(it, letter(body)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
            end
        elseif it.class(true) == "potion" then
            if it.name():find("experience") then
                return drink(it)
            end

            if it.name():find("mutation") and want_cure_mutations() then
                return drink(it)
            end
        end
    end

    return false
end

function plan_drop_other_items()
    upgrade_phase = false
    for it in inventory() do
        if it.class(true) == "missile" and not want_missile(it) or
             it.class(true) == "wand" and not want_wand(it) or
             it.class(true) == "potion" and not want_potion(it) or
             it.class(true) == "scroll" and not want_scroll(it) then
            say("DROPPING " .. it.name() .. ".")
            magic("d" .. letter(it) .. "\r")
            return true
        end
    end

    return false
end

function plan_quaff_id()
    for it in inventory() do
        if it.class(true) == "potion" and it.quantity > 1 and
             not it.fully_identified then
            return drink(it)
        end
    end
    return false
end

function plan_read_id()
    if not can_read() then
        return false
    end

    for it in inventory() do
        if it.class(true) == "scroll" and not it.fully_identified then
            items.swap_slots(it.slot, items.letter_to_index('Y'), false)
            weap = items.equipped_at("Weapon")
            scroll_letter = 'Y'
            if weap and not weap.artefact
                    and not brand_is_great(weap.ego()) then
                scroll_letter = items.index_to_letter(weap.slot)
                items.swap_slots(weap.slot, items.letter_to_index('Y'), false)
            end
            if you.race() ~= "Felid" then
                return read(scroll_letter, ".Y" .. string.char(27) .. "YB")
            else
                return read(scroll_letter, ".Y" .. string.char(27) .. "YC")
            end
        end
    end

    return false
end

function plan_use_id_scrolls()
    if not can_read() then
        return false
    end

    local id_scroll
    for it in inventory() do
        if it.class(true) == "scroll" and it.name():find("identify") then
            id_scroll = it
            break
        end
    end
    if not id_scroll then
        return false
    end

    local count = 0
    if id_scroll.quantity > 1 then
        for it in inventory() do
            if it.class(true) == "potion" and not it.fully_identified then
                oldname = it.name()
                if read(id_scroll, letter(it)) then
                    say("IDENTIFYING " .. oldname)
                    return true
                end
            end
        end
    end

    return false
end

function want_to_buy(it)
    local class = it.class(true)
    if class == "missile" then
        return false
    elseif class == "scroll" then
        local sub = it.subtype()
        if sub == "identify" and count_item("scroll",sub) > 9 then
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
                magic("<//" .. letter(n - 1) .. "\ry")
                return
            -- Should in theory also work in Bazaar, but doesn't make much
            -- sense (since we won't really return or acquire money and travel
            -- back here)
            elseif not on_list
                 and not in_branch("Bazaar") and not branch_soon("Zot") then
                say("SHOPLISTING " .. it.name() .. " (" .. price .. " gold"
                 .. ", have " .. wealth .. ").")
                magic("<//" .. string.upper(letter(n - 1)))
                return
            end
        elseif on_list then
            -- We no longer want the item. Remove it from shopping list.
            magic("<//" .. string.upper(letter(n - 1)))
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

    magic("$" .. letter(which_item - 1))
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
            dsay("Offered " .. item:name(), true)
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
    local cur_weapon = get_weapon()
    local acq_items = items.acquirement_items(const.acquire.okawaru_weapon)

    local best_val = -1000
    local best_ind, best_item
    for i, item in ipairs(acq_items) do
        local val = equip_value(item, true, cur_weapon)

        if debug_channel("items") then
            dsay("Offered " .. item:name() .. " with value " .. tostring(val),
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
    if val == -1000 then
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
    local cur_weapon = get_weapon()
    local acq_items = items.acquirement_items(const.acquire.okawaru_armour)

    local cur_vals = {}
    local best_diff, best_int, best_item
    for i, item in ipairs(acq_items) do
        local diff = equip_value_difference(item, cur_vals)

        if debug_channel("items") then
            dsay("Offered " .. item:name() .. " with value difference "
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
