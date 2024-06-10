-------------------------------------
-- General item usage and autopickup

const.rune_suffix = " rune of Zot"
const.orb_name = "Orb of Zot"

const.wand_types = { "flame", "mindburst", "iceblast", "acid", "light",
    "quicksilver", "paralysis" }

function item_is_penetrating(item)
    if item.ego() == "penetration" or item.name():find("storm bow") then
        return true
    end

    local class = item.class(true)
    local subtype = item.subtype()
    return subtype == "javelin"
        or class == "wand"
            and (subtype == "acid"
                or subtype == "light"
                or subtype == "quicksilver")
end

function item_is_exploding(item)
    if item.name():find("{damnation}") then
        return true
    end

    if item.class(true) == "wand" then
        local subtype = item.subtype()
        return subtype == "iceblast" or subtype == "roots"
    end

    return false
end

function item_explosion_ignores_player(item)
    return item.name():find("{damnation}")
        or item.class(true) == "wand" and item.subtype() == "roots"
end

function item_range(item)
    if item.class(true) == "wand" then
        local subtype = item.subtype()
        if subtype == "acid"
                or subtype == "iceblast"
                or subtype == "light"
                or subtype == "roots" then
            return 5
        else
            return qw.los_radius
        end
    end

    return qw.los_radius
end

function item_can_target_empty(item)
    return item.class(true) == "wand" and item.subtype() == "iceblast"
end

function count_charges(wand_type)
    local count = 0
    for item in inventory_iter() do
        if item.class(true) == "wand" and item.subtype() == wand_type then
            count = count + item.plus
        end
    end
    return count
end

function want_wand(item)
    if you.mutation("inability to use devices") > 0 then
        return false
    end

    local subtype = item.subtype()
    if not subtype then
        return true
    end

    if not util.contains(const.wand_types, subtype) then
        return false
    end

    if subtype == "flame" then
        return you.xl() <= 8
    elseif subtype == "mindburst" then
        return you.xl() <= 17
    else
        return true
    end
end

function want_potion(item)
    local subtype = item.subtype()
    if not subtype then
        return true
    end

    local wanted = { "cancellation", "curing", "enlightenment", "experience",
        "heal wounds", "haste", "resistance", "might", "mutation",
        "cancellation" }

    if god_uses_mp() or qw.future_gods_use_mp then
        table.insert(wanted, "magic")
    end

    if qw.planning_tomb then
        table.insert(wanted, "lignification")
        table.insert(wanted, "attraction")
    end

    return util.contains(wanted, subtype)
end

function want_scroll(item)
    local subtype = item.subtype()
    if not subtype then
        return true
    end

    local wanted = { "acquirement", "brand weapon", "enchant armour",
        "enchant weapon", "identify", "teleportation"}

    if qw.planning_zig then
        table.insert(wanted, "blinking")
        table.insert(wanted, "fog")
    end

    return util.contains(wanted, subtype)
end

function want_missile(item)
    if item.is_useless or using_ranged_weapon(true) then
        return false
    end

    local st = item.subtype()
    return st == "boomerang" or st == "javelin" or st == "large rock"
end

function want_miscellaneous(item)
    local subtype = item.subtype()
    if subtype == "figurine of a ziggurat" then
        return qw.planning_zig
    end

    return false
end

function record_seen_item(level, name)
    if not c_persist.seen_items[level] then
        c_persist.seen_items[level] = {}
    end

    c_persist.seen_items[level][name] = true
end

function have_quest_item(name)
    return name:find(const.rune_suffix)
            and you.have_rune(name:gsub(const.rune_suffix, ""))
        or name == const.orb_name and qw.have_orb
end

function autopickup(item, name)
    if not qw.initialized or item.is_useless then
        return
    end

    reset_cached_turn_data()

    local class = item.class(true)
    if class == "gem" then
        return true
    elseif class == "rune" then
        record_seen_item(you.where(), item.name())
        return true
    elseif class == "orb" then
        record_seen_item(you.where(), item.name())
        c_persist.found_orb = true
        return goal_status == "Orb"
    end

    if equip_slot(item) then
        return not equip_is_dominated(item)
    elseif class == "gold" then
        return true
    elseif class == "potion" then
        return want_potion(item)
    elseif class == "scroll" then
        return want_scroll(item)
    elseif class == "wand" then
        return want_wand(item)
    elseif class == "missile" then
        return want_missile(item)
    elseif class == "misc" then
        return want_miscellaneous(item)
    else
        return false
    end
end

-----------------------------------------
-- item functions

function inventory_iter()
    return iter.invent_iterator:new(items.inventory())
end

function floor_item_iter()
    return iter.invent_iterator:new(you.floor_items())
end

function free_inventory_slots()
    local slots = 52
    for _ in inventory_iter() do
        slots = slots - 1
    end
    return slots
end

function item_letter(item)
    return items.index_to_letter(item.slot)
end

function get_item(letter)
    return items.inslot(items.letter_to_index(letter))
end

function find_item(cls, name)
    return turn_memo_args("find_item",
        function()
            for item in inventory_iter() do
                if item.class(true) == cls and item.name():find(name) then
                    return item
                end
            end
        end, cls, name)
end

function missile_damage(missile)
    if missile.class(true) ~= "missile"
            or missile:name():find("throwing net") then
        return
    end

    local damage = missile.damage
    if missile.ego() == "silver" then
        damage = damage * 7 / 6
    end

    return damage
end

function missile_quantity(missile)
    if missile.class(true) ~= "missile"
            or missile:name():find("throwing net") then
        return
    end

    return missile.quantity
end

function best_missile(value_func)
    return turn_memo_args("best_missile",
        function()
            local best_missile, best_value
            for item in inventory_iter() do
                local value = value_func(item)
                if value and (not best_value or value > best_value) then
                    best_missile = item
                    best_value = value
                end
            end
            return best_missile
        end, value_func)
end

function count_item(cls, name)
    local it = find_item(cls, name)
    if it then
        return it.quantity
    end

    return 0
end

function record_item_ident(item_type, item_subtype)
    if item_type == "potion" then
        c_persist.potion_ident[item_subtype] = true
    elseif item_type == "scroll" then
        c_persist.scroll_ident[item_subtype] = true
    end
end

function item_type_is_ided(item_type, subtype)
    if item_type == "potion" then
        return c_persist.potion_ident[subtype]
    elseif item_type == "scroll" then
        return c_persist.scroll_ident[subtype]
    end

    return false
end

function item_string(item)
    local name = item.name()
    local letter
    if item.slot then
        letter = item_letter(item)
    end
    return (letter and (letter .. " - ") or "") .. item.name()
        .. (item.equipped and " (equipped)" or "")
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
