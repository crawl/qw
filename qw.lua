{
-- some global variables:

local initialized = false
local time_passed
local update_coroutine
local do_dummy_action

local dump_count = you.turns() + 100 - (you.turns() % 100)
local skill_count = you.turns() - (you.turns() % 5)
local danger
local immediate_danger
local cloudy
local where
local where_shafted_from = nil
local expect_new_location
local expect_portal
local base_corrosion

local automatic = false

local ignore_list = { }
local failed_move = { }
local invisi_count = 0
local next_delay = 100

local sigmund_dx = 0
local sigmund_dy = 0
local invisi_sigmund = false

local sgd_timer = -200

local stuck_turns = 0

local stepped_on_lair = false
local stepped_on_tomb = false
local lair_step_mode = false

-- are these still necessary?
local did_move = false
local move_count = 0

local did_move_towards_monster = 0
local target_memory_x
local target_memory_y

local last_wait = 0
local wait_count = 0
local old_turn_count = you.turns()-1
local hiding_turn_count = -100

local travel_destination = nil
local game_status = "normal"

local have_message = false
local read_message = true

local monster_array
local enemy_list

local upgrade_phase = false
local acquirement_pickup = false
local acquirement_class = nil

local tactical_step
local tactical_reason

local is_waiting

local did_first_turn = false

local stairdance_count = {}
local clear_exclusion_count = {}
local v5_entry_turn
local tomb2_entry_turn
local tomb3_entry_turn

local last_swamp_fail_count = -1
local swamp_rune_reachable = false

local offlevel_travel = true

local last_min_delay_skill = 18

local only_linear_resists = false

local no_spells = false

local level_map
local stair_dists
local waypoint_parity
local cur_where
local prev_where
local did_waypoint = false
local good_stair_list
local target_stair
local last_flee_turn = -100

local ABYSSAL_RUNE = false
local SLIMY_RUNE = false
local PAN_RUNE = false
local HELL_RUNE = false
local GOLDEN_RUNE = false
local TSO_CONVERSION = false
local LUGONU_CONVERSION = false
local WILL_ZIG = false
local MIGHT_BE_GOOD = false
local endgame_plan_list = {}
local which_endgame_plan = 1
local dislike_pan_level = false

local prev_hatch_dist = 1000
local prev_hatch_x
local prev_hatch_y

-- options to set while qw is running
-- maybe should add more mutes for watchability

function set_options()
    crawl.setopt("pickup_mode = multi")
    crawl.setopt("message_colour += mute:Search for what")
    crawl.setopt("message_colour += mute:Can't find anything")
    crawl.setopt("message_colour += mute:Drop what")
    crawl.setopt("message_colour += mute:Okay, then")
    crawl.setopt("message_colour += mute:Use which ability")
    crawl.setopt("message_colour += mute:Read which item")
    crawl.setopt("message_colour += mute:Drink which item")
    crawl.setopt("message_colour += mute:not good enough")
    crawl.setopt("message_colour += mute:Attack whom")
    crawl.setopt("message_colour += mute:move target cursor")
    crawl.setopt("message_colour += mute:Aim:")
    crawl.setopt("message_colour += mute:You reach to attack")
    crawl.enable_more(false)
end

function unset_options()
    crawl.setopt("pickup_mode = auto")
    crawl.setopt("message_colour -= mute:Search for what")
    crawl.setopt("message_colour -= mute:Can't find anything")
    crawl.setopt("message_colour -= mute:Drop what")
    crawl.setopt("message_colour -= mute:Okay, then")
    crawl.setopt("message_colour -= mute:Use which ability")
    crawl.setopt("message_colour -= mute:Read which item")
    crawl.setopt("message_colour -= mute:Drink which item")
    crawl.setopt("message_colour -= mute:not good enough")
    crawl.setopt("message_colour -= mute:Attack whom")
    crawl.setopt("message_colour -= mute:move target cursor")
    crawl.setopt("message_colour -= mute:Aim:")
    crawl.setopt("message_colour -= mute:You reach to attack")
    crawl.enable_more(true)
end

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
--        = "extended", assume we are in (or about to enter) Pan if
--                      TSO_CONVERSION, we need this weapon to be TSO-friendly
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

-- Returns the amount of an artprop granted by an item - not all artprops are
-- currently handled here.
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
            elseif ego == "fire resistance" or ego == "resistance"
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
            if name:find("storm dragon") then
                return 1
            else
                return 0
            end
        elseif str == "rPois" then
            if ego == "poison resistance"
                    or subtype == "ring of poison resistance"
                    or name:find("swamp dragon")
                    or name:find("gold dragon") then
                return 1
            else
                return 0
            end
        elseif str == "rN" then
            if ego == "positive energy" or subtype == "ring of positive energy"
                 or name:find("pearl dragon") then
                return 1
            else
                return 0
            end
        elseif str == "Will" then
            if ego == "willpower" or subtype == "ring of willpower"
                 or name:find("quicksilver dragon") then
                return 1
            else
                return 0
            end
        elseif str == "rCorr" then
            if subtype == "ring of resist corrosion"
                    or name:find("acid dragon") then
                return 1
            else
                return 0
            end
        elseif str == "SInv" then
            if ego == "see invisible"
                    or subtype == "ring of see invisible" then
                return 1
            else
                return 0
            end
        elseif str == "Spirit" then
            if ego == "spirit shield"
                    or subtype == "amulet of guardian spirit" then
                return 1
            else
                return 0
            end
        elseif str == "Regen" then
             if name:find("troll leather")
                     or subtype == "amulet of regeneration" then
                 return 1
             else
                 return 0
             end
        elseif str == "Acrobat" then
             if subtype == "amulet of the acrobat" then
                 return 1
             else
                 return 0
             end
        elseif str == "Reflect" then
             if ego == "reflection" or subtype == "amulet of reflection" then
                 return 1
             else
                 return 0
             end
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
            if subtype == "ring of slaying" then
                return it.plus or 0
            end
        elseif str == "AC" then
            if subtype == "ring of protection" then
                return it.plus or 0
            -- Wrong for weapons, but we scale things differently for weapons.
            elseif ego == "protection" then
                return 3
            end
        elseif str == "EV" then
            if subtype == "ring of evasion" then
                return it.plus or 0
            end
        elseif str == "SH" then
            if subtype == "amulet of reflection" then
                return 5
            end
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
        if intrinsic_rpois() or (you.mutation("poison resistance") > 0) then
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
        if intrinsic_sinv() or (you.mutation("see invisible") > 0) then
            return 1
        else
            return 0
        end
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
    if slime_soon()
       and (str == "rF" or str == "rElec" or str == "rPois"
            or str == "rN" or str == "Will" or str == "SInv") then
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
        if str == "rF" and zot_soon() then
            val = val * 2.5
        elseif str == "rC" and slime_soon() then
            val = val * 1.5
        end
        return val
    elseif str == "rElec" then
        return 75
    elseif str == "rPois" then
        return easy_runes() < 2 and 225 or 75
    elseif str == "rN" then
        return 25 * n
    elseif str == "Will" then
        if n <= 2 then
            return 75 * n
        else
            return 200
        end
    elseif str == "rCorr" then
        return slime_soon() and 1200 or 50
    elseif str == "SInv" then
        return 200
    elseif str == "Spirit" then
        return 100
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
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
            val = 150
        elseif d == 2 then
            val = 275
        elseif d == 3 then
            val = 350
        end
        if str == "rF" then
            val = val * 2.5
        elseif str == "rC" and SLIMY_RUNE then
            val = val * 1.5
        end
        return val
    elseif str == "rElec" then
        return ires < 1 and 75 or 0
    elseif str == "rPois" then
        return ires < 1 and (easy_runes() < 2 and 225 or 75) or 0
    elseif str == "rN" then
        return ires < 3 and 25 * d or 0
    elseif str == "Will" then
        return 75 * d
    elseif str == "rCorr" then
        return ires < 1 and (SLIMY_RUNE and 1200 or 50) or 0
    elseif str == "SInv" then
        return ires < 1 and 200 or 0
    elseif str == "Spirit" then
        return ires < 1 and 100 or 0
    elseif str == "Acrobat" then
        return ires < 1 and 100 or 0
    elseif str == "Reflect" then
        return ires < 1 and 20 or 0
    end
    return 0
end

function min_resist_value(str, d)
    if d >= 0 then
        return 0
    end
    if str == "rF" then
        return -375
    elseif str == "rC" then
        return SLIMY_RUNE and -225 or -150
    elseif str == "Will" then
        return 75 * d
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
    end
    return 0
end

function total_resist_value(it, cur, it2)
    resistlist = { "rF", "rC", "rElec", "rPois", "rN", "Will", "rCorr", "SInv",
                   "Spirit", "Acrobat", "Reflect", "Str", "Dex", "Int" }
    linearlist = { "Str", "Dex", "Slay", "AC", "EV", "SH", "Regen" }
    local val = 0
    for _, str in ipairs(linearlist) do
        val = val + item_resist(str, it) * linear_resist_value(str)
    end
    local val1, val2 = val, val
    if not only_linear_resists then
        for _, str in ipairs(resistlist) do
            local a, b = resist_value(str, it, cur, it2)
            val1 = val1 + a
            val2 = val2 + b
        end
    end
    return val1, val2
end

function resist_vec(it)
    local resistlist = { "rF", "rC", "rElec", "rPois", "rN", "Will", "rCorr",
                         "SInv", "Spirit", "Acrobat", "Reflect" }
    local vec = { }
    for _, str in ipairs(resistlist) do
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

-- complicated check:
-- is it going to be worse than it2 no matter what other resists we have?
function resist_dominated(it, it2)
    local bmin, bmax = base_equip_value(it)
    local bmin2, bmax2 = base_equip_value(it2)
    local diff = bmin2 - bmax
    if diff < 0 then
        return false
    end
    local vec = resist_vec(it)
    local vec2 = resist_vec(it2)
    local l = #vec
    for i = 1, l do
        if vec[i] > vec2[i] then
            diff = diff - (vec[i] - vec2[i])
        end
    end
    return (diff >= 0)
end

function rune_goal()
    return 3 + (ABYSSAL_RUNE and 1 or 0) + (SLIMY_RUNE and 1 or 0)
        + (PAN_RUNE and 5 or 0) + (HELL_RUNE and 4 or 0)
        + (GOLDEN_RUNE and 1 or 0)
end

function easy_runes()
    return (you.have_rune("decaying") and 1 or 0)
                 + (you.have_rune("serpentine") and 1 or 0)
                 + (you.have_rune("barnacled") and 1 or 0)
                 + (you.have_rune("gossamer") and 1 or 0)
end

function update_game_status()
    if you.have_orb() then
        game_status = "orbrun"
        return
    end
    if game_status == "normal" and you.have_rune("silver")
         and not where:find("Vaults") and not where:find("Abyss") then
        game_status = "shopping"
    end
    if game_status == "shopping" and c_persist.done_shopping then
        game_status = endgame_plan_list[1]
    end
    while (game_status == "slime"
            and you.have_rune("slimy") and not where:find("Slime")
            or game_status == "pan" and have_pan_runes() and where ~= "Pan"
                and not where:find("Abyss")
            or game_status == "abyss" and you.have_rune("abyssal")
                and not where:find("Abyss"))
            or game_status == "hells" and have_hell_runes() and where ~= "Hell"
                and not where:find("Dis") and not where:find("Geh")
                and not where:find("Coc") and not where:find("Tar")
                and not where:find("Abyss")
            or game_status == "tomb" and you.have_rune("golden")
                and not where:find("Tomb") and not where:find("Abyss")
            or game_status == "tso" and you.god() == "the Shining One"
            or game_status == "zig" and c_persist.entered_zig
                and not where:find("Zig") do
        which_endgame_plan = which_endgame_plan + 1
        game_status = endgame_plan_list[which_endgame_plan]
    end
end

function zot_soon()
    return game_status == "zot"
end

function slime_soon()
    return game_status == "slime"
end

function in_extended()
    return game_status == "pan"
        or game_status == "hells"
        or game_status == "tomb"
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
        ap = it.artprops
        if ap and (ap["-Tele"] or ap["*Tele"])
                and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["*Rage"] and you.race() ~= "Mummy"
             and you.race() ~= "Ghoul" and you.race() ~= "Formicid" then
            return -1, -1
        end
        if name:find("Pondering") or name:find("hauberk") then
            return -1, -1
        end
        if ap and ap["Fragile"] then
            return -1, -1
        end
        if ap and ap["*Slow"] and you.race() ~= "Formicid" then
            value = value - 100
        end
        if ap and ap["*Corrode"] then
            value = value - 100
        end
        if ap and ap["Harm"] then
            return -1, -1
        end
    elseif name:find("runed") or name:find("glowing") or name:find("dyed")
            or name:find("embroidered") or name:find("shiny") then
        val2 = val2 + 400
        val1 = val1 + (cur and 400 or -200)
    elseif ego then -- names in armour_ego_name()
        if ego == "running" then
            value = value + 25
            if you.god() == "Cheibriados" then
                return -1, -1
            end
        elseif ego == "flying" and not intrinsic_amphibious_or_flight() then
            value = value + 200
        elseif ego == "ponderousness" or ego == "harm" then
            return -1, -1
        elseif ego == "repulsion" then
            value = value + 200
        end
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
        or extended and TSO_CONVERSION
        or you.god() == "Elyvilon"
        or you.god() == "Zin"
        or you.god() == "No God" and MIGHT_BE_GOOD
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
    if it.artefact then
        ap = it.artprops
        if ap and (ap["-Tele"] or ap["*Tele"])
                and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["*Rage"] and you.race() ~= "Mummy"
             and you.race() ~= "Ghoul" and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["Fragile"] then
            return -1, -1
        end
        if ap and ap["*Slow"] and you.race() ~= "Formicid" then
            value = value - 100
        end
        if ap and ap["*Corrode"] then
            value = value - 100
        end
        if (intrinsic_evil()
                or you.god() == "Yredelemnul") and name:find("holy") then
            return -1, -1
        end
        if name:find("obsidian axe") then
            value = value + 300
            if tso then
                return -1, -1
            end
        end
    end
    local val1, val2 = total_resist_value(it, cur, it2)
    if it.artefact and not it.fully_identified or name:find("runed")
            or name:find("glowing") then
        val2 = val2 + 500
        val1 = val1 + (cur and 500 or -250)
    end
    local ego = it.ego()
    if hydra_swap then
        local hydra_quality = hydra_weapon_status(it)
        if hydra_quality == -1 then
            return -1, -1
        elseif hydra_quality == 1 then
            value = value + 500
        end
    end
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
            value = value + 500 -- this is what we want
            if tso then
                return -1, -1
            end
            if extended then
                value = value - 400
            end
        elseif ego == "speed" then
            value = value + 300 -- this is good too
            if you.god() == "Cheibriados" then
                return -1, -1
            end
        elseif ego == "electrocution" or ego == "spectralizing" then
            value = value + 150 -- not bad
        elseif ego == "draining" then
            if not extended then
                value = value + 75
            end
            if tso then
                return -1, -1
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
    -- we might be delayed by a shield or not yet at min delay, so add a little
    delay_estimate = delay_estimate + 1
    value = value + 1200 * it.damage / delay_estimate
    -- subtract a bit for very slow weapons because of how much skill they
    -- require to reach min delay
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
    local subtype = it.subtype()
    local value = 0
    if it.artefact then
        ap = it.artprops
        if ap and (ap["-Tele"] or ap["*Tele"])
                and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["*Rage"] and you.race() ~= "Mummy"
             and you.race() ~= "Ghoul" and you.race() ~= "Formicid" then
            return -1, -1
        end
        if name:find("macabre finger necklace") then
            return -1, -1
        end
        if ap and ap["Fragile"] then
            return -1, -1
        end
        if ap and ap["*Slow"] and you.race() ~= "Formicid" then
            value = value - 100
        end
        if ap and ap["*Corrode"] then
            value = value - 100
        end
    end
    if subtype == "amulet of faith" then
        -- we don't use piety much on these gods at the moment
        if you.god() == "Cheibriados" or you.god() == "Beogh"
                or you.god() == "Qazlal" or you.god() == "Hepliaklqana" then
            return -1, -1
        -- fixed value so we don't unequip for a randart one
        elseif you.god() ~= "Ru" and you.god() ~= "Xom" then
            return 1000, 1000
         end
    end
    if it.artefact and not it.fully_identified
            or not (it.artefact or name:find("amulet of")) then
        if cur then
            return 800, 800
        else
            return -1, 1000
        end
    end
    local val1, val2 = total_resist_value(it, cur, it2)
    return value + val1, value + val2
end

function ring_value(it, cur, it2)
    local name = it.name()
    local subtype = it.subtype()
    local value = 0
    if it.artefact then
        ap = it.artprops
        if ap and (ap["-Tele"] or ap["*Tele"])
                and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["*Rage"] and you.race() ~= "Mummy"
             and you.race() ~= "Ghoul" and you.race() ~= "Formicid" then
            return -1, -1
        end
        if ap and ap["Fragile"] then
            return -1, -1
        end
        if ap and ap["*Slow"] and you.race() ~= "Formicid" then
            value = value - 100
        end
        if ap and ap["*Corrode"] then
            value = value - 100
        end
    end
    if subtype == "ring of teleportation" and you.race() ~= "Formicid" then
        return -1, -1
    end
    if it.artefact and not it.fully_identified
            or not (it.artefact or name:find("ring of")) then
        if cur then
            return 5000, 5000
        else
            return -1, 5000
        end
    end
    local val1, val2 = total_resist_value(it, cur, it2)
    if not it.artefact and not it.plus then
        local linval = 0
        if subtype == "ring of slaying" or subtype == "ring of protection"
         or subtype == "ring of evasion" then
            linval = 50
        elseif subtype == "ring of strength" then
            linval = 30
        elseif subtype == "ring of dexterity" then
            linval = 20
        end
        value = value + 6 * linval
        if not cur then
            val1 = val1 - 12 * linval
        end
    end
    return value + val1, value + val2
end

function count_charges(wand_type, ignore_it)
    count = 0
    for it in inventory() do
        if it.class(true) == "wand"
             and (ignore_it == nil or slot(it) ~= slot(ignore_it))
             and it.subtype() == wand_type then
            if it.plus then
                count = count + it.plus
            elseif it.plus == nil and not it.name():find("empty") then
                if it.name():find("zapped") then
                    count = count + 3
                else
                    count = count + 6
                end
            end
        end
    end
    return count
end

function want_wand(it)
    if you.mutation("inability to use devices") > 0 then
        return false
    end

    only_wand = true
    for it2 in inventory() do
        if only_wand and it2.class(true) == "wand"
                and slot(it2) ~= slot(it) then
            only_wand = false
        end
    end
    if only_wand then
        return true -- for Evo training
    end
    sub = it.subtype()
    if sub == nil then
        return true
    end
    if sub ~= "digging" then
        return false
    end
    if it.name():find("empty") or it.plus == 0 then
        for it2 in inventory() do
            if it2.class(true) == "wand" and slot(it2) ~= slot(it) and
                 it2.subtype() == sub then
                return false
            end
        end
    elseif sub == "digging" then
        return (count_charges("digging", it) < 18)
    end
    return true
end

function want_potion(it)
    sub = it.subtype()
    if sub == nil then
        return true
    end

    wanted = { "curing", "heal wounds", "haste", "resistance",
        "experience", "might", "mutation", "cancellation" }

    if TSO_CONVERSION and (PAN_RUNE or HELL_RUNE or GOLDEN_RUNE) then
        table.insert(wanted, "magic")
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

    if WILL_ZIG then
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
    elseif (PAN_RUNE or HELL_RUNE or GOLDEN_RUNE) and slotname == "Weapon"
                 and not item_is_sit_dominated(it, "extended") then
        return false
    elseif slotname == "Weapon"
            and (you.god() == "the Shining One"
                and not you.one_time_ability_used()
                or you.god() ~= "the Shining One" and TSO_CONVERSION)
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

        return old_it.subtype() ~= "amulet of faith"
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

function autopickup(it, name)
    if name:find("of Zot") then
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
    else
        return false
    end
end

clear_autopickup_funcs()
add_autopickup_func(autopickup)

------------------------------
-- some tables with hardcoded data about branches/portals/monsters:

-- branch data: interlevel travel code, where name
local branch_data = {
    {"T", "Temple"},
    {"O", "Orc"},
    --{"E", "Elf"},
    {"L", "Lair"},
    {"S", "Swamp"},
    {"A", "Shoals"},
    {"P", "Snake"},
    {"N", "Spider"},
    {"M", "Slime"},
    {"V", "Vaults"},
    {"C", "Crypt"},
    {"W", "Tomb"},
    {"D", "D:"},
    {"U", "Depths"},
    {"H", "Hell"},
    {"I", "Dis"},
    {"G", "Geh"},
    {"X", "Coc"},
    {"Y", "Tar"},
    {"Z", "Zot"},
} -- hack

-- portal data: where name, full name, feature name
local portal_data = {
    --{"Bailey", "a flagged portal", "bailey"},
    {"Bazaar", "gateway to a bazaar", "bazaar"},
    --{"IceCv", "a frozen archway", "ice_cave"},
    {"Ossuary", "covered staircase", "ossuary"},
    {"Sewer", "a glowing drain", "sewer"},
    --{"Volcano", "a dark tunnel", "volcano"},
    --{"WizLab", "a magical portal", "wizlab"},
    --{"Desolation", "crumbling gateway", "desolation"},
    --{"Gauntlet", "gauntlet entrance", "gauntlet"},
} -- hack

-- functions for use in the monster lists below
function in_desc(lev, str)
    return function (m)
        return you.xl() < lev and m:desc():find(str)
    end
end

function pan_lord(lev)
    return function (m)
        return (you.xl() < lev and m:type() == ENUM_MONS_PANDEMONIUM_LORD)
    end
end

local res_func_table = {
    rF=you.res_fire,
    rC=you.res_cold,
    rPois=you.res_poison,
    rElec=you.res_shock,
    rN=you.res_draining,
    -- returns a boolean
    rCorr=(function() return you.res_corr() and 1 or 0 end),
    Will=you.willpower,
} --hack

function check_resist(lev, resist, value)
    return function (m)
        return (you.xl() < lev and res_func_table[resist]() < value)
    end
end

function slow_berserk(lev)
    return function (m)
        return (you.xl() < lev and count_monsters_near(0, 0, 1) > 0)
    end
end

function hydra_weapon_status(weap)
    if not weap then
        return 0
    end
    local sk = weap.weap_skill
    if sk == "Maces & Flails" or sk == "Short Blades"
         or sk == "Polearms" and weap.hands == 1 then
        return 0
    elseif weap.ego() == "flaming" then
        return 1
    else
        return -1
    end
end

function hydra_check_flaming(lev)
    return function (m)
        return you.xl() < lev
            and m:desc():find("hydra")
            and not contains_string_in(m:name(),
                {"skeleton", "zombie", "simulacrum", "spectral"})
            and hydra_weapon_status(items.equipped_at("Weapon")) ~= 1
    end
end

-- The format in monster lists below is that a num is equivalent to checking
-- XL < num, otherwise we want a function. ["*"] should be a table of
-- functions to check for every monster.

-- Used for:
-- Ru's Apocalypse, Trog's Berserk, Okawaru's Heroism, whether to buff on the
-- orb run.
local scary_monsters = {
    ["*"] = {
        in_desc(15, "hydra"),
        hydra_check_flaming(20),
        in_desc(100, "berserk[^e]"),
        in_desc(100, "statue"),
        in_desc(100, "'s ghost"),
        in_desc(100, "' ghost"),
        in_desc(100, "'s illusion"),
        in_desc(100, "' illusion"),
        pan_lord(100),
    },

    ["Terence"] = 3,

    ["worm"] = slow_berserk(4),

    ["gnoll"] = 5,
    ["ice beast"] = 5,
    ["iguana"] = 5,
    ["Natasha"] = 5,
    ["Robin"] = 5,

    ["ice beast"] = check_resist(7, "rC", 1),
    ["orc wizard"] = 7,
    ["gnoll sergeant"] = 7,
    ["Grinder"] = 7,
    ["Ijyb"] = 7,
    ["Dowan"] = 7,
    ["Duvessa"] = 7,
    ["Menkaure"] = 7,
    ["Edmund"] = 7,
    ["Blork the orc"] = 7,
    ["Eustachio"] = 7,

    ["orc priest"] = 10,
    ["ogre"] = 10,
    ["decayed bog body"] = 10,
    ["Prince Ribbit"] = 10,
    ["Pikel"] = 10,
    ["Crazy Yiuf"] = 10,
    ["Sigmund"] = 10,

    ["orc warrior"] = 12,
    ["two-headed ogre"] = 12,
    ["troll"] = 12,
    ["cyclops"] = 12,
    ["cane toad"] = 12,
    ["black mamba"] = 12,
    ["snapping turtle"] = 12,
    ["electric eel"] = 12,
    ["Nergalle"] = 12,
    ["jelly"] = 12,
    ["guardian mummy"] = 12,
    ["oklob sapling"] = 12,
    ["Snorg"] = 12,
    ["Harold"] = 12,
    ["Gastronok"] = 12,
    ["Psyche"] = 12,
    ["Urug"] = 12,
    ["Grum"] = 12,
    ["Amaemon"] = 12,

    ["komodo dragon"] = 14,
    ["lindwurm"] = 14,
    ["manticore"] = 14,
    ["polar bear"] = 14,
    ["blink frog"] = 14,

    ["torpor snail"] = 15,
    ["death yak"] = 15,
    ["catoblepas"] = 15,
    ["orc knight"] = 15,
    ["swamp worm"] = 15,
    ["boulder beetle"] = 15,
    ["wolf spider"] = 15,
    ["Erica"] = 15,
    ["Erolcha"] = 15,

    ["fire dragon"] = 17,
    ["ice dragon"] = 17,
    ["storm dragon"] = 17,
    ["ogre mage"] = 17,
    ["orc sorcerer"] = 17,
    ["orc high priest"] = 17,
    ["orc warlord"] = 17,
    ["dire elephant"] = 17,
    ["very large slime creature"] = 17,
    ["quicksilver ooze"] = 17,
    ["skeletal warrior"] = 17,
    ["Arachne"] = 17,
    ["Mlioglotl"] = 17,
    ["deep troll"] = 17,
    ["thorn hunter"] = 17,
    ["goliath frog"] = 17,
    ["bunyip"] = 17,
    ["meliai"] = 17,
    ["shambling mangrove"] = 17,
    ["sun demon"] = 17,
    ["white ugly thing"] = check_resist(17, "rC", 1),
    ["white very ugly thing"] = check_resist(17, "rC", 1),

    ["merfolk impaler"] = 20,
    ["water nymph"] = 20,
    ["alligator snapping turtle"] = 20,
    ["fenstrider witch"] = 20,
    ["goliath frog"] = 20,
    ["spriggan rider"] = 20,
    ["spriggan druid"] = 20,
    ["spriggan berserker"] = 20,
    ["spriggan defender"] = 20,
    ["spriggan air mage"] = 20,
    ["nagaraja"] = 20,
    ["naga sharpshooter"] = 20,
    ["salamander tyrant"] = 20,
    ["shock serpent"] = check_resist(17, "rElec", 1),
    ["sun moth"] = 20,
    ["broodmother"] = 20,
    ["radroach"] = 20,
    ["emperor scorpion"] = 20,
    ["Donald"] = 20,
    ["Rupert"] = 20,
    ["Aizul"] = 20,
    ["Azrael"] = 20,
    ["Frances"] = 20,
    ["Saint Roka"] = 20,
    ["Agnes"] = 20,
    ["Jory"] = 20,
    ["Nikola"] = 20,
    ["stone giant"] = 20,
    ["fire giant"] = 20,
    ["frost giant"] = 20,
    ["acid blob"] = 20,
    ["azure jelly"] = 20,
    ["rockslime"] = 20,
    ["Asterion"] = 20,
    ["deep troll shaman"] = 20,
    ["Xtahua"] = 20,
    ["ironbound thunderhulk"] = check_resist(20, "rElec", 1),
    ["ironbound frostheart"] = check_resist(20, "rC", 1),
    ["ettin"] = 20,
    ["Polyphemus"] = 20,
    ["Bai Suzhen"] = 20,
    ["Zenata"] = 20,
    ["crystal guardian"] = 20,

    ["tentacled monstrosity"] = 24,
    ["golden dragon"] = 24,
    ["merfolk javelineer"] = 24,
    ["hell hog"] = check_resist(24, "rF", 1),
    ["storm dragon"] = check_resist(24, "rElec", 1),
    ["titan"] = check_resist(24, "rElec", 1),
    ["fire giant"] = check_resist(24, "rF", 1),
    ["frost giant"] = check_resist(24, "rC", 1),
    ["azure jelly"] = check_resist(24, "rC", 1),

    ["walking crystal tome"] = 100,
    ["walking divine tome"] = 100,
    ["tengu reaver"] = 100,
    ["Xtahua"] = check_resist(100, "rF", 1),
    ["deep elf annihilator"] = 100,
    ["deep elf sorcerer"] = 100,
    ["draconian annihilator"] = 100,
    ["draconian scorcher"] = 100,
    ["draconian stormcaller"] = 100,
    ["titanic slime creature"] = 100,
    ["enormous slime creature"] = 100,
    ["titan"] = 100,
    ["juggernaut"] = 100,
    ["caustic shrike"] = 100,
    ["shard shrike"] = 100,
    ["Killer Klown"] = 100,
    ["orb of fire"] = 100,
    ["mummy priest"] = 100,
    ["royal mummy"] = 100,
    ["seraph"] = 100,
    ["draconian monk"] = 100,
    ["boggart"] = 100,
    ["lich"] = 100,
    ["ancient lich"] = 100,
    ["dread lich"] = 100,
    ["oklob plant"] = 100,
    ["hellion"] = 100,
    ["tormentor"] = 100,
    ["doom hound"] = 100,
    ["curse toe"] = 100,
    ["curse skull"] = 100,
    ["iron golem"] = 100,
    ["iron giant"] = 100,
    ["Hell Sentinel"] = 100,
    ["Ice Fiend"] = 100,
    ["Tzitzimitl"] = 100,
    ["Brimstone Fiend"] = 100,
    ["the Enchantress"] = 100,
    ["Vashnia"] = 100,
    ["Sojobo"] = 100,
    ["Roxanne"] = 100,
    ["Nessos"] = 100,
    ["Sonja"] = 100,
    ["Louise"] = 100,
    ["Mennas"] = 100,
    ["Margery"] = check_resist(100, "rF", 2),
    ["Frederick"] = 100,
    ["Boris"] = 100,
    ["Mara"] = 100,
    ["Tiamat"] = 100,
    ["Royal Jelly"] = 100,
    ["Cerebov"] = 100,
    ["Gloorx Vloq"] = 100,
    ["Lom Lobon"] = 100,
    ["Mnoleg"] = 100,
    ["Dispater"] = 100,
    ["Asmodeus"] = 100,
    ["Antaeus"] = 100,
    ["Ereshkigal"] = 100,
    ["Khufu"] = 100,
    ["Vv"] = 100,
    ["Parghit"] = 100,
    ["Grunn"] = 100,
} -- hack

-- Used for:
-- Trog's Brothers in Arms, Okawaru's Finesse, Makhleb's Summon Greater
-- Servant, Ru's Apocalypse, The Shining One's Summon Divine Warrior.
local nasty_monsters = {
    ["*"] = {
        hydra_check_flaming(17),
        in_desc(100, "statue"),
        in_desc(100, "'s ghost"),
        in_desc(100, "' ghost"),
        pan_lord(100),
    },

    ["fire dragon"] = 15,
    ["ice dragon"] = 15,
    ["Snorg"] = 15,
    ["death yak"] = 15,
    ["red devil"] = 15,
    ["Erolcha"] = 15,
    ["Rupert"] = 15,
    ["Azrael"] = 15,

    ["Nikola"] = 17,

    ["orc warlord"] = 20,
    ["orb spider"] = 20,
    ["thorn hunter"] = 20,
    ["sun demon"] = check_resist(20, "rF", 1),
    ["merfolk avatar"] = 20,
    ["crystal guardian"] = 20,
    ["ironbound thunderhulk"] = check_resist(20, "rElec", 1),
    ["Aizul"] = 20,
    ["Agnes"] = 20,
    ["Arachne"] = 20,
    ["Asterion"] = 20,
    ["Bai Suzhen"] = 20,
    ["Frances"] = 20,
    ["Ilsuiw"] = 20,
    ["Jory"] = 20,
    ["Nikola"] = check_resist(20, "rElec", 1),
    ["Polyphemus"] = 20,
    ["Saint Roka"] = 20,
    ["Vashnia"] = 20,
    ["Zenata"] = 20,

    ["oklob plant"] = 100,
    ["deep troll shaman"] = 100,
    ["spriggan air mage"] = check_resist(100, "rElec", 1),
    ["boggart"] = 100,
    ["lich"] = 100,
    ["ancient lich"] = 100,
    ["spark wasp"] = check_resist(100, "rElec", 1),
    ["juggernaut"] = 100,
    ["iron golem"] = 100,
    ["iron giant"] = 100,
    ["Hell Sentinel"] = 100,
    ["Ice Fiend"] = 100,
    ["Brimstone Fiend"] = 100,
    ["Tzitzimitl"] = 100,
    ["entropy weaver"] = check_resist(100, "rCorr", 1),
    ["doom hound"] = 100,
    ["royal mummy"] = 100,
    ["orb of fire"] = 100,
    ["Killer Klown"] = 100,
    ["caustic shrike"] = 100,
    ["shard shrike"] = 100,
    ["seraph"] = 100,
    ["Sojobo"] = 100,
    ["Roxanne"] = 100,
    ["Nessos"] = 100,
    ["Sonja"] = 100,
    ["Louise"] = 100,
    ["the Enchantress"] = 100,
    ["Mennas"] = 100,
    ["Margery"] = 100,
    ["Frederick"] = 100,
    ["Boris"] = 100,
    ["Mara"] = 100,
    ["Royal Jelly"] = 100,
    ["Tiamat"] = 100,
    ["Cerebov"] = 100,
    ["Gloorx Vloq"] = 100,
    ["Lom Lobon"] = 100,
    ["Mnoleg"] = 100,
    ["Dispater"] = 100,
    ["Asmodeus"] = 100,
    ["Antaeus"] = 100,
    ["Ereshkigal"] = 100,
    ["Khufu"] = 100,
    ["Parghit"] = 100,
    ["Vv"] = 100,
    ["Grunn"] = 100,
} -- hack

-- BiA these even at low piety.
local bia_necessary_monsters = {
    ["*"] = {
        hydra_check_flaming(15),
        in_desc(100, "statue"),
    },

    ["orb spider"] = 20,
} -- hack

-- Use haste/might on these few.
local ridiculous_uniques = {
    ["*"] = {},
    ["Antaeus"] = 100,
    ["Asmodeus"] = 100,
    ["Lom Lobon"] = 100,
} -- hack

-- Trog's Hand these.
local hand_monsters = {
    ["*"] = {},

    ["Grinder"] = 10,

    ["orc sorcerer"] = 17,
    ["wizard"] = 17,

    ["ogre mage"] = 100,
    ["Rupert"] = 100,
    ["Xtahua"] = 100,
    ["Aizul"] = 100,
    ["Erolcha"] = 100,
    ["Louise"] = 100,
    ["lich"] = 100,
    ["ancient lich"] = 100,
    ["dread lich"] = 100,
    ["Kirke"] = 100,
    ["golden eye"] = 100,
    ["deep elf sorcerer"] = 100,
    ["deep elf demonologist"] = 100,
    ["sphinx"] = 100,
    ["great orb of eyes"] = 100,
    ["vault sentinel"] = 100,
    ["the Enchantress"] = 100,
    ["satyr"] = 100,
    ["fenstrider witch"] = 100,
    ["vampire knight"] = 100,
    ["siren"] = 100,
    ["merfolk avatar"] = 100,
} -- hack

-- Potion of resistance these.
local fire_resistance_monsters = {
    ["*"] = {},

    ["Margery"] = check_resist(100, "rF", 2),
    ["orb of fire"] = 100,
    ["hellephant"] = check_resist(100, "rF", 2),
    ["Xtahua"] = check_resist(100, "rF", 2),
    ["Cerebov"] = 100,
    ["Asmodeus"] = check_resist(100, "rF", 2),
    ["Vv"] = 100,
} -- hack

local cold_resistance_monsters = {
    ["*"] = {},
    ["Ice Fiend"] = 100,
    ["Antaeus"] = 100,
    ["Vv"] = 100,
} -- hack

local elec_resistance_monsters = {
    ["*"] = {
        in_desc(20, "black draconian"),
    },
    ["ironbound thunderhulk"] = 20,
    ["storm dragon"] = 20,
    ["electric golem"] = 100,
    ["spark wasp"] = 100,
    ["Antaeus"] = 100,
} -- hack

local pois_resistance_monsters = {
    ["*"] = {},
    ["swamp drake"] = 100,
} -- hack

local acid_resistance_monsters = {
    ["*"] = {},
    ["acid blob"] = 100,
} -- hack

-----------------------------------------
-- player functions

-- "intrinsics" that shouldn't change over the course of the game:

function intrinsic_rpois()
    local sp = you.race()
    if sp == "Gargoyle" or sp == "Naga" or sp == "Ghoul" or sp == "Mummy" then
        return true
    end
    return false
end

function intrinsic_relec()
    local sp = you.race()
    if sp == "Gargoyle" then
        return true
    end
    return false
end

function intrinsic_sinv()
    local sp = you.race()
    if sp == "Naga" or sp == "Felid" or sp == "Formicid"
            or sp == "Vampire" then
        return true
    end
    -- we assume TSO piety won't drop below 2* and that we won't change gods
    -- away from TSO
    if you.god() == "the Shining One" and you.piety_rank() >= 2 then
        return true
    end
    return false
end

function intrinsic_amphibious_or_flight()
    local sp = you.race()
    if (sp == "Gargoyle" or sp == "Black Draconian") and you.xl() >= 14
            or sp == "Tengu" and you.xl() >= 5
            or sp == "Merfolk"
            or sp == "Octopode"
            or sp == "Barachi" then
        return true
    end
    return false
end

function intrinsic_fumble()
    local sp = you.race()
    if intrinsic_amphibious_or_flight()
            or sp == "Grey Draconian"
            or sp == "Palentonga"
            or sp == "Naga"
            or sp == "Troll"
            or sp == "Ogre" then
        return false
    end
    return true
end

function intrinsic_evil()
    local sp = you.race()
    if sp == "Demonspawn" or sp == "Mummy" or sp == "Ghoul" or
         sp == "Vampire" then
        return true
    end
    return false
end

function intrinsic_undead()
    return (you.race() == "Ghoul" or you.race() == "Mummy"
                    or you.race() == "Vampire")
end

-- We group all species into four categories:
-- heavy: species that can use arbitrary armour and aren't particularly great
--        at dodging
-- dodgy: species that can use arbitrary armour but are very good at dodging
-- large: species with armour restrictions that want heavy dragon scales
-- light: species with no body armour or who don't want anything heavier than
--        7 encumbrance
function armour_plan()
    local sp = you.race()
    if sp == "Ogre" or sp == "Troll" then
        return "large"
    elseif sp == "Deep Elf" or sp == "Kobold"
                 or sp == "Merfolk" then
        return "dodgy"
    elseif sp:find("Draconian") or sp == "Felid" or sp == "Octopode"
                 or sp == "Spriggan" then
        return "light"
    else
        return "heavy"
    end
end

function expected_armour_multiplier()
    local ap = armour_plan()
    if ap == "heavy" then
        return 2
    elseif ap == "large" or ap == "dodgy" then
        return 1.5
    else
        return 1.25
    end
end

function unfitting_armour()
    local sp = you.race()
    return armour_plan() == "large" or sp == "Palentonga" or sp == "Naga"
end

function want_buckler()
    local sp = you.race()
    if sp == "Felid" then
        return false
    end
    if SHIELD_CRAZY then
        return true
    end
    if wskill() == "Short Blades" or wskill() == "Unarmed Combat" then
        return true
    end
    if sp == "Formicid" or sp == "Kobold" then
        return true
    end
    return false
end

function want_shield()
    if not want_buckler() then
        return false
    end
    if SHIELD_CRAZY then
        return true
    end
    return (you.race() == "Troll" or you.race() == "Formicid")
end

-- used for backgrounds who don't get to choose a weapon
function weapon_choice()
    sp = you.race()
    if sp == "Felid" or sp == "Troll" or sp == "Ghoul" then
        return "Unarmed Combat"
    elseif sp == "Ogre" or sp == "Kobold" then
        return "Maces & Flails"
    elseif sp == "Merfolk" then
        return "Polearms"
    elseif sp == "Spriggan" then
        return "Short Blades"
    else
        return "Axes"
    end
end

function wskill()
    -- cache in case you unwield a weapon somehow
    if c_persist.cached_wskill then
        return c_persist.cached_wskill
    end
    weap = items.equipped_at("Weapon")
    if weap and weap.class(true) == "weapon"
         and weap.weap_skill ~= "Short Blades"
         and you.class() ~= "Wanderer" then
        c_persist.cached_wskill = weap.weap_skill
    else
        c_persist.cached_wskill = weapon_choice()
    end
    return c_persist.cached_wskill
end

function max_rings()
    if you.race() == "Octopode" then
        return 8
    else
        return 2
    end
end

-- other player functions

function hp_is_low(percentage)
    local hp, mhp = you.hp()
    return (100 * hp <= percentage * mhp)
end

function chp()
    local hp, mhp = you.hp()
    return hp
end

function cmp()
    local mp, mmp = you.mp()
    return mp
end

function meph_immune()
    -- should also check clarity and unbreathing
    return (you.res_poison() >= 1)
end

function miasma_immune()
    -- this isn't all the cases, I know
    return (you.race() == "Gargoyle" or you.race() == "Vine Stalker"
                    or you.race() == "Ghoul" or you.race() == "Mummy")
end

function is_waypointable(loc)
    return (not is_portal_location(loc) and not loc:find("Abyss")
        and loc ~= "Pan" and not loc:find("Zig"))
end

function is_portal_location(loc)
    for _, value in ipairs(portal_data) do
        if value[1] == loc then
            return true
        end
    end
    return false
end

function in_portal()
    return is_portal_location(where)
end

function get_feat_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function cur_branch()
    for _, value in ipairs(branch_data) do
        if where:find(value[2]) then
            return value[1]
        end
    end
end

function found_branch(br)
    if br == "D" then
        return true
    end
    for _, value in ipairs(branch_data) do
        if value[1] == br then
            if travel.find_deepest_explored(value[2]) > 0 then
                return true
            else
                return false
            end
        end
    end
    return false
end

function in_branch(br)
    for _, value in ipairs(branch_data) do
        if value[1] == br then
            if where:find(value[2]) then
                return true
            else
                return false
            end
        end
    end
    return false
end

function is_traversable(x, y)
    local feat = view.feature_at(x, y)
    return feat ~= "unseen" and travel.feature_traversable(feat)
end

function is_cornerish(x, y)
    if is_traversable(x+ 1, y + 1)
            or is_traversable(x + 1, y - 1)
            or is_traversable(x - 1, y + 1)
            or is_traversable(x - 1, y - 1) then
        return false
    end
    return (is_traversable(x + 1, y) or is_traversable(x - 1, y))
        and (is_traversable(x, y + 1) or is_traversable(x, y - 1))
end

function is_solid(x, y)
    local feat = view.feature_at(x, y)
    return feat == "unseen" or travel.feature_solid(feat)
end

function dangerous_to_rest()
    if danger then
        return true
    end
    for x = -1, 1 do
        for y = -1, 1 do
            if view.feature_at(x, y) == "slimy_wall" then
                return true
            end
        end
    end
    return false
end

function transformed()
    return you.transform() ~= ""
end

function can_read()
    if you.berserk() or you.confused() or you.silenced()
         or you.status("engulfed (cannot breathe)")
         or you.status("unable to read") then
        return false
    end
    return true
end

function can_drink()
    if you.berserk()
            or you.race() == "Mummy"
            or you.transform() == "lich"
            or you.status("unable to drink") then
        return false
    end
    return true
end

function can_zap()
    if you.berserk() or you.confused() or transformed() then
        return false
    end
    if you.mutation("inability to use devices") > 0 then
        return false
    end
    return true
end

function can_teleport()
    return can_read()
        and not (you.teleporting()
            or you.anchored()
            or you.transform() == "tree"
            or you.race() == "Formicid")
end

function can_invoke()
    return not (you.berserk()
            or you.confused()
            or you.silenced()
            or you.status("engulfed (cannot breathe)"))
end

function can_berserk()
    return you.god() == "Trog"
        and you.piety_rank() >= 1
        and you.race() ~= "Mummy"
        and you.race() ~= "Ghoul"
        and you.race() ~= "Formicid"
        and not (you.status("on berserk cooldown")
            or you.mesmerised()
            or you.transform() == "tree"
            or you.transform() == "lich"
            or you.status("afraid"))
        and can_invoke()
end

function can_hand()
    return you.god() == "Trog"
                 and you.piety_rank() >= 2
                 and not you.regenerating()
                 and can_invoke()
end

function can_bia()
    return you.god() == "Trog"
                 and you.piety_rank() >= 4
                 and can_invoke()
end


function can_heroism()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 1
                 and cmp() >= 2
                 and not you.status("heroic")
                 and can_invoke()
end

function can_finesse()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 5
                 and cmp() >= 5
                 and not you.status("finesse-ful")
                 and can_invoke()
end

function can_recall()
    return (you.god() == "Yredelemnul" and you.piety_rank() >= 2)
                    or (you.god() == "Beogh" and you.piety_rank() >= 4)
                 and not you.status("recalling")
                 and cmp() >= 2
                 and can_invoke()
end

function can_drain_life()
    return you.god() == "Yredelemnul"
                 and you.piety_rank() >= 4
                 and cmp() >= 6
                 and can_invoke()
end

function can_recall_ancestor()
    return you.god() == "Hepliaklqana"
                 and cmp() >= 2
                 and can_invoke()
end

function can_slouch()
    return you.god() == "Cheibriados"
                 and you.piety_rank() >= 4
                 and cmp() >= 5
                 and can_invoke()
end

function can_ely_healing()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 4
                 and cmp() >= 2
                 and can_invoke()
end

function can_purification()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 3
                 and cmp() >= 3
                 and can_invoke()
end

function can_recite()
    return you.god() == "Zin"
                 and you.piety_rank() >= 1
                 and not you.status("reciting")
                 and can_invoke()
end

function can_ru_healing()
    return you.god() == "Ru"
                 and you.piety_rank() >= 3
                 and not you.exhausted()
                 and can_invoke()
end

function can_apocalypse()
    return you.god() == "Ru"
                 and you.piety_rank() >= 5
                 and cmp() >= 8
                 and not you.exhausted()
                 and can_invoke()
end

function can_grand_finale()
    return you.god() == "Uskayaw"
                 and you.piety_rank() >= 5
                 and cmp() >= 8
                 and can_invoke()
end

function can_sgd()
    return you.god() == "Makhleb"
                 and you.piety_rank() >= 5
                 and chp() > 10
                 and can_invoke()
end

function can_cleansing_flame(ignore_mp)
    return you.god() == "the Shining One"
        and you.piety_rank() >= 3
        and (ignore_mp or cmp() >= 5)
        and can_invoke()
end

function can_divine_warrior(ignore_mp)
    return you.god() == "the Shining One"
                 and you.piety_rank() >= 5
                 and (ignore_mp or cmp() >= 8)
                 and can_invoke()
end

function can_destruction()
    return you.god() == "Makhleb"
                 and chp() > 6
                 and you.piety_rank() >= 4
                 and can_invoke()
end

function player_speed_num()
    local num = 3
    if you.god() == "Cheibriados" then
        num = 1
    elseif you.race() == "Spriggan" then
        num = 4
    elseif you.race() == "Naga" then
        num = 2
    end
    if you.hasted() or you.berserk() then
        num = num + 1
    end
    if you.slowed() then
        num = num - 1
    end
    return num
end

-----------------------------------------
-- monster functions

function mon_speed_num(m)
    local sdesc = m:speed_description()
    local num
    if sdesc == "extremely fast" then
        num = 6
    elseif sdesc == "very fast" then
        num = 5
    elseif sdesc == "fast" then
        num = 4
    elseif sdesc == "normal" then
        num = 3
    elseif sdesc == "slow" then
        num = 2
    elseif sdesc == "very slow" then
        num = 1
    end
    if m:status("fast") then
        num = num + 1
    end
    if m:status("slow") then
        num = num - 1
    end
    if m:name():find("boulder beetle") then
        num = num + 3
    end
    if m:name():find("spriggan") or m:name() == "the Enchantress" then
        num = num + 1
    elseif m:name():find("naga") or m:name() == "Vashnia" then
        num = num - 1
    end
    return num
end

function is_fast(m)
    return (mon_speed_num(m) > player_speed_num())
end

function is_ranged(m)
    local name = m:name()
    if name:find("kraken") then
        return false
    end
    if m:has_known_ranged_attack() then
        return true
    end
    if name == "Maurice" or name == "Ijyb" or name == "crimson imp"
         or name == "lost soul" then
        return true
    end
    return false
end

function sense_immediate_danger()
    local e
    for _, e in ipairs(enemy_list) do
        local dist = supdist(e.x, e.y)
        if dist <= 2 then
            return true
        elseif dist == 3 and e.m:reach_range() >= 2 then
            return true
        elseif is_ranged(e.m) then
            return true
        end
    end

    return false
end

function sense_danger(r, moveable)
    local e
    for _, e in ipairs(enemy_list) do
        if (moveable and you.see_cell_solid_see(e.x, e.y) or not moveable)
                and supdist(e.x, e.y) <= r then
            return true
        end
    end

    return false
end

function sense_sigmund()
    local e
    for _, e in ipairs(enemy_list) do
        if e.m:name() == "Sigmund" then
            sigmund_dx = e.x
            sigmund_dy = e.y
            return
        end
    end
end

function initialize_monster_array()
    monster_array = {}
    local x
    for x = -LOS, LOS do
        monster_array[x] = {}
    end
end

function update_monster_array()
    local x, y
    enemy_list = {}
    --c_persist.mlist = {}
    for x = -LOS, LOS do
        for y = -LOS, LOS do
            if you.see_cell_no_trans(x, y) then
                monster_array[x][y] = monster.get_monster_at(x, y)
                if is_candidate_for_attack(x, y) then
                    entry = {}
                    entry.x = x
                    entry.y = y
                    entry.m = monster_array[x][y]
                    table.insert(enemy_list, entry)
                    --table.insert(c_persist.mlist, entry.m:name())
                end
            else
                monster_array[x][y] = nil
            end
        end
    end
end

function mons_in_list(m, mlist)
    local entry = mlist[m:name()]
    if type(entry) == "number" and you.xl() < entry then
        return true
    elseif type(entry) == "function" and entry(m) then
        return true
    end

    for _, entry in ipairs(mlist["*"]) do
        if entry(m) then
            return true
        end
    end

    return false
end

function check_monster_list(r, mlist, filter)
    local e
    for _, e in ipairs(enemy_list) do
        if you.see_cell_no_trans(e.x, e.y)
                and supdist(e.x, e.y) <= r
                and (not filter or filter(e.m))
                and mons_in_list(e.m, mlist) then
            return true
        end
    end

    return false
end

function count_bia(r)
    if you.god() ~= "Trog" then
        return 0
    end

    local x, y
    local i = 0
    for x = -r, r do
        for y = -r, r do
            m = monster_array[x][y]
            if m and m:is_safe() and m:is("berserk")
                    and contains_string_in(m:name(),
                        {"ogre", "giant", "bear", "troll"}) then
                i = i + 1
            end
        end
    end
    return i
end

function count_elliptic(r)
    if you.god() ~= "Hepliaklqana" then
        return 0
    end

    local x, y
    local i = 0
    for x = -r, r do
        for y = -r, r do
            m = monster_array[x][y]
            if m and m:is_safe() and contains_string_in(m:name(),
                    {"elliptic"}) then
                i = i + 1
            end
        end
    end
    return i
end

function mons_is_greater_demon(m)
    return contains_string_in(m:name(), {"Executioner", "green death",
        "blizzard demon", "balrug", "cacodemon"})
end

function count_sgd(r)
    if you.god() ~= "Makhleb" then
        return 0
    end

    local x, y
    local i = 0
    for x = -r, r do
        for y = -r, r do
            local m = monster_array[x][y]
            if m and m:is_safe() and m:is("summoned")
                    and mons_is_greater_demon(m) then
                i = i + 1
            end
        end
    end
    return i
end

function count_divine_warrior(r)
    if you.god() ~= "the Shining One" then
        return 0
    end

    local x, y
    local i = 0
    for x = -r, r do
        for y = -r, r do
            local m = monster_array[x][y]
            if m and m:is_safe()
                    and contains_string_in(m:name(), {"angel", "daeva"}) then
                i = i + 1
            end
        end
    end
    return i
end

function count_monsters_near(cx, cy, r, filter)
    local e
    local i = 0
    for _, e in ipairs(enemy_list) do
        if supdist(cx - e.x, cy - e.y) <= r
                and (not filter or filter(e.m)) then
            i = i + 1
        end
    end
    return i
end

function count_monsters_near_by_name(cx, cy, r, name)
    return count_monsters_near(cx, cy, r,
        function(m) return m:name() == name end)
end

function count_monsters(r, filter)
    return count_monsters_near(0, 0, r, filter)
end

function count_monster_list(r, mlist, filter)
    return count_monsters(r,
        function(m)
            return (not filter or filter(m)) and mons_in_list(m, mlist)
        end)
end

function count_monster_by_name(r, name)
    return count_monsters(r, function(m) return m:name() == name end)
end

function count_hostile_sgd(r)
    if you.god() ~= "Makhleb" then
        return 0
    end

    return count_monsters(r,
        function(m) return m:is("summoned") and mons_is_greater_demon(m) end)
end

function count_big_slimes(r)
    return count_monsters(r,
        function(m)
            return contains_string_in(m:name(),
                {"enormous slime creature", "titanic slime creature"})
        end)
end

function count_pan_lords(r)
    return count_monsters(r,
        function(m) return m:type() == ENUM_MONS_PANDEMONIUM_LORD end)
end

-- should only be called for adjacent squares
function monster_in_way(dx, dy)
    local m = monster_array[dx][dy]
    return m and (m:attitude() <= ATT_NEUTRAL and not lair_step_mode
        or m:attitude() > ATT_NEUTRAL
            and (m:is_constricted() or m:is_caught() or m:status("petrified")
                or m:status("paralysed") or m:desc():find("sleeping")
                or view.feature_at(0, 0) == "deep_water"
                or view.feature_at(0, 0) == "lava"
                or view.feature_at(0, 0) == "trap_zot"))
end

function tabbable_square(x, y)
    if view.feature_at(x, y) ~= "unseen" and view.is_safe_square(x, y) then
        local m = monster_array[x][y]
        if not m or not m:is_firewood() then
            return true
        end
    end
    return false
end

function mons_tabbable_square(x, y)
    local feat = view.feature_at(x, y)
    return feat ~= "deep_water" and feat ~= "lava" and not is_solid(x, y)
end

function try_move(dx, dy)
    if view.is_safe_square(dx, dy)
            and not view.withheld(dx, dy)
            and not monster_in_way(dx, dy) then
        return delta_to_vi(dx, dy)
    else
        return nil
    end
end

function will_tab(cx, cy, ex, ey, square_func)
    local dx = ex - cx
    local dy = ey - cy
    if abs(dx) <= 1 and abs(dy) <= 1 then
        return true
    end
    local function attempt_move(fx, fy)
        if fx == 0 and fy == 0 then return end
        if supdist(cx + fx, cy + fy) > LOS then return end
        if square_func(cx + fx, cy + fy) then
            return will_tab(cx + fx, cy + fy, ex, ey, square_func)
        end
    end
    local move = nil
    if abs(dx) > abs(dy) then
        if abs(dy) == 1 then move = attempt_move(sign(dx), 0) end
        if move == nil then move = attempt_move(sign(dx), sign(dy)) end
        if move == nil then move = attempt_move(sign(dx), 0) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = attempt_move(sign(dx), 1) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = attempt_move(sign(dx), -1) end
        if move == nil then move = attempt_move(0, sign(dy)) end
    elseif abs(dx) == abs(dy) then
        move = attempt_move(sign(dx), sign(dy))
        if move == nil then move = attempt_move(sign(dx), 0) end
        if move == nil then move = attempt_move(0, sign(dy)) end
    else
        if abs(dx) == 1 then move = attempt_move(0, sign(dy)) end
        if move == nil then move = attempt_move(sign(dx), sign(dy)) end
        if move == nil then move = attempt_move(0, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = attempt_move(1, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = attempt_move(-1, sign(dy)) end
        if move == nil then move = attempt_move(sign(dx), 0) end
    end
    if move == nil then return false end
    return move
end

function get_monster_info(dx, dy)
    local m = monster_array[dx][dy]
    if not m then return nil end
    local name = m:name()
    local info = {}
    info.distance = abs(dx) > abs(dy) and -abs(dx) or -abs(dy)
    if not have_reaching() then
        info.attack_type = -info.distance < 2 and 2 or 0
    else
        if -info.distance > 2 then info.attack_type = 0
        elseif -info.distance < 2 then info.attack_type = 2
        elseif you.caught() or you.confused() then info.attack_type = 0
        else info.attack_type = view.can_reach(dx, dy) and 1 or 0 end
    end
    info.can_attack = info.attack_type > 0 and 1 or 0
    info.safe = m:is_safe() and -1 or 0
    info.constricting_you = m:is_constricting_you() and 1 or 0
    info.very_stabbable = m:stabbability() >= 1 and 1 or 0
    -- info.stabbable = m:is(0) and 1 or 0
    info.injury = m:damage_level()
    info.threat = m:threat()
    info.orc_priest_wizard = (name == "orc priest"
        or name == "orc wizard") and 1 or 0
    return info
end

function compare_monster_info(m1, m2, flag_order, flag_reversed)
    local i, flag

    if not flag_order then
        flag_order = {"can_attack", "safe", "distance", "constricting_you",
            "very_stabbable", "injury", "threat", "orc_priest_wizard"}
    end
    if not flag_reversed then
        flag_reversed = {}
        for _, flag in ipairs(flag_order) do
            table.insert(flag_reversed, false)
        end
    end

    for i, flag in ipairs(flag_order) do
        local if_greater_val = not flag_reversed[i] and true or false
        if m1[flag] > m2[flag] then return if_greater_val end
        if m1[flag] < m2[flag] then return not if_greater_val end
    end
    return false
end

function is_candidate_for_attack(x, y, no_untabbable)
    if supdist(x, y) > LOS then
        return false
    end
    local m = monster_array[x][y]
    if not m or m:attitude() > ATT_NEUTRAL then
        return false
    end
    if m:is_firewood() or m:name() == "butterfly"
            or m:name() == "orb of destruction" then
        return false
    end
    if no_untabbable then
        if will_tab(0, 0, x, y, tabbable_square) then
            remove_ignore(x, y)
        else
            add_ignore(x, y)
            return false
        end
    end
    return true
end

function count_ranged(cx, cy, r)
    local e
    local i = 0
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.x, cy - e.y)
        if dist > 1 and dist <= r then
            if dist == 2 and is_fast(e.m)
                 or (is_ranged(e.m) or dist == 2 and e.m:reach_range() >= 2)
                        and view.cell_see_cell(cx, cy, e.x, e.y) then
                i = i + 1
            end
        end
    end
    return i
end

function count_shortranged(cx, cy, r)
    local e
    local i = 0
    for _, e in ipairs(enemy_list) do
        if supdist(cx - e.x, cy - e.y) <= r and is_ranged(e.m) then
            i = i + 1
        end
    end
    return i
end

function estimate_slouch_damage()
    local e
    local count = 0
    local s, v
    for _, e in ipairs(enemy_list) do
        s = mon_speed_num(e.m)
        v = 0
        if s >= 6 then
            v = 3
        elseif s == 5 then
            v = 2.5
        elseif s == 4 then
            v = 1.5
        elseif s == 3 then
            v = 1
        end
        if e.m:name() == "orb of fire" then
            v = v + 1
        elseif v > 0 and e.m:threat() <= 1 then
            v = 0.5
        end
        count = count + v
    end
    return count
end

function mons_is_holy_vulnerable(m)
    local holiness = m:holiness()
    return holiness == "undead" or holiness == "demonic"
end

function mons_liquid_bound(m)
    return m:name() == "electric eel"
        or m:name() == "kraken"
        or m:name() == "elemental wellspring"
        or m:name() == "lava snake"
end

function assess_square_monsters(a, cx, cy)
    local best_dist = 10
    local e

    a.enemy_distance = 0
    a.followers_to_land = false
    a.adjacent = 0
    a.slow_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.x, cy - e.y)
        local see_cell = view.cell_see_cell(cx, cy, e.x, e.y)
        local ranged = is_ranged(e.m)
        local liquid_bound = mons_liquid_bound(e.m, true)

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound and not ranged and e.m:reach_range() < 2 then
                a.followers_to_land = true
            end

            if have_reaching()
                    and not ranged
                    and e.m:reach_range() < 2
                    and mon_speed_num(e.m) < player_speed_num() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (dist == 2 and (is_fast(e.m) or e.m:reach_range() >= 2)
                    or ranged) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (e.m:desc():find("wandering")
                        and not e.m:desc():find("mushroom")
                    or e.m:desc():find("sleeping")
                    or e.m:desc():find("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (e.m:desc():find("wandering")
                    or e.m:desc():find("sleeping")
                    or e.m:desc():find("dormant")
                    or e.m:desc():find("stupefied")
                    or liquid_bound
                    or e.m:is_stationary())
                and will_tab(e.x, e.y, 0, 0, mons_tabbable_square) then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function distance_to_enemy(cx, cy)
    local best_dist = 10
    local e
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.x, cy - e.y)
        if dist < best_dist then
            best_dist = dist
        end
    end
    return best_dist
end

function distance_to_tabbable_enemy(cx, cy)
    local best_dist = 10
    local e
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.x, cy - e.y)
        if dist < best_dist then
            if will_tab(e.x, e.y, 0,  0, mons_tabbable_square) then
                best_dist = dist
            end
        end
    end
    return dist
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

