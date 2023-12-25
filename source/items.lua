-------------------------------------
-- General item usage and autopickup

const.rune_suffix = " rune of Zot"
const.orb_name = "Orb of Zot"

function count_charges(wand_type, ignore_it)
    local count = 0
    for it in inventory() do
        if it.class(true) == "wand"
                and (not ignore_it or it.slot ~= ignore_it.slot)
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
    return not sub or sub == "digging"
end

function want_potion(it)
    local sub = it.subtype()
    if sub == nil then
        return true
    end

    local wanted = { "cancellation", "curing", "enlightenment", "experience",
        "heal wounds", "haste", "resistance", "might", "mutation",
        "cancellation" }

    if god_uses_mp() or future_gods_use_mp then
        table.insert(wanted, "magic")
    end

    if planning_tomb then
        table.insert(wanted, "lignification")
        table.insert(wanted, "attraction")
    end

    return util.contains(wanted, sub)
end

function want_scroll(it)
    local sub = it.subtype()
    if sub == nil then
        return true
    end

    local wanted = { "acquirement", "brand weapon", "enchant armour",
        "enchant weapon", "identify", "teleportation"}

    if planning_zig then
        table.insert(wanted, "blinking")
        table.insert(wanted, "fog")
    end

    return util.contains(wanted, sub)
end

function want_missile(it)
    if use_ranged_weapon() then
        return false
    end

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

function record_seen_item(level, name)
    if not c_persist.seen_items[level] then
        c_persist.seen_items[level] = {}
    end

    c_persist.seen_items[level][name] = true
end

function have_progression_item(name)
    return name:find(const.rune_suffix)
            and you.have_rune(name:gsub(const.rune_suffix, ""))
        or name == const.orb_name and have_orb
end

function autopickup(it, name)
    if not qw.initialized then
        return
    end

    local item_name = it.name()
    if item_name:find(const.rune_suffix) then
        record_seen_item(you.where(), item_name)
        return true
    elseif item_name == const.orb_name then
        record_seen_item(you.where(), item_name)
        c_persist.found_orb = true
        return true
    end

    if it.is_useless then
        return false
    end
    local class = it.class(true)
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

function letter_slot(letter)
    return items.letter_to_index(letter)
end

function slot_letter(slot)
    return items.index_to_letter(slot)
end

function item_letter(item)
    return slot_letter(item.slot)
end

function find_item(cls, name)
    return turn_memo_args("find_item",
        function(cls_arg, name_arg)
            for it in inventory() do
                if it.class(true) == cls_arg and it.name():find(name_arg) then
                    return it
                end
            end
        end, cls, name)
end

local missile_ratings = {
    ["boomerang"] = 1,
    ["javelin"] = 2,
    ["large rock"] = 3
}
function missile_rating(missile)
    for name, rating in pairs(missile_ratings) do
        if missile.name():find(name) then
            if missile.ego() then
                rating = rating + 0.5
            end

            return rating
        end
    end
end

function best_missile()
    return turn_memo("best_missile",
        function()
            local best_rating = 0
            local best_item
            for it in inventory() do
                local rating = missile_rating(it)
                if rating and rating > best_rating then
                    best_rating = rating
                    best_item = it
                end
            end
            return best_item
        end)
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