function target_shield_skill()
    local shield = items.equipped_at("Shield")
    if not shield then
        return 0
    end
    if shield.encumbrance == 0 and not want_buckler()
         or shield.encumbrance ~= 0 and not want_shield() then
        return 0
    end
    enc = shield.encumbrance > 0 and shield.encumbrance or 0.8
    local size_factor = 5 - 2 * body_size()
    if you.race() == "Formicid" then
        size_factor = size_factor - 2
    end
    return enc * size_factor
end

function at_target_shield_skill()
    return you.base_skill("Shields") >= min(27,
        target_shield_skill() + (you.god() == "Ru" and 1 or 0))
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
    if it and (it.cursed or it.name():find("+14 obsidian axe")
                and you.status("mesmerised")) then
        return false
    end
    if it and it.ego() == "flying" and
         (view.feature_at(0, 0) == "deep_water" or
            view.feature_at(0, 0) == "lava") then
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

-----------------------------------------
-- "plans" - functions that take actions, and logic to determine which actions
--           to take.
-- Every function that might take an action should return as follows:
--   true if tried to do something
--   false if didn't do anything
--   nil if should be rerun (currently only used by cascades, be careful
--       of loops... this is poorly tested)

function get_target()
    local e, bestx, besty, best_info, new_info
    bestx = 0
    besty = 0
    best_info = nil
    for _, e in ipairs(enemy_list) do
        if not util.contains(failed_move, 20 * e.x + e.y) then
            if is_candidate_for_attack(e.x, e.y, true) then
                new_info = get_monster_info(e.x, e.y)
                if not best_info
                        or compare_monster_info(new_info, best_info) then
                    bestx = e.x
                    besty = e.y
                    best_info = new_info
                end
            end
        end
    end
    return bestx, besty, best_info
end

function should_rest()
    if you.confused() or you.berserk() or transformed() then
        return true
    end
    if dangerous_to_rest() then
        return false
    end
    if you.turns() < hiding_turn_count + 10 then
        dsay("Waiting for ranged monster.")
        return true
    end
    return reason_to_rest(99.9)
        or you.god() == "Makhleb" and you.turns() <= sgd_timer + 100
        or should_ally_rest()
end

-- Check statuses to see whether there is something to rest off, does not
-- include some things in should_rest() because they are not clearly good to
-- wait out with monsters around.
function reason_to_rest(percentage)
    if not no_spells and starting_spell() then
        local mp, mmp = you.mp()
        if mp < mmp then
            return true
        end
    end
    if you.god() == "Elyvilon" and you.piety_rank() >= 4 then
        local mp, mmp = you.mp()
        if mp < mmp and mp < 10 then
            return true
        end
    end
    return you.confused()
        or transformed()
        or hp_is_low(percentage)
            and (you.god() ~= "the Shining One"
                or hp_is_low(75)
                or count_divine_warrior(2) == 0)
        or you.slowed()
        or you.exhausted()
        or you.teleporting()
        or you.status("on berserk cooldown")
        or you.status("marked")
        or you.status("spiked")
        or you.status("weakened")
        or you.silencing()
        or you.corrosion() > base_corrosion
end

-- Are we significantly stronger than usual thanks to a buff that we used?
function buffed()
    if hp_is_low(50)
            or transformed()
            or you.corrosion() >= 2 + base_corrosion then
        return false
    end
    if you.god() == "Okawaru" and
         (you.status("heroic") or you.status("finesse-ful")) then
        return true
    end
    if you.extra_resistant() then
        return true
    end
    return false
end

function should_ally_rest()
    if you.god() ~= "Yredelemnul" and you.god() ~= "Beogh" then
        return false
    end
    if dangerous_to_rest() then
        return false
    end
    local x, y
    for x = -3, 3 do
        for y = -3, 3 do
            m = monster_array[x][y]
            if m and m:attitude() == ATT_FRIENDLY and m:damage_level() > 0 then
                dsay("Waiting for " .. m:name() .. " to heal.")
                return true
            end
        end
    end
    return false
end

function rest()
    magic("s")
    next_delay = 5
end

function easy_rest()
    magic("5")
end

function attack()
    local bestx, besty, best_info
    local success = false
    failed_move = { }
    while not success do
        bestx, besty, best_info = get_target()
        if best_info == nil then
            return false
        end
        success = make_attack(bestx, besty, best_info)
    end
    return true
end

function berserk()
    use_ability("Berserk")
end

function heroism()
    use_ability("Heroism")
end

function recall()
    if you.god() == "Yredelemnul" then
        use_ability("Recall Undead Slaves", "", true)
    else
        use_ability("Recall Orcish Followers", "", true)
    end
end

function recall_ancestor()
    use_ability("Recall Ancestor", "", true)
end

function finesse()
    use_ability("Finesse")
end

function slouch()
    use_ability("Slouch")
end

function drain_life()
    use_ability("Drain Life")
end

function hand()
    use_ability("Trog's Hand")
end

function ru_healing()
    use_ability("Draw Out Power")
end

function ely_healing()
    use_ability("Greater Healing")
end

function purification()
    use_ability("Purification")
end

function recite()
    use_ability("Recite", "", true)
end

function bia()
    use_ability("Brothers in Arms")
end

function sgd()
    use_ability("Greater Servant of Makhleb")
end

function cleansing_flame()
    use_ability("Cleansing Flame")
end

function divine_warrior()
    use_ability("Summon Divine Warrior")
end

function apocalypse()
    use_ability("Apocalypse")
end

function plan_bia()
    if can_bia() and want_to_bia() then
        bia()
        return true
    end
    return false
end

function plan_sgd()
    if can_sgd() and want_to_sgd() then
        sgd()
        return true
    end
    return false
end

function plan_cleansing_flame()
    if can_cleansing_flame() and want_to_cleansing_flame() then
        cleansing_flame()
        return true
    end
    return false
end

function plan_divine_warrior()
    if can_divine_warrior() and want_to_divine_warrior() then
        divine_warrior()
        return true
    end
    return false
end

function plan_orbrun_divine_warrior()
    if can_divine_warrior() and want_to_orbrun_divine_warrior() then
        divine_warrior()
        return true
    end
    return false
end

function plan_recite()
    if can_recite() and danger
            and not (immediate_danger and hp_is_low(33)) then
        recite()
        return true
    end
    return false
end

function plan_grand_finale()
    if not danger or not can_grand_finale() then
        return false
    end
    local invo = you.skill("Invocations")
    -- fail rate potentially too high, need to add ability failure rate lua
    if invo < 10 or you.piety_rank() < 6 and invo < 15 then
        return false
    end
    local e, bestx, besty, best_info, new_info
    local flag_order = {"threat", "injury", "distance"}
    local flag_reversed = {false, true, true}
    best_info = nil
    for _, e in ipairs(enemy_list) do
        if is_traversable(e.x, e.y)
                and not cloud_is_dangerous(view.cloud_at(e.x, e.y)) then
            new_info = get_monster_info(e.x, e.y)
            if new_info.safe == 0
                    and (not best_info
                        or compare_monster_info(new_info, best_info,
                            flag_order, flag_reversed)) then
                best_info = new_info
                bestx = e.x
                besty = e.y
            end
        end
    end
    if best_info then
        use_ability("Grand Finale", "r" .. vector_move(bestx, besty) .. "\rY")
        return true
    end
    return false
end

function plan_apocalypse()
    if can_apocalypse() and want_to_apocalypse() then
        apocalypse()
        return true
    end
    return false
end

function plan_hydra_destruction()
    if not can_destruction()
            or you.skill("Invocations") < 8
            or count_sgd(4) > 0
            or hydra_weapon_status(items.equipped_at("Weapon")) > -1
            or you.xl() >= 20 then
        return false
    end

    local e
    for _, e in ipairs(enemy_list) do
        if supdist(e.x, e.y) <= 5 and string.find(e.m:desc(), "hydra") then
            say("INVOKING MAJOR DESTRUCTION")
            for letter, abil in pairs(you.ability_table()) do
                if abil == "Major Destruction" then
                    magic("a" .. letter .. "r" .. vector_move(e.x, e.y) ..
                        "\r")
                    return true
                end
            end
        end
    end
    return false
end

function plan_resistance()
    if not you.extra_resistant() and not you.teleporting()
         and want_resistance() then
        return drink_by_name("resistance")
    end
    return false
end

function plan_magic_points()
    if not you.teleporting() and want_magic_points() then
        return drink_by_name("magic")
    end
    return false
end

function plan_hand()
    if can_hand() and want_to_hand() and not you.teleporting() then
        hand()
        return true
    end
    return false
end

function prefer_ru_healing()
    return drain_level() <= 1
end

function prefer_ely_healing()
    if you.god() ~= "Elyvilon" or you.piety_rank() < 4 then
        return false
    end
    return true
end

function plan_abyss_hand()
    local hp, mhp = you.hp()
    if mhp - hp >= 30 and can_hand() then
        hand()
        return true
    end
    return false
end

function plan_orbrun_hand()
    local hp, mhp = you.hp()
    if mhp - hp >= 30 and can_hand() then
        hand()
        return true
    end
    return false
end

function plan_cure_bad_poison()
    if not danger then
        return false
    end
    if you.poison_survival() <= chp() - 60 then
        if drink_by_name("curing") then
            say("(to cure bad poison)")
            return true
        end
        if can_purification() then
            purification()
            return true
        end
    end
    return false
end

function plan_cancellation()
    if not danger or not can_drink() or you.teleporting() then
        return false
    end
    if you.petrifying()
            or you.corrosion() >= 4 + base_corrosion
            or you.corrosion() >= 3 + base_corrosion and hp_is_low(70)
            or you.transform() == "pig"
            or you.transform() == "wisp"
            or you.transform() == "bat" then
        if drink_by_name("cancellation") then
            return true
        end
    end
    return false
end

function plan_blinking()
    if not where:find("Zig") or not danger or not can_read() then
        return false
    end
    local para_danger = false
    local e
    for _, e in ipairs(enemy_list) do
        if e.m:name() == "floating eye" or e.m:name() == "starcursed mass" then
            para_danger = true
        end
    end
    if not para_danger then
        return false
    end
    if count_item("scroll", "of blinking") == 0 then
        return false
    end
    local x, y, dx, dy, m
    local cur_count = 0
    local best_count = 0
    local count
    local best_x, best_y
    for x = -1, 1 do
        for y = -1, 1 do
            m = monster_array[x][y]
            if m and m:name() == "floating eye" then
                cur_count = cur_count + 3
            elseif m and m:name() == "starcursed mass" then
                cur_count = cur_count + 1
            end
        end
    end
    if cur_count >= 2 then
        return false
    end
    for x = -LOS, LOS do
        for y = -LOS, LOS do
            if is_traversable(x, y)
                    and not is_solid(x, y)
                    and monster_array[x][y] == nil
                    and view.is_safe_square(x, y)
                    and not view.withheld(x, y)
                    and you.see_cell_no_trans(x, y) then
                count = 0
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        if abs(x + dx) <= LOS and abs(y + dy) <= LOS then
                            m = monster_array[x + dx][y + dy]
                            if m and m:name() == "floating eye" then
                                count = count + 3
                            elseif m and m:name() == "starcursed mass" then
                                count = count + 1
                            end
                        end
                    end
                end
                if count > best_count then
                    best_count = count
                    best_x = x
                    best_y = y
                end
            end
        end
    end
    if best_count >= cur_count + 2 then
        local c = find_item("scroll", "blinking")
        return read2(letter(c),  vector_move(best_x, best_y) .. ".")
    end
    return false
end

function heal_general()
    if can_ru_healing() and prefer_ru_healing() then
        ru_healing()
        return true
    end
    if can_ely_healing() and prefer_ely_healing() then
        ely_healing()
        return true
    end
    if heal_wounds() then
        return true
    end
    if can_ru_healing() then
        ru_healing()
        return true
    end
    if can_ely_healing() then
        ely_healing()
        return true
    end
    return false
end

function plan_heal_wounds()
    if want_to_heal_wounds() then
        return heal_general()
    end
    return false
end

function plan_orbrun_heal_wounds()
    if want_to_orbrun_heal_wounds() then
        return heal_general()
    end
    return false
end

function plan_orbrun_haste()
    if want_to_orbrun_buff() and not you.status("finesse-ful") then
        return haste()
    end
    return false
end

function plan_orbrun_might()
    if want_to_orbrun_buff() then
        return might()
    end
    return false
end

function plan_haste()
    if want_to_serious_buff() then
        return haste()
    end
    return false
end

function plan_might()
    if want_to_serious_buff() then
        return might()
    end
    return false
end

function plan_orbrun_heroism()
    if can_heroism() and want_to_orbrun_buff() then
        return heroism()
    end
    return false
end

function plan_orbrun_finesse()
    if can_finesse() and want_to_orbrun_buff() then
        return finesse()
    end
    return false
end

function heal_wounds()
    if you.mutation("no potion heal") < 2
         and drink_by_name("heal wounds") then
        return true
    end
    return false
end

function haste()
    if you.hasted() or you.race() == "Formicid"
            or you.god() == "Cheibriados" then
        return false
    end

    return drink_by_name("haste")
end

function might()
    if you.mighty() then
        return false
    end

    return drink_by_name("might")
end

function attraction()
    if you.status("attractive") then
        return false
    end

    return drink_by_name("attraction")
end

function cloud_is_dangerous(cloud)
    if cloud == "flame" or cloud == "fire" then
        return (you.res_fire() < 1)
    elseif cloud == "noxious fumes" then
        return (not meph_immune())
    elseif cloud == "freezing vapour" then
        return (you.res_cold() < 1)
    elseif cloud == "poison gas" then
        return (you.res_poison() < 1)
    elseif cloud == "calcifying dust" then
        return (you.race() ~= "Gargoyle")
    elseif cloud == "foul pestilence" then
        return (not miasma_immune())
    elseif cloud == "seething chaos" or cloud == "mutagenic fog" then
        return true
    end
    return false
end

function assess_square(x, y)
    a = {}

    -- Distance to current square
    a.supdist = supdist(x, y)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_bia(3) + count_sgd(3)
            + count_divine_warrior(3) > 0
    end

    -- Can we move there?
    a.can_move = (a.supdist == 0)
                  or not view.withheld(x, y)
                      and not monster_in_way(x, y)
                      and is_traversable(x, y)
                      and not is_solid(x, y)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_monsters(a, x, y)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish(x, y)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and not intrinsic_amphibious_or_flight()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = view.is_safe_square(x, y)
    cloud = view.cloud_at(x, y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil) or a.safe
                                 or danger and not cloud_is_dangerous(cloud)

    -- Equal to 10000 if the move is not closer to any stair in
    -- good_stair_list, otherwise equal to the (min) dist to such a stair
    a.stair_closer = stair_improvement(x, y)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   reaching    - kiting slower monsters with reaching
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from a square adjacent to multiple monsters
--                 (when not cleaving)
--   fleeing     - moving towards stairs
function step_reason(a1, a2)
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow) and a1.cloud_safe then
        return false
    elseif not a1.near_ally
            and a2.stair_closer < 10000
            and a1.stair_closer > 0
            and a1.enemy_distance < 10
            and reason_to_rest(90)
            and not buffed()
            and (no_spells or starting_spell() ~= "Summon Small Mammal") then
        return "fleeing"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require some close threats that try to say adjacent to us before
        -- we'll try to move out of water. We also require that we are no worse
        -- in at least one of ranged threats or enemy distance at the new
        -- position.
        if a1.followers_to_land
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return false
        end
    elseif have_reaching() and a1.slow_adjacent > 0 and a2.adjacent == 0
                 and a2.ranged == 0 then
        return "reaching"
    elseif cleaving() then
        return false
    elseif a1.adjacent == 1 then
        return false
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2 then
        return "outnumbered"
    else
        return false
    end
end

-- determines whether moving a0->a2 is an improvement over a0->a1
-- assumes that these two moves have already been determined to be better
-- than not moving, with given reasons
function step_improvement(bestreason, reason, a1, a2)
    if reason == "fleeing" and bestreason ~= "fleeing" then
        return true
    elseif bestreason == "fleeing" and reason ~= "fleeing" then
        return false
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.adjacent + a2.ranged < a1.adjacent + a1.ranged then
        return true
    elseif a2.adjacent + a2.ranged > a1.adjacent + a1.ranged then
        return false
    elseif cleaving() and a2.ranged < a1.ranged then
        return true
    elseif cleaving() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif reason == "fleeing" and a2.stair_closer < a1.stair_closer then
        return true
    elseif reason == "fleeing" and a2.stair_closer > a1.stair_closer then
        return false
    elseif a2.enemy_distance < a1.enemy_distance then
        return true
    elseif a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.stair_closer < a1.stair_closer then
        return true
    elseif a2.stair_closer > a2.stair_closer then
        return false
    elseif a1.cornerish and not a2.cornerish then
        return true
    else
        return false
    end
end

function choose_tactical_step()
    tactical_step = nil
    tactical_reason = "none"
    if you.confused()
            or you.berserk()
            or you.constricted()
            or you.transform() == "tree"
            or you.transform() == "fungus"
            or where:find("Slime")
            or you.status("spiked") then
        return
    end
    local a0 = assess_square(0, 0)
    if a0.cloud_safe
            and not (a0.fumble and sense_danger(3))
            and (not have_reaching() or a0.slow_adjacent == 0)
            and (a0.adjacent <= 1 or cleaving())
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end
    local bestx, besty, bestreason
    local besta = nil
    local x, y
    local a
    local reason
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 then
                a = assess_square(x, y)
                reason = step_reason(a0, a)
                if reason then
                    if besta == nil
                            or step_improvement(bestreason, reason, besta,
                                a) then
                        bestx = x
                        besty = y
                        besta = a
                        bestreason = reason
                    end
                end
            end
        end
    end
    if besta then
        tactical_step = delta_to_vi(bestx, besty)
        tactical_reason = bestreason
    end
end

function plan_cloud_step()
    if tactical_reason == "cloud" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_water_step()
    if tactical_reason == "water" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_coward_step()
    if tactical_reason == "hiding" or tactical_reason == "stealth" then
        if tactical_reason == "hiding" then
            hiding_turn_count = you.turns()
        end
        dsay("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_flee_step()
    if tactical_reason == "fleeing" then
        dsay("FLEEEEING.")
        set_stair_target(tactical_step)
        last_flee_turn = you.turns()
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_other_step()
    if tactical_reason ~= "none" then
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_berserk()
    if can_berserk() and want_to_berserk() then
        berserk()
        return true
    end
    return false
end

function plan_heroism()
    if can_heroism() and want_to_heroism() then
        heroism()
        return true
    end
    return false
end

function plan_recall()
    if can_recall() and want_to_recall() then
        recall()
        return true
    end
    return false
end

function plan_recall_ancestor()
    if can_recall_ancestor() and want_to_recall_ancestor() then
        recall_ancestor()
        return true
    end
    return false
end

function plan_zig_fog()
    if not where:find("Zig")
         or you.berserk() or you.teleporting() or you.confused()
         or not danger or not hp_is_low(70)
         or count_monsters_near(0, 0, LOS) - count_monsters_near(0, 0, 2) < 15
         or view.cloud_at(0, 0) ~= nil then
        return false
    end
    return read_by_name("fog")
end

function plan_finesse()
    if can_finesse() and want_to_finesse() then
        finesse()
        return true
    end
    return false
end

function plan_slouch()
    if can_slouch() and want_to_slouch() then
        slouch()
        return true
    end
    return false
end

function plan_drain_life()
    if can_drain_life() and want_to_drain_life() then
        drain_life()
        return true
    end
    return false
end

function want_to_bia()
    if not danger then
        return false
    end

    -- Always BiA this list of monsters.
    if (check_monster_list(LOS, bia_necessary_monsters)
                -- If piety as high, we can also use BiA as a fallback for when
                -- we'd like to berserk, but can't, or if when we see nasty
                -- monsters.
                or you.piety_rank() > 4
                    and (want_to_berserk() and not can_berserk()
                        or check_monster_list(LOS, nasty_monsters)))
            and count_bia(4) == 0
            and not you.teleporting() then
        return true
    end
    return false
end

function want_to_finesse()
    if danger and where:find("Zig") and hp_is_low(80)
            and count_monsters_near(0, 0, LOS) >= 5 then
        return true
    end
    if danger and check_monster_list(LOS, nasty_monsters)
            and not you.teleporting() then
        return true
    end
    return false
end

function want_to_slouch()
    if danger and you.piety_rank() == 6 and not you.teleporting()
            and estimate_slouch_damage() >= 6 then
        return true
    end
    return false
end

function want_to_drain_life()
    if not danger then
        return false
    end
    return count_monsters(LOS, function(m) return m:res_draining() == 0 end)
end

function want_to_sgd()
    if you.skill("Invocations") >= 12
            and (check_monster_list(LOS, nasty_monsters)
                or hp_is_low(50) and immediate_danger) then
        if count_sgd(4) == 0 and not you.teleporting() then
            return true
        end
    end
    return false
end

function want_to_cleansing_flame()
    if not check_monster_list(1, scary_monsters, mons_is_holy_vulnerable)
            and check_monster_list(2, scary_monsters, mons_is_holy_vulnerable)
        or count_monsters(2, mons_is_holy_vulnerable) > 8 then
        return true
    end

    local filter = function(m)
        local holiness = m:holiness()
        return not m:desc():find("summoned")
            and (holiness == "undead"
                or holiness == "demonic"
                or holiness == "evil")
    end
    if hp_is_low(50) and immediate_danger then
        local flame_restore_count = count_monsters(2, filter)
        return flame_restore_count > count_monsters(1, filter)
            and flame_restore_count >= 4
    end

    return false
end

function want_to_divine_warrior()
    return you.skill("Invocations") >= 8
        and (check_monster_list(LOS, nasty_monsters)
            or hp_is_low(50) and immediate_danger)
        and count_divine_warrior(4) == 0
        and not you.teleporting()
end

function want_to_orbrun_divine_warrior()
    return danger and count_pan_lords(LOS) > 0
        and count_divine_warrior(4) == 0 and not you.teleporting()
end

function drain_level()
    local drain_levs = { ["lightly drained"] = 1, ["drained"] = 2,
        ["heavily drained"] = 3, ["very heavily drained"] = 4,
        ["extremely drained"] = 5 }
    for s, v in pairs(drain_levs) do
        if you.status(s) then
            return v
        end
    end
    return 0
end

function want_to_apocalypse()
    local dlevel = drain_level()
    return dlevel == 0 and check_monster_list(LOS, scary_monsters)
        or dlevel <= 2
            and (danger and hp_is_low(50)
                or check_monster_list(LOS, nasty_monsters))
end

function bad_corrosion()
    if you.corrosion() == base_corrosion then
        return false
    elseif where:find("Slime") then
        return you.corrosion() >= 6 + base_corrosion and hp_is_low(70)
    else
        return (you.corrosion() >= 3 + base_corrosion and hp_is_low(50)
            or you.corrosion() >= 4 + base_corrosion and hp_is_low(70))
    end
end

function want_to_teleport()
    if where:find("Zig") then
        return false
    end
    if count_hostile_sgd(LOS) > 0 and you.xl() < 21 then
        sgd_timer = you.turns()
        return true
    end
    if where == "Pan"
            and (count_monster_by_name(LOS, "hellion") >= 3
                or count_monster_by_name(LOS, "daeva") >= 3) then
        dislike_pan_level = true
        return true
    end
    if you.xl() <= 17 and not can_berserk() and count_big_slimes(LOS) > 0 then
        return true
    end
    return immediate_danger and bad_corrosion()
            or you.god() ~= "Trog" and immediate_danger and hp_is_low(25)
            or you.god() == "Trog"
                and you.slowed()
                and want_to_berserk()
                and not can_berserk()
                and count_bia(4) == 0
            or count_nasty_hell_monsters(LOS) >= 9
end

function want_to_orbrun_teleport()
    return hp_is_low(33) and sense_danger(2)
end

function want_to_heal_wounds()
    if danger and can_ely_healing() and hp_is_low(50)
            and you.piety_rank() >= 5 then
        return true
    end
    return (danger and hp_is_low(25))
end

function want_to_orbrun_heal_wounds()
    if danger then
        return hp_is_low(25) or hp_is_low(50) and you.teleporting()
    else
        return hp_is_low(50)
    end
end

function want_to_orbrun_buff()
    return count_pan_lords(LOS) > 0 or check_monster_list(LOS, scary_monsters)
end

function want_to_serious_buff()
    if danger and where:find("Zig")
            and hp_is_low(50)
            and count_monsters_near(0, 0, LOS) >= 5 then
        return true
    end
    if you.god() == "Okawaru" or you.god() == "Trog" then
        return false -- these gods have their own buffs
    end
    if you.num_runes() < 3 then
        return false -- none of these uniques exist early
    end
    if you.teleporting() then
        return false -- don't waste a potion if we are already leaving
    end
    return check_monster_list(LOS, ridiculous_uniques)
end

function want_resistance()
    return check_monster_list(LOS, fire_resistance_monsters)
            and you.res_fire() < 3
        or check_monster_list(LOS, cold_resistance_monsters)
            and you.res_cold() < 3
        or check_monster_list(LOS, elec_resistance_monsters)
            and you.res_shock() < 1
        or check_monster_list(LOS, pois_resistance_monsters)
            and you.res_poison() < 1
        or where:find("Zig")
            and check_monster_list(LOS, acid_resistance_monsters)
            and not you.res_corr()
end

function want_magic_points()
    return (you.where() == "Tomb:2" or you.where() == "Tomb:3")
        and (can_cleansing_flame(true)
                and not can_cleansing_flame()
                and want_to_cleansing_flame()
            or can_divine_warrior(true)
                and not can_divine_warrior()
                and want_to_divine_warrior())
end

function want_to_hand()
    return check_monster_list(LOS, hand_monsters)
end

function want_to_berserk()
    return (hp_is_low(50) and sense_danger(2, true)
        or check_monster_list(2, scary_monsters)
        or (invisi_sigmund and not options.autopick_on))
end

function want_to_heroism()
    return danger
        and (hp_is_low(70)
            or check_monster_list(LOS, scary_monsters)
            or count_monsters_near(0, 0, LOS) >= 4)
end

function want_to_recall()
    if immediate_danger and hp_is_low(66) then
        return false
    end
    local mp, mmp = you.mp()
    return (mp == mmp)
end

function want_to_recall_ancestor()
    return (count_elliptic(LOS) == 0)
end

function want_to_stay_in_abyss()
    return game_status == "abyss"
        and not you.have_rune("abyssal")
        and not hp_is_low(50)
end

function have_pan_runes()
    return you.have_rune("demonic")
        and you.have_rune("fiery")
        and you.have_rune("dark")
        and you.have_rune("magical")
        and you.have_rune("glowing")
end

function have_hell_runes()
    return you.have_rune("iron")
        and you.have_rune("obsidian")
        and you.have_rune("icy")
        and you.have_rune("bone")
end

function want_to_be_in_pan()
    return (game_status == "pan" and not have_pan_runes())
end

function plan_wait_for_melee()
    is_waiting = false
    if sense_danger(1)
            or have_reaching() and sense_danger(2)
            or not options.autopick_on
            or you.berserk()
            or you.have_orb()
            or count_bia(LOS) > 0
            or count_sgd(LOS) > 0
            or count_divine_warrior(LOS) > 0
            or not view.is_safe_square(0, 0)
            or view.feature_at(0, 0) == "shallow_water" and not you.flying()
            or where:find("Abyss") then
        wait_count = 0
        return false
    end
    if you.turns() >= last_wait + 10 then
        wait_count = 0
    end
    if (not danger) or wait_count >= 10 then
        return false
    end
    -- hack to make us wait when we enter v5 so we don't move off stairs
    if v5_entry_turn and you.turns() <= v5_entry_turn + 2 then
        is_waiting = true
        return false
    end
    count = 0
    sleeping_count = 0
    local e
    for _, e in ipairs(enemy_list) do
        if is_ranged(e.m) then
            wait_count = 0
            return false
        end
        if e.m:reach_range() >= 2 and supdist(e.x, e.y) <= 2 then
            wait_count = 0
            return false
        end
        if will_tab(e.x, e.y, 0, 0, mons_tabbable_square) and not
             (e.m:name() == "wandering mushroom" or
                e.m:name():find("vortex") or
                e.m:desc():find("fleeing") or
                e.m:status("paralysed") or
                e.m:status("confused") or
                e.m:status("petrified")) then
            count = count + 1
            if e.m:desc():find("sleeping") or e.m:desc():find("dormant") then
                sleeping_count = sleeping_count + 1
            end
        end
    end
    if count == 0 then
        return false
    end
    -- say "Waiting for monsters to approach."
    if sleeping_count == 0 then
        wait_count = wait_count + 1
    end
    last_wait = you.turns()
    if plan_cure_poison() then
        return true
    end
    -- don't actually wait yet, because we might use a ranged attack instead
    is_waiting = true
    return false
end

function plan_wait_spit()
    if not is_waiting then
        return false
    end
    if you.mutation("spit poison") < 1 then
        return false
    end
    if you.berserk() or you.confused() or you.breath_timeout() then
        return false
    end
    if you.xl() > 11 then
        return false
    end
    local best_dist = 10
    local cur_e = none
    local e
    for _, e in ipairs(enemy_list) do
        local dist = supdist(e.x, e.y)
        if dist < best_dist and e.m:res_poison() < 1 then
            best_dist = dist
            cur_e = e
        end
    end
    ab_range = 6
    ab_name = "Spit Poison"
    if you.mutation("spit poison") > 2 then
        ab_range = 7
        ab_name = "Breathe Poison Gas"
    end
    if best_dist <= ab_range then
        if use_ability(ab_name,
                "r" .. vector_move(cur_e.x, cur_e.y) .. "\r") then
            return true
        end
    end
    return false
end

function starting_spell()
    if you.god() == "Trog" or you.xl() > 9 then
        no_spells = true
        return
    end
    local spell_list = {"Shock", "Magic Dart", "Sandblast", "Foxfire",
        "Freeze", "Pain", "Summon Small Mammal", "Beastly Appendage", "Sting"}
    for _, sp in ipairs(spell_list) do
        if spells.memorised(sp) and spells.fail(sp) <= 25 then
            return sp
        end
    end
    no_spells = true
end

function spell_range(sp)
    if sp == "Summon Small Mammal" then
        return LOS
    elseif sp == "Beastly Appendage" then
        return 4
    elseif sp == "Sandblast" then
        return 3
    else
        return spells.range(sp)
    end
end

function spell_castable(sp)
    if sp == "Beastly Appendage" then
        if transformed() then
            return false
        end
    elseif sp == "Summon Small Mammal" then
        local x, y
        local count = 0
        for x = -LOS, LOS do
            for y = -LOS, LOS do
                m = monster_array[x][y]
                if m and m:attitude() == ATT_FRIENDLY then
                    count = count + 1
                end
            end
        end
        if count >= 4 then
            return false
        end
    elseif sp == "Sandblast" then
        if not have_item("missile", "stone") then
            return false
        end
    end
    return true
end

function plan_starting_spell()
    if no_spells then
        return false
    end
    if you.silenced() or you.confused() or you.berserk() then
        return false
    end
    local sp = starting_spell()
    if not sp then
        return false
    end
    if cmp() < spells.mana_cost(sp) then
        return false
    end
    if you.xl() > 4 and not is_waiting then
        return false
    end
    local dist = distance_to_tabbable_enemy(0, 0)
    if dist < 2 and wskill() ~= "Unarmed Combat" then
        local weap = items.equipped_at("Weapon")
        if weap and weap.weap_skill == wskill() then
            return false
        end
    end
    if dist > spell_range(sp) then
        return false
    end
    if not spell_castable(sp) then
        return false
    end
    say("CASTING " .. sp)
    if spells.range(sp) > 0 then
        magic("z" .. spells.letter(sp) .. "f")
    else
        magic("z" .. spells.letter(sp))
    end
    return true
end

function plan_wait_throw()
    if not is_waiting then
        return false
    end

    if distance_to_enemy(0, 0) < 3 then
        return false
    end

    local missile
    _, missile = best_missile()
    if missile then
        local cur_missile = items.fired_item()
        if cur_missile and missile.name() == cur_missile.name() then
            magic("ff")
        else
            magic("Q*" .. letter(missile) .. "ff")
        end
        return true
    else
        return false
    end
end

function plan_wait_wait()
    if not is_waiting then
        return false
    end
    magic("s")
    return true
end

function plan_attack()
    if danger and attack() then
        return true
    end
    return false
end

function plan_easy_rest()
    if should_rest() then
        easy_rest()
        return true
    end
    return false
end

function plan_rest()
    if should_rest() then
        rest()
        return true
    end
    return false
end

function plan_orbrun_rest()
    if you.confused() or you.slowed() or
         you.berserk() or you.teleporting() or you.silencing() or
         transformed() then
        rest()
        return true
    end
    return false
end

function plan_abyss_rest()
    local hp, mhp = you.hp()
    if you.confused() or you.slowed() or
         you.berserk() or you.teleporting() or you.silencing() or
         transformed() or hp < mhp and you.regenerating() then
        rest()
        return true
    end
    return false
end

function magicfind(target, secondary)
    -- This will be turned on again in ready().
    offlevel_travel = false
    if secondary then
        crawl.sendkeys(control('f') .. target .. "\r", arrowkey('d'), "\r\r" ..
            string.char(27) .. string.char(27) .. string.char(27))
    else
        magic(control('f') .. target .. "\r\r\r")
    end
end

function god_options()
    return c_persist.cur_god_list or GOD_LIST
end

function endgame_plan_options()
    local plan = c_persist.cur_endgame_plan or ENDGAME_PLAN
    return ENDGAME_PLANS[plan]
end

function plan_find_altar()
    if not want_altar() then
        return false
    end
    str = "@altar&&<<of " .. table.concat(god_options(), "||of ")
    if FADED_ALTAR then
        str = str .. "||of an unknown god"
    end
    str = str .. ">>"
    magicfind(str)
    return true
end

-- local tried_find_altar_turn = -1
function plan_find_conversion_altar()
    if unshafting() then
        return false
    end
    if game_status == "tso" and you.god() ~= "the Shining One" then
        str = "altar of the Shining One"
    elseif LUGONU_CONVERSION and you.xl() == 12 and you.god() == "Lugonu" then
        str = "altar of Makhleb"
    else
        return false
    end
    expect_new_location = true
    magicfind(str)
    -- Currently broken.
--  if tried_find_altar_turn ~= you.turns() then
--      tried_find_altar_turn = you.turns()
--      magicfind(str)
--      return true
--  end
--  -- magicfind(str, true)
    return true
end

function plan_abandon_god()
    if you.god() ~= "No God" and you.num_runes() == 0
         and not util.contains(god_options(), you.god()) then
        magic("aXYY")
        return true
    end
    return false
end

function plan_unwield_weapon()
    if wskill() ~= "Unarmed Combat" then
        return false
    end
    if not items.equipped_at("Weapon") then
        return false
    end
    magic("w-")
    return true
end

function plan_join_beogh()
    if you.race() ~= "Hill Orc" or not want_altar() or you.confused() then
        return false
    end
    for _, god in ipairs(god_options()) do
        if god == "Beogh" and use_ability("Convert to Beogh", "YY") then
            return true
        end
    end
    return false
end

function plan_convert()
    if (game_status ~= "tso" or you.god() == "the Shining One"
            or view.feature_at(0, 0) ~= "altar_the_shining_one") and
         ((not LUGONU_CONVERSION) or you.god() ~= "Lugonu"
            or view.feature_at(0, 0) ~= "altar_makhleb") then
        return false
    end
    if you.silenced() then
        rest()
    else
        if view.feature_at(0, 0) == "altar_makhleb" then
            for i, br in ipairs(c_persist.branches_entered) do
                if br == "L" then
                    table.remove(c_persist.branches_entered, i)
                end
            end
        end
        magic("<JY")
    end
    return true
end

function plan_join_god()
    if not want_altar() then
        return false
    end
    feat = view.feature_at(0, 0)
    for _, god in ipairs(god_options()) do
        if feat == ("altar_" .. string.gsub(string.lower(god), " ", "_")) then
            if you.silenced() then
                rest()
            else
                magic("<J")
            end
            return true
        end
    end
    if FADED_ALTAR and feat == "altar_ecumenical" then
        if you.silenced() then
            rest()
        else
            magic("<J")
        end
        return true
    end
    return false
end

function plan_autoexplore()
    if free_inventory_slots() == 0 then
        return false
    end
    magic("o")
    return true
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
                return read2(scroll_letter, ".Y" .. string.char(27) .. "YB")
            else
                return read2(scroll_letter, ".Y" .. string.char(27) .. "YC")
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
        end
    end
    if not id_scroll then
        return false
    end
    local oldslots = { }
    local newslots = {[0] = 'B', [1] = 'N', [2] = 'Y'} -- harmless keys
    local count = 0
    if id_scroll.quantity > 1 then
        for it in inventory() do
            if it.class(true) == "potion" and not it.fully_identified then
                oldname = it.name()
                if read2(id_scroll, letter(it)) then
                    say("IDENTIFYING " .. oldname)
                    return true
                end
            end
        end
    end
    return false
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
    if in_branch("Z") then
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
        return name:find("robe of fire resistance")
    end
end

-- do we want to keep this brand?
function brand_is_great(brand)
    if brand == "speed" then
        return true
    elseif brand == "vampirism" then
        return not you.have_orb()
    elseif brand == "spectralizing" then
        return true
    elseif brand == "electrocution" then
        return where ~= "Zot:5"
    elseif brand == "holy wrath" then
        return where == "Zot:5" or you.have_orb() or PAN_RUNE or HELL_RUNE
        or GOLDEN_RUNE
    else
        return false
    end
end

function plan_use_good_consumables()
    for it in inventory() do
        if it.class(true) == "scroll" and can_read() then
            if it.name():find("acquirement") then
                if view.feature_at(0, 0) ~= "deep_water"
                        and view.feature_at(0, 0) ~= "lava" then
                    if read(it) then
                        return true
                    end
                end
            elseif it.name():find("enchant weapon") then
                weapon = items.equipped_at("weapon")
                if weapon and weapon.class(true) == "weapon"
                        and not weapon.artefact and weapon.plus < 9 then
                    oldname = weapon.name()
                    if read2(it, letter(weapon)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
            elseif it.name():find("brand weapon") then
                weapon = items.equipped_at("weapon")
                if weapon and weapon.class(true) == "weapon"
                        and not weapon.artefact
                        and not brand_is_great(weapon.ego()) then
                    oldname = weapon.name()
                    if read2(it, letter(weapon)) then
                        say("BRANDING " .. oldname .. ".")
                        return true
                    end
                end
            elseif it.name():find("enchant armour") then
                body = items.equipped_at("Body Armour")
                ac = armour_ac()
                if body and not body.artefact and body.plus < ac
                         and body_armour_is_great(body)
                         and not body.name():find("quicksilver dragon") then
                    oldname = body.name()
                    if read2(it, letter(body)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
                for _, slotname in pairs(good_slots) do
                    if slotname ~= "Body Armour" and slotname ~= "Shield" then
                        it2 = items.equipped_at(slotname)
                        if it2 and not it2.artefact and it2.plus < 2
                            and it2.plus >= 0
                            and not it2.name():find("scarf") then
                            oldname = it2.name()
                            if read2(it, letter(it2)) then
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
                            oldname = it2.name()
                            if read2(it, letter(it2)) then
                                say("ENCHANTING " .. oldname .. ".")
                                return true
                            end
                        end
                    end
                end
                if body and not body.artefact and body.plus < ac
                     and body_armour_is_good(body)
                     and not body.name():find("quicksilver dragon scales") then
                    oldname = body.name()
                    if read2(it, letter(body)) then
                        say("ENCHANTING " .. oldname .. ".")
                        return true
                    end
                end
            end
        elseif it.class(true) == "potion" then
            if it.name():find("experience") then
                return drink(it)
            end
            if it.name():find("mutation") then
                if base_mutation("inhibited regeneration") > 0
                            and you.race() ~= "Ghoul"
                        or base_mutation("teleportitis") > 0
                        or base_mutation("inability to read while threatened") > 0
                        or base_mutation("deformed body") > 0
                            and you.race() ~= "Naga"
                            and you.race() ~= "Palentonga"
                            and (armour_plan() == "heavy"
                                or armour_plan() == "large")
                        or base_mutation("berserk") > 0
                        or base_mutation("deterioration") > 1
                        or base_mutation("frail") > 0
                        or base_mutation("no potion heal") > 0
                            and you.race() ~= "Vine Stalker" then
                    if you.god() ~= "Zin" then
                        return drink(it)
                    elseif you.piety_rank() >= 6
                            and not you.one_time_ability_used()
                            and use_ability("Cure All Mutations", "Y") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function base_mutation(str)
    return you.mutation(str) - you.temp_mutation(str)
end

function is_melee_weapon(it)
    return it
        and it.class(true) == "weapon"
        and it.weap_skill ~= "Ranged Weapons"
end

function plan_wield_weapon()
    local weap = items.equipped_at("Weapon")
    if is_melee_weapon(weap) or you.berserk() or transformed() then
        return false
    end
    if wskill() == "Unarmed Combat" then
        return false
    end
    for it in inventory() do
        if it and it.class(true) == "weapon" then
            if should_equip(it) then
                l = items.index_to_letter(it.slot)
                say("Wielding weapon " .. it.name() .. ".")
                magic("w" .. l .. "YY")
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
    if you.race() == "Troll" or you.berserk() or transformed()
            or not items.equipped_at("Weapon") then
        return false
    end
    local sit, e
    if you.xl() < 18 then
        for _, e in ipairs(enemy_list) do
            if supdist(e.x, e.y) <= 3
                    and string.find(e.m:desc(), "hydra")
                    and will_tab(0, 0, e.x, e.y, tabbable_square) then
                sit = "hydra"
            end
        end
    end
    if in_extended() then
        sit = "extended"
    end
    twohands = true
    if items.equipped_at("Shield") and you.race() ~= "Formicid" then
        twohands = false
    end
    it_old = items.equipped_at("Weapon")
    swappable = can_swap("Weapon")
    if not swappable then
        return false
    end
    cur_val = weapon_value(it_old, true, it_old, sit)
    max_val = cur_val
    max_it = nil
    for it in inventory() do
        if it and it.class(true) == "weapon" and not it.equipped then
            if twohands or it.hands < 2 then
                val2 = weapon_value(it, true, it_old, sit)
                if val2 > max_val then
                    max_val = val2
                    max_it = it
                end
            end
        end
    end
    if max_it then
        l = items.index_to_letter(max_it.slot)
        say("SWAPPING to " .. max_it.name() .. ".")
        magic("w" .. l .. "YY")
        -- this might have a 0-turn fail because of unIDed holy
        return nil
    end
    return false
end

function plan_bless_weapon()
    if you.god() ~= "the Shining One" or you.one_time_ability_used()
         or you.piety_rank() < 6 or you.silenced() then
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

function plan_maybe_pickup_acquirement()
    if acquirement_pickup then
        magic(";")
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
    local sit
    if in_extended() then
        sit = "extended"
    end
    twohands = true
    if items.equipped_at("Shield") and you.race() ~= "Formicid" then
        twohands = false
    end
    it_old = items.equipped_at("Weapon")
    swappable = can_swap("Weapon")
    for it in inventory() do
        if it and it.class(true) == "weapon" and not it.equipped then
            local equip = false
            local drop = false
            if should_upgrade(it, it_old, sit) then
                equip = true
            elseif should_drop(it) then
                drop = true
            end
            if equip and swappable and (twohands or it.hands < 2) then
                l = items.index_to_letter(it.slot)
                say("UPGRADING to " .. it.name() .. ".")
                magic("w" .. l .. "YY")
                -- this might have a 0-turn fail because of unIDed holy
                return nil
            end
            if drop then
                l = items.index_to_letter(it.slot)
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. l .. "\r")
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
    it_old = items.equipped_at("Amulet")
    swappable = can_swap("Amulet")
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
                l = items.index_to_letter(it.slot)
                say("UPGRADING to " .. it.name() .. ".")
                magic("P" .. l .. "YY")
                return true
            end
            if drop then
                l = items.index_to_letter(it.slot)
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. l .. "\r")
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
    local empty = (empty_ring_slots() > 0)
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
                    if not equip and not it_old.cursed and should_upgrade(it, it_old) then
                        equip = true
                        swap = it_old.slot
                    end
                end
            end
            if not equip and should_drop(it) then
                drop = true
            end
            if equip then
                l = items.index_to_letter(it.slot)
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
                l = items.index_to_letter(it.slot)
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. l .. "\r")
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
    if cloudy or you.mesmerised() then
        return false
    end
    for it in inventory() do
        if it and it.class(true) == "armour" and not it.equipped then
            local st, _ = it.subtype()
            local equip = false
            local drop = false
            local swappable
            it_old = items.equipped_at(good_slots[st])
            swappable = can_swap(good_slots[st])
            if should_upgrade(it, it_old) then
                equip = true
            elseif should_drop(it) then
                drop = true
            end
            if good_slots[st] == "Helmet" and it.ac == 1 and (you.mutation("horns") > 0
                 or you.mutation("beak") > 0 or you.mutation("antennae") > 0) then
                equip = false
                drop = true
            end
            if good_slots[st] == "Helmet" and
                 (you.mutation("horns") >= 3 or you.mutation("antennae") >= 3) then
                equip = false
                drop = true
            end
            if it.name():find("boots") and
                 (you.mutation("talons") >= 3 or you.mutation("hooves") >= 3) then
                equip = false
                drop = true
            end
            if it.name():find("boots") and you.race() == "Merfolk"
                 and (view.feature_at(0, 0) == "shallow_water" or
                         view.feature_at(0, 0) == "deep_water") then
                equip = false
                drop = false
            end
            if good_slots[st] == "Gloves" and you.mutation("claws") >= 3 then
                equip = false
                drop = true
            end
            if equip and swappable then
                l = items.index_to_letter(it.slot)
                say("UPGRADING to " .. it.name() .. ".")
                magic("W" .. l .. "YN")
                upgrade_phase = true
                return true
            end
            if drop then
                l = items.index_to_letter(it.slot)
                say("DROPPING " .. it.name() .. ".")
                magic("d" .. l .. "\r")
                return true
            end
        end
    end
    for it in inventory() do
        if it and it.equipped and it.class(true) == "armour" and not it.cursed
                    and should_remove(it) then
            l = items.index_to_letter(it.slot)
            say("REMOVING " .. it.name() .. ".")
            magic("T" .. l .. "YN")
            return true
        end
    end
    return false
end

function plan_go_up()
    local feat = view.feature_at(0, 0)
    if feat:find("stone_stairs_up") or feat == "escape_hatch_up"
         or feat == "exit_zot" or feat == "exit_dungeon"
         or feat == "exit_depths" then
        if you.mesmerised() then
            return false
        end
        expect_new_location = true
        magic("<")
        return true
    end
    return false
end

function plan_go_down()
    local feat = view.feature_at(0, 0)
    if feat:find("stone_stairs_down") then
        expect_new_location = true
        magic(">")
        return true
    end
    return false
end

function ready_for_lair()
    if you.god() == "Trog"
            or you.god() == "Cheibriados"
            or you.god() == "Okawaru"
            or you.god() == "Qazlal"
            or you.god() == "the Shining One"
            or you.god() == "Lugonu"
            or you.god() == "Uskayaw"
            or you.god() == "Xom"
            or you.god() == "Zin"
            or (you.god() == "Beogh"
                or you.god() == "Makhleb"
                or you.god() == "Yredelemnul") and you.piety_rank() >= 4
            or (you.god() == "Ru" or you.god() == "Elyvilon")
                and you.piety_rank() >= 3
            or you.god() == "Hepliaklqana" and you.piety_rank() >= 2 then
        return true
    end
    return false
end

function feat_is_upstairs(feat)
    return (feat:find("stone_stairs_up") or
                    feat:find("exit_") and (feat == "exit_hell" or feat == "exit_vaults"
                    or feat == "exit_zot" or feat == "exit_slime_pits"
                    or feat == "exit_orcish_mines" or feat == "exit_lair"
                    or feat == "exit_crypt" or feat == "exit_snake_pit"
                    or feat == "exit_elven_halls" or feat == "exit_tomb"
                    or feat == "exit_swamp" or feat == "exit_shoals"
                    or feat == "exit_spider_nest" or feat == "exit_depths"))
end

function want_to_stairdance_up()
    if not feat_is_upstairs(view.feature_at(0, 0)) then
        return false
    end

    local n = stairdance_count[where] or 0
    if n >= 20 then
        return false
    end

    if you.caught()
            or you.mesmerised()
            or you.constricted()
            or you.rooted()
            or you.transform() == "tree"
            or you.transform() == "fungus"
         or count_bia(3) > 0
         or count_sgd(3) > 0
         or count_divine_warrior(3) > 0 then
        return false
    end

    local only_when_safe = you.berserk() or hp_is_low(33)
    local follow_count = 0
    local other_count = 0
    local e
    for _, e in ipairs(enemy_list) do
        if supdist(e.x, e.y) == 1
                and e.m:stabbability() == 0
                and can_use_stairs(e.m) then
            follow_count = follow_count + 1
        else
            other_count = other_count + 1
        end
    end
    if only_when_safe and follow_count > 0 then
        return false
    end
    if follow_count == 0
                and (reason_to_rest(90) or you.status("spiked"))
                and not buffed()
            or other_count > 0
                and follow_count > 0 then
        stairdance_count[where] = n + 1
        return true
    end
    return false
end

-- adding some clua for this would be better
function can_use_stairs(m)
    local mname = m:name()

    if m:is_stationary()
            or mons_liquid_bound(m)
            or mname:find("zombie")
            or mname:find("skeleton")
            or mname:find("spectral")
            or mname:find("simulacrum")
            or mname:find("tentacle")
            or mname == "silent spectre"
            or mname == "Geryon"
            or mname == "Royal Jelly"
            or mname == "bat"
            or mname == "unseen horror"
            or mname == "fire vortex" then
        return false
    else
        return true
    end
end

function plan_stairdance_up()
    if want_to_stairdance_up() then
        expect_new_location = true
        -- set travel_destination to the current location in case we
        -- leave the branch while stairdancing
        if not travel_destination then
            travel_destination = cur_branch()
        end
        say("STAIRDANCE")
        if you.status("spiked") then
            magic("<Y")
        else
            magic("<")
        end
        return true
    end
    return false
end

function plan_tomb2_arrival()
    if not tomb2_entry_turn
            or you.turns() >= tomb2_entry_turn + 5
            or c_persist.did_tomb2_buff then
        return false
    end

    if not you.hasted() then
        return haste()
    elseif not you.status("attractive") then
        if attraction() then
            c_persist.did_tomb2_buff = true
            return true
        end
        return false
    end
end

function plan_tomb3_arrival()
    if not tomb3_entry_turn
            or you.turns() >= tomb3_entry_turn + 5
            or c_persist.did_tomb3_buff then
        return false
    end

    if not you.hasted() then
        return haste()
    elseif not you.status("attractive") then
        if attraction() then
            c_persist.did_tomb3_buff = true
            return true
        end
        return false
    end
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
            -- Should in theory also work in Bazaar, but doesn't make much sense
            -- (since we won't really return or acquire money and travel back here)
            elseif not on_list
                 and not you.where():find("Bazaar") and not zot_soon() then
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
    if game_status ~= "shopping" then
        return false
    end
    which_item = can_afford_any_shoplist_item()
    if not which_item then
        -- Remove everything on shoplist
        clear_out_shopping_list()
        -- Set travel_destination if necessary so that we will return to D.
        if not in_branch("D") then
            travel_destination = "D"
        end
        -- record that we are done shopping this game
        c_persist.done_shopping = true
        update_game_status()
        return false
    end
    say("SHOPPING SPREE")
    magic("$" .. letter(which_item - 1))
    expect_new_location = true
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
        return false
    end
    say("CLEARING SHOPPING LIST")
    -- Press ! twice to toggle action to 'delete'
    local clear_shoplist_magic = "$!!"
    for n, it in ipairs(shoplist) do
        clear_shoplist_magic = clear_shoplist_magic .. "a"
    end
    magic(clear_shoplist_magic)
    return false
end

function plan_simple_go_down()
    if travel_destination or unshafting() then
        return false
    end
    if (found_branch("L") and ready_for_lair() or where == "D:11") and not
         util.contains(c_persist.branches_entered, "L") then
        return false
    end
    if where == "Vaults:4" and easy_runes() < 2 then
        return false
    end
    if where == "Tomb:1" or where == "Tomb:2" or where == "Tomb:3" then
        return false
    end
    expect_new_location = true
    magic("G>")
    return true
end

function want_altar()
    return you.race() ~= "Demigod" and you.num_runes() == 0
        and not util.contains(god_options(), you.god())
end

function plan_go_to_temple()
    local c = c_persist.plan_fail_count["try_go_to_temple"]
    if c and c >= 100 then
        return false
    end
    if found_branch("T")
            and (want_altar() or TSO_CONVERSION or LUGONU_CONVERSION)
            and not util.contains(c_persist.branches_entered, "T")
            and in_branch("D") then
        expect_new_location = true
        magic("GTY")
        return true
    end
    return false
end

function plan_enter_branch()
    local br
    if found_branch("L") and ready_for_lair() and not
         util.contains(c_persist.branches_entered, "L") and in_branch("D") then
        br = "L"
    elseif found_branch("O") and not LATE_ORC and not
                 util.contains(c_persist.branches_entered, "O") and in_branch("D") and
                 util.contains(c_persist.branches_entered, "L") then
        br = "O"
    end
    if br then
        expect_new_location = true
        magic("G" .. br .. "\rY")
        return true
    end
    return false
end

function plan_go_to_portal_entrance()
    for _, por in ipairs(c_persist.portals_found) do
        for _, val in ipairs(portal_data) do
            if val[1] == por then
                magicfind("@" .. val[2])
                return true
            end
        end
    end
    return false
end

function plan_go_to_zig()
    if not where:find("Depths") or game_status ~= "zig" or c_persist.entered_zig then
        return false
    else
        expect_new_location = true
        magicfind("gateway to a ziggurat")
        return true
    end
end

function plan_go_to_zig_dig()
    if not where:find("Depths") or game_status ~= "zig" or c_persist.entered_zig
         or view.feature_at(0, 0) == "enter_ziggurat"
         or view.feature_at(3, 1) == "enter_ziggurat"
         or count_charges("digging") == 0 then
        return false
    else
        expect_new_location = true
        off_level_travel = false
        magic(control('f') .. "gateway to a ziggurat" .. "\rayby\r")
        return true
    end
end

function plan_zig_dig()
    if not where:find("Depths") or game_status ~= "zig" or c_persist.entered_zig
         or view.feature_at(3, 1) ~= "enter_ziggurat" then
        return false
    else
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "L")
            return true
        end
    end
    return false
end

function plan_go_to_portal_exit()
    if in_portal() then
        magic("X<\r")
        return true
    end
    return false
end

function plan_go_to_abyss_portal()
    if not where:find("Depths") or not want_to_stay_in_abyss() then
        return false
    else
        expect_new_location = true
        magicfind("one-way gate to the infinite horrors of the Abyss")
        return true
    end
end

function plan_go_to_pan_portal()
    if not where:find("Depths") or not want_to_be_in_pan() then
        return false
    else
        expect_new_location = true
        magicfind("halls of Pandemonium")
        return true
    end
end

function plan_go_to_abyss_downstairs()
    if where:find("Abyss") and want_to_stay_in_abyss()
         and where ~= "Abyss:3" and where ~= "Abyss:4" and where ~= "Abyss:5" then
        magic("X>\r")
        return true
    end
    return false
end

function plan_go_to_pan_downstairs()
    if where == "Pan" then
        magic("X>\r")
        return true
    end
    return false
end

local pan_failed_rune_count = -1
function want_to_dive_pan()
    return (where == "Pan" and you.num_runes() > pan_failed_rune_count
                    and (you.have_rune("demonic") and not have_pan_runes()
                             or dislike_pan_level))
end

function plan_dive_go_to_pan_downstairs()
    if want_to_dive_pan() then
        magic("X>\r")
        return true
    end
    return false
end

function plan_open_runed_doors()
    if where ~= "Pan" and (where ~= "Depths:3" or not PAN_RUNE) then
        return false
    end
    for x = -1, 1 do
        for y = -1, 1 do
            if view.feature_at(x, y) == "runed_door" then
                magic(delta_to_vi(x, y) .. "Y")
                return true
            end
        end
    end
    return false
end

function plan_go_to_abyss_exit()
    if want_to_stay_in_abyss() then
        return false
    end
    magic("X<\r")
    return true
end

function plan_go_to_pan_exit()
    if where == "Pan" and not want_to_be_in_pan() then
        magic("X<\r")
        return true
    end
    return false
end

function plan_dive()
    if (in_branch("M") and where ~= "Slime:5" or game_status == "hells" and
            (in_branch("I") and where ~= "Dis:7"
             or in_branch("G") and where ~= "Geh:7"
             or in_branch("X") and where ~= "Coc:7"
             or in_branch("Y") and where ~= "Tar:7"))
         and not travel_destination then
        expect_new_location = true
        magic("G>")
        return true
    end
    return false
end

function plan_early_new_travel()
    if game_status == "hells" and
         (where == "Dis:7" and you.have_rune("iron")
            or where == "Geh:7" and you.have_rune("obsidian")
            or where == "Coc:7" and you.have_rune("icy")
            or where == "Tar:7" and you.have_rune("bone"))
         and not travel_destination then
        travel_destination = "H"
        return plan_continue_travel()
    end
    return false
end

function plan_enter_zig()
    if not where:find("Depths") or game_status ~= "zig" or c_persist.entered_zig then
        return false
    end
    if view.feature_at(0, 0) == "enter_ziggurat" then
        expect_new_location = true
        c_persist.entered_zig = true
        magic(">Y")
        return true
    end
    return false
end

function plan_enter_portal()
    for _, por in ipairs(c_persist.portals_found) do
        if string.find(view.feature_at(0, 0), "enter_" .. get_feat_name(por)) then
            expect_portal = true
            expect_new_location = true
            magic(">")
            return true
        end
        return false
    end
    return false
end

function plan_exit_portal()
    if not in_portal() or you.mesmerised() then
        return false
    end
    if string.find(view.feature_at(0, 0), "exit_" .. get_feat_name(where)) then
        expect_new_location = true
        magic("<")
        return true
    end
    return false
end

function plan_enter_abyss()
    if view.feature_at(0, 0) == "enter_abyss" and want_to_stay_in_abyss() then
        expect_new_location = true
        magic(">Y")
        return true
    end
    return false
end

function plan_enter_pan()
    if view.feature_at(0, 0) == "enter_pandemonium" and want_to_be_in_pan() then
        expect_new_location = true
        magic(">Y")
        return true
    end
    return false
end

function plan_go_down_abyss()
    if view.feature_at(0, 0) == "abyssal_stair" and want_to_stay_in_abyss()
         and where ~= "Abyss:3" and where ~= "Abyss:4" and where ~= "Abyss:5" then
        expect_new_location = true
        magic(">")
        return true
    end
    return false
end

local pan_stair_turn = -100
function plan_go_down_pan()
    if view.feature_at(0, 0) == "transit_pandemonium"
         or view.feature_at(0, 0) == "exit_pandemonium" then
        if pan_stair_turn == you.turns() then
            magic("X" .. control('f'))
            return true
        end
        expect_new_location = true
        pan_stair_turn = you.turns()
        magic(">Y")
        return nil -- in case we are trying to leave a rune level
    end
    return false
end

function plan_dive_pan()
    if not want_to_dive_pan() then
        return false
    end
    if view.feature_at(0, 0) == "transit_pandemonium"
         or view.feature_at(0, 0) == "exit_pandemonium" then
        if pan_stair_turn == you.turns() then
            pan_failed_rune_count = you.num_runes()
            return false
        end
        expect_new_location = true
        pan_stair_turn = you.turns()
        dislike_pan_level = false
        magic(">Y")
        return nil -- in case we are trying to leave a rune level
    end
    return false
end

function plan_zig_leave_level()
    if not where:find("Zig") then
        return false
    end
    if where:find(tostring(ZIG_DIVE)) then
        if view.feature_at(0, 0) == "exit_ziggurat" then
            magic("<Y")
            expect_new_location = true
            return true
        end
    elseif string.find(view.feature_at(0, 0), "stone_stairs_down") then
        magic(">")
        expect_new_location = true
        return true
    end
    return false
end

function plan_lugonu_exit_abyss()
    if you.god() ~= "Lugonu" then
        return false
    end
    if (you.berserk() or you.confused() or you.silenced()
                    or you.piety_rank() < 1 or cmp() < 1) then
        return false
    end
    expect_new_location = true
    use_ability("Depart the Abyss")
    return true
end

function plan_exit_abyss()
    if view.feature_at(0, 0) == "exit_abyss"
            and not want_to_stay_in_abyss()
            and not you.mesmerised()
            and you.transform() ~= "tree" then
        expect_new_location = true
        magic("<")
        return true
    end
    return false
end

function plan_exit_pan()
    if view.feature_at(0, 0) == "exit_pandemonium"
            and not want_to_be_in_pan()
            and not you.mesmerised()
            and you.transform() ~= "tree" then
        expect_new_location = true
        magic("<")
        return true
    end
    return false
end

function plan_step_towards_branch()
    local x, y, feat
    if (stepped_on_lair or not found_branch("L"))
         and (where ~= "Crypt:3" or stepped_on_tomb or not found_branch("W")) then
        return false
    end
    for x = -LOS, LOS do
        for y = -LOS, LOS do
            feat = view.feature_at(x, y)
            if (feat == "enter_lair" or feat == "enter_tomb")
                 and you.see_cell_no_trans(x, y) then
                if x == 0 and y == 0 then
                    if where == "Crypt:3" then
                        stepped_on_tomb = true
                    else
                        stepped_on_lair = true
                    end
                    return false
                else
                    lair_step_mode = true
                    local result = move_towards(x, y)
                    lair_step_mode = false
                    return result
                end
            end
        end
    end
    return false
end

function plan_continue_travel()
    if travel_destination then
        if in_branch(travel_destination) or
             not found_branch(travel_destination) then
            travel_destination = nil
            return false
        end
        expect_new_location = true
        magic("G" .. travel_destination .. "\rY")
        return true
    end
    return false
end

function choose_lair_rune_branch()
    if RUNE_PREFERENCE == "smart" then
        if crawl.random2(2) == 0 then
            branch_options = { "N", "P", "S", "A" }
        else
            branch_options = { "N", "S", "P", "A" }
        end
    elseif RUNE_PREFERENCE == "dsmart" then
        if crawl.random2(2) == 0 then
            branch_options = { "N", "S", "P", "A" }
        else
            branch_options = { "S", "N", "P", "A" }
        end
    elseif RUNE_PREFERENCE == "nowater" then
        branch_options = { "P", "N", "S", "A" }
    else -- "random"
        if crawl.random2(2) == 0 then
            branch_options = { "P", "N", "S", "A" }
        else
            branch_options = { "S", "A", "P", "N" }
        end
    end
    for _, branch_code in ipairs(branch_options) do
        if found_branch(branch_code) and
             not util.contains(c_persist.branches_entered, branch_code) then
            return branch_code
        end
    end
    return nil
end

function choose_hell_rune_branch()
    local hell_branches = { "I", "G", "X", "Y" }
    local untried_branches = {}
    local count = 0
    for _, branch_code in ipairs(hell_branches) do
        if not util.contains(c_persist.branches_entered, branch_code) then
            table.insert(untried_branches, branch_code)
            count = count + 1
        end
    end
    if count == 0 then
        return "U" -- depths
    end
    return untried_branches[crawl.roll_dice(1, count)]
end

local depths_loop_count = 0
function plan_new_travel()
    if cloudy then
        return false
    end
    local back_to_D_places = { "Temple", "Orc:2", "Vaults:4"}
    if util.contains(back_to_D_places, where) then
        travel_destination = "D"
    end
    if where == "D:11" and not util.contains(c_persist.branches_entered, "L") then
        travel_destination = "L"
    end
    if where == "Lair:6" then
        if travel.find_deepest_explored("D") == 15 and easy_runes() < 2 then
            travel_destination = choose_lair_rune_branch()
        elseif game_status == "slime" then
            travel_destination = "M"
        else
            travel_destination = "D"
        end
    end
    if where == "Snake:4" and you.have_rune("serpentine") then
        travel_destination = "D"
    end
    if where == "Swamp:4" and you.have_rune("decaying") then
        travel_destination = "D"
    end
    if where == "Spider:4" and you.have_rune("gossamer") then
        travel_destination = "D"
    end
    if where == "Shoals:4" and you.have_rune("barnacled") then
        travel_destination = "D"
    end
    if where == "Vaults:5" and you.have_rune("silver") then
        if game_status == "tomb" then
            travel_destination = "C"
        else
            travel_destination = "D"
        end
    end
    if where == "Slime:5" and you.have_rune("slimy") then
        travel_destination = "D"
    end
    if where == "D:15" then
        if easy_runes() == 1
                    and not util.contains(c_persist.branches_entered, "V")
                or easy_runes() == 2
                    and util.contains(c_persist.branches_entered, "U")
                    and not you.have_rune("silver") then
            travel_destination = "V"
        elseif easy_runes() >= 1
                and not util.contains(c_persist.branches_entered, "U")
                and not (EARLY_SECOND_RUNE and easy_runes() == 1) then
            travel_destination = "U"
        elseif you.have_rune("silver") then
            if game_status == "slime" then
                travel_destination = "L"
            elseif game_status == "tomb" then
                travel_destination = "V"
            else
                travel_destination = "U"
            end
        elseif LATE_ORC and found_branch("O") and not
                     util.contains(c_persist.branches_entered, "O") then
            travel_destination = "O"
        else
            travel_destination = "L"
        end
    end
    if where == "Depths:4" then
        if game_status == "zot" then
            travel_destination = "Z"
        elseif game_status == "hells" then
            travel_destination = "H"
        else
            if game_status == "shopping" then
                c_persist.done_shopping = true
            end
            if depths_loop_count < 20 then
                travel_destination = "D"
                depths_loop_count = depths_loop_count + 1
            else
                game_status = "zot"
                travel_destination = "Z"
            end
        end
    end
    if where == "Hell" then
        travel_destination = choose_hell_rune_branch()
    end
    -- travel back from hell ends is handled in plan_early_new_travel()
    if where == "Crypt:3" then
        if game_status == "tomb" then
            travel_destination = "W"
        else
            travel_destination = "V"
        end
    end
    if where == "Tomb:3" and you.have_rune("golden") then
        travel_destination = "C"
    end
    return plan_continue_travel()
end

local did_ancestor_identity = false
function plan_ancestor_identity()
    if you.god() ~= "Hepliaklqana" then
        return false
    end
    if not did_ancestor_identity then
        use_ability("Ancestor Identity","\b\b\b\b\b\b\b\b\b\b\b\b\b\b\belliptic\ra")
        did_ancestor_identity = true
        return true
    end
    return false
end

function plan_ancestor_life()
    if you.god() ~= "Hepliaklqana" then
        return false
    end
    local ancestor_options = {"Knight", "Battlemage", "Hexer"}
    if use_ability("Ancestor Life: " ..
            ancestor_options[crawl.roll_dice(1, 3)], "Y") then
        return true
    end
    return false
end

function plan_sacrifice()
    if you.god() ~= "Ru" then
        return false
    end
    -- Sacrifices that we won't do for now: words, drink, courage, durability,
    -- hand, resistance, purity, health
    good_sacrifices = {
        "Sacrifice Artifice", -- 55
        "Sacrifice Love", -- 40
        "Sacrifice Experience", -- 40
        "Sacrifice Nimbleness", -- 30
        "Sacrifice Skill", -- 30
        "Sacrifice Arcana", -- 25
        "Sacrifice an Eye", -- 20
        "Sacrifice Stealth", -- 15
        "Sacrifice Essence", -- variable
        "Reject Sacrifices",
    } -- hack
    for _, sacrifice in ipairs(good_sacrifices) do
        if sacrifice == "Sacrifice Nimbleness" then
            for letter, abil in pairs(you.ability_table()) do
                if abil == sacrifice then
                    you.train_skill("Fighting", 1)
                    say("INVOKING " .. sacrifice .. ".")
                    magic("a" .. letter .. "YY")
                    return true
                end
            end
        elseif use_ability(sacrifice, "YY") then
            return true
        end
    end
    return false
end

function plan_find_upstairs()
    magic("X<\r")
    return true
end

function plan_gd1()
    expect_new_location = true
    magic("GD1\rY")
    return true
end

function plan_zig_go_to_stairs()
    if not where:find("Zig") then
        return false
    end
    if where:find(tostring(ZIG_DIVE)) then
        magic("X<\r")
    else
        magic("X>\r")
    end
    return true
end

function plan_find_downstairs()
    -- try to avoid branch entrances by going to a random > from them
    local feat = view.feature_at(0, 0)
    if feat:find("enter_") or feat == "escape_hatch_down" then
        local i, j
        local c = "X"
        j = crawl.roll_dice(1, 12)
        for i = 1, j do
            c = (c .. ">")
        end
        magic(c .. "\r")
        return true
    end
    magic("X>\r")
    return true
end

function set_waypoint()
    magic(control('w') .. waypoint_parity)
    did_waypoint = true
    return true
end

function clear_level_map(num)
    level_map[num] = {}
    for i = -100, 100 do
        level_map[num][i] = {}
    end
    stair_dists[num] = {}
end

function update_level_map(num)
    local dx, dy = travel.waypoint_delta(num)
    local val, oldval
    local staircount = #stair_dists[num]
    local newcount = staircount
    local mapqueue = {}
    local distqueue = {}
    for j = 1, staircount do
        distqueue[j] = {}
    end
    for x = -LOS, LOS do
        for y = -LOS, LOS do
            table.insert(mapqueue, {x + dx, y + dy})
        end
    end
    local first = 1
    local last = #mapqueue
    local x, y
    local feat
    while first < last do
        if first % 1000 == 0 then
            coroutine.yield()
        end
        x = mapqueue[first][1]
        y = mapqueue[first][2]
        first = first + 1
        feat = view.feature_at(x - dx, y - dy)
        if feat ~= "unseen" then
            if level_map[num][x][y] == nil then
                for ddx = -1, 1 do
                    for ddy = -1, 1 do
                        if ddx ~= 0 or ddy ~= 0 then
                            last = last + 1
                            mapqueue[last] = {x + ddx, y + ddy}
                        end
                    end
                end
            end
            if travel.feature_traversable(feat)
                    and not travel.feature_solid(feat) then
                if level_map[num][x][y] ~= "." then
                    if feat_is_upstairs(feat) then
                        newcount = #stair_dists[num] + 1
                        stair_dists[num][newcount] = {}
                        for i = -100, 100 do
                            stair_dists[num][newcount][i] = {}
                        end
                        stair_dists[num][newcount][x][y] = 0
                        distqueue[newcount] = {{x, y}}
                    end
                    for j = 1, staircount do
                        oldval = stair_dists[num][j][x][y]
                        for ddx = -1, 1 do
                            for ddy = -1, 1 do
                                if (ddx ~= 0 or ddy ~= 0) then
                                    val = stair_dists[num][j][x + ddx][y + ddy]
                                    if val ~= nil
                                            and (oldval == nil
                                                or oldval > val + 1) then
                                        oldval = val + 1
                                    end
                                end
                            end
                        end
                        if stair_dists[num][j][x][y] ~= oldval then
                            stair_dists[num][j][x][y] = oldval
                            table.insert(distqueue[j], {x, y})
                        end
                    end
                end
                level_map[num][x][y] = "."
            else
                level_map[num][x][y] = "#"
            end
        end
    end
    for j = 1, newcount do
        update_dist_map(stair_dists[num][j], distqueue[j])
    end
end

function update_dist_map(dist_map, queue)
    local first = 1
    local last = #queue
    local x, y, val
    while first <= last do
        if first % 300 == 0 then
            coroutine.yield()
        end
        x = queue[first][1]
        y = queue[first][2]
        first = first + 1
        val = dist_map[x][y] + 1
        for dx = -1, 1 do
            for dy = -1, 1 do
                if (dx ~= 0 or dy ~= 0)
                        and level_map[waypoint_parity][x + dx][y + dy]
                            == "." then
                    oldval = dist_map[x + dx][y + dy]
                    if oldval == nil or oldval > val then
                        dist_map[x + dx][y + dy] = val
                        last = last + 1
                        queue[last] = {x + dx, y + dy}
                    end
                end
            end
        end
    end
end

function find_good_stairs()
    good_stair_list = { }

    if not is_waypointable(where) then
        return
    end

    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local staircount = #(stair_dists[num])
    local pdist, mdist, minmdist, speed_diff
    local pspeed = player_speed_num()
    for i = 1, staircount do
        pdist = stair_dists[num][i][dx][dy]
        if pdist == nil then
            pdist = 10000
        end
        minmdist = 1000
        local e
        for _, e in ipairs(enemy_list) do
            mdist = stair_dists[num][i][dx + e.x][dy + e.y]
            if mdist == nil then
                mdist = 10000
            end
            speed_diff = mon_speed_num(e.m) - pspeed
            if speed_diff > 1 then
                mdist = mdist / 2
            elseif speed_diff > 0 then
                mdist = mdist / 1.5
            end
            if is_ranged(e.m) then
                mdist = mdist - 4
            end
            if mdist < minmdist then
                minmdist = mdist
            end
        end
        if pdist < minmdist then
            table.insert(good_stair_list, i)
        end
    end
end

function stair_improvement(x, y)
    if not is_waypointable(where) then
        return 10000
    end
    if x == 0 and y == 0 then
        if feat_is_upstairs(view.feature_at(0, 0)) then
            return 0
        else
            return 10000
        end
    end
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local val
    local minval = 10000
    for _, i in ipairs(good_stair_list) do
        val = stair_dists[num][i][dx + x][dy + y]
        if val < stair_dists[num][i][dx][dy] and val < minval then
            minval = val
        end
    end
    return minval
end

function set_stair_target(c)
    local x, y = vi_to_delta(c)
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local val
    local minval = 10000
    local best_stair
    for _, i in ipairs(good_stair_list) do
        val = stair_dists[num][i][dx + x][dy + y]
        if val < stair_dists[num][i][dx][dy] and val < minval then
            minval = val
            best_stair = i
        end
    end
    target_stair = best_stair
end

function plan_continue_flee()
    if you.turns() >= last_flee_turn + 10 or not target_stair then
        return false
    end
    if danger
            or not reason_to_rest(90)
            or you.transform() == "tree"
            or count_bia(3) > 0
            or count_sgd(3) > 0
            or count_divine_warrior(3) > 0
            or you.status("spiked")
            or you.confused()
            or buffed() then
        return false
    end
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local val
    for x = -1, 1 do
        for y = -1, 1 do
            if is_traversable(x, y) and not is_solid(x, y)
                 and not monster_in_way(x, y) and view.is_safe_square(x, y)
                 and not view.withheld(x, y) then
                val = stair_dists[num][target_stair][dx + x][dy + y]
                if val and val < stair_dists[num][target_stair][dx][dy] then
                    dsay("STILL FLEEEEING.")
                    magic(delta_to_vi(x, y) .. "YY")
                    return true
                end
            end
        end
    end
    return false
end

function plan_stuck()
    stuck_turns = stuck_turns + 1
    if stuck_turns > QUIT_TURNS then
        magic(control('q') .. "yes\r")
        return true
    end
    return random_step("stuck")
    -- panic("Stuck!")
end

function plan_full_inventory_panic()
    if FULL_INVENTORY_PANIC and free_inventory_slots() == 0 then
        panic("Inventory is full!")
    else
        return false
    end
end

function unshafting()
    return (where_shafted_from and (where_shafted_from ~= you.where())
                    and not where:find("Slime"))
end

function plan_unshaft()
    if unshafting() and where ~= "Temple" then
        dsay("Trying to unshaft to " .. where_shafted_from .. ".")
        expect_new_location = true
        magic("G<")
        return true
    end
    return false
end

function plan_not_coded()
    panic("Need to code this!")
    return true
end

function random_step(reason)
    if you.mesmerised() then
        say("Waiting to end mesmerise (" .. reason .. ").")
        magic("s")
        return true
    end
    local i, j
    local dx, dy
    local count = 0
    for i = -1, 1 do
        for j = -1, 1 do
            if not (i == 0 and j == 0)
                    and is_traversable(i, j)
                    and not view.withheld(i, j)
                    and not monster_in_way(i, j) then
                count = count + 1
                if crawl.one_chance_in(count) then
                    dx = i
                    dy = j
                end
            end
        end
    end
    if count > 0 then
        say("Stepping randomly (" .. reason .. ").")
        magic(delta_to_vi(dx, dy) .. "YY")
        return true
    else
        say("Standing still (" .. reason .. ").")
        magic("s")
        return true
    end
    -- return false
end

function plan_disturbance_random_step()
    if crawl.messages(5):find("There is a strange disturbance nearby!") then
        return random_step("disturbance")
    end
    return false
end

function plan_wait()
    rest()
    return true
end

function plan_flail_at_invis()
    if options.autopick_on then
        invisi_count = 0
        invisi_sigmund = false
        return false
    end
    if invisi_count > 100 then
        say("Invisible monster not found???")
        invisi_count = 0
        invisi_sigmund = false
        magic(control('a'))
        return true
    end
    invisi_count = invisi_count + 1
    local x, y

    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and view.invisible_monster(x, y) then
                magic(control(delta_to_vi(x, y)))
                return true
            end
        end
    end

    if invisi_sigmund and (sigmund_dx ~= 0 or sigmund_dy ~= 0) then
        x = sigmund_dx
        y = sigmund_dy
        if adjacent(x, y) and is_traversable(x, y) then
            magic(control(delta_to_vi(x, y)))
            return true
        elseif x == 0 and is_traversable(0, sign(y)) then
            magic(delta_to_vi(0, sign(y)))
            return true
        elseif y == 0 and is_traversable(sign(x),0) then
            magic(delta_to_vi(sign(x),0))
            return true
        end
    end

    local success = false
    local tries = 0
    while not success and tries < 100 do
        x = -1 + crawl.random2(3)
        y = -1 + crawl.random2(3)
        tries = tries + 1
        if (x ~= 0 or y ~= 0) and is_traversable(x, y)
             and view.feature_at(x, y) ~= "closed_door"
             and view.feature_at(x, y) ~= "runed_door" then
            success = true
        end
    end
    if tries >= 100 then
        magic("s")
    else
        magic(control(delta_to_vi(x, y)))
    end
    return true
end

function plan_cure_confusion()
    if you.confused() and (danger or not options.autopick_on) then
        if view.cloud_at(0, 0) == "noxious fumes" and not meph_immune() then
            if you.god() == "Beogh" then
                magic("s") -- avoid Beogh penance
                return true
            end
            return false
        end
        if drink_by_name("curing") then
            say("(to cure confusion)")
            return true
        end
        if can_purification() then
            purification()
            return true
        end
        if you.god() == "Beogh" then
            magic("s") -- avoid Beogh penance
            return true
        end
    end
    return false
end

-- curing poison/confusion with purification is handled elsewhere
function plan_special_purification()
    if not can_purification() then
        return false
    end
    if you.slowed() or you.petrifying() then
        purification()
        return true
    end
    local str, mstr = you.strength()
    local int, mint = you.intelligence()
    local dex, mdex = you.dexterity()
    if str < mstr and (str < mstr - 5 or str < 3)
         or int < mint and int < 3
         or dex < mdex and (dex < mdex - 8 or dex < 3) then
        purification()
        return true
    end
    return false
end

function plan_teleport()
    if can_teleport() and want_to_teleport() then
        -- return false
        return teleport()
    end
    return false
end

function plan_orbrun_teleport()
    if can_teleport() and want_to_orbrun_teleport() then
        return teleport()
    end
    return false
end

function plan_tomb_use_hatch()
    if (where == "Tomb:2" and not you.have_rune("golden")
            or where == "Tomb:1")
         and view.feature_at(0, 0) == "escape_hatch_down" then
        expect_new_location = true
        prev_hatch_dist = 1000
        magic(">")
        return true
    end
    if (where == "Tomb:3" and you.have_rune("golden")
            or where == "Tomb:2")
         and view.feature_at(0, 0) == "escape_hatch_up" then
        expect_new_location = true
        prev_hatch_dist = 1000
        magic("<")
        return true
    end
    return false
end

function plan_tomb_go_to_final_hatch()
    if where == "Tomb:2" and not you.have_rune("golden")
         and view.feature_at(0, 0) ~= "escape_hatch_down" then
        magic("X>\r")
        return true
    end
    return false
end

function plan_tomb_go_to_hatch()
    if where == "Tomb:3" then
        if you.have_rune("golden")
             and view.feature_at(0, 0) ~= "escape_hatch_up" then
            magic("X<\r")
            return true
        end
    elseif where == "Tomb:2" then
        if not you.have_rune("golden")
             and view.feature_at(0, 0) == "escape_hatch_down" then
            return false
        end
        if view.feature_at(0, 0) == "escape_hatch_up" then
            local x, y = travel.waypoint_delta(waypoint_parity)
            local new_hatch_dist = supdist(x, y)
            if new_hatch_dist >= prev_hatch_dist
                 and (x ~= prev_hatch_x or y ~= prev_hatch_y) then
                return false
            end
            prev_hatch_dist = new_hatch_dist
            prev_hatch_x = x
            prev_hatch_y = y
        end
        magic("X<\r")
        return true
    elseif where == "Tomb:1" then
        if view.feature_at(0, 0) == "escape_hatch_down" then
            local x, y = travel.waypoint_delta(waypoint_parity)
            local new_hatch_dist = supdist(x, y)
            if new_hatch_dist >= prev_hatch_dist
                 and (x ~= prev_hatch_x or y ~= prev_hatch_y) then
                return false
            end
            prev_hatch_dist = new_hatch_dist
            prev_hatch_x = x
            prev_hatch_y = y
        end
        magic("X>\r")
        return true
    end
    return false
end

function plan_stuck_clear_exclusions()
    local n = clear_exclusion_count[where] or 0
    if n > 20 then
        return false
    end
    clear_exclusion_count[where] = n + 1
    magic("X" .. control('e'))
    return true
end

function plan_swamp_clear_exclusions()
    if where ~= "Swamp:4" then
        return false
    end
    magic("X" .. control('e'))
    return true
end

function plan_swamp_go_to_rune()
    if where ~= "Swamp:4" or you.have_rune("decaying") then
        return false
    end
    if last_swamp_fail_count == c_persist.plan_fail_count.try_swamp_go_to_rune then
        swamp_rune_reachable = true
    end
    last_swamp_fail_count = c_persist.plan_fail_count.try_swamp_go_to_rune
    magicfind("@decaying rune")
    return true
end

function plan_swamp_clouds_hack()
    if where ~= "Swamp:4" then
        return false
    end
    if you.have_rune("decaying") and can_teleport() and teleport() then
        return true
    end
    if swamp_rune_reachable then
        say("Waiting for clouds to move.")
        magic("s")
        return true
    end
    local x, y
    local bestx, besty
    local dist
    local bestdist = 11
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and view.is_safe_square(x, y)
                 and not view.withheld(x, y) and not monster_in_way(x, y) then
                dist = 11
                for x2 = -LOS, LOS do
                    for y2 = -LOS, LOS do
                        if (view.cloud_at(x2, y2) == "freezing vapour"
                                or view.cloud_at(x2, y2) == "foul pestilence")
                             and you.see_cell_no_trans(x2, y2)
                             and (you.god() ~= "Qazlal"
                                 or not view.is_safe_square(x2, y2)) then
                            if supdist(x - x2, y - y2) < dist then
                                dist = supdist(x - x2, y - y2)
                            end
                        end
                    end
                end
                if dist < bestdist then
                    bestx = x
                    besty = y
                    bestdist = dist
                end
            end
        end
    end
    if bestdist < 11 then
        magic(delta_to_vi(bestx, besty) .. "Y")
        return true
    end
    for x = -LOS, LOS do
        for y = -LOS, LOS do
            if (view.cloud_at(x, y) == "freezing vapour"
                    or view.cloud_at(x, y) == "foul pestilence")
                 and you.see_cell_no_trans(x, y) then
                return random_step("Swamp:4")
            end
        end
    end
    return plan_stuck_teleport()
end

function plan_dig_grate()
    local grate_mon_list
    local grate_count_needed = 3
    if where:find("Zot") then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher"}
    elseif where == "Depths:4" then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher",
            "angel", "daeva", "lich", "eye"}
    elseif where:find("Depths") then
        grate_mon_list = {"angel", "daeva", "lich", "eye"}
    elseif where == "Pan" or where == "Geh:7" then
        grate_mon_list = {"smoke demon"}
        grate_count_needed = 1
    elseif where:find("Zig") then
        grate_mon_list = {""}
        grate_count_needed = 1
    else
        return false
    end
    local e
    for _, e in ipairs(enemy_list) do
        local name = e.m:name()
        if contains_string_in(name, grate_mon_list)
             and not will_tab(0, 0, e.x, e.y, tabbable_square) then
            local grate_count = 0
            local dx, dy
            local closest_grate = 20
            local gx, gy, cgx, cgy
            for dx = -1, 1 do
                for dy = -1, 1 do
                    gx = e.x + dx
                    gy = e.y + dy
                    if supdist(gx, gy) <= LOS
                            and view.feature_at(gx, gy) == "iron_grate" then
                        grate_count = grate_count + 1
                        if abs(gx) + abs(gy) < closest_grate
                                and you.see_cell_solid_see(gx, gy) then
                            cgx = gx
                            cgy = gy
                            closest_grate = abs(gx) + abs(gy)
                        end
                    end
                end
            end
            if grate_count >= grate_count_needed and closest_grate < 20 then
                local c = find_item("wand", "digging")
                if c and can_zap() then
                    say("ZAPPING " .. item(c).name() .. ".")
                    magic("V" .. letter(c) .. "r" .. vector_move(cgx, cgy) ..
                        "\r")
                    return true
                end
            end
        end
    end
    return false
end

function plan_stuck_dig_grate()
    local dx, dy
    local closest_grate = 20
    local cx, cy
    for dx = -LOS, LOS do
        for dy = -LOS, LOS do
            if view.feature_at(dx, dy) == "iron_grate" then
                if abs(dx) + abs(dy) < closest_grate
                        and you.see_cell_solid_see(dx, dy) then
                    cx = dx
                    cy = dy
                    closest_grate = abs(dx) + abs(dy)
                end
            end
        end
    end

    if closest_grate < 20 then
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "r" .. vector_move(cx, cy) .. "\r")
            return true
        end
    end

    return false
end

function plan_stuck_forget_map()
    if not cloudy
            and not danger
            and (where == "Slime:5" and not you.have_rune("slimy")
                or where == "Geh:7" and not you.have_rune("obsidian")) then
        magic("X" .. control('f'))
        return true
    end
    return false
end

function plan_stuck_cloudy()
    if cloudy and not hp_is_low(50) and not you.mesmerised() then
        return random_step("cloudy")
    end
    return false
end

function plan_stuck_teleport()
    if can_teleport() then
        return teleport()
    end
    return false
end

function read(c)
    if not can_read() then
        return false
    end
    say("READING " .. item(c).name() .. ".")
    magic("r" .. letter(c))
    return true
end

function read2(c, etc)
    if not can_read() then
        return false
    end
    local int, mint = you.intelligence()
    if int <= 0 then
        -- failing to read a scroll due to intzero can make qw unhappy
        return false
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
    if read_by_name("teleportation") then
        return true
    end
    return false
end

function plan_cure_poison()
    if you.poison_survival() <= 1 and you.poisoned() then
        if drink_by_name("curing") then
            say("(to cure poison)")
            return true
        end
    end
    if you.poison_survival() <= 1 and you.poisoned() then
        if can_hand() then
            hand()
            return true
        end
        if can_purification() then
            purification()
            return true
        end
    end
    return false
end

function move_towards(dx, dy)
    if you.transform() == "tree"
            or you.transform() == "fungus"
            or you.confused()
                and (count_bia(1) > 0
                    or count_sgd(1) > 0
                    or count_divine_warrior(1) > 0) then
        magic("s")
        return true
    end
    local move = nil
    if abs(dx) > abs(dy) then
        if abs(dy) == 1 then move = try_move(sign(dx), 0) end
        if move == nil then move = try_move(sign(dx), sign(dy)) end
        if move == nil then move = try_move(sign(dx), 0) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = try_move(sign(dx), 1) end
        if move == nil and abs(dx) > abs(dy) + 1 then
                 move = try_move(sign(dx), -1) end
        if move == nil then move = try_move(0, sign(dy)) end
    elseif abs(dx) == abs(dy) then
        move = try_move(sign(dx), sign(dy))
        if move == nil then move = try_move(sign(dx), 0) end
        if move == nil then move = try_move(0, sign(dy)) end
    else
        if abs(dx) == 1 then move = try_move(0, sign(dy)) end
        if move == nil then move = try_move(sign(dx), sign(dy)) end
        if move == nil then move = try_move(0, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = try_move(1, sign(dy)) end
        if move == nil and abs(dy) > abs(dx) + 1 then
                 move = try_move(-1, sign(dy)) end
        if move == nil then move = try_move(sign(dx), 0) end
    end
    if move == nil or move_count >= 10 then
        add_ignore(dx, dy)
        table.insert(failed_move, 20 * dx + dy)
        return false
    else
        if (abs(dx) > 1 or abs(dy) > 1) and not lair_step_mode
             and view.feature_at(dx, dy) ~= "closed_door" then
            did_move = true
            if monster_array[dx][dy] or did_move_towards_monster > 0 then
                local move_x, move_y = vi_to_delta(move)
                target_memory_x = dx - move_x
                target_memory_y = dy - move_y
                did_move_towards_monster = 2
            end
        end
        if lair_step_mode then
            local move_x, move_y = vi_to_delta(move)
            if view.feature_at(move_x, move_y) == "shallow_water" then
                return false
            end
        end
        magic(move .. "Y")
        return true
    end
end

function plan_continue_tab()
    if did_move_towards_monster == 0 then
        return false
    end
    if supdist(target_memory_x, target_memory_y) == 0 then
        return false
    end
    if not options.autopick_on then
        return false
    end
    return move_towards(target_memory_x, target_memory_y)
end

function add_ignore(dx, dy)
    m = monster_array[dx][dy]
    if not m then
        return
    end
    name = m:name()
    if not util.contains(ignore_list, name) then
        table.insert(ignore_list, name)
        crawl.setopt("runrest_ignore_monster ^= " .. name .. ":1")
        dsay("Ignoring " .. name .. ".")
    end
end

function remove_ignore(dx, dy)
    m = monster_array[dx][dy]
    name = m:name()
    for i, mname in ipairs(ignore_list) do
        if mname == name then
            table.remove(ignore_list, i)
            crawl.setopt("runrest_ignore_monster -= " .. name .. ":1")
            dsay("Unignoring " .. name .. ".")
            return
        end
    end
end

function clear_ignores()
    local size = #ignore_list
    local mname
    local i
    if size > 0 then
        for i = 1, size do
            mname = table.remove(ignore_list)
            crawl.setopt("runrest_ignore_monster -= " .. mname .. ":1")
            dsay("Unignoring " .. mname .. ".")
        end
    end
end

-- this gets stuck if netted, confused, etc
function attack_reach(x, y)
    magic('vr' .. vector_move(x, y) .. '.')
end

function attack_melee(x, y)
    if you.confused() then
        if count_bia(1) > 0
                or count_sgd(1) > 0
                or count_divine_warrior(1) > 0 then
            magic("s")
            return
        elseif you.transform() == "tree" then
            magic(control(delta_to_vi(x, y)) .. "Y")
            return
        end
    end
    if monster_array[x][y]:attitude() == ATT_NEUTRAL then
        if you.god() == "the Shining One" or you.god() == "Elyvilon"
             or you.god() == "Zin" then
            magic("s")
        else
            magic(control(delta_to_vi(x, y)))
        end
    end
    magic(delta_to_vi(x, y) .. "Y")
end

function make_attack(x, y, info)
    if info.attack_type == 2 then attack_melee(x, y)
    elseif info.attack_type == 1 then attack_reach(x, y)
    else
        return move_towards(x, y)
    end
    return true
end

function use_ability(name, extra, mute)
    for letter, abil in pairs(you.ability_table()) do
        if abil == name then
            if not mute or DEBUG_MODE then
                say("INVOKING " .. name .. ".")
            end
            magic("a" .. letter .. (extra or ""))
            return true
        end
    end
end

function note(x)
    crawl.take_note(you.turns() .. " ||| " .. x)
end

function say(x, debug)
    crawl.mpr(you.turns() .. " ||| " .. x)
    note(x)
end

function dsay(x)
    if DEBUG_MODE then
        crawl.mpr(you.turns() .. " ||| " .. x)
    end
end

-- these few functions are called directly from ready()

function record_portal_found(por)
    if not util.contains(c_persist.portals_found, por) then
        say("Found " .. por .. ".")
        table.insert(c_persist.portals_found, por)
    end
end

function check_messages()
    local recent_messages = crawl.messages(20)
    local very_recent_messages = crawl.messages(5)
    if very_recent_messages:find("Sigmund flickers and vanishes") then
        invisi_sigmund = true
    end
    if very_recent_messages:find("Your surroundings suddenly seem different") then
        invisi_sigmund = false
    end
    str1 = "Your pager goes off"
    str2 = "qwqwqw"
    if recent_messages:find(str1) then
        a = recent_messages:reverse():find(str1:reverse())
        b = recent_messages:reverse():find(str2:reverse())
        if (not b) or a < b then
            have_message = true
        end
    end
    if in_portal() then
        return false
    end
    if recent_messages:find("Found") then
        for _, value in ipairs(portal_data) do
            if recent_messages:find(value[2]) then
                record_portal_found(value[1])
            end
        end
    end
end

function plan_message()
    if read_message then
        crawl.setopt("clear_messages = false")
        magic("_")
        read_message = false
    else
        crawl.setopt("clear_messages = true")
        magic(":qwqwqw\r")
        read_message = true
        have_message = false
        crawl.delay(2500)
    end
end

----------------------------------------
-- cascading plans: this is the bot's flowchart for using the above plans

function cascade(plans)
    local plan_turns = {}
    local plan_result = {}
    return function ()
        for i, plandata in ipairs(plans) do
            plan = plandata[1]
            if you.turns() ~= plan_turns[plan] or plan_result[plan] == nil then
                result = plan()
                if not automatic then
                    return true
                end
                plan_turns[plan] = you.turns()
                plan_result[plan] = result
                if result == nil or result == true then
                    if DELAYED and result == true then
                        crawl.delay(next_delay)
                    end
                    next_delay = DELAY_TIME
                    return nil
                end
            elseif plan_turns[plan] and plan_result[plan] == true then
                if not plandata[2]:find("^try") then
                    panic(plandata[2] .. " failed despite returning true.")
                end
                fail_count = c_persist.plan_fail_count[plandata[2]]
                if not fail_count then
                    fail_count = 0
                end
                fail_count = fail_count + 1
                c_persist.plan_fail_count[plandata[2]] = fail_count
            end
        end
        return false
    end
end

-- any plan that might not know whether or not it successfully took an action
-- (e.g. autoexplore) should prepend "try_" to its text

-- These plans will only execute after a successful acquirement.
plan_handle_acquirement_result = cascade {
    {plan_maybe_pickup_acquirement, "try_pickup_acquirement"},
    {plan_maybe_upgrade_armour, "maybe_upgrade_armour"},
    {plan_maybe_upgrade_amulet, "maybe_upgrade_amulet"},
    {plan_maybe_upgrade_rings, "maybe_upgrade_rings"},
} -- hack


plan_pre_explore = cascade {
    {plan_ancestor_life, "ancestor_life"},
    {plan_sacrifice, "sacrifice"},
    {plan_handle_acquirement_result, "handle_acquirement_result"},
    {plan_bless_weapon, "bless_weapon"},
    {plan_upgrade_weapon, "upgrade_weapon"},
    {plan_use_good_consumables, "use_good_consumables"},
} -- hack

plan_pre_explore2 = cascade {
    {plan_disturbance_random_step, "disturbance_random_step"},
    {plan_upgrade_armour, "upgrade_armour"},
    {plan_upgrade_amulet, "upgrade_amulet"},
    {plan_upgrade_rings, "upgrade_rings"},
    {plan_read_id, "try_read_id"},
    {plan_quaff_id, "quaff_id"},
    {plan_use_id_scrolls, "use_id_scrolls"},
    {plan_drop_other_items, "drop_other_items"},
    {plan_full_inventory_panic, "full_inventory_panic"},
} -- hack

plan_emergency = cascade {
    {plan_special_purification, "special_purification"},
    {plan_cure_confusion, "cure_confusion"},
    {plan_coward_step, "coward_step"},
    {plan_flee_step, "flee_step"},
    {plan_remove_terrible_jewellery, "remove_terrible_jewellery"},
    {plan_teleport, "teleport"},
    {plan_cure_bad_poison, "cure_bad_poison"},
    {plan_cancellation, "cancellation"},
    {plan_drain_life, "drain_life"},
    {plan_heal_wounds, "heal_wounds"},
    {plan_cloud_step, "cloud_step"},
    {plan_hand, "hand"},
    {plan_haste, "haste"},
    {plan_resistance, "resistance"},
    {plan_magic_points, "magic_points"},
    {plan_heroism, "heroism"},
    {plan_cleansing_flame, "try_cleansing_flame"},
    {plan_bia, "bia"},
    {plan_sgd, "sgd"},
    {plan_divine_warrior, "divine_warrior"},
    {plan_apocalypse, "try_apocalypse"},
    {plan_slouch, "try_slouch"},
    {plan_hydra_destruction, "try_hydra_destruction"},
    {plan_grand_finale, "grand_finale"},
    {plan_wield_weapon, "wield_weapon"},
    {plan_swap_weapon, "swap_weapon"},
    {plan_water_step, "water_step"},
    {plan_zig_fog, "zig_fog"},
    {plan_finesse, "finesse"},
    {plan_dig_grate, "try_dig_grate"},
    {plan_might, "might"},
    {plan_blinking, "blinking"},
    {plan_berserk, "berserk"},
    {plan_continue_flee, "continue_flee"},
    {plan_other_step, "other_step"},
} -- hack

plan_orbrun_emergency = cascade {
    {plan_special_purification, "special_purification"},
    {plan_cure_confusion, "cure_confusion"},
    {plan_orbrun_teleport, "orbrun_teleport"},
    {plan_orbrun_heal_wounds, "orbrun_heal_wounds"},
    {plan_orbrun_finesse, "orbrun_finesse"},
    {plan_orbrun_haste, "orbrun_haste"},
    {plan_orbrun_heroism, "orbrun_heroism"},
    {plan_orbrun_divine_warrior, "orbrun_divine_warrior"},
    {plan_hand, "hand"},
    {plan_resistance, "resistance"},
    {plan_wield_weapon, "wield_weapon"},
    {plan_orbrun_might, "orbrun_might"},
} -- hack

plan_rest = cascade {
    {plan_easy_rest, "try_easy_rest"},
    {plan_rest, "rest"},
} -- hack

plan_abyss_rest = cascade {
    {plan_go_to_abyss_exit, "try_go_to_abyss_exit"},
    {plan_abyss_hand, "abyss_hand"},
    {plan_abyss_rest, "rest"},
    {plan_go_down_abyss, "go_down_abyss"},
    {plan_go_to_abyss_downstairs, "try_go_to_abyss_downstairs"},
} -- hack

plan_orbrun_rest = cascade {
    {plan_orbrun_rest, "orbrun_rest"},
    {plan_orbrun_hand, "orbrun_hand"},
} -- hack

plan_explore = cascade {
    {plan_unshaft, "try_unshaft"},
    {plan_continue_travel, "try_continue_travel"},
    {plan_enter_portal, "enter_portal"},
    {plan_go_to_portal_entrance, "try_go_to_portal_entrance"},
    {plan_enter_abyss, "enter_abyss"},
    {plan_go_to_abyss_portal, "try_go_to_abyss_portal"},
    {plan_enter_pan, "enter_pan"},
    {plan_go_to_pan_portal, "try_go_to_pan_portal"},
    {plan_enter_zig, "enter_zig"},
    {plan_go_to_zig, "try_go_to_zig"},
    {plan_zig_dig, "zig_dig"},
    {plan_go_to_zig_dig, "try_go_to_zig_dig"},
    {plan_dive, "try_dive"},
    {plan_dive_pan, "dive_pan"},
    {plan_dive_go_to_pan_downstairs, "try_dive_go_to_pan_downstairs"},
    {plan_early_new_travel, "try_early_new_travel"},
    {plan_autoexplore, "try_autoexplore"},
} -- hack

plan_explore2 = cascade {
    {plan_zig_leave_level, "zig_leave_level"},
    {plan_zig_go_to_stairs, "try_zig_go_to_stairs"},
    {plan_exit_portal, "exit_portal"},
    {plan_go_to_portal_exit, "try_go_to_portal_exit"},
    {plan_open_runed_doors, "open_runed_doors"},
    {plan_exit_pan, "exit_pan"},
    {plan_go_to_pan_exit, "try_go_to_pan_exit"},
    {plan_go_down_pan, "try_go_down_pan"},
    {plan_go_to_pan_downstairs, "try_go_to_pan_downstairs"},
    {plan_enter_branch, "try_enter_branch"},
    {plan_shopping_spree, "try_shopping_spree"},
    {plan_simple_go_down, "try_simple_go_down"},
    {plan_new_travel, "try_new_travel"},
} -- hack

plan_move = cascade {
    {plan_ancestor_identity, "try_ancestor_identity"},
    {plan_join_beogh, "join_beogh"},
    {plan_shop, "shop"},
    {plan_stairdance_up, "stairdance_up"},
    {plan_emergency, "emergency"},
    {plan_tomb2_arrival, "tomb2_arrival"},
    {plan_tomb3_arrival, "tomb3_arrival"},
    {plan_recall, "recall"},
    {plan_recall_ancestor, "try_recall_ancestor"},
    {plan_recite, "try_recite"},
    {plan_wait_for_melee, "wait_for_melee"},
    {plan_starting_spell, "try_starting_spell"},
    {plan_wait_spit, "try_wait_spit"},
    {plan_wait_throw, "try_wait_throw"},
    {plan_wait_wait, "wait_wait"},
    {plan_attack, "attack"},
    {plan_cure_poison, "cure_poison"},
    {plan_flail_at_invis, "try_flail_at_invis"},
    {plan_rest, "rest"},
    {plan_pre_explore, "pre_explore"},
    {plan_step_towards_branch, "step_towards_branch"},
    {plan_continue_tab, "continue_tab"},
    {plan_abandon_god, "abandon_god"},
    {plan_unwield_weapon, "unwield_weapon"},
    {plan_convert, "convert"},
    -- bug with faded altar not taking time
    {plan_join_god, "try_join_god"},
    {plan_find_conversion_altar, "try_find_conversion_altar"},
    {plan_find_altar, "try_find_altar"},
    {plan_go_to_temple, "try_go_to_temple"},
    {plan_explore, "explore"},
    {plan_pre_explore2, "pre_explore2"},
    {plan_explore2, "explore2"},
    {plan_tomb_go_to_final_hatch, "try_tomb_go_to_final_hatch"},
    {plan_tomb_go_to_hatch, "try_tomb_go_to_hatch"},
    {plan_tomb_use_hatch, "tomb_use_hatch"},
    {plan_swamp_clear_exclusions, "try_swamp_clear_exclusions"},
    {plan_swamp_go_to_rune, "try_swamp_go_to_rune"},
    {plan_swamp_clouds_hack, "swamp_clouds_hack"},
    {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
    {plan_stuck_dig_grate, "try_stuck_dig_grate"},
    {plan_stuck_cloudy, "stuck_cloudy"},
    {plan_stuck_forget_map, "try_stuck_forget_map"},
    {plan_stuck_teleport, "stuck_teleport"},
    {plan_stuck, "stuck"},
} -- hack

plan_orbrun_move = cascade {
    {plan_orbrun_emergency, "orbrun_emergency"},
    {plan_recall, "recall"},
    {plan_recall_ancestor, "try_recall_ancestor"},
    {plan_attack, "attack"},
    {plan_cure_poison, "cure_poison"},
    {plan_orbrun_rest, "orbrun_rest"},
    {plan_go_up, "go_up"},
    {plan_use_good_consumables, "use_good_consumables"},
    {plan_find_upstairs, "try_find_upstairs"},
    {plan_disturbance_random_step, "disturbance_random_step"},
    {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
    {plan_stuck_cloudy, "stuck_cloudy"},
    {plan_stuck_teleport, "stuck_teleport"},
    {plan_autoexplore, "try_autoexplore"},
    {plan_gd1, "try_gd1"},
    {plan_stuck, "stuck"},
} -- hack

plan_abyss_move = cascade {
    {plan_lugonu_exit_abyss, "lugonu_exit_abyss"},
    {plan_exit_abyss, "exit_abyss"},
    {plan_emergency, "emergency"},
    {plan_recall_ancestor, "try_recall_ancestor"},
    {plan_recite, "try_recite"},
    {plan_attack, "attack"},
    {plan_cure_poison, "cure_poison"},
    {plan_flail_at_invis, "try_flail_at_invis"},
    {plan_abyss_rest, "abyss_rest"},
    {plan_pre_explore, "pre_explore"},
    {plan_autoexplore, "try_autoexplore"},
    {plan_pre_explore2, "pre_explore2"},
    {plan_stuck_cloudy, "stuck_cloudy"},
    {plan_wait, "wait"},
} -- hack

----------------------------------------
-- skill selection
local skill_list = {
    "Fighting", "Short Blades", "Long Blades", "Axes", "Maces & Flails",
    "Polearms", "Staves", "Unarmed Combat", "Ranged Weapons", "Throwing",
    "Armour", "Dodging", "Shields", "Invocations", "Evocations", "Stealth",
    "Spellcasting", "Conjurations", "Hexes", "Summonings",
    "Necromancy", "Translocations", "Transmutations", "Fire Magic",
    "Ice Magic", "Air Magic", "Earth Magic", "Poison Magic"
} -- hack

function choose_single_skill(sk)
    you.train_skill(sk, 1)
    for _, sk2 in ipairs(skill_list) do
        if sk ~= sk2 then
            you.train_skill(sk2, 0)
        end
    end
end

function skill_value(sk)
    if you.god() == "Okawaru"
            and you.base_skill(sk) >= 22
            and sk ~= "Fighting"
            and sk ~= "Invocations" then
        return 0
    end

    if sk == "Dodging" then
        local str, _ = you.strength()
        if str < 1 then
            str = 1
        end
        local dex, _ = you.dexterity()
        local evp_adj = max(armour_evp() - 3, 0)
        local penalty_factor
        if evp_adj >= str then
            penalty_factor = str / (2 * evp_adj)
        else
            penalty_factor = 1 - evp_adj / (2 * str)
        end
        if you.race() == "Tengu" and intrinsic_amphibious_or_flight() then
            penalty_factor = penalty_factor * 1.2 -- flying EV mult
        end
        return 18 * math.log(1 + dex / 18)
            / (20 + 2 * body_size()) * penalty_factor
    elseif sk == "Armour" then
        local str, _ = you.strength()
        if str < 0 then
            str = 0
        end
        local val1 = 2 / 225 * armour_evp() ^ 2 / (3 + str)
        local val2 = base_ac() / 22
        return val1 + val2
    elseif sk == "Fighting" then
        return 0.75
    elseif sk == "Shields" then
        local shield = items.equipped_at("Shield")
        if not shield then
            return 0
        end
        return at_target_shield_skill() and 0.2 or 0.75
    elseif sk == "Throwing" then
        local rating
        rating, _ = best_missile()
        return 0.3 * rating
    elseif sk == "Invocations" then
        if you.god() == "the Shining One" then
            return in_extended() and 1.5 or 0.5
        elseif you.god() == "Uskayaw" or you.god() == "Zin" then
            return 0.75
        elseif you.god() == "Elyvilon" then
            return 0.5
        else
            return 0
        end
    elseif sk == wskill() then
        return (at_min_delay() and 0.20 or 1.5)
    end
end

function god_wants_invocations()
    return you.god() == "Makhleb"
        or you.god() == "Cheibriados"
        or you.god() == "Okawaru"
        or you.god() == "Yredelemnul"
        or you.god() == "Beogh"
        or you.god() == "Qazlal"
        or you.god() == "the Shining One"
        or you.god() == "Lugonu"
        or you.god() == "Hepliaklqana"
        or you.god() == "Uskayaw"
        or you.god() == "Elyvilon"
        or you.god() == "Zin"
end

function choose_skills()
    local skills = {}
    -- Choose one martial skill to train.
    local martial_skills = {
        wskill(), "Fighting", "Shields", "Armour", "Dodging", "Invocations",
        "Throwing"
    } --hack

    local best_sk
    local best_utility = 0
    local utility
    for _, sk in ipairs(martial_skills) do
        if you.skill_cost(sk) then
            utility = skill_value(sk) / you.skill_cost(sk)
            if utility > best_utility then
                best_utility = utility
                best_sk = sk
            end
        end
    end
    if best_utility > 0 then
        dsay("Best skill: " .. best_sk .. ", utility: " .. best_utility)
        table.insert(skills, best_sk)
    end

    -- Choose one MP skill to train.
    mp_skill = "Evocations"
    if god_wants_invocations() then
        mp_skill = "Invocations"
    elseif you.god() == "Ru" or you.god() == "Xom" then
        mp_skill = "Spellcasting"
    end
    mp_skill_level = you.base_skill(mp_skill)
    bmp = you.base_mp()
    if you.god() == "Makhleb"
            and you.piety_rank() >= 2
            and mp_skill_level < 15 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Okawaru"
            and you.piety_rank() >= 1
            and mp_skill_level < 4 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Okawaru"
            and you.piety_rank() >= 4
            and mp_skill_level < 10 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Cheibriados"
            and you.piety_rank() >= 5
            and mp_skill_level < 8 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Yredelemnul"
            and you.piety_rank() >= 4
            and mp_skill_level < 8 then
        table.insert(skills, mp_skill)
    elseif you.race() == "Vine Stalker"
            and you.god() ~= "No God"
            and mp_skill_level < 12
            and (at_min_delay()
                 or you.base_skill(wskill()) >= 3 * mp_skill_level) then
        table.insert(skills, mp_skill)
    end

    skills2 = {}
    safe_count = 0
    for _, sk in ipairs(skills) do
        if you.can_train_skill(sk) and you.base_skill(sk) < 27 then
            table.insert(skills2, sk)
            if you.base_skill(sk) < 26.5 then
                safe_count = safe_count + 1
            end
        end
    end
    -- Try to avoid getting stuck in the skill screen.
    if safe_count == 0 then
        if you.base_skill("Fighting") < 26.5 then
            table.insert(skills2, "Fighting")
        elseif you.base_skill(mp_skill) < 26.5 then
            table.insert(skills2, mp_skill)
        else
            for _, sk in ipairs(skill_list) do
                if you.can_train_skill(sk) and you.base_skill(sk) < 26.5 then
                    table.insert(skills2, sk)
                    return skills2
                end
            end
        end
    end
    return skills2
end

function handle_skills()
    skills = choose_skills()
    choose_single_skill(skills[1])
    for _, sk in ipairs(skills) do
        you.train_skill(sk, 1)
    end
end

function choose_stat_gain()
    local ap = armour_plan()
    if ap == "heavy" or ap == "large" then
        return "s"
    elseif ap == "light" then
        return "d"
    else
        local str, _ = you.strength()
        local dex, _ = you.dexterity()
        if 3 * str < 2 * dex then
            return "s"
        else
            return "d"
        end
    end
end

function auto_experience()
    return true
end

-------------------------------------------
-- a few utility functions

function contains_string_in(name, t)
    for _, value in ipairs(t) do
        if string.find(name, value) then
            return true
        end
    end
    return false
end

function split(str, del)
    local res = { }
    local v
    for v in string.gmatch(str, "([^" .. del .. "]+)") do
        table.insert(res, v)
    end
    return res
end

function control(c)
    return string.char(string.byte(c) - string.byte('a') + 1)
end

function arrowkey(c)
    local a2c = { ['u'] = -254, ['d'] = -253, ['l'] = -252 ,['r'] = -251 }
    return a2c[c]
end

function delta_to_vi(dx, dy)
    local d2v = {
        [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b'},
        [0]    = { [-1] = 'k',                        [1] = 'j'},
        [1]    = { [-1] = 'u', [0] = 'l', [1] = 'n'},
    } -- hack
    return d2v[dx][dy]
end

function vi_to_delta(c)
    local d2v = {
        [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b'},
        [0]    = { [-1] = 'k',                        [1] = 'j'},
        [1]    = { [-1] = 'u', [0] = 'l', [1] = 'n'},
    } -- hack
    local x, y
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and d2v[x][y] == c then
                return x, y
            end
        end
    end
end

function sign(a)
    return a > 0 and 1 or a < 0 and -1 or 0
end

function abs(a)
    return a * sign(a)
end

function vector_move(dx, dy)
    local str = ''
    for i = 1, abs(dx) do
        str = str .. delta_to_vi(sign(dx), 0)
    end
    for i = 1, abs(dy) do
        str = str .. delta_to_vi(0, sign(dy))
    end
    return str
end

function max(x, y)
    if x > y then
        return x
    else
        return y
    end
end

function min(x, y)
    if x < y then
        return x
    else
        return y
    end
end

function supdist(dx, dy)
    return max(abs(dx), abs(dy))
end

function adjacent(dx, dy)
    return abs(dx) <= 1 and abs(dy) <= 1
end

---------------------------------------------
-- initialization/control/saving

function make_endgame_plans()
    endgame_plan_list = split(endgame_plan_options(), ", ")
    for _, pl in ipairs(endgame_plan_list) do
        if pl == "slime" then
            SLIMY_RUNE = true
        elseif pl == "pan" then
            PAN_RUNE = true
        elseif pl == "abyss" then
            ABYSSAL_RUNE = true
        elseif pl == "hells" then
            HELL_RUNE = true
        elseif pl == "tomb" then
            GOLDEN_RUNE = true
        elseif pl == "tso" then
            TSO_CONVERSION = true
        elseif pl == "zig" then
            WILL_ZIG = true
        end
    end
    if endgame_plan_list[#endgame_plan_list] ~= "zot" then
        table.insert(endgame_plan_list, "zot")
    end
end

function initialize()
    if you.turns() == 0 then
        first_turn_initialize()
    end
    make_endgame_plans()
    where = "nowhere"
    expect_new_location = true
    if c_persist.branches_entered == nil then
        c_persist.branches_entered = { "D" }
    end
    if c_persist.portals_found == nil then
        c_persist.portals_found = { }
    end
    if c_persist.plan_fail_count == nil then
        c_persist.plan_fail_count = { }
    end
    set_options()
    initialize_monster_array()
    if not level_map then
        level_map = {}
        stair_dists = {}
        clear_level_map(1)
        clear_level_map(2)
        waypoint_parity = 1
        prev_where = "nowhere"
    end
    for _, god in ipairs(god_options()) do
        if god == "the Shining One" or god == "Elyvilon" or god == "Zin" then
            MIGHT_BE_GOOD = true
        end
    end
    initialized = true
end

function stop()
    automatic = false
    unset_options()
end

function start()
    automatic = true
    set_options()
    ready()
end

function panic(msg)
    crawl.mpr("<lightred>" .. msg .. "</lightred>")
    stop()
end

function startstop()
    if automatic then
        stop()
    else
        start()
    end
end

function hit_closest()
    startstop()
end

function set_counter()
    crawl.formatted_mpr("Set game counter to what? ", "prompt")
    local res = crawl.c_input_line()
    c_persist.record.counter = tonumber(res)
    note("Game counter set to " .. c_persist.record.counter)
end

function bool_string(x)
    return x and "true" or "false"
end

function note_qw_data()
    note("qw: Version: " .. QW_VERSION)
    note("qw: Game counter: " .. c_persist.record.counter)
    note("qw: Always use a shield: " .. bool_string(SHIELD_CRAZY))
    if not util.contains(god_options(), you.god()) then
        note("qw: God list: " .. table.concat(god_options(), ", "))
        note("qw: Allow faded altars: " .. bool_string(FADED_ALTAR))
    end
    note("qw: Do Orc after D:15: " .. bool_string(LATE_ORC))
    note("qw: Do second Lair branch before Depths: " ..
        bool_string(EARLY_SECOND_RUNE))
    note("qw: Lair rune preference: " .. RUNE_PREFERENCE)

    local plans = endgame_plan_options()
    note("qw: Endgame plans: " .. plans)
    if plans:find("zig") then
        note("qw: Max Zig depth: " .. ZIG_DIVE)
    end
end

function first_turn_initialize()
    if AUTO_START then
        automatic = true
    end

    if not c_persist.record then
        c_persist.record = {}
    end

    local counter = c_persist.record.counter
    if not counter then
        counter = 1
    else
        counter = counter + 1
    end
    c_persist.record.counter = counter

    --if not c_persist.mlist then
    --    c_persist.mlist = {}
    --end
    --if not c_persist.record.mlist then
    --    c_persist.record.mlist = {}
    --end
    --for _, mname in ipairs(c_persist.mlist) do
    --    if not c_persist.record.mlist[mname] then
    --        c_persist.record.mlist[mname] = 1
    --    else
    --        c_persist.record.mlist[mname] = c_persist.record.mlist[mname] + 1
    --    end
    --end

    local god_list = c_persist.next_god_list
    local plan = c_persist.next_endgame_plan
    for key, _ in pairs(c_persist) do
        if key ~= "record" then
            c_persist[key] = nil
        end
    end

    c_persist.cur_god_list = god_list
    c_persist.cur_endgame_plan = plan
    note_qw_data()

    if COMBO_CYCLE then
        local combo_string_list = split(COMBO_CYCLE_LIST, ", ")
        local combo_string = combo_string_list[
            1 + (c_persist.record.counter % (#combo_string_list))]
        local combo_parts = split(combo_string, "^")
        c_persist.options = "combo = " .. combo_parts[1]
        if #combo_parts > 1 then
            local plan_parts = split(combo_parts[2], "!")
            c_persist.next_god_list = { }
            for g in plan_parts[1]:gmatch(".") do
                table.insert(c_persist.next_god_list, fullgodname(g))
            end
            if #plan_parts > 1 then
                if not ENDGAME_PLANS[plan_parts[2]] then
                    error("Unknown plan name '" .. plan_parts[2] .. "'" ..
                    " given in combo spec '" .. combo_string .. "'")
                end
                c_persist.next_endgame_plan = plan_parts[2]
            end
        end
    end
end

function fullgodname(g)
    if g == "B" then
        return "Beogh"
    elseif g == "C" then
        return "Cheibriados"
    elseif g == "E" then
        return "Elyvilon"
    elseif g == "H" then
        return "Hepliaklqana"
    elseif g == "L" then
        return "Lugonu"
    elseif g == "M" then
        return "Makhleb"
    elseif g == "O" then
        return "Okawaru"
    elseif g == "Q" then
        return "Qazlal"
    elseif g == "R" then
        return "Ru"
    elseif g == "T" then
        return "Trog"
    elseif g == "U" then
        return "Uskayaw"
    elseif g == "X" then
        return "Xom"
    elseif g == "Y" then
        return "Yredelemnul"
    elseif g == "Z" then
        return "Zin"
    elseif g == "1" then
        return "the Shining One"
    else
        return "???"
    end
end

function run_update()
    if update_coroutine == nil then
        update_coroutine = coroutine.create(update_stuff)
    end
    local okay, err = coroutine.resume(update_coroutine)
    if not okay then
        error("Error in coroutine: " .. err)
    end
    if coroutine.status(update_coroutine) == "dead" then
        update_coroutine = nil
        do_dummy_action = false
    else
        do_dummy_action = true
    end
end

-- We want to call this exactly once each turn.
function update_stuff()
    if not initialized then
        initialize()
    end
    if you.turns() == old_turn_count then
        time_passed = false
        return
    end
    time_passed = true
    old_turn_count = you.turns()
    if you.turns() >= dump_count then
        dump_count = dump_count + 100
        crawl.dump_char()
    end
    if you.turns() >= skill_count then
        skill_count = skill_count + 5
        handle_skills()
    end
    if did_move then
        move_count = move_count + 1
    else
        move_count = 0
    end
    did_move = false
    if did_move_towards_monster > 0 then
        did_move_towards_monster = did_move_towards_monster - 1
    end
    if you.where() ~= where then
        if (where == "nowhere" or is_waypointable(where))
                and is_waypointable(you.where()) then
            waypoint_parity = 3 - waypoint_parity
            if you.where() ~= prev_where or you.where():find("Tomb") then
                clear_level_map(waypoint_parity)
                set_waypoint()
                coroutine.yield()
            end
            cur_where = you.where()
            prev_where = where
        elseif is_waypointable(you.where()) and you.where() ~= cur_where then
            clear_level_map(waypoint_parity)
            set_waypoint()
            coroutine.yield()
            cur_where = you.where()
        end
        clear_ignores()
        target_stair = nil
        if expect_new_location then
            if where_shafted_from == you.where() then
                say("Successfully unshafted to " .. you.where() .. ".")
                where_shafted_from = nil
            end
        elseif automatic and not you.where():find("Abyss") then
            say("Shafted from " .. where .. " to " .. you.where() .. ".")
            if not where_shafted_from then
                where_shafted_from = where
            end
        end
        where = you.where()
        base_corrosion = where:find("Dis") and 2 or 0
        if cur_branch() and not util.contains(c_persist.branches_entered,
                cur_branch()) then
            say("Entered " .. cur_branch() .. ".")
            table.insert(c_persist.branches_entered, cur_branch())
        end
        if expect_portal and in_portal() then
            say("Entered " .. where .. ".")
        end
        c_persist.portals_found = { }
        if where == "Vaults:5" and not v5_entry_turn then
            v5_entry_turn = you.turns()
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            dsay("Tomb:2 arrival")
            tomb2_entry_turn = you.turns()
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            dsay("Tomb:3 arrival")
            tomb3_entry_turn = you.turns()
        end
    end
    if is_waypointable(where) then
        update_level_map(waypoint_parity)
    end
    update_game_status()
    expect_new_location = false
    expect_portal = false
    check_messages()
    update_monster_array()
    danger = sense_danger(LOS)
    immediate_danger = sense_immediate_danger()
    find_good_stairs()
    cloudy = not view.is_safe_square(0, 0) and view.cloud_at(0, 0) ~= nil
    sense_sigmund()
    choose_tactical_step()
    if collectgarbage("count") > 7000 then
        collectgarbage()
    end
end

function ready()
    offlevel_travel = true
    run_update()
    if do_dummy_action then
        if not did_waypoint then
            crawl.process_keys(":" .. string.char(27) .. string.char(27))
        else
            did_waypoint = false
        end
        return
    end
    if time_passed and SINGLE_STEP then
        stop()
    end
    if automatic then
        crawl.flush_input()
        crawl.more_autoclear(true)
        if have_message then
            plan_message()
        elseif you.where():find("Abyss") then
            plan_abyss_move()
        elseif you.have_orb() then
            plan_orbrun_move()
        else
            plan_move()
        end
    end
end

function magic(command)
    crawl.process_keys(command .. string.char(27) .. string.char(27) ..
                                         string.char(27))
end

--------------------------------
-- a function to test various things conveniently
function ttt()
    for i = -7, 7 do
        for j = -7, 7 do
            m = monster.get_monster_at(i, j)
            if m then
                crawl.mpr("(" .. i .. "," .. j .. "): name = " .. m:name() .. ", desc = " .. m:desc() .. ".")
            end
        end
    end
    --for it in inventory() do
    --    crawl.mpr("name = " .. it.name() .. ", ego = " ..
    --        (it.ego() or "none") .. ", subtype = " ..
    --        (it.subtype() or "none") .. ", slot = " .. slot(it) .. ".")
    --end
    for it in at_feet() do
        local val1, val2 = equip_value(it)
        local val3, val4 = equip_value(it, true)
        crawl.mpr("name = " .. it.name() .. ", ego = " ..
            (it.ego() or "none") .. it.ego_type .. ", subtype = " ..
            (it.subtype() or "none") .. ", slot = " .. (slot(it) or -1) ..
            ", values = " .. val1 .. " " .. val2 .. " " .. val3 .. " " ..
            val4 .. ".")
    end
end

function print_level_map()
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local x, y
    local str
    for y = -20, 20 do
        str = ""
        for x = -20, 20 do
            if level_map[num][dx + x][dy + y] == nil then
                str = str .. " "
            else
                str = str .. level_map[num][dx + x][dy + y]
            end
        end
        say(str)
    end
end

function print_stair_dists()
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local x, y
    local i
    local str
    for i = 1, #stair_dists[num] do
    say("---------------------------------------")
    for y = -20, 20 do
        str = ""
        for x = -20, 20 do
            if stair_dists[num][i][dx + x][dy + y] == nil then
                str = str .. " "
            else
                str = str .. string.char(string.byte('A') +
                stair_dists[num][i][dx + x][dy + y])
            end
        end
        say(str)
    end
    end
end

function c_trap_is_safe(trap)
    return you.race() == "Formicid"
        or trap ~= "permanent teleport" and trap ~= "dispersal"
end

function c_answer_prompt(prompt)
    if prompt == "Die?" then
        return false
    end
    if prompt:find("Have to go through") then
        return offlevel_travel
    end
    if prompt:find("transient mutations") then
        return true
    end
    if prompt:find("Keep disrobing") then
        return false
    end
    if prompt:find("Really unwield") or prompt:find("Really take off")
         or prompt:find("Really remove") or prompt:find("Really wield")
         or prompt:find("Really wear") or prompt:find("Really put on")
         or prompt:find("Really quaff") then
        return true
    end
    if prompt:find("Keep reading") then
        return true
    end
    if prompt:find("This attack would place you under penance") then
        return false
    end
    if prompt:find("You cannot afford")
            and prompt:find("travel there anyways") then
        return true
    end
    if prompt:find("Shopping list") then
        return false
    end
    if prompt:find("Are you sure you want to drop") then
        return true
    end
    if prompt:find("Really rampage") then
        return true
    end
end

function ch_stash_search_annotate_item(it)
    return ""
end

function c_choose_acquirement()
    local acq_items = items.acquirement_items()

    -- These categories should be in order of preference.
    local wanted = {"weapon", "armour", "jewellery", "gold"}
    local item_ind = {}
    for _, c in ipairs(wanted) do
        item_ind[c] = 0
    end

    for n, it in ipairs(acq_items) do
        local class = it.class(true)
        if item_ind[class] ~= nil then
            item_ind[class] = n
        end
    end

    for _, c in ipairs(wanted) do
        local ind = item_ind[c]
        if item_ind[c] > 0 then
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
}
