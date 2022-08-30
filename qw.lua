------------------------
-- Some global variables

-- The version of qw for logging purposes. Run the make-qw-rc.sh script to set
-- this variable automatically based on the latest annotate git tag and commit,
-- or change it here to a custom version string.
local qw_version = "%VERSION%"

-- Crawl enum values :/
local enum_mons_pan_lord = 344
local enum_att_friendly = 4
local enum_att_neutral = 1

function enum(tbl)
    local e = {}
    for i = 0, #tbl - 1 do
        e[tbl[i + 1]] = i
    end

    return e
end

-- Exploration state enum
local AUTOEXP = enum {
    "NEEDED",
    "PARTIAL",
    "TRANSPORTER",
    "RUNED_DOOR",
    "FULL",
} --hack

-- Feature LOS state enum
local FEAT_LOS = enum {
    "NONE",
    "SEEN",
    "DIGGABLE",
    "REACHABLE",
    "EXPLORED",
} --hack

-- Stair direction
local DIR = {
    UP   = -1,
    DOWN =  1,
} --hack

local INF_TURNS = 200000000

local los_radius = you.race() == "Barachi" and 8 or 7

local initialized = false
local time_passed
local automatic = false
local update_coroutine
local do_dummy_action

local branch_data = {}
local portal_data = {}
local god_data = {}

local where
local where_branch
local where_depth
local can_waypoint
local base_corrosion

local dump_count = you.turns() + 100 - (you.turns() % 100)
local skill_count = you.turns() - (you.turns() % 5)

local early_first_lair_branch
local first_lair_branch_end
local early_second_lair_branch
local second_lair_branch_end
local early_vaults
local vaults_end
local early_zot
local zot_end

local gameplan_list
local override_gameplans
local which_gameplan = 1
local gameplan_status
local gameplan_branch
local gameplan_depth
local permanent_bazaar

local planning_god_uses_mp
local planning_vaults
local planning_slime
local planning_tso
local planning_pan
local planning_undead_demon_branches
local planning_cocytus
local planning_gehenna

local travel_branch
local travel_depth
local want_gameplan_update
local want_go_travel
local disable_autoexplore

local stairs_search_dir
local stairs_search
local stairs_travel

local travel_fail_count = 0
local backtracked_to

local transp_search
local transp_zone
local zone_counts = {}

local danger
local immediate_danger
local cloudy

local ignore_list = { }
local failed_move = { }
local invisi_count = 0
local next_delay = 100

local sigmund_dx = 0
local sigmund_dy = 0
local invis_sigmund = false

local sgd_timer = -200

local stuck_turns = 0

local stepped_on_lair = false
local stepped_on_tomb = false
local branch_step_mode = false

local did_move = false
local move_count = 0

local did_move_towards_monster = 0
local target_memory_x
local target_memory_y

local last_wait = 0
local wait_count = 0
local old_turn_count = you.turns() - 1
local hiding_turn_count = -100

local have_message = false
local read_message = true

local monster_array
local enemy_list

local upgrade_phase = false
local acquirement_pickup = false
local acquirement_class

local tactical_step
local tactical_reason

local is_waiting

local stairdance_count = {}
local clear_exclusion_count = {}
local vaults_end_entry_turn
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
local current_where
local previous_where
local did_waypoint = false
local good_stair_list
local target_stair
local last_flee_turn = -100
local map_search
local map_search_key
local map_search_pos
local map_search_zone
local map_search_count

local will_zig = false
local might_be_good = false
local dislike_pan_level = false

local prev_hatch_dist = 1000
local prev_hatch_x
local prev_hatch_y

local hell_branches = { "Coc", "Dis", "Geh", "Tar" }

saved_locals = {}

-- Options to set while qw is running. Maybe should add more mutes for
-- watchability.

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
--        = "extended", assume we are in (or about to enter) extended branches
--        if planning to convert to TSO, we need this weapon to be TSO-friendly
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

-- Returns the amount of an artprop granted by an item.
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
            elseif ego == "fire resistance"
                    or ego == "resistance"
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
            return name:find("storm dragon") and 1 or 0
        elseif str == "rPois" then
            return (ego == "poison resistance"
                or subtype == "ring of poison resistance"
                or name:find("swamp dragon")
                or name:find("gold dragon")) and 1 or 0
        elseif str == "rN" then
            return (ego == "positive energy"
                or subtype == "ring of positive energy"
                or name:find("pearl dragon")) and 1 or 0
        elseif str == "Will" then
            return (ego == "willpower"
                or subtype == "ring of willpower"
                or name:find("quicksilver dragon")) and 1 or 0
        elseif str == "rCorr" then
            return (subtype == "ring of resist corrosion"
                or name:find("acid dragon")) and 1 or 0
        elseif str == "SInv" then
            return (ego == "see invisible"
                or subtype == "ring of see invisible") and 1 or 0
        elseif str == "Fly" then
            return ego == "flying" and 1 or 0
        elseif str == "Faith" then
            return subtype == "amulet of faith" and 1 or 0
        elseif str == "Spirit" then
            return (ego == "spirit shield"
                    or subtype == "amulet of guardian spirit") and 1 or 0
        elseif str == "Regen" then
             return (name:find("troll leather")
                     or subtype == "amulet of regeneration") and 1 or 0
        elseif str == "Acrobat" then
             return subtype == "amulet of the acrobat" and 1 or 0
        elseif str == "Reflect" then
             return (ego == "reflection" or subtype == "amulet of reflection")
                 and 1 or 0
        elseif str == "Repulsion" then
             return ego == "repulsion" and 1 or 0
        elseif str == "Ponderous" then
             return ego == "ponderousness" and 1 or 0
        elseif str == "Harm" then
             return ego == "harm" and 1 or 0
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
            return subtype == "ring of slaying" and it.plus or 0
        elseif str == "AC" then
            if subtype == "ring of protection" then
                return it.plus or 0
            -- Wrong for weapons, but we scale things differently for weapons.
            elseif ego == "protection" then
                return 3
            end
        elseif str == "EV" then
            return subtype == "ring of evasion"  and it.plus or 0
        elseif str == "SH" then
            return subtype == "amulet of reflection" and 5 or 0
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
        if intrinsic_rpois() or you.mutation("poison resistance") > 0 then
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
        if intrinsic_sinv() or you.mutation("see invisible") > 0 then
            return 1
        else
            return 0
        end
    elseif str == "Fly" then
        return intrinsic_flight() and 1 or 0
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
    local stat
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
    if branch_soon("Slime")
            and (str == "rF"
                or str == "rElec"
                or str == "rPois"
                or str == "rN"
                or str == "Will"
                or str == "SInv") then
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
        if str == "rF" then
            if branch_soon("Zot") then
                val = val * 2.5
            elseif branch_soon("Geh") then
                val = val * 1.5
            end
        elseif str == "rC" then
            if branch_soon("Coc") then
                val = val * 2.5
            elseif branch_soon("Slime") then
                val = val * 1.5
            end
        end
        return val
    elseif str == "rElec" then
        return 75
    elseif str == "rPois" then
        return easy_runes() < 2 and 225 or 75
    elseif str == "rN" then
        return 25 * min(n, 3)
    elseif str == "Will" then
        local branch_factor = branch_soon("Vaults") and 1.5 or 1
        return min(100 * branch_factor * n, 300 * branch_factor)
    elseif str == "rCorr" then
        return branch_soon("Slime") and 1200 or 50
    elseif str == "SInv" then
        return 200
    elseif str == "Fly" then
        return 200
    elseif str == "Faith" then
        -- We either don't use invocations much for these gods
        if you.god() == "Cheibriados"
                or you.god() == "Beogh"
                or you.god() == "Qazlal"
                or you.god() == "Hepliaklqana"
                or you.god() ~= "Ru"
                or you.god() ~= "Xom" then
            return 0
        -- Otherwise, we like Faith a lot.
        else
            return 1000
        end
    elseif str == "Spirit" then
        return god_uses_mp() and -150 or 100
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
    elseif str == "Repulsion" then
        return 200
    -- Begin properties we always assign a nonpositive value.
    elseif str == "Harm" then
        return -500
    elseif str == "Ponderous" then
        return -300
    elseif str == "Fragile" then
        return -10000
    elseif str == "-Tele" then
        return you.race() == "Formicid" and 0 or -10000
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
            val = 125
        elseif d == 2 then
            val = 200
        elseif d == 3 then
            val = 250
        end

        if str == "rF" then
            val = val * 2.5
        elseif str == "rC" then
            if planning_cocytus then
                val = val * 2.5
            elseif planning_slime then
                val = val * 1.5
            end
        end
        return val
    elseif str == "rElec" then
        return ires < 1 and 75 or 0
    elseif str == "rPois" then
        return ires < 1 and (easy_runes() < 2 and 225 or 75) or 0
    elseif str == "rN" then
        return ires < 3 and 25 * d or 0
    elseif str == "Will" then
        local branch_factor = planning_vaults and 1.5 or 1
        return min(100 * branch_factor * d, 300 * branch_factor)
    elseif str == "rCorr" then
        return ires < 1 and (planning_slime and 1200 or 50) or 0
    elseif str == "SInv" then
        return ires < 1 and 200 or 0
    elseif str == "Fly" then
        return ires < 1 and 200 or 0
    elseif str == "Faith" then
        if you.god() == "Cheibriados"
                or you.god() == "Beogh"
                or you.god() == "Qazlal"
                or you.god() == "Hepliaklqana"
                or you.god() ~= "Ru"
                or you.god() ~= "Xom" then
            return 0
        else
            return 1000
        end
    elseif str == "Spirit" then
        return ires < 1 and not god_uses_mp() and 100 or 0
    elseif str == "Acrobat" then
        return 100
    elseif str == "Reflect" then
        return 20
    elseif str == "Repulsion" then
        return 200
    end

    return 0
end

function min_resist_value(str, d)
    if d < 0 then
        if str == "rF" then
            return -450
        elseif str == "rC" then
            if planning_cocytus then
                return -450
            elseif planning_slime then
                return -225
            end

            return -150
        elseif str == "Will" then
            return 75 * d
        end
    -- Begin properties that are always bad.
    elseif d > 0 then
        if str == "Harm" then
            return -500
        elseif str == "Ponderous" then
            return -300
        elseif str == "Fragile" then
            return -10000
        elseif str == "-Tele" then
            return you.race() == "Formicid" and 0 or -10000
        end
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
    -- Begin negative properties.
    elseif str == "*Tele" then
        return you.race() == "Formicid" and 0 or -300
    elseif str == "*Rage" then
        return (intrinsic_undead() or you.race() == "Formicid")
            and 0 or -300
    elseif str == "*Slow" then
        return you.race() == "Formicid" and 0 or -100
    elseif str == "*Corrode" then
        return -100
    end

    return 0
end

-- Resistances and properties that don't have a linear progression of value at
-- different levels. The Str/Dex/Int in nonlinear_resists can only recieve
-- negative utility, which happens when they are reduced to dangerous levels.
local nonlinear_resists = { "Str", "Dex", "Int", "rF", "rC", "rElec", "rPois",
    "rN", "Will", "rCorr", "SInv", "Fly", "Faith", "Spirit", "Acrobat",
    "Reflect", "Repulsion", "-Tele", "Ponderous", "Harm", "Fragile" }
-- These properties always provide the same benefit (or detriment) with each
-- point/pip/instance of the property.
local linear_resists = { "Str", "Dex", "Slay", "AC", "EV", "SH", "Regen",
    "*Slow", "*Corrode", "*Tele", "*Rage" }

function total_resist_value(it, cur, it2)
    local val = 0
    for _, str in ipairs(linear_resists) do
        val = val + item_resist(str, it) * linear_resist_value(str)
    end

    local val1, val2 = val, val
    if not only_linear_resists then
        for _, str in ipairs(nonlinear_resists) do
            local a, b = resist_value(str, it, cur, it2)
            val1 = val1 + a
            val2 = val2 + b
        end
    end
    return val1, val2
end

function resist_vec(it)
    local vec = { }
    for _, str in ipairs(nonlinear_resists) do
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

-- Is the first item going to be worse than the second item no matter what
-- other resists we have?
function resist_dominated(it, it2)
    local bmin, bmax = base_equip_value(it)
    local bmin2, bmax2 = base_equip_value(it2)
    local diff = bmin2 - bmax
    if diff < 0 then
        return false
    end

    local vec = resist_vec(it)
    local vec2 = resist_vec(it2)
    for i = 1, #vec do
        if vec[i] > vec2[i] then
            diff = diff - (vec[i] - vec2[i])
        end
    end
    return diff >= 0
end

function easy_runes()
    local branches = {"Swamp", "Snake", "Shoals", "Spider"}
    local count = 0
    for _, br in ipairs(branches) do
        if have_branch_runes(br) then
            count = count + 1
        end
    end
    return count
end

function gameplan_normal_next(final)
    local gameplan

    -- Don't try to convert from Ignis too early.
    if explored_level_range("D:1-8")
            and you.god() == "Ignis"
            and you.piety_rank() == 0 then
        local found = {}
        local gods = god_options()
        local keep_ignis = false
        for _, g in ipairs(gods) do
            if g == "Ignis" then
                keep_ignis = true
                break
            elseif altar_found(g) then
                table.insert(found, g)
            end
        end

        if not keep_ignis then
            if #found ~= #gods
                    and branch_found("Temple")
                    and not explored_level_range("Temple") then
                return "Temple"
            end

            if #found > 0 then
                if not c_persist.chosen_god then
                    c_persist.chosen_god = found[crawl.roll_dice(1, #found)]
                end

                return "God:" .. c_persist.chosen_god
            end
        end
    end

    if not explored_level_range("D:1-11") then
        -- We head to Lair early, before having explored through D:11, if we
        -- feel we're ready.
        if branch_found("Lair")
                and not explored_level_range("Lair")
                and ready_for_lair() then
            gameplan = "Lair"
        else
            gameplan = "D:1-11"
        end
    -- D:1-11 explored, but not Lair.
    elseif not explored_level_range("Lair") then
        gameplan = "Lair"
    -- D:1-11 and Lair explored, but not D:12.
    elseif not explored_level_range("D:12") then
        if LATE_ORC then
            gameplan = "D"
        else
            gameplan = "D:12"
        end
    -- D:1-12 and Lair explored, but not all of D.
    elseif not explored_level_range("D") then
        if not LATE_ORC
                and branch_found("Orc")
                and not explored_level_range("Orc") then
            gameplan = "Orc"
        else
            gameplan = "D"
        end
    -- D and Lair explored, but not Orc.
    elseif not explored_level_range("Orc") then
        gameplan = "Orc"
    end

    if gameplan then
        return gameplan
    end

    -- At this point we're sure we've found Lair branches.
    if not early_first_lair_branch then
        local first_br = next_branch(lair_branch_order())
        early_first_lair_branch = make_level_range(first_br, 1, -1)
        first_lair_branch_end = branch_end(first_br)

        local second_br = next_branch(lair_branch_order(), 1)
        early_second_lair_branch = make_level_range(second_br, 1, -1)
        second_lair_branch_end = branch_end(second_br)
    end

    -- D, Lair, and Orc explored, but no Lair branch.
    if not explored_level_range(early_first_lair_branch) then
        gameplan = early_first_lair_branch
    -- D, Lair, and Orc explored, levels 1-3 of the first Lair branch.
    elseif not explored_level_range(early_second_lair_branch) then
        gameplan = early_second_lair_branch
    -- D, Lair, and Orc explored, levels 1-3 of both Lair branches.
    elseif not explored_level_range(first_lair_branch_end) then
        gameplan = first_lair_branch_end
    -- D, Lair, Orc, and at least one Lair branch explored, but not early
    -- Vaults.
    elseif not explored_level_range(early_vaults) then
        gameplan = early_vaults
    -- D, Lair, Orc, one Lair branch, and early Vaults explored, but the
    -- second Lair branch not fully explored.
    elseif not explored_level_range(second_lair_branch_end) then
        if not explored_level_range("Depths")
                and not EARLY_SECOND_RUNE then
            gameplan = "Depths"
        else
            gameplan = second_lair_branch_end
        end
    -- D, Lair, Orc, both Lair branches, and early Vaults explored, but not
    -- Depths.
    elseif not explored_level_range("Depths") then
        gameplan = "Depths"
    -- D, Lair, Orc, both Lair branches, early Vaults, and Depths explored,
    -- but no Vaults rune.
    elseif not explored_level_range(vaults_end) then
        gameplan = vaults_end
    -- D, Lair, Orc, both Lair branches, Vaults, and Depths explored, and it's
    -- time to shop.
    elseif not c_persist.done_shopping then
        gameplan = "Shopping"
    -- If we have other gameplan entries, the Normal plan stops here, otherwise
    -- early Zot.
    elseif final and not explored_level_range(early_zot) then
        gameplan = early_zot
    -- Time to win.
    elseif final then
        gameplan = "Orb"
    end

    return gameplan
end

function gameplan_complete(plan, final)
    if plan:find("^God:") then
        return you.god() == gameplan_god(plan)
    elseif plan:find("^Rune:") then
        local branch = gameplan_rune_branch(plan)
        return not branch_exists(branch) or have_branch_runes(branch)
    end

    local branch = parse_level_range(plan)
    return plan == "Normal" and not gameplan_normal_next(final)
        or branch and not branch_exists(branch)
        or branch and explored_level_range(plan)
        or plan == "Shopping" and c_persist.done_shopping
        or plan == "Abyss"
            and have_branch_runes("Abyss")
        or plan == "Pan" and have_branch_runes("Pan")
        or plan == "Zig" and c_persist.zig_completed
end

function choose_gameplan()
    local next_gameplan, chosen_gameplan, normal_gameplan
    while not chosen_gameplan and which_gameplan <= #gameplan_list do
        chosen_gameplan = gameplan_list[which_gameplan]
        next_gameplan = gameplan_list[which_gameplan + 1]
        local chosen_final = not next_gameplan
        local next_final = not gameplan_list[which_gameplan + 2]

        if chosen_gameplan == "Normal" then
            normal_gameplan = gameplan_normal_next(chosen_final)
            if not normal_gameplan then
                chosen_gameplan = nil
            end
        -- For God conversions, we don't perform them if we see that the next
        -- plan is complete. This way if a gameplan list has god conversions,
        -- past ones won't be re-attempted when we save and reload.
        elseif chosen_gameplan:find("^God:")
                and (gameplan_complete(chosen_gameplan, chosen_final)
                    or next_gameplan
                        and gameplan_complete(next_gameplan, next_final)) then
            chosen_gameplan = nil
        elseif gameplan_complete(chosen_gameplan, chosen_final) then
            chosen_gameplan = nil
        end

        if not chosen_gameplan then
            which_gameplan = which_gameplan + 1
        end
    end

    -- We're out of gameplans, so we make our final task be getting the ORB.
    if not chosen_gameplan then
        which_gameplan = nil
        chosen_gameplan = "Orb"
    end

    if DEBUG_MODE then
        dsay("Current gameplan: " .. chosen_gameplan, "explore")
    end

    return chosen_gameplan, normal_gameplan
end

-- Choose an active portal on this level. We only consider allowed portals, and
-- choose the oldest one. Permanent bazaars get chosen last.
function choose_level_portal(level)
    local oldest_portal
    local oldest_turns
    for portal, turns_list in pairs(c_persist.portals[level]) do
        if portal_allowed(portal) then
            if #turns_list > 0
                    and (not oldest_turns
                        or turns_list[#turns_list] < oldest_turns) then
                oldest_portal = portal
                oldest_turns = turns_list[#turns_list]
            end
        end
    end

    return oldest_portal, oldest_turns
end

-- If we found a viable portal on the current level, that becomes our gameplan.
function check_portal_gameplan()
    local chosen_portal, chosen_level, chosen_turns
    for level, portals in pairs(c_persist.portals) do
        local portal, turns = choose_level_portal(level)
        if portal and (not chosen_turns or turns < chosen_turns) then
            chosen_portal = portal
            chosen_level = level
            chosen_turns = turns
        end
    end

    -- We only load a portal's parent branch info when it's actually chosen,
    -- and the parent info will be removed once the portal expires or is
    -- completed.
    if chosen_portal then
        local branch, depth = parse_level_range(chosen_level)
        branch_data[chosen_portal].parent = branch
        branch_data[chosen_portal].parent_min_depth = depth
        branch_data[chosen_portal].parent_max_depth = depth
    end

    return chosen_portal, chosen_turns == INF_TURNS
end

function update_gameplan()
    permanent_bazaar = nil
    local chosen_gameplan, normal_gameplan = choose_gameplan()
    local old_status = gameplan_status
    local status = chosen_gameplan
    local gameplan = status
    local desc

    if status == "Normal" then
        status = normal_gameplan
        gameplan = normal_gameplan
    end

    -- Once we have the rune for this branch, this gameplan will be complete.
    -- Until then, we're diving to and exploring the branch end.
    if status:find("^Rune:") then
        local branch = gameplan_rune_branch(status)
        gameplan = branch_end(branch)
        desc = status .. " rune"
    end

    local portal
    portal, permanent_bazaar = check_portal_gameplan()
    if portal then
        status = portal
        gameplan = portal
        desc = portal
    end

    -- If we're configured to join a god, prioritize exploring Temple, once
    -- it's found.
    if want_altar()
            and branch_found("Temple")
            and not explored_level_range("Temple") then
        status = "Temple"
        gameplan = status
        desc = status
    end

    -- Until the ORB is actually found, dive to and explore the end of Zot.
    if status == "Orb" and not c_persist.found_orb then
        gameplan = branch_end("Zot")
        desc = "Orb"
    end

    -- Portals remain our gameplan while we're there.
    if in_portal() then
        status = where_branch
        gameplan = where_branch
        desc = where_branch
    end

    local branch = parse_level_range(gameplan)
    if branch == "Vaults" and you.num_runes() < 1 then
        error("Couldn't get a rune to enter Vaults!")
    elseif branch == "Zot" and you.num_runes() < 3 then
        error("Couldn't get three runes to enter Zot!")
    end

    if old_status ~= status then
        if not desc then
            if status:find("^God:") then
                desc = "conversion to " .. gameplan_god(status)
            elseif status == "Shopping" then
                desc = "shopping spree"
            elseif status == "Orb" then
                desc = "orb"
            else
                desc = status
            end
        end
        say("PLANNING " .. desc:upper())
    end

    if DEBUG_MODE then
        dsay("Current gameplan status: " .. status, "explore")
    end

    update_gameplan_data(status, gameplan)
end

function branch_soon(branch)
    return branch == gameplan_branch
end

function in_extended()
    return gameplan_branch == "Pan"
        or gameplan_branch == "Coc"
        or gameplan_branch == "Dis"
        or gameplan_branch == "Geh"
        or gameplan_branch == "Tar"
        or gameplan_branch == "Tomb"
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

        -- Unrands
        if name:find("hauberk") then
            return -1, -1
        end
        if it.name():find("Mad Mage's Maulers") then
            if god_uses_mp() then
                return -1, -1
            else
                value = value + 200
            end
        elseif it.name():find("lightning scales") then
            if you.god() == "Cheibriados" then
                return -1, -1
            else
                value = value + 100
            end
        end
    elseif name:find("runed") or name:find("glowing") or name:find("dyed")
            or name:find("embroidered") or name:find("shiny") then
        val2 = val2 + 400
        val1 = val1 + (cur and 400 or -200)
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
        or planning_undead_demon_branches and planning_tso
        or you.god() == "Elyvilon"
        or you.god() == "Zin"
        or you.god() == "No God" and might_be_good
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

    if (intrinsic_evil() or you.god() == "Yredelemnul")
            and name:find("holy") then
        return -1, -1
    end

    if name:find("obsidian axe") then
        if tso then
            return -1, -1
        -- This is much less good when it can't make friendly demons.
        elseif you.mutation("hated by all") or you.god() == "Okawaru" then
            value = value - 200
        -- XXX: De-value this on certain levels or give qw better strats
        -- while mesmerized.
        else
            value = value + 200
        end
    end

    local val1, val2 = total_resist_value(it, cur, it2)
    if it.artefact and not it.fully_identified
            or name:find("runed")
            or name:find("glowing") then
        val2 = val2 + 500
        val1 = val1 + (cur and 500 or -250)
    end

    if hydra_swap then
        local hydra_quality = hydra_weapon_status(it)
        if hydra_quality == -1 then
            return -1, -1
        elseif hydra_quality == 1 then
            value = value + 500
        end
    end

    local ego = it.ego()
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
            if tso then
                return -1, -1
            end

            if extended then
                value = value - 400
            end

             -- This is what we want.
            value = value + 500
        elseif ego == "speed" then
            if you.god() == "Cheibriados" then
                return -1, -1
            end

            -- This is good too
            value = value + 300
        elseif ego == "spectralizing" then
            value = value + 200
        elseif ego == "electrocution" then
            value = value + 150
        elseif ego == "draining" then
            if tso then
                return -1, -1
            end

            if not extended then
                value = value + 75
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
    -- We might be delayed by a shield or not yet at min delay, so add a little.
    delay_estimate = delay_estimate + 1
    value = value + 1200 * it.damage / delay_estimate

    -- Subtract a bit for very slow weapons because of how much skill they
    -- require to reach min delay.
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
    if name:find("macabre finger necklace") then
        return -1, -1
    end

    if not it.fully_identified then
        if cur then
            return 800, 800
        else
            return -1, 1000
        end
    end

    local val1, val2 = total_resist_value(it, cur, it2)
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

    local val1, val2 = total_resist_value(it, cur, it2)
    return val1, val2
end

function count_charges(wand_type, ignore_it)
    local count = 0
    for it in inventory() do
        if it.class(true) == "wand"
                and (not ignore_it or slot(it) ~= slot(ignore_it))
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
    if not sub or sub ~= "digging" then
        return false
    end
    return count_charges("digging", it) < 18
end

function want_potion(it)
    sub = it.subtype()
    if sub == nil then
        return true
    end

    wanted = { "curing", "heal wounds", "haste", "resistance",
        "experience", "might", "mutation", "cancellation" }

    if planning_god_uses_mp then
        table.insert(wanted, "magic")
    end

    if planning_undead_demon_branches then
        table.insert(wanted, "lignification")
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

    if will_zig then
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
    elseif planning_undead_demon_branches
            and slotname == "Weapon"
            and not item_is_sit_dominated(it, "extended") then
        return false
    elseif slotname == "Weapon"
                and (you.god() == "the Shining One"
                        and not you.one_time_ability_used()
                    or planning_tso)
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

        -- Don't like to swap Faith.
        return item_resist("Faith", old_it) == 0
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
    if not initialized then
        return
    end

    if name:find("rune of Zot")
            or (gameplan_status == "Orb" and name:find("Orb of Zot")) then
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
-- Some tables with hardcoded data about branches/gods/portals/monsters:

-- Branch data: branch abbreviation, interlevel travel code, max depth,
-- entrance description, parent branch, min parent branch depth, max parent
-- branch depth, rune name(s).
--
-- This gets loaded into the branch_data table, which is keyed by the branch
-- name. Use the helper functions to access this data: branch_travel(),
-- branch_depth(), parent_branch(), and have_branch_runes().
local branch_data_values = {
    { "D", "D", 15 },
    { "Ossuary", nil, 1, "enter_ossuary" },
    { "Sewer", nil, 1, "enter_sewer" },
    { "Bailey", nil, 1, "enter_bailey" },
    { "IceCv", nil, 1, "enter_ice_cave" },
    { "Volcano", nil, 1, "enter_volcano" },
    { "Bailey", nil, 1, "enter_bailey" },
    { "Gauntlet", nil, 1, "enter_gauntlet" },
    { "Bazaar", nil, 1, "enter_bazaar" },
    { "WizLab", nil, 1, "enter_wizlab" },
    { "Desolation", nil, 1, "enter_desolation" },
    { "Zig", nil, 1, "enter_ziggurat" },
    { "Temple", "T", 1, "enter_temple", "D", 4, 7 },
    { "Orc", "O", 2, "enter_orcish_mines", "D", 9, 12 },
    { "Elf", "E", 3, "enter_elven_halls", "Orc", 2, 2 },
    { "Lair", "L", 5, "enter_lair", "D", 8, 11 },
    { "Swamp", "S", 4, "enter_swamp", "Lair", 2, 4, "decaying" },
    { "Shoals", "A", 4, "enter_shoals", "Lair", 2, 4, "barnacled" },
    { "Snake", "P", 4, "enter_snake_pit", "Lair", 2, 4, "serpentine" },
    { "Spider", "N", 4, "enter_spider_nest", "Lair", 2, 4, "gossamer" },
    { "Slime", "M", 5, "enter_slime_pits", "Lair", 5, 6, "slimy" },
    { "Vaults", "V", 5, "enter_vaults", "D", 13, 14, "silver" },
    { "Crypt", "C", 3, "enter_crypt", "Vaults", 3, 4 },
    { "Tomb", "W", 3, "enter_tomb", "Crypt", 3, 3, "golden" },
    { "Depths", "U", 4, "enter_depths", "D", 15, 15 },
    { "Zot", "Z", 5, "enter_zot", "Depths", 4, 4 },
    { "Pan", nil, 1, "enter_pandemonium", "Depths", 2, 2,
        { "dark", "demonic", "fiery", "glowing", "magical" } },
    { "Abyss", nil, 7, "enter_abyss", "Depths", 4, 4, "abyssal" },
    { "Hell", "H", 1, "enter_hell", "Depths", 1, 4 },
    { "Dis", "I", 7, "enter_dis", "Hell", 1, 1, "iron" },
    { "Geh", "G", 7, "enter_gehenna", "Hell", 1, 1, "obsidian" },
    { "Coc", "X", 7, "enter_cocytus", "Hell", 1, 1, "icy" },
    { "Tar", "Y", 7, "enter_tartarus", "Hell", 1, 1, "bone" },
} -- hack

-- Portal branch, entry description, max timeout in turns, description.
local portal_data_values = {
    { "Ossuary", "sand-covered staircase", 800 },
    { "Sewer", "glowing drain", 800 },
    { "Bailey", "flagged portal", 800 },
    { "Volcano", "dark tunnel", 800 },
    { "IceCv", "frozen_archway", 800, "ice cave" },
    { "Gauntlet", "gate leading to a gauntlet", 800 },
    { "Bazaar", "gateway to a bazaar", 1300 },
    { "WizLab", "magical portal", 800, "wizard's laboratory" },
    { "Desolation", "crumbling gateway", 800 },
    { "Zig", "one-way gate to a zigguart", },
} -- hack

function initialize_branch_data()
    for _, entry in ipairs(branch_data_values) do
        local br = entry[1]
        local data = {}
        data["travel"] = entry[2]
        data["depth"] = entry[3]
        data["entrance"] = entry[4]
        data["parent"] = entry[5]
        data["parent_min_depth"] = entry[6]
        data["parent_max_depth"] = entry[7]
        data["rune"] = entry[8]

        -- Update the parent entry depth with that of an entry found in the
        -- parent either if the entry depth is unconfirmed our the found entry
        -- is at a lower depth.
        if c_persist.branches[br] then
            for level, _ in pairs(c_persist.branches[br]) do
                local parent, depth = parse_level_range(level)
                if parent == data.parent
                        and (not data.parent_min_depth
                            or data.parent_min_depth ~= data.parent_max_depth
                            or depth < data.parent_min_depth) then
                    data.parent_min_depth = depth
                    data.parent_max_depth = depth
                    break
                end
            end
        end

        branch_data[br] = data

    end

    for _, entry in ipairs(portal_data_values) do
        local br = entry[1]
        local data = {}
        data["entrance_description"] = entry[2]
        data["timeout"] = entry[3]
        data["description"] = entry[4]
        if not data["description"] then
            data["description"] = br:lower()
        end
        portal_data[br] = data
    end

    early_vaults = make_level_range("Vaults", 1, -1)
    vaults_end = branch_end("Vaults")

    early_zot = make_level_range("Zot", 1, -1)
end

function branch_travel(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].travel
end

function branch_depth(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].depth
end

function branch_entrance(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].entrance
end

function portal_entrance_description(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].entrance_description
end

function portal_timeout(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].timeout
end

function portal_description(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].description
end

function parent_branch(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].parent,
        branch_data[branch].parent_min_depth,
        branch_data[branch].parent_max_depth

end

function branch_rune(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].rune
end

function branch_exists(branch)
    return not (branch == "Snake" and branch_found("Spider")
        or branch == "Spider" and branch_found("Snake")
        or branch == "Shoals" and branch_found("Swamp")
        or branch == "Swamp" and branch_found("Shoals")
        or not branch_data[branch])
end

function branch_found(branch, los_state)
    if branch == "D" then
        return {"D:0"}
    end

    if not los_state then
        -- Hack. Temple entries sometimes restrict access when they reveal the
        -- branch, requiring entry via stairs inside the vault. Requiring
        -- reachable means we won't try to access temple until we've explored
        -- these stairs and can therefore successfully travel to it. Other
        -- branches tend to not cause travel problems yet are sometimes
        -- initially spotted behind e.g. statues, so we allow only seeing them
        -- to consider them found.
        if branch == "Temple" then
            los_state = FEAT_LOS.REACHABLE
        else
            los_state = FEAT_LOS.SEEN
        end
    end

    if not c_persist.branches[branch] then
        return
    end

    for w, s in pairs(c_persist.branches[branch]) do
        if s >= los_state then
            return w
        end
    end
end

function in_branch(branch)
    return where_branch == branch
end

function branch_end(branch)
    return make_level(branch, branch_depth(branch))
end

function at_branch_end(branch)
    if not branch then
        branch = where_branch
    end

    return where_branch == branch and where_depth == branch_depth(branch)
end

function in_hell_branch()
    return util.contains(hell_branches, where_branch)
end

function branch_rune_depth(branch)
    if branch == "Abyss" then
        return 3
    else
        return branch_depth(branch)
    end
end

function have_branch_runes(branch)
    local rune = branch_rune(branch)
    if not rune then
        return true
    elseif type(rune) == "table" then
        for _, r in ipairs(rune) do
            if not you.have_rune(r) then
                return false
            end
        end

        return true
    end

    return you.have_rune(rune)
end

-- God data: name (as reported by you.god()), whether the god uses Invocations,
-- whether the god has abilities that use MP.
--
-- This gets loaded into the god_data table, which is keyed by the god name
-- name. Use the helper functions to access this data: god_full_name(),
-- god_uses_mp(), god_uses_invocations().
local god_data_values = {
    { "No God", false, false },
    { "the Shining One", true, true },
    { "Ashenzari", false, false },
    { "Beogh", true, true },
    { "Cheibriados", true, true },
    { "Dithmenos", true, true },
    { "Elyvilon", true, true },
    { "Fedhas", true, true },
    { "Gozag", false, false },
    { "Hepliaklqana", false, false },
    { "Ignis", false, false },
    { "Jiyva", true, true },
    { "Kikubaaqudgha", false, true },
    { "Lugonu", false, true },
    { "Makhleb", true, false },
    { "Nemelex Xobeh", true, true },
    { "Okawaru", true, true },
    { "Qazlal", true, true },
    { "Ru", false, false },
    { "Sif Muna", true, true },
    { "Trog", false, false },
    { "Uskayaw", true, true },
    { "Vehumet", false, false },
    { "Wu Jian", false, false },
    { "Xom", false, false },
    { "Yredelemnul", true, true },
    { "Zin", true, true },
} --hack

local god_data = {}
local god_lookups = {}
function initialize_god_data()
    for _, entry in ipairs(god_data_values) do
        local god = entry[1]
        god_data[god] = {}
        god_data[god]["uses_invocations"] = entry[2]
        god_data[god]["uses_mp"] = entry[3]

        god_lookups[god:upper()] = god
        if god == "the Shining One" then
            god_lookups["1"] = god
            god_lookups["TSO"] = god
        elseif god == "No God" then
            god_lookups["0"] = god
            god_lookups["None"] = god
        else
            god_lookups[god:sub(1, 1)] = god
            local name = god:sub(1, 3)
            name = trim(name)
            god_lookups[name:upper()] = god

            name = god:sub(1, 4)
            name = trim(name)
            god_lookups[name:upper()] = god
        end
    end
end

function god_full_name(str)
    return god_lookups[str:upper()]
end

function god_uses_mp(god)
    if not god then
        god = you.god()
    end

    if not god_data[god] then
        return false
    end

    return god_data[god].uses_mp
end

function god_uses_invocations(god)
    if not god then
        god = you.god()
    end

    if not god_data[god] then
        return false
    end

    return god_data[god].uses_invocations
end

function altar_found(god, los_state)
    if not los_state then
        los_state = FEAT_LOS.REACHABLE
    end

    if not c_persist.altars[god] then
        return
    end

    for w, s in pairs(c_persist.altars[god]) do
        if s >= los_state then
            return w
        end
    end
end

-- functions for use in the monster lists below
function in_desc(lev, str)
    return function (m)
        return you.xl() < lev and m:desc():find(str)
    end
end

function pan_lord(lev)
    return function (m)
        return you.xl() < lev and m:type() == enum_mons_pan_lord
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

-- Used for: Ru's Apocalypse, Trog's Berserk, Okawaru's Heroism, TSO's
-- Cleansing Flame, whether to buff on the orb run.
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

    ["worm"] = slow_berserk(4),

    ["iguana"] = 5,

    ["ice beast"] = check_resist(7, "rC", 1),
    ["gnoll"] = 7,
    ["orc wizard"] = 7,

    ["Natasha"] = 8,
    ["Robin"] = 8,
    ["Terence"] = 8,

    ["black bear"] = 10,
    ["ogre"] = 10,
    ["orc priest"] = 10,
    ["decayed bog body"] = 10,
    ["Blork the orc"] = 10,
    ["Crazy Yiuf"] = 10,
    ["Dowan"] = 10,
    ["Edmund"] = 10,
    ["Eustachio"] = 10,
    ["Grinder"] = 10,
    ["Ijyb"] = 10,
    ["Prince Ribbit"] = 10,
    ["Pikel"] = 10,
    ["Sigmund"] = 10,

    ["black mamba"] = 12,
    ["cane toad"] = 12,
    ["cyclops"] = 12,
    ["electric eel"] = 12,
    ["gnoll bouda"] = 12,
    ["guardian mummy"] = 12,
    ["jelly"] = 12,
    ["oklob sapling"] = 12,
    ["orc warrior"] = 12,
    ["snapping turtle"] = 12,
    ["troll"] = 12,
    ["two-headed ogre"] = 12,
    ["Duvessa"] = 12,
    ["Menkaure"] = 12,

    ["blink frog"] = 14,
    ["komodo dragon"] = 14,
    ["lindwurm"] = 14,
    ["manticore"] = 14,
    ["polar bear"] = 14,
    ["steam dragon"] = 14,
    ["Amaemon"] = 14,
    ["Gastronok"] = 14,
    ["Harold"] = 14,
    ["Nergalle"] = 14,
    ["Psyche"] = 14,

    ["boulder beetle"] = 15,
    ["catoblepas"] = 15,
    ["death yak"] = 15,
    ["swamp worm"] = 15,
    ["torpor snail"] = 15,
    ["wolf spider"] = 15,
    ["Azrael"] = 15,
    ["Erolcha"] = 15,
    ["Grum"] = 15,

    ["bunyip"] = 17,
    ["death scarab"] = 17,
    ["deep troll"] = 17,
    ["dire elephant"] = 17,
    ["fenstrider witch"] = 20,
    ["fire dragon"] = 17,
    ["goliath frog"] = 17,
    ["ice dragon"] = 17,
    ["meliai"] = 17,
    ["minotaur"] = 17,
    ["ogre mage"] = 17,
    ["orc high priest"] = 17,
    ["orc knight"] = 17,
    ["orc sorcerer"] = 17,
    ["quicksilver ooze"] = 17,
    ["red devil"] = 17,
    ["shambling mangrove"] = 17,
    ["shock serpent"] = check_resist(17, "rElec", 1),
    ["skeletal warrior"] = 17,
    ["storm dragon"] = 17,
    ["sun demon"] = check_resist(17, "rF", 1),
    ["thorn hunter"] = 17,
    ["very large slime creature"] = 17,
    ["white ugly thing"] = check_resist(17, "rC", 1),
    ["white very ugly thing"] = check_resist(17, "rC", 1),
    ["Aizul"] = 17,
    ["Arachne"] = 17,
    ["Azrael"] = 17,
    ["Erica"] = 17,
    ["Jorgrun"] = 17,
    ["Kirke"] = 17,
    ["Lodul"] = check_resist(17, "rElec", 1),
    ["Louise"] = 17,
    ["Polyphemus"] = 17,
    ["Rupert"] = 17,
    ["Snorg"] = 15,
    ["Urug"] = 17,
    ["Vashnia"] = 17,

    ["acid blob"] = 20,
    ["alligator snapping turtle"] = 20,
    ["azure jelly"] = 20,
    ["broodmother"] = 20,
    ["crystal guardian"] = 20,
    ["deep troll shaman"] = 20,
    ["emperor scorpion"] = 20,
    ["ettin"] = 20,
    ["fire giant"] = 20,
    ["frost giant"] = 20,
    ["goliath frog"] = 20,
    ["ironbound thunderhulk"] = check_resist(20, "rElec", 1),
    ["ironbound frostheart"] = check_resist(20, "rC", 1),
    ["orc warlord"] = 20,
    ["merfolk avatar"] = 20,
    ["merfolk impaler"] = 20,
    ["nagaraja"] = 20,
    ["naga sharpshooter"] = 20,
    ["radroach"] = 20,
    ["rockslime"] = 20,
    ["salamander tyrant"] = 20,
    ["spriggan air mage"] = 20,
    ["spriggan berserker"] = 20,
    ["spriggan defender"] = 20,
    ["spriggan druid"] = 20,
    ["spriggan rider"] = 20,
    ["stone giant"] = 20,
    ["sun moth"] = 20,
    ["thorn hunter"] = 20,
    ["water nymph"] = 20,
    ["Agnes"] = 20,
    ["Aizul"] = 20,
    ["Bai Suzhen"] = 20,
    ["Donald"] = 20,
    ["Frances"] = 20,
    ["Ilsuiw"] = 20,
    ["Jory"] = 20,
    ["Mlioglotl"] = 20,
    ["Nikola"] = 20,
    ["Polyphemus"] = 20,
    ["Roxanne"] = 20,
    ["Rupert"] = 20,
    ["Saint Roka"] = 20,

    ["azure jelly"] = check_resist(24, "rC", 1),
    ["ettin"] = 24,
    ["fire giant"] = check_resist(24, "rF", 1),
    ["frost giant"] = check_resist(24, "rC", 1),
    ["golden dragon"] = 24,
    ["hell hog"] = check_resist(24, "rF", 1),
    ["merfolk javelineer"] = 24,
    ["shadow dragon"] = 24,
    ["tentacled monstrosity"] = 24,
    ["Asterion"] = 24,
    ["Grunn"] = 24,
    ["Josephina"] = 24,
    ["Margery"] = check_resist(24, "rF", 2),
    ["Xtahua"] = check_resist(24, "rF", 2),
    ["Zenata"] = 24,

    ["ancient lich"] = 100,
    ["boggart"] = 100,
    ["caustic shrike"] = 100,
    ["curse toe"] = 100,
    ["curse skull"] = 100,
    ["deep elf annihilator"] = 100,
    ["deep elf sorcerer"] = 100,
    ["doom hound"] = 100,
    ["draconian annihilator"] = 100,
    ["draconian monk"] = 100,
    ["draconian scorcher"] = 100,
    ["draconian stormcaller"] = 100,
    ["dread lich"] = 100,
    ["enormous slime creature"] = 100,
    ["golden dragon"] = 100,
    ["hellion"] = 100,
    ["iron golem"] = 100,
    ["iron giant"] = 100,
    ["juggernaut"] = 100,
    ["lich"] = 100,
    ["mummy priest"] = 100,
    ["oklob plant"] = 100,
    ["orb of fire"] = 100,
    ["royal mummy"] = 100,
    ["seraph"] = 100,
    ["shard shrike"] = 100,
    ["spriggan air mage"] = check_resist(100, "rElec", 1),
    ["storm dragon"] = 100,
    ["tengu reaver"] = 100,
    ["titan"] = 100,
    ["titanic slime creature"] = 100,
    ["tormentor"] = 100,
    ["walking crystal tome"] = 100,
    ["walking divine tome"] = 100,
    ["Asmodeus"] = 100,
    ["Antaeus"] = 100,
    ["Boris"] = 100,
    ["Brimstone Fiend"] = 100,
    ["Cerebov"] = 100,
    ["Dispater"] = 100,
    ["the Enchantress"] = 100,
    ["Ereshkigal"] = 100,
    ["Frederick"] = 100,
    ["Gloorx Vloq"] = 100,
    ["Hell Sentinel"] = 100,
    ["Ice Fiend"] = 100,
    ["Khufu"] = 100,
    ["Killer Klown"] = 100,
    ["Lom Lobon"] = 100,
    ["Mara"] = 100,
    ["Mennas"] = 100,
    ["Mnoleg"] = 100,
    ["Parghit"] = 100,
    -- For the Royal Jelly, the clua monster name doesn't include the article.
    ["Royal Jelly"] = 100,
    ["Sojobo"] = 100,
    ["Tiamat"] = 100,
    ["Tzitzimitl"] = 100,
    ["Vv"] = 100,
} -- hack

-- Used for: Trog's Brothers in Arms, Okawaru's Finesse, Makhleb's Summon
-- Greater Servant, Ru's Apocalypse, the Shining One's Summon Divine Warrior,
-- whether to use consumables in Hell branches.
local nasty_monsters = {
    ["*"] = {
        hydra_check_flaming(17),
        in_desc(100, "statue"),
        in_desc(100, "'s ghost"),
        in_desc(100, "' ghost"),
        pan_lord(100),
    },

    ["boulder beetle"] = 15,
    ["catoblepas"] = 15,
    ["death yak"] = 15,
    ["fire dragon"] = 15,
    ["ice dragon"] = 15,
    ["minotaur"] = 15,
    ["red devil"] = 15,
    ["Azrael"] = 15,
    ["Erolcha"] = 15,
    ["Grum"] = 15,

    ["sun demon"] = check_resist(17, "rF", 1),
    ["Arachne"] = 17,
    ["Azrael"] = 17,
    ["Erica"] = 17,
    ["Jorgrun"] = 17,
    ["Kirke"] = 17,
    ["Lodul"] = check_resist(17, "rElec", 1),
    ["Louise"] = 17,
    ["Nessos"] = 17,
    ["Polyphemus"] = 17,
    ["Rupert"] = 17,
    ["Snorg"] = 17,
    ["Sonja"] = 17,
    ["Urug"] = 17,
    ["Vashnia"] = 17,

    ["crystal guardian"] = 20,
    ["ironbound frostheart"] = check_resist(20, "rC", 1),
    ["ironbound thunderhulk"] = check_resist(20, "rElec", 1),
    ["merfolk avatar"] = 20,
    ["orc warlord"] = 20,
    ["orb spider"] = 20,
    ["thorn hunter"] = 20,
    ["Agnes"] = 20,
    ["Aizul"] = 20,
    ["Arachne"] = 20,
    ["Bai Suzhen"] = 20,
    ["Donald"] = 20,
    ["Frances"] = 20,
    ["Ilsuiw"] = 20,
    ["Jory"] = 20,
    ["Mlioglotl"] = 20,
    ["Nikola"] = 20,
    ["Polyphemus"] = 20,
    ["Roxanne"] = 20,
    ["Rupert"] = 20,
    ["Saint Roka"] = 20,

    ["azure jelly"] = check_resist(24, "rC", 1),
    ["ettin"] = 24,
    ["fire giant"] = check_resist(24, "rF", 1),
    ["frost giant"] = check_resist(24, "rC", 1),
    ["golden dragon"] = 24,
    ["hell hog"] = check_resist(24, "rF", 1),
    ["merfolk javelineer"] = 24,
    ["shadow dragon"] = check_resist(24, "rN", 1),
    ["storm dragon"] = check_resist(24, "rElec", 1),
    ["tentacled monstrosity"] = 24,
    ["titan"] = check_resist(24, "rElec", 1),
    ["Asterion"] = 24,
    ["Grunn"] = 24,
    ["Josephina"] = 24,
    ["Margery"] = check_resist(24, "rF", 2),
    ["Xtahua"] = check_resist(24, "rF", 2),
    ["Zenata"] = 24,

    ["ancient lich"] = 100,
    ["boggart"] = 100,
    ["caustic shrike"] = 100,
    ["deep troll shaman"] = 100,
    ["doom hound"] = 100,
    ["dread lich"] = 100,
    ["electric golem"] = check_resist(100, "rElec", 1),
    ["entropy weaver"] = check_resist(100, "rCorr", 1),
    ["iron golem"] = 100,
    ["iron giant"] = 100,
    ["juggernaut"] = 100,
    ["lich"] = 100,
    ["oklob plant"] = 100,
    ["orb of fire"] = 100,
    ["royal mummy"] = 100,
    ["seraph"] = 100,
    ["shard shrike"] = 100,
    ["spark wasp"] = check_resist(100, "rElec", 1),
    ["spriggan air mage"] = check_resist(100, "rElec", 1),
    ["Asmodeus"] = 100,
    ["Antaeus"] = 100,
    ["Boris"] = 100,
    ["Brimstone Fiend"] = 100,
    ["Cerebov"] = 100,
    ["Dispater"] = 100,
    ["Ereshkigal"] = 100,
    ["the Enchantress"] = 100,
    ["Frederick"] = 100,
    ["Gloorx Vloq"] = 100,
    ["Grunn"] = 100,
    ["Hell Sentinel"] = 100,
    ["Ice Fiend"] = 100,
    ["Khufu"] = 100,
    ["Killer Klown"] = 100,
    ["Mnoleg"] = 100,
    ["Lom Lobon"] = 100,
    ["Mara"] = 100,
    ["Mennas"] = 100,
    ["Mnoleg"] = 100,
    ["Parghit"] = 100,
    ["Royal Jelly"] = 100,
    ["Sojobo"] = 100,
    ["Tiamat"] = 100,
    ["Tzitzimitl"] = 100,
    ["Vv"] = 100,
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
    ["Cerebov"] = 100,
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

function intrinsic_flight()
    local sp = you.race()
    return (sp == "Gargoyle" or sp == "Black Draconian") and you.xl() >= 14
        or sp == "Tengu" and you.xl() >= 5
end

function intrinsic_amphibious()
    local sp = you.race()
    return sp == "Merfolk" or sp == "Octopode" or sp == "Barachi"
end

function intrinsic_amphibious_or_flight()
    return intrinsic_amphibious() or intrinsic_flight()
end

function intrinsic_fumble()
    local sp = you.race()
    return not (intrinsic_amphibious_or_flight()
        or sp == "Grey Draconian"
        or sp == "Palentonga"
        or sp == "Naga"
        or sp == "Troll"
        or sp == "Ogre")
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
    return you.race() == "Ghoul" or you.race() == "Mummy"
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
    return not (is_portal_branch(loc) or loc:find("Abyss") or loc == "Pan")
end

function is_portal_branch(branch)
    return portal_data[branch] ~= nil
end

function in_portal()
    return is_portal_branch(where_branch)
end

function get_feat_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function range_contains(parent, child)
    local parent_br, parent_min, parent_max = parse_level_range(parent)
    local child_br, child_min, child_max = parse_level_range(child)
    return parent_br and child_br
        and child_br == parent_br
        and child_min >= parent_min
        and child_max <= parent_max
end

function gameplans_visit_branch(branch)
    if branch == "Zot" then
        return true
    elseif not which_gameplan then
        return false
    end

    for i = which_gameplan, #gameplan_list do
        local plan = gameplan_list[i]
        local plan_branch
        if plan:find("^Rune:") then
            plan_branch = gameplan_rune_branch(plan)
        else
            plan_branch = parse_level_range(plan)
        end

        if plan_branch
                and plan_branch == branch
                and not gameplan_complete(plan, i == #gameplan_list) then
            return true
        end
    end
end

function check_future_branches()
    planning_undead_demon_branches = false

    for _, br in ipairs(hell_branches) do
        if gameplans_visit_branch(br) then
            planning_undead_demon_branches = true
            break
        end
    end

    planning_undead_demon_branches = planning_undead_demon_branches
        or gameplans_visit_branch("Pan")
        or gameplans_visit_branch("Tomb")

    planning_vaults = gameplans_visit_branch("Vaults")
    planning_slime = gameplans_visit_branch("Slime")
    planning_pan = gameplans_visit_branch("Pan")
    planning_cocytus = gameplans_visit_branch("Coc")
    planning_gehenna = gameplans_visit_branch("Geh")
end

function check_future_gods()
    planning_god_uses_mp = false
    planning_tso = false

    if god_uses_mp() then
        planning_god_uses_mp = true
        return
    end

    if not which_gameplan then
        return
    end

    for i = which_gameplan, #gameplan_list do
        local plan = gameplan_list[i]
        local next_plan = gameplan_list[i + 1]
        local plan_final = not next_plan
        local next_final = not gameplan_list[i + 2]

        if plan:find("^God:") then
            local god = gameplan_god(plan)
            if not gameplan_complete(plan, plan_final)
                    and not (next_plan
                        and not gameplan_complete(next_plan, next_final)) then
                if god_uses_mp(god) then
                    planning_god_uses_mp = true
                elseif god == "the Shining One" then
                    planning_tso = true
                end
            end
        end
    end
end

-- Make a level range for the given branch and ranges, e.g. D:1-11. The
-- returned string is normalized so it's as simple as possible. Invalid level
-- ranges raise an error.
-- @string      branch The branch.
-- @number      first  The first level in the range.
-- @number[opt] last   The last level in the range, defaulting to the branch end.
--                     If negative, the range stops that many levels from the
--                     end of the end of the branch
-- @treturn string The level range.
function make_level_range(branch, first, last)
    local max_depth = branch_depth(branch)
    if not last then
        last = max_depth
    elseif last < 0 then
        last = max_depth + last
    end

    if first < 1
            or first > max_depth
            or last < 1
            or last > max_depth
            or first > last then
        error("Invalid level level range for " .. tostring(branch)
            ..": " .. tostring(first) .. ", " .. tostring(last))
    end

    if first == 1 and last == max_depth then
        return branch
    elseif first == last then
        return branch .. ":" .. first
    else
        return branch .. ":" .. first .. "-" .. last
    end
end

-- Make a level range for a single level, e.g. D:1.
-- @string branch The branch.
-- @int    first  The level.
-- @treturn string The level range.
function make_level(branch, depth)
    return make_level_range(branch, depth, depth)
end

-- Parse components of a level range.
-- @string      range The level range.
-- @treturn string The branch. Will be nil if the level is invalid.
-- @treturn int    The starting level.
-- @treturn int    The ending level.
function parse_level_range(range)
    local terms = split(range, ":")
    local br = terms[1]

    if not branch_data[br] then
        return
    end

    local br_depth = branch_depth(br)
    -- A branch name with no level range.
    if #terms == 1 then
        return br, 1, br_depth
    end

    local min_level, max_level
    local level_terms = split(terms[2], "-")
    min_level = tonumber(level_terms[1])
    if not min_level
            or math.floor(min_level) ~= min_level
            or min_level < 1
            or min_level > br_depth then
        return
    end

    if #level_terms == 1 then
        max_level = min_level
    else
        max_level = tonumber(level_terms[2])
        if not max_level
                or math.floor(max_level) ~= max_level
                or max_level < min_level
                or max_level > br_depth then
            return
        end
    end

    return br, min_level, max_level
end

function autoexplored_level(branch, depth)
    local state = c_persist.autoexplore[make_level(branch, depth)]
    return state and state > AUTOEXP.NEEDED
end

function explored_level(branch, depth)
    if branch == "Abyss" or branch == "Pan" then
        return have_branch_runes(branch)
    end

    return autoexplored_level(branch, depth)
        and have_all_stairs(branch, depth, DIR.DOWN, FEAT_LOS.REACHABLE)
        and have_all_stairs(branch, depth, DIR.UP, FEAT_LOS.REACHABLE)
        and (depth < branch_rune_depth(branch) or have_branch_runes(branch))
end

function explored_level_range(range)
    local br, min_level, max_level
    br, min_level, max_level = parse_level_range(range)
    if not br then
        return false
    end

    for l = min_level, max_level do
        if not explored_level(br, l) then
            return false
        end
    end

    return true
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
            or you.race() == "Formicid"
            or where_branch == "Gauntlet")
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

function can_fiery_armour()
    return you.god() == "Ignis"
                 and you.piety_rank() >= 1
                 and not you.status("fiery-armoured")
                 and can_invoke()
end

function can_foxfire_swarm()
    return you.god() == "Ignis"
                 and you.piety_rank() >= 1
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
    for _, e in ipairs(enemy_list) do
        if (moveable and you.see_cell_solid_see(e.x, e.y) or not moveable)
                and supdist(e.x, e.y) <= r then
            return true
        end
    end

    return false
end

function sense_sigmund()
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
    for x = -los_radius, los_radius do
        monster_array[x] = {}
    end
end

function update_monster_array()
    enemy_list = {}
    --c_persist.mlist = {}
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
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
        function(m) return m:type() == enum_mons_pan_lord end)
end

-- Should only be called for adjacent squares.
function monster_in_way(dx, dy)
    local m = monster_array[dx][dy]
    local feat = view.feature_at(0, 0)
    return m and (m:attitude() <= enum_att_neutral and not branch_step_mode
        or m:attitude() > enum_att_neutral
            and (m:is_constricted() or m:is_caught() or m:status("petrified")
                or m:status("paralysed") or m:desc():find("sleeping")
                or feat_is_deep_water_or_lava(feat)
                or feat  == "trap_zot"))
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

function feat_is_deep_water_or_lava(feat)
    return feat == "deep_water" or feat == "lava"
end

function deep_water_or_lava(x, y)
    return feat_is_deep_water_or_lava(view.feature_at(x, y))
end

function mons_tabbable_square(x, y)
    return not deep_water_or_lava(x, y) and not is_solid(x, y)
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
        if supdist(cx + fx, cy + fy) > los_radius then return end
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
    if supdist(x, y) > los_radius then
        return false
    end
    local m = monster_array[x][y]
    if not m or m:attitude() > enum_att_neutral then
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
    local i = 0
    for _, e in ipairs(enemy_list) do
        if supdist(cx - e.x, cy - e.y) <= r and is_ranged(e.m) then
            i = i + 1
        end
    end
    return i
end

function estimate_slouch_damage()
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
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.x, cy - e.y)
        if dist < best_dist then
            if will_tab(e.x, e.y, 0,  0, mons_tabbable_square) then
                best_dist = dist
            end
        end
    end
    return best_dist
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

function shield_skill_utility()
    local shield = items.equipped_at("Shield")
    if not shield then
        return 0
    end

    local shield_factor = you.mutation("four strong arms") > 0 and -2
        or 2 * body_size()
    local shield_penalty = 2 * shield.encumbrance * shield.encumbrance
        * (27 - you.base_skill("Shields"))
        / (5 * (20 - 3 * shield_factor)) / 27
    return 0.25 + 0.5 * shield_penalty
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
    if it and (it.cursed
                or it.name():find("obsidian axe")
                    and you.status("mesmerised")) then
        return false
    end

    local feat = view.feature_at(0, 0)
    if you.flying()
            and (feat == "deep_water" and not intrinsic_amphibious()
                or feat == "lava" and not intrinsic_flight())
            and player_resist("Fly", items.equipped_at("Weapon")) == 0 then
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
    local bestx, besty, best_info, new_info
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
    if (you.god() ~= "Yredelemnul" and you.god() ~= "Beogh")
            or dangerous_to_rest() then
        return false
    end

    for x = -3, 3 do
        for y = -3, 3 do
            m = monster_array[x][y]
            if m and m:attitude() == enum_att_friendly
                    and m:damage_level() > 0 then
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
    local bestx, besty, best_info, new_info
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

function fiery_armour()
    use_ability("Fiery Armour")
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
    if not in_branch("Zig") or not danger or not can_read() then
        return false
    end
    local para_danger = false
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
    local m
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
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            if is_traversable(x, y)
                    and not is_solid(x, y)
                    and monster_array[x][y] == nil
                    and view.is_safe_square(x, y)
                    and not view.withheld(x, y)
                    and you.see_cell_no_trans(x, y) then
                count = 0
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        if abs(x + dx) <= los_radius
                                and abs(y + dy) <= los_radius then
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
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked.
            and a1.adjacent == 0
            and a2.adjacent == 0
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
            or in_branch("Slime")
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
        say("Stepping ~*~*~tactically~*~*~ (" .. tactical_reason .. ").")
        magic(tactical_step .. "Y")
        return true
    end
    return false
end

function plan_flee_step()
    if tactical_reason == "fleeing" then
        say("FLEEEEING.")
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
    if not in_branch("Zig")
            or you.berserk()
            or you.teleporting()
            or you.confused()
            or not danger
            or not hp_is_low(70)
            or count_monsters_near(0, 0, los_radius)
                - count_monsters_near(0, 0, 2) < 15
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

function plan_fiery_armour()
    if can_fiery_armour() and want_to_fiery_armour() then
        fiery_armour()
        return true
    end

    return false
end

function want_to_bia()
    if not danger then
        return false
    end

    -- Always BiA this list of monsters.
    if (check_monster_list(los_radius, bia_necessary_monsters)
                -- If piety as high, we can also use BiA as a fallback for when
                -- we'd like to berserk, but can't, or if when we see nasty
                -- monsters.
                or you.piety_rank() > 4
                    and (want_to_berserk() and not can_berserk()
                        or check_monster_list(los_radius, nasty_monsters)))
            and count_bia(4) == 0
            and not you.teleporting() then
        return true
    end
    return false
end

function want_to_finesse()
    if danger
            and in_branch("Zig")
            and hp_is_low(80)
            and count_monsters_near(0, 0, los_radius) >= 5 then
        return true
    end
    if danger and check_monster_list(los_radius, nasty_monsters)
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
    return count_monsters(los_radius, function(m) return m:res_draining() == 0 end)
end

function want_to_sgd()
    if you.skill("Invocations") >= 12
            and (check_monster_list(los_radius, nasty_monsters)
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
        and (check_monster_list(los_radius, nasty_monsters)
            or hp_is_low(50) and immediate_danger)
        and count_divine_warrior(4) == 0
        and not you.teleporting()
end

function want_to_orbrun_divine_warrior()
    return danger and count_pan_lords(los_radius) > 0
        and count_divine_warrior(4) == 0 and not you.teleporting()
end

function want_to_fiery_armour()
    return danger
        and (hp_is_low(50)
            or count_monster_list(los_radius, scary_monsters) >= 2
            or check_monster_list(los_radius, nasty_monsters)
            or count_monsters_near(0, 0, los_radius) >= 6)
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
    return dlevel == 0 and check_monster_list(los_radius, scary_monsters)
        or dlevel <= 2
            and (danger and hp_is_low(50)
                or check_monster_list(los_radius, nasty_monsters))
end

function bad_corrosion()
    if you.corrosion() == base_corrosion then
        return false
    elseif in_branch("Slime") then
        return you.corrosion() >= 6 + base_corrosion and hp_is_low(70)
    else
        return (you.corrosion() >= 3 + base_corrosion and hp_is_low(50)
            or you.corrosion() >= 4 + base_corrosion and hp_is_low(70))
    end
end

function want_to_teleport()
    if in_branch("Zig") then
        return false
    end

    if count_hostile_sgd(los_radius) > 0 and you.xl() < 21 then
        sgd_timer = you.turns()
        return true
    end

    if in_branch("Pan")
            and (count_monster_by_name(los_radius, "hellion") >= 3
                or count_monster_by_name(los_radius, "daeva") >= 3) then
        dislike_pan_level = true
        return true
    end

    if you.xl() <= 17
            and not can_berserk()
            and count_big_slimes(los_radius) > 0 then
        return true
    end

    return immediate_danger and bad_corrosion()
            or immediate_danger and hp_is_low(25)
            or count_nasty_hell_monsters(los_radius) >= 9
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
    return count_pan_lords(los_radius) > 0
        or check_monster_list(los_radius, scary_monsters)
end

function count_nasty_hell_monsters(r)
    if not in_hell_branch() then
        return 0
    end

    -- We're most concerned with hell monsters that aren't vulnerable to any
    -- holy wrath we might have (either from TSO Cleansing Flame or the weapon
    -- brand).
    local have_holy_wrath = you.god() == "the Shining One"
        or items.equipped_at("weapon")
            and items.equipped_at("weapon").ego() == "holy wrath"
    local filter = function(m)
        return not (have_holy_wrath and mons_is_holy_vulnerable(m))
    end
    return count_monster_list(r, nasty_monsters, filter)
end

function want_to_serious_buff()
    if danger and in_branch("Zig")
            and hp_is_low(50)
            and count_monsters_near(0, 0, los_radius) >= 5 then
        return true
    end

    -- These gods have their own buffs.
    if you.god() == "Okawaru" or you.god() == "Trog" then
        return false
    end

    -- None of these uniques exist early.
    if you.num_runes() < 3 then
        return false
    end

    -- Don't waste a potion if we are already leaving.
    if you.teleporting() then
        return false
    end

    if check_monster_list(los_radius, ridiculous_uniques) then
        return true
    end

    if count_nasty_hell_monsters(los_radius) >= 5 then
        return true
    end

    return false
end

function want_resistance()
    return check_monster_list(los_radius, fire_resistance_monsters)
            and you.res_fire() < 3
        or check_monster_list(los_radius, cold_resistance_monsters)
            and you.res_cold() < 3
        or check_monster_list(los_radius, elec_resistance_monsters)
            and you.res_shock() < 1
        or check_monster_list(los_radius, pois_resistance_monsters)
            and you.res_poison() < 1
        or in_branch("Zig")
            and check_monster_list(los_radius, acid_resistance_monsters)
            and not you.res_corr()
end

function want_magic_points()
    -- No point trying to restore MP with ghost moths around.
    return count_monster_by_name(los_radius, "ghost moth") == 0
            and (hp_is_low(50) or you.have_orb() or in_extended())
        -- We want and could use these abilities if we had more MP.
        and (can_cleansing_flame(true)
                and not can_cleansing_flame()
                and want_to_cleansing_flame()
            or can_divine_warrior(true)
                and not can_divine_warrior()
                and want_to_divine_warrior())
end

function want_to_hand()
    return check_monster_list(los_radius, hand_monsters)
end

function want_to_berserk()
    return (hp_is_low(50) and sense_danger(2, true)
        or check_monster_list(2, scary_monsters)
        or invis_sigmund and not options.autopick_on)
end

function want_to_heroism()
    return danger
        and (hp_is_low(70)
            or check_monster_list(los_radius, scary_monsters)
            or count_monsters_near(0, 0, los_radius) >= 4)
end

function want_to_recall()
    if immediate_danger and hp_is_low(66) then
        return false
    end

    local mp, mmp = you.mp()
    return mp == mmp
end

function want_to_recall_ancestor()
    return count_elliptic(los_radius) == 0
end

function want_to_stay_in_abyss()
    return gameplan_branch == "Abyss"
        and not have_branch_runes("Abyss")
        and not hp_is_low(50)
end

function want_to_be_in_pan()
    return gameplan_branch == "Pan" and not have_branch_runes("Pan")
end

function plan_wait_for_melee()
    is_waiting = false
    if sense_danger(1)
            or have_reaching() and sense_danger(2)
            or not options.autopick_on
            or you.berserk()
            or you.have_orb()
            or count_bia(los_radius) > 0
            or count_sgd(los_radius) > 0
            or count_divine_warrior(los_radius) > 0
            or not view.is_safe_square(0, 0)
            or view.feature_at(0, 0) == "shallow_water"
                and intrinsic_fumble()
                and not you.flying()
            or in_branch("Abyss") then
        wait_count = 0
        return false
    end

    if you.turns() >= last_wait + 10 then
        wait_count = 0
    end

    if not danger or wait_count >= 10 then
        return false
    end

    -- Hack to wait when we enter the Vaults end, so we don't move off stairs.
    if vaults_end_entry_turn and you.turns() <= vaults_end_entry_turn + 2 then
        is_waiting = true
        return false
    end

    count = 0
    sleeping_count = 0
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

    if sleeping_count == 0 then
        wait_count = wait_count + 1
    end
    last_wait = you.turns()
    if plan_cure_poison() then
        return true
    end

    -- Don't actually wait yet, because we might use a ranged attack instead.
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
        return los_radius
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
        local count = 0
        for x = -los_radius, los_radius do
            for y = -los_radius, los_radius do
                m = monster_array[x][y]
                if m and m:attitude() == enum_att_friendly then
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
    return c_persist.current_god_list
end

function gameplan_options()
    if override_gameplans then
        return override_gameplans
    end

    local plan = c_persist.current_gameplans or DEFAULT_GAMEPLAN
    return GAMEPLANS[plan]
end

function plan_find_altar()
    if not want_altar() then
        return false
    end

    str = "altar&&<<of " .. table.concat(god_options(), "||of ")
    if FADED_ALTAR then
        str = str .. "||of an unknown god"
    end
    str = str .. ">>"
    magicfind(str)
    return true
end

function plan_find_conversion_altar()
    if not gameplan_status:find("^God:") then
        return false
    end

    local god = gameplan_god(gameplan_status)
    if you.god() == god then
        return false
    end

    magicfind("altar&&<<of " .. god .. ">>")
    return true
end

function plan_abandon_god()
    local want_god = gameplan_god(gameplan_status)
    if want_god == "No God"
            or you.class() == "Chaos Knight"
                and you.god() == "Xom"
                and CK_ABANDON_XOM then
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
    if not gameplan_status:find("^God:") then
        return false
    end

    local god = gameplan_god(gameplan_status)
    if you.god() == god then
        return false
    end

    local altar = "altar_" .. god:lower():gsub(" ", "_")
    if view.feature_at(0, 0) ~= altar then
        return false
    end

    if you.silenced() then
        rest()
    else
        magic("<JY")
        want_gameplan_update = true
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
    if disable_autoexplore
            -- Autoexplore will try to take us near any runed doors. We don't
            -- even attempt it if doing a stairs search, since it would move us
            -- off our map travel destination.
            or stairs_search
            or free_inventory_slots() == 0 then
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
    if brand == "speed" or brand == "spectralizing" then
        return true
    elseif brand == "vampirism" then
        return not you.have_orb()
    elseif brand == "electrocution" then
        return at_branch_end("Zot")
    elseif brand == "holy wrath" then
        return at_branch_end("Zot")
            or planning_undead_demon_branches
            or you.have_orb()
    else
        return false
    end
end

function plan_use_good_consumables()
    for it in inventory() do
        if it.class(true) == "scroll" and can_read() then
            if it.name():find("acquirement")
                    and not deep_water_or_lava(0, 0) then
                if read(it) then
                    return true
                end
            elseif it.name():find("enchant weapon") then
                local weapon = items.equipped_at("weapon")
                if weapon and weapon.class(true) == "weapon"
                        and not weapon.artefact and weapon.plus < 9 then
                    local oldname = weapon.name()
                    if read2(it, letter(weapon)) then
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
                    if read2(it, letter(weapon)) then
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
                    if read2(it, letter(body)) then
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
                            local oldname = it2.name()
                            if read2(it, letter(it2)) then
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
                        or base_mutation("inability to drink after injury") > 0
                        or base_mutation("inability to read after injury") > 0
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

    local sit
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
        return
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

        magic("<")
        return true
    end

    return false
end

function plan_go_down()
    local feat = view.feature_at(0, 0)
    if feat:find("stone_stairs_down") then
        magic(">")
        return true
    end
    return false
end

function ready_for_lair()
    if want_altar()
            or gameplan_branch
                and gameplan_branch == "D"
                and gameplan_depth <= 11
                and not explored_level(gameplan_branch, gameplan_depth) then
        return false
    end

    return you.god() == "Trog"
        or you.god() == "Cheibriados"
        or you.god() == "Okawaru"
        or you.god() == "Ignis"
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
        or you.god() == "Hepliaklqana" and you.piety_rank() >= 2
end

function feat_is_upstairs(feat)
    return feat:find("stone_stairs_up")
        or feat:find("^exit_") and not feat == "exit_dungeon"
end

function feat_uses_map_key(key, feat)
    if key == ">" then
        return feat:find("stone_stairs_down")
            or feat:find("enter_")
            or feat == "transporter"
            or feat == "escape_hatch_down"
    elseif key == "<" then
        return feat:find("stone_stairs_up")
            or feat:find("exit_")
            or feat == "escape_hatch_up"
    else
        return false
    end
end

function want_to_stairdance_up()
    if where == "D:1"
            or in_portal()
            or in_hell_branch()
            or in_branch("Abyss")
            or in_branch("Pan")
            or not feat_is_upstairs(view.feature_at(0, 0)) then
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
    if gameplan_status ~= "Shopping" then
        return false
    end

    which_item = can_afford_any_shoplist_item()
    if not which_item then
        -- Remove everything on shoplist
        clear_out_shopping_list()
        -- record that we are done shopping this game
        c_persist.done_shopping = true
        update_gameplan()
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

function want_altar()
    return you.race() ~= "Demigod"
        and you.god() == "No God"
        and god_options()[1] ~= "No God"
end

function send_travel(branch, depth)
    local depth_str
    if depth == nil or branch_depth(branch) == 1 then
        depth_str = ""
    else
        depth_str = depth
    end

    magic("G" .. branch_travel(branch) .. depth_str .. "\rY")
end

function plan_go_to_orb()
    if gameplan_status ~= "Orb" or not c_persist.found_orb or cloudy then
        return false
    end

    if travel_fail_count == 0 then
        travel_fail_count = 1
        magicfind("orb of zot")
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_zig_dig()
    if gameplan_branch ~= "Zig"
            or not branch_found("Zig")
            or view.feature_at(0, 0) == branch_entrance("Zig")
            or view.feature_at(3, 1) == branch_entrance("Zig")
            or count_charges("digging") == 0
            or cloudy then
        return false
    end

    if travel_fail_count == 0 then
        travel_fail_count = 1
        magic(control('f') .. portal_entrance_description("Zig") .. "\rayby\r")
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_portal_entrance()
    if in_portal()
            or not is_portal_branch(gameplan_branch)
            or not branch_found(gameplan_branch)
            or cloudy then
        return false
    end

    if travel_fail_count == 0 then
        local desc = portal_entrance_description(gameplan_branch)
        -- For timed bazaars, make a search string that can' match permanent
        -- ones.
        if gameplan_branch == "Bazaar" and not permanent_bazaar then
            desc = "a flickering " .. desc
        end
        magicfind(desc)

        travel_fail_count = 1
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_abyss_portal()
    if where_branch == "Abyss"
            or not want_to_stay_in_abyss()
            or not branch_found("Abyss")
            or cloudy then
        return false
    end

    if travel_fail_count == 0 then
        travel_fail_count = 1
        magicfind("one-way gate to the infinite horrors of the Abyss")
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_pan_portal()
    if where_branch == "Pan"
            or not want_to_be_in_pan()
            or not branch_found("Pan")
            or cloudy then
        return false
    end

    if travel_fail_count == 0 then
        travel_fail_count = 1
        magicfind("halls of Pandemonium")
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

-- Use the 'G' command to travel to our next destination.
function plan_go_command()
    if not want_go_travel or cloudy then
        return false
    end

    -- Attempt to travel to our calculated location first. Return nil so we'll
    -- retry this plan if it doesn't succeed in performing an action.
    if want_go_travel and travel_fail_count == 0 then
        travel_fail_count = 1
        send_travel(travel_branch, travel_depth)
        return
    end

    travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_portal_exit()
    -- Zig has its own stair handling in plan_zig_go_to_stairs().
    if in_portal() and where_branch ~= "Zig" then
        magic("X<\r")
        return true
    end

    return false
end

function plan_go_to_abyss_downstairs()
    if in_branch("Abyss")
            and want_to_stay_in_abyss()
            and where_depth < gameplan_depth then
        magic("X>\r")
        return true
    end

    return false
end

function plan_go_to_pan_downstairs()
    if in_branch("Pan") then
        magic("X>\r")
        return true
    end

    return false
end

local pan_failed_rune_count = -1
function want_to_dive_pan()
    return in_branch("Pan")
        and you.num_runes() > pan_failed_rune_count
        and (you.have_rune("demonic") and not have_branch_runes("Pan")
            or dislike_pan_level)
end

function plan_dive_go_to_pan_downstairs()
    if want_to_dive_pan() then
        magic("X>\r")
        return true
    end
    return false
end

-- Open runed doors in Pan to get to the pan lord vault and open them on levels
-- that are known to contain entrances to Pan if we intend to visit Pan.
function plan_open_runed_doors()
    if not in_branch("Pan") and not in_branch("Abyss") and not in_portal() then
        local br, min_depth, max_depth = parent_branch("Pan")
        if where_branch ~= parent_branch("Pan")
                or where_depth < min_depth
                or where_depth > max_depth
                or not planning_pan then
            return false
        end
    end

    for x = -1, 1 do
        for y = -1, 1 do
            if view.feature_at(x, y) == "runed_clear_door" then
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
    if in_branch("Pan") and not want_to_be_in_pan() then
        magic("X<\r")
        return true
    end
    return false
end

function plan_zig_dig()
    if not in_branch("Depths")
            or gameplan_branch ~= "Zig"
            or view.feature_at(3, 1) ~= branch_entrance("Zig") then
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

function plan_enter_portal()
    if not is_portal_branch(gameplan_branch)
            or view.feature_at(0, 0) ~= branch_entrance(gameplan_branch) then
        return false
    end

    magic(">" .. (gameplan_branch == "Zig" and "Y" or ""))
    return true
end

function plan_exit_portal()
    if not in_portal()
            -- Zigs have their own exit rules.
            or gameplan_branch == "Zig"
            or you.mesmerised()
            or not view.feature_at(0, 0):find("exit_" .. where:lower()) then
        return false
    end

    local parent, depth = parent_branch(where_branch)
    remove_portal(make_level(parent, depth), where_branch, true)

    magic("<")
    return true
end

function plan_enter_abyss()
    if view.feature_at(0, 0) == "enter_abyss"
            and want_to_stay_in_abyss() then
        magic(">Y")
        return true
    end

    return false
end

function plan_enter_pan()
    if view.feature_at(0, 0) == "enter_pandemonium"
            and want_to_be_in_pan() then
        magic(">Y")
        return true
    end

    return false
end

function plan_enter_transporter()
    if not transp_search or view.feature_at(0, 0) ~= "transporter" then
        return false
    end

    magic(">")
    return true
end

function plan_go_down_abyss()
    if view.feature_at(0, 0) == "abyssal_stair"
            and want_to_stay_in_abyss()
            and where_depth < 3 then
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
        pan_stair_turn = you.turns()
        dislike_pan_level = false
        magic(">Y")
        -- In case we are trying to leave a rune level.
        return
    end
    return false
end

function plan_zig_leave_level()
    if not in_branch("Zig") then
        return false
    end

    if c_persist.zig_completed
            and view.feature_at(0, 0) == "exit_ziggurat" then
        remove_portal(make_level(parent, depth), gameplan_branch, true)
        magic("<Y")
        return true
    elseif string.find(view.feature_at(0, 0), "stone_stairs_down") then
        magic(">")
        return true
    end

    return false
end

function plan_lugonu_exit_abyss()
    if you.god() ~= "Lugonu"
            or you.berserk()
            or you.confused()
            or you.silenced()
            or you.piety_rank() < 1
            or cmp() < 1 then
        return false
    end

    use_ability("Depart the Abyss")
    return true
end

function plan_exit_abyss()
    if view.feature_at(0, 0) == "exit_abyss"
            and not want_to_stay_in_abyss()
            and not you.mesmerised()
            and you.transform() ~= "tree" then
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
        magic("<")
        return true
    end

    return false
end

function plan_step_towards_branch()
    if (stepped_on_lair
            or not branch_found("Lair"))
                and (at_branch_end("Crypt")
                    or stepped_on_tomb
                    or not branch_found("Tomb")) then
        return false
    end

    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            local feat = view.feature_at(x, y)
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
                    branch_step_mode = true
                    local result = move_towards(x, y)
                    branch_step_mode = false
                    return result
                end
            end
        end
    end

    return false
end

-- Return the next existing level range in a list.
-- @param[opt=0] skip A number giving how many valid level ranges to skip.
-- @tparam options A list of level ranges.
-- @treturn string The next level range.
function next_branch(options, skip)
    if not skip then
        skip = 0
    end

    local skipped = 0
    for _, level in ipairs(options) do
        local branch = parse_level_range(level)
        -- Reject any levels in branches that couldn't exist given the branches
        -- we've found already.
        if branch and branch_exists(branch) then
            if skipped < skip then
                skipped = skipped + 1
            else
                return branch
            end
        end
    end
end

function lair_branch_order()
    if c_persist.lair_branch_order then
        return c_persist.lair_branch_order
    end

    local branch_options
    if RUNE_PREFERENCE == "smart" then
        if crawl.random2(2) == 0 then
            branch_options = { "Spider", "Snake", "Swamp", "Shoals" }
        else
            branch_options = { "Spider", "Swamp", "Snake", "Shoals" }
        end
    elseif RUNE_PREFERENCE == "dsmart" then
        if crawl.random2(2) == 0 then
            branch_options = { "Spider", "Swamp", "Snake", "Shoals" }
        else
            branch_options = { "Swamp", "Spider", "Snake", "Shoals" }
        end
    elseif RUNE_PREFERENCE == "nowater" then
        branch_options = { "Snake", "Spider", "Swamp", "Shoals" }
    -- "random"
    else
        if crawl.random2(2) == 0 then
            branch_options = { "Snake", "Spider", "Swamp", "Shoals" }
        else
            branch_options = { "Swamp", "Shoals", "Snake", "Spider" }
        end
    end

    c_persist.lair_branch_order = branch_options
    return branch_options
end

function dir_key(dir)
    return dir == DIR.DOWN and ">" or "<"
end

function level_stair_reset(branch, depth, dir)
    set_stairs(branch, depth, dir, FEAT_LOS.REACHABLE)

    local lev = make_level(branch, depth)
    if lev == where then
        map_search[waypoint_parity][dir_key(dir)] = nil
    elseif lev == previous_where then
        map_search[3 - waypoint_parity][dir_key(dir)] = nil
    end

    if where ~= lev then
        c_persist.autoexplore[lev] = AUTOEXP.NEEDED
    end
end

function final_depth_dir(branch, depth, dir, backtrack)
    if backtrack then
        return depth + dir, -dir
    elseif autoexplored_level(branch, depth) then
        return depth, dir
    else
        return depth
    end
end

function finalize_exploration_depth(branch, depth)
    if not autoexplored_level(branch, depth) then
        return depth
    end

    -- We just backtracked from an adjacent level to this depth. We'll not try
    -- to return to the to final search depth we calculate, but rather try to
    -- reach that search depth via unexplored stairs from the current depth.
    local backtrack = backtracked_to == make_level(branch, depth)
    -- Adjust depth for any backtracking, reversing to our previous level and
    -- searching in the opposite direction. Otherwise we only set the dir if
    -- the level is autoexplored.

    local up_depth = depth - 1
    local up_unreach = true
    local up_finished, up_lev
    if up_depth >= 1 then
        up_lev = make_level(branch, up_depth)
        up_unreach = count_stairs(branch, depth, DIR.UP,
            FEAT_LOS.REACHABLE) == 0
        up_finished = autoexplored_level(branch, up_depth)
            and count_stairs(branch, up_depth, DIR.DOWN, FEAT_LOS.REACHABLE)
                == count_stairs(branch, up_depth, DIR.DOWN, FEAT_LOS.EXPLORED)
    end

    depth_up_finished = count_stairs(branch, depth, DIR.UP, FEAT_LOS.REACHABLE)
                == count_stairs(branch, depth, DIR.UP, FEAT_LOS.EXPLORED)
    depth_down_finished = count_stairs(branch, depth,
        DIR.DOWN, FEAT_LOS.REACHABLE)
            == count_stairs(branch, depth, DIR.DOWN, FEAT_LOS.EXPLORED)

    local down_depth = depth + 1
    local down_unreach = true
    local down_finished, down_lev
    if down_depth <= branch_depth(branch) then
        down_depth_lev = make_level(branch, down_depth)
        down_unreach
            = count_stairs(branch, depth, DIR.DOWN, FEAT_LOS.REACHABLE) == 0
        down_finished = autoexplored_level(branch, down_depth)
            and count_stairs(branch, down_depth, DIR.UP, FEAT_LOS.REACHABLE)
                == count_stairs(branch, down_depth, DIR.UP, FEAT_LOS.EXPLORED)
    end

    if up_unreach then
        if depth_down_finished then
            if down_unreach then
                return depth
            end

            if down_finished then
                level_stair_reset(branch, depth, DIR.DOWN)
                level_stair_reset(branch, down_depth, DIR.UP)
                return depth
            end

            return final_depth_dir(branch, down_depth, DIR.UP, backtrack)
        end

        return depth, DIR.DOWN
    end

    if up_finished then
        if depth_up_finished then
            if depth_down_finished then
                if down_unreach then
                    level_stair_reset(branch, up_depth, DIR.DOWN)
                    level_stair_reset(branch, depth, DIR.UP)
                    return depth
                end

                if down_finished then
                    level_stair_reset(branch, up_depth, DIR.DOWN)
                    level_stair_reset(branch, depth, DIR.UP)
                    level_stair_reset(branch, depth, DIR.DOWN)
                    level_stair_reset(branch, down_depth, DIR.UP)
                    return depth
                end
            end

            return final_depth_dir(branch, down_depth, DIR.UP, backtrack)
        end

        return depth, DIR.UP
    end

    return final_depth_dir(branch, up_depth, DIR.DOWN, backtrack)
end

function explore_next_range_depth(branch, min_depth, max_depth)
    -- The earliest depth that either lacks autoexplore or doesn't have all
    -- stairs reachable.
    local branch_max = branch_depth(branch)
    for d = min_depth, max_depth do
        if not autoexplored_level(branch, d) then
            return d
        elseif not have_all_stairs(branch, d, DIR.UP, FEAT_LOS.REACHABLE)
                or not have_all_stairs(branch, d, DIR.DOWN,
                    FEAT_LOS.REACHABLE) then
            return d
        end
    end

    if max_depth == branch_depth(branch) and not have_branch_runes(branch) then
        return max_depth
    end
end

function update_gameplan_data(status, gameplan)
    gameplan_status = status

    gameplan_branch = nil
    gameplan_depth = nil
    local min_depth, max_depth
    gameplan_branch, min_depth, max_depth = parse_level_range(gameplan)

    -- This status doesn't indicate a level range.
    if not gameplan_branch then
        return
    end

    gameplan_depth
        = explore_next_range_depth(gameplan_branch, min_depth, max_depth)

    if DEBUG_MODE then
        dsay("Gameplan branch: " .. tostring(gameplan_branch), "explore")
        dsay("Gameplan depth: " .. tostring(gameplan_depth), "explore")
    end
end

-- Go up from branch, tracking parent branches and their entries to the child
-- branches we came from.
function parent_branch_chain(branch, check_branch, check_entries)
    if branch == "D" then
        return
    end

    local parents = {}
    local entries = {}
    local cur_branch = branch
    local stop_search = false
    while cur_branch ~= "D" and not stop_search do
        local parent, min_depth = parent_branch(cur_branch)

        if check_branch == parent
                or check_entries and check_entries[parent] then
            stop_search = true
        end

        -- Travel into the branch assuming we enter from min_depth. If this
        -- ends up being our stopping point because we haven't found the
        -- branch, this will be handled later in update_travel().
        entries[parent] = min_depth
        table.insert(parents, parent)
        cur_branch = parent
    end

    return parents, entries
end

function travel_branch_levels(branch, start_depth, dest_depth)
    local dir = sign(dest_depth - start_depth)
    local depth = start_depth
    while depth ~= dest_depth do
        if count_stairs(branch, depth, dir, FEAT_LOS.SEEN) == 0 then
            return depth
        end

        depth = depth + dir
    end

    return depth
end

function travel_up_branches(start_branch, start_depth, parents, entries,
        dest_branch)
    local branch = start_branch
    local depth = start_depth
    local i = 1
    for i = 1, #parents do
        if branch == dest_branch then
            break
        end

        depth = travel_branch_levels(branch, depth, 1)
        if depth ~= 1 then
            break
        end

        branch = parents[i]
        depth = entries[branch]
    end

    return branch, depth
end

function travel_down_branches(dest_branch, dest_depth, parents, entries)
    local i = #parents
    local branch, depth
    local dir = 1
    for i = #parents, 1, -1 do
        branch = parents[i]
        depth = entries[branch]

        -- Try to travel into our next branch.
        local next_depth
        if i > 1 then
            local next_parent = parents[i - 1]
            if not branch_found(next_parent)
                    -- A branch we can't actually enter with travel.
                    or not branch_travel(next_parent) then
                dir = next_parent
                break
            end
            branch = next_parent
            next_depth = entries[branch]
        else
            if not branch_found(dest_branch)
                    or not branch_travel(dest_branch) then
                dir = dest_branch
                break
            end
            branch = dest_branch
            next_depth = dest_depth
        end
        depth = 1

        depth = travel_branch_levels(branch, depth, next_depth)
        if depth ~= next_depth then
            break
        end

        i = i - 1
    end

    return branch, depth, dir
end

-- Search branch and stair data from a starting level to a destination level,
-- returning the furthest point we know we can travel and any direction we'd
-- need to go next.
-- @string  start_branch The starting branch.
-- @int     start_depth  The starting depth.
-- @string  dest_branch  The destination branch.
-- @int     dest_depth   The destination depth.
-- @treturn string       The furthest branch traveled.
-- @treturn int          The furthest depth traveled in the furthest branch.
-- @return               Either -1, 1, a string, or nil. Values of -1 or 1
--                       indicate the next stair direction to travel from the
--                       furthest travel level. A string gives the branch name
--                       of an entry that needs to be taken next. nil indicates
--                       we don't need to go any further.
function travel_destination_search(dest_branch, dest_depth, start_branch,
        start_depth)
    if not start_branch then
        start_branch = where_branch
    end
    if not start_depth then
        start_depth = where_depth
    end

    -- We're already there.
    if start_branch == dest_branch and start_depth == dest_depth then
        return dest_branch, dest_depth
    end

    local start_parents, start_entries = parent_branch_chain(start_branch,
        dest_branch)
    local dest_parents, dest_entries = parent_branch_chain(dest_branch,
        start_branch, start_entries)
    local common_parent
    if dest_parents then
        common_parent = dest_parents[#dest_parents]
    else
        common_parent = "D"
    end

    local cur_branch = start_branch
    local cur_depth = start_depth
    local dir = -1
    -- Travel up and out of the starting branch until we reach the common
    -- parent branch. Don't bother traveling up if the destination branch is a
    -- sub-branch of the starting branch.
    if start_branch ~= common_parent then
        cur_branch, cur_depth = travel_up_branches(cur_branch, cur_depth,
            start_parents, start_entries, common_parent)

        -- We weren't able to travel all the way up to the common parent.
        if cur_depth ~= start_entries[common_parent] then
            return cur_branch, cur_depth, -1
        end
    end

    -- We've already arrived at our ultimate destination.
    if cur_branch == dest_branch and cur_depth == dest_depth then
        return cur_branch, cur_depth
    end

    -- We're now in the nearest branch in the chain of parent branches of our
    -- starting branch that is also in the chain of parent branches containing
    -- the destination branch. Travel in this nearest branch to the depth of
    -- the first branch entry we'll need to take to start descending to our
    -- destination.
    local next_depth
    if common_parent == dest_branch then
        next_depth = dest_depth
    else
        next_depth = dest_entries[common_parent]
    end
    cur_depth = travel_branch_levels(common_parent, cur_depth, next_depth)

    -- We couldn't make it to the branch entry we need.
    if cur_depth ~= next_depth then
        return cur_branch, cur_depth, sign(next_depth - cur_depth)
    -- We already arrived at our ultimate destination.
    elseif cur_branch == dest_branch and cur_depth == dest_depth then
        return cur_branch, cur_depth
    end

    -- Travel into and down branches to reach our ultimate destination. We're
    -- always starting at the first branch entry we'll need to take.
    local dir
    cur_branch, cur_depth, dir = travel_down_branches(dest_branch,
        dest_depth, dest_parents, dest_entries)
    return cur_branch, cur_depth,
        (cur_branch ~= dest_branch or cur_depth ~= dest_depth) and dir or nil
end

function travel_destination(dest_branch, dest_depth)
    if not dest_branch or in_portal() then
        return
    end

    local branch, depth, dir = travel_destination_search(dest_branch,
        dest_depth)

    -- We were unable enter the branch in stairs_dir, so figure out the
    -- next best location to travel to in its parent branch.
    if type(dir) == "string" then
        -- We actually found this branch, but can't travel into it (e.g.
        -- Abyss, Pan, portals), so just unset the travel direction. A
        -- stash search travel will happen instead.
        if branch_found(dir) then
            dir = nil
        -- We haven't found the branch entance, so systematically explore over
        -- the possible entry depths in the parent branch.
        else
            local parent, min_depth, max_depth = parent_branch(dir)
            depth = explore_next_range_depth(parent, min_depth, max_depth)
            depth, dir = finalize_exploration_depth(branch, depth)
        end
    -- Get the final depth we should travel to given the state of stair
    -- exploration at our travel destination.
    else
        depth, dir = finalize_exploration_depth(branch, depth)
    end

    return branch, depth, dir
end

function update_travel()
    travel_branch, travel_depth, stairs_search_dir
        = travel_destination(gameplan_branch, gameplan_depth)

    want_go_travel = (travel_branch
            and (where_branch ~= travel_branch or where_depth ~= travel_depth))
    local want_stash_travel = not gameplan_branch
            or is_portal_branch(gameplan_branch)
                and not in_portal()
                and branch_found(gameplan_branch)
            or gameplan_branch == "Abyss"
                and where_branch ~= "Abyss"
                and branch_found("Abyss")
            or gameplan_branch == "Pan"
                and where_branch ~= "Pan"
                and branch_found("Pan")

    -- Don't autoexplore if we want to travel in some way. This is so we can
    -- leave our current level before it's completely explored. If the level is
    -- fully explored, always allow autexplore so we can get any nearby items
    -- (e.g. from dead stairdanced monsters or thrown ammo). After autoexplore
    -- finishes, it will fail on the next attempt, and the cascade will proceed
    -- to travel.
    disable_autoexplore = (stairs_search_dir
        or want_go_travel
        or want_stash_travel)
            and not explored_level(where_branch, where_depth)

    if DEBUG_MODE then
        dsay("Travel branch: " .. tostring(travel_branch) .. ", depth: "
            .. tostring(travel_depth) .. ", stairs search dir: "
            .. tostring(stairs_search_dir), "explore")
        dsay("Want go travel: " .. bool_string(want_go_travel), "explore")
        dsay("Want stash travel: " .. bool_string(want_stash_travel),
            "explore")
        dsay("Disable autoexplore: " .. bool_string(disable_autoexplore),
            "explore")
    end
end

function plan_go_to_unexplored_stairs()
    if not can_waypoint
            or stairs_search
            or not stairs_search_dir
            or where_branch ~= travel_branch
            or where_depth ~= travel_depth then
        return false
    end

    -- No point in trying if we don't have unexplored stairs.
    if have_all_stairs(where_branch, where_depth, stairs_search_dir,
            FEAT_LOS.EXPLORED) then
        return false
    end

    local key = dir_key(stairs_search_dir)
    local dx, dy = travel.waypoint_delta(waypoint_parity)
    local pos = 100 * dx + dy
    local map = map_search[waypoint_parity]
    local count = 1
    while map[key] and map[key][pos] and map[key][pos][count] do
        -- Trying to go one past this count lands us at the same destination as
        -- the count, so there are no more accessible unexplored stairs to be
        -- found from where we are, and we stop the search. The backtrack plan
        -- can take over from here.
        if map[key][pos][count] == map[key][pos][count + 1] then
            return false
        end

        count = count + 1
    end

    map_search_key = key
    map_search_pos = pos
    map_search_count = count
    magic("X" .. key:rep(count) .. "\r")
    return true
end

function can_use_transporters()
    return c_persist.autoexplore[where] == AUTOEXP.TRANSPORTER
        and (where_branch == "Temple" or in_portal())
end

function plan_go_to_transporter()
    if not can_use_transporters() or transp_search then
        return false
    end

    local search_count
    if where_branch == "Gauntlet" then
        -- Maps can have functionally different types of transporter routes and
        -- always start the player closest to a route of one type, so randomize
        -- which of the starting transporters we choose. No Gauntlet map has
        -- more than 3 starting transporters, and most have two, so use '>' 1
        -- to 4 times to reduce bias.
        if transp_zone == 0 then
            search_count = crawl.roll_dice(1, 4)
        -- After the first transporter, always take the closest one. This is
        -- important for gammafunk_gauntlet_77_escape_option so we don't take
        -- the early exit after each portal.
        else
            search_count = 1
        end
    else
        search_count = 1
        while zone_counts[transp_zone]
                and zone_counts[transp_zone][search_count] do
            search_count = search_count + 1
        end
    end

    map_search_zone = transp_zone
    map_search_count = search_count
    magic("X" .. (">"):rep(search_count) .. "\r")
    return true
end

function plan_transporter_orient_exit()
    if not can_use_transporters() or not transp_orient then
        return false
    end

    magic("X<\r")
    return true
end

function stone_stair_type(feat)
    local dir
    if feat:find("stone_stairs_down") then
        dir = DIR.DOWN
    elseif feat:find("stone_stairs_up") then
        dir = DIR.UP
    else
        return
    end

    return dir, feat:gsub("stone_stairs_"
        .. (dir == DIR.DOWN and "down_" or "up_"), "")
end

function plan_take_unexplored_stairs()
    if not stairs_search then
        return false
    end

    local dir = stone_stair_type(stairs_search)

    -- Ensure that we autoexplore any new area we arrive in, otherwise, if we
    -- have completed autoexplore at least once, we may immediately leave once
    -- we see we've found the last missing staircase.
    local level = make_level(where_branch, where_depth + dir)
    c_persist.autoexplore[level] = AUTOEXP.NEEDED

    magic("G" .. dir_key(dir))
    return true
end

-- Backtrack to the previous level if we're trying to explore stairs on a
-- travel or gameplan destination level yet have no further accessible
-- unexplored stairs. We require a travel or gameplan stairs search direction
-- to know whether to attempt this and what direction we should backtrack.
function plan_unexplored_stairs_backtrack()
    if not stairs_search_dir
            or where_branch ~= travel_branch
            or where_depth ~= travel_depth
            or cloudy then
        return false
    end

    local next_depth = where_depth + stairs_search_dir
    level_stair_reset(where_branch, where_depth, stairs_search_dir)
    level_stair_reset(where_branch, next_depth, -stairs_search_dir)
    backtracked_to = make_level(where_branch, next_depth)
    send_travel(where_branch, next_depth)
    return true
end

local did_ancestor_identity = false
function plan_ancestor_identity()
    if you.god() ~= "Hepliaklqana" or not can_invoke() then
        return false
    end
    if not did_ancestor_identity then
        use_ability("Ancestor Identity",
            "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\belliptic\ra")
        did_ancestor_identity = true
        return true
    end
    return false
end

function plan_ancestor_life()
    if you.god() ~= "Hepliaklqana" or not can_invoke() then
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
    if you.god() ~= "Ru" or not can_invoke() then
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
    magic("GD1\rY")
    return true
end

function plan_zig_go_to_stairs()
    if not in_branch("Zig") then
        return false
    end

    if c_persist.zig_completed then
        magic("X<\r")
    else
        magic("X>\r")
    end
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
    map_search[num] = {}
end

function record_stairs(branch, depth, feat, state, force)
    local dir, num
    dir, num = stone_stair_type(feat)
    local data = dir == DIR.DOWN and c_persist.downstairs or c_persist.upstairs

    local level = make_level(branch, depth)
    if not data[level] then
        data[level] = {}
    end
    local old_state = not data[level][num] and FEAT_LOS.NONE
        or data[level][num]
    if old_state < state or force then
        if DEBUG_MODE then
            dsay("Updating " .. level .. " stair " .. feat .. " from "
                .. old_state .. " to " .. state, "explore")
        end
        data[level][num] = state

        if not force then
            want_gameplan_update = true
        end
    end
end

function set_stairs(branch, depth, dir, feat_los, min_feat_los)
    local level = make_level(branch, depth)

    if not min_feat_los then
        min_feat_los = feat_los
    end

    for i = 1, num_required_stairs(branch, depth, dir) do
        if stairs_state(branch, depth, dir, num) >= min_feat_los then
            local feat = "stone_stairs_"
                .. (dir == DIR.DOWN and "down_" or "up_") .. ("i"):rep(i)
            record_stairs(branch, depth, feat, feat_los, true)
        end
    end
end

function check_stairs_search(feat)
    local dir, num
    dir, num = stone_stair_type(feat)
    if not dir then
        return
    end

    if stairs_state(where_branch, where_depth, dir, num) < FEAT_LOS.EXPLORED then
        stairs_search = feat
    end
end

function stairs_state(branch, depth, dir, num)
    local level = make_level(branch, depth)
    if dir == DIR.UP then
        if not c_persist.upstairs[level]
                or not c_persist.upstairs[level][num] then
            return FEAT_LOS.NONE
        end

        return c_persist.upstairs[level][num]
    elseif dir == DIR.DOWN then
        if not c_persist.downstairs[level]
                or not c_persist.downstairs[level][num] then
            return FEAT_LOS.NONE
        end

        return c_persist.downstairs[level][num]
    end
end

function num_required_stairs(branch, depth, dir)
    if dir == DIR.UP then
        if depth == 1
                or is_portal_branch(branch)
                or branch == "Tomb"
                or branch == "Abyss"
                or util.contains(hell_branches, branch) then
            return 0
        else
            return 3
        end
    elseif dir == DIR.DOWN then
        if depth == branch_depth(branch)
                    or is_portal_branch(branch)
                    or branch == "Tomb"
                    or branch == "Abyss" then
            return 0
        elseif util.contains(hell_branches, branch) then
            return 1
        else
            return 3
        end
    end
end

function count_stairs(branch, depth, dir, state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required == 0 then
        return 0
    end

    local num
    local count = 0
    for i = 1, num_required do
        num = "i"
        num = num:rep(i)
        if stairs_state(branch, depth, dir, num) >= state then
            count = count + 1
        end
    end
    return count
end

function have_all_stairs(branch, depth, dir, state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required > 0 then
        local num
        for i = 1, num_required do
            num = "i"
            num = num:rep(i)
            if stairs_state(branch, depth, dir, num) < state then
                return false
            end
        end
    end

    return true
end

function record_map_search(parity, key, start_pos, count, end_pos)
    if not map_search[parity][key] then
        map_search[parity][key] = {}
    end

    if not map_search[parity][key][start_pos] then
        map_search[parity][key][start_pos]  = {}
    end

    map_search[parity][key][start_pos][count] = end_pos
end

function record_branch(x, y)
    local feat = view.feature_at(x, y)
    for br, entry in pairs(branch_data) do
        if entry.entrance == feat then
            if not c_persist.branches[br] then
                c_persist.branches[br] = {}
            end

            local state = los_state(x, y)
            -- We already have a suitable entry recorded.
            if c_persist.branches[br][where]
                    and c_persist.branches[br][where] >= state then
                return
            end

            c_persist.branches[br][where] = state

            -- Update the parent entry depth with that of an entry
            -- found in the parent either if the entry depth is
            -- unconfirmed our the found entry is at a lower depth.
            local cur_br, cur_depth = parse_level_range(where)
            local parent_br, parent_min, parent_max = parent_branch(br)
            if cur_br == parent_br
                    and (parent_min ~= parent_max
                        or cur_depth < parent_min) then
                branch_data[br].parent_min_depth = cur_depth
                branch_data[br].parent_max_depth = cur_depth
            end

            want_gameplan_update = true
            return
        end
    end
end

function record_altar(x, y)
    local feat = view.feature_at(x, y)
    local god = god_full_name(feat:gsub("altar_", ""):gsub("_", " "))
    local state = los_state(x, y)
    if not c_persist.altars[god] then
        c_persist.altars[god] = {}
    end

    if c_persist.altars[god][where]
            and c_persist.altars[god][where] >= state then
        return
    end

    c_persist.altars[god][where] = state
    want_gameplan_update = true
end

function update_level_map(num)
    local distqueue = {}
    local staircount = #stair_dists[num]
    for j = 1, staircount do
        distqueue[j] = {}
    end

    local dx, dy = travel.waypoint_delta(num)
    local mapqueue = {}
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            local feat = view.feature_at(x, y)
            if feat:find("stone_stairs") then
                record_stairs(where_branch, where_depth, feat, los_state(x, y))
            elseif feat:find("enter_") then
                record_branch(x, y)
            elseif feat:find("altar_") and feat ~= "altar_ecumenical" then
                record_altar(x, y)
            end
            table.insert(mapqueue, {x + dx, y + dy})
        end
    end

    local newcount = staircount
    local first = 1
    local last = #mapqueue
    local x, y, feat, val, oldval
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

    if map_search_key then
        local feat = view.feature_at(0, 0)
        -- We assume we've landed on the next feature in our current "X<key>"
        -- cycle because the feature at our position uses that key.
        if feat_uses_map_key(map_search_key, feat) then
            record_map_search(num, map_search_key, map_search_pos,
                map_search_count, 100 * dx + dy)
            check_stairs_search(feat)
        end
        map_search_key = nil
        map_search_pos = nil
        map_search_count = nil
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

    if not can_waypoint then
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
    if not can_waypoint then
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
        invis_sigmund = false
        return false
    end
    if invisi_count > 100 then
        say("Invisible monster not found???")
        invisi_count = 0
        invis_sigmund = false
        magic(control('a'))
        return true
    end

    invisi_count = invisi_count + 1
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and view.invisible_monster(x, y) then
                magic(control(delta_to_vi(x, y)))
                return true
            end
        end
    end

    if invis_sigmund and (sigmund_dx ~= 0 or sigmund_dy ~= 0) then
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
             and not view.feature_at(x, y):find("runed") then
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
    if (where == "Tomb:2" and not have_branch_runes("Tomb")
            or where == "Tomb:1")
         and view.feature_at(0, 0) == "escape_hatch_down" then
        prev_hatch_dist = 1000
        magic(">")
        return true
    end
    if (where == "Tomb:3" and have_branch_runes("Tomb")
            or where == "Tomb:2")
         and view.feature_at(0, 0) == "escape_hatch_up" then
        prev_hatch_dist = 1000
        magic("<")
        return true
    end
    return false
end

function plan_tomb_go_to_final_hatch()
    if where == "Tomb:2" and not have_branch_runes("Tomb")
         and view.feature_at(0, 0) ~= "escape_hatch_down" then
        magic("X>\r")
        return true
    end
    return false
end

function plan_tomb_go_to_hatch()
    if where == "Tomb:3" then
        if have_branch_runes("Tomb")
             and view.feature_at(0, 0) ~= "escape_hatch_up" then
            magic("X<\r")
            return true
        end
    elseif where == "Tomb:2" then
        if not have_branch_runes("Tomb")
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
    if not at_branch_end("Swamp") then
        return false
    end
    magic("X" .. control('e'))
    return true
end

function plan_swamp_go_to_rune()
    if not at_branch_end("Swamp") or have_branch_runes("Swamp") then
        return false
    end

    if last_swamp_fail_count
            == c_persist.plan_fail_count.try_swamp_go_to_rune then
        swamp_rune_reachable = true
    end
    last_swamp_fail_count = c_persist.plan_fail_count.try_swamp_go_to_rune
    magicfind("@" .. branch_rune("Swamp") .. "rune")
    return true
end

function plan_swamp_clouds_hack()
    if not at_branch_end("Swamp") then
        return false
    end

    if have_branch_runes("Swamp") and can_teleport() and teleport() then
        return true
    end

    if swamp_rune_reachable then
        say("Waiting for clouds to move.")
        magic("s")
        return true
    end

    local bestx, besty
    local dist
    local bestdist = 11
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and view.is_safe_square(x, y)
                 and not view.withheld(x, y) and not monster_in_way(x, y) then
                dist = 11
                for x2 = -los_radius, los_radius do
                    for y2 = -los_radius, los_radius do
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
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            if (view.cloud_at(x, y) == "freezing vapour"
                    or view.cloud_at(x, y) == "foul pestilence")
                 and you.see_cell_no_trans(x, y) then
                return random_step(where)
            end
        end
    end
    return plan_stuck_teleport()
end

function plan_dig_grate()
    local grate_mon_list
    local grate_count_needed = 3
    if in_branch("Zot") then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher"}
    elseif in_branch("Depths") and at_branch_end() then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher",
            "angel", "daeva", "lich", "eye"}
    elseif in_branch("Depths") then
        grate_mon_list = {"angel", "daeva", "lich", "eye"}
    elseif in_branch("Pan") or at_branch_end("Geh") then
        grate_mon_list = {"smoke demon"}
        grate_count_needed = 1
    elseif in_branch("Zig") then
        grate_mon_list = {""}
        grate_count_needed = 1
    else
        return false
    end

    for _, e in ipairs(enemy_list) do
        local name = e.m:name()
        if contains_string_in(name, grate_mon_list)
             and not will_tab(0, 0, e.x, e.y, tabbable_square) then
            local grate_count = 0
            local closest_grate = 20
            local gx, gy, cgx, cgy
            for dx = -1, 1 do
                for dy = -1, 1 do
                    gx = e.x + dx
                    gy = e.y + dy
                    if supdist(gx, gy) <= los_radius
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
    local closest_grate = 20
    local cx, cy
    for dx = -los_radius, los_radius do
        for dy = -los_radius, los_radius do
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
            and (at_branch_end("Slime") and not have_branch_runes("Slime")
                or at_branch_end("Geh") and not have_branch_runes("Geh")) then
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
        if (abs(dx) > 1 or abs(dy) > 1) and not branch_step_mode
             and view.feature_at(dx, dy) ~= "closed_door" then
            did_move = true
            if monster_array[dx][dy] or did_move_towards_monster > 0 then
                local move_x, move_y = vi_to_delta(move)
                target_memory_x = dx - move_x
                target_memory_y = dy - move_y
                did_move_towards_monster = 2
            end
        end
        if branch_step_mode then
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
    local m = monster_array[dx][dy]
    if not m then
        return
    end

    local name = m:name()
    if not util.contains(ignore_list, name) then
        table.insert(ignore_list, name)
        crawl.setopt("runrest_ignore_monster ^= " .. name .. ":1")
        if DEBUG_MODE then
            dsay("Ignoring " .. name .. ".")
        end
    end
end

function remove_ignore(dx, dy)
    local m = monster_array[dx][dy]
    local name = m:name()
    for i, mname in ipairs(ignore_list) do
        if mname == name then
            table.remove(ignore_list, i)
            crawl.setopt("runrest_ignore_monster -= " .. name .. ":1")
            if DEBUG_MODE then
                dsay("Unignoring " .. name .. ".")
            end
            return
        end
    end
end

function clear_ignores()
    local size = #ignore_list
    local mname
    if size > 0 then
        for i = 1, size do
            mname = table.remove(ignore_list)
            crawl.setopt("runrest_ignore_monster -= " .. mname .. ":1")
            dsay("Unignoring " .. mname .. ".")
        end
    end
end

-- This gets stuck if netted, confused, etc
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
    if monster_array[x][y]:attitude() == enum_att_neutral then
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

function say(x)
    crawl.mpr(you.turns() .. " ||| " .. x)
    note(x)
end

function dsay(x, channel)
    if not channel then
        channel = "main"
    end

    if DEBUG_MODE and util.contains(DEBUG_CHANNELS, channel) then
        local str
        if type(x) == "table" then
            str = stringify_table(x)
        else
            str = tostring(x)
        end
        -- Convert x to string to make debugging easier. We don't do this for
        -- say() and note() so we can catch errors.
        crawl.mpr(you.turns() .. " ||| " .. str)
    end
end

-- these few functions are called directly from ready()

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

------------------
-- Cascading plans

-- This is the bot's flowchart for using the above plans
function cascade(plans)
    local plan_turns = {}
    local plan_result = {}
    return function ()
        for i, plandata in ipairs(plans) do
            local plan = plandata[1]
            if you.turns() ~= plan_turns[plan] or plan_result[plan] == nil then
                local result = plan()
                if not automatic then
                    return true
                end

                plan_turns[plan] = you.turns()
                plan_result[plan] = result

                if DEBUG_MODE then
                    dsay("Ran " .. plandata[2] .. ": " .. tostring(result),
                        "plans")
                end

                if result == nil or result == true then
                    if DELAYED and result == true then
                        crawl.delay(next_delay)
                    end
                    next_delay = DELAY_TIME
                    return
                end
            elseif plan_turns[plan] and plan_result[plan] == true then
                if not plandata[2]:find("^try") then
                    panic(plandata[2] .. " failed despite returning true.")
                end

                local fail_count = c_persist.plan_fail_count[plandata[2]]
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

-- Any plan that might not know whether or not it successfully took an action
-- (e.g. autoexplore) should prepend "try_" to its text.

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
    {plan_tomb2_arrival, "tomb2_arrival"},
    {plan_tomb3_arrival, "tomb3_arrival"},
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
    {plan_fiery_armour, "fiery_armour"},
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
    {plan_enter_portal, "enter_portal"},
    {plan_enter_abyss, "enter_abyss"},
    {plan_enter_pan, "enter_pan"},
    {plan_enter_transporter, "enter_transporter"},
    {plan_zig_dig, "zig_dig"},
    {plan_dive_pan, "dive_pan"},
    {plan_dive_go_to_pan_downstairs, "try_dive_go_to_pan_downstairs"},
    {plan_autoexplore, "try_autoexplore"},
} -- hack

plan_explore2 = cascade {
    {plan_go_to_orb, "try_go_to_orb"},
    {plan_shopping_spree, "try_shopping_spree"},
    {plan_go_to_pan_portal, "try_go_to_pan_portal"},
    {plan_go_to_abyss_portal, "try_go_to_abyss_portal"},
    {plan_go_to_zig_dig, "try_go_to_zig_dig"},
    {plan_go_to_portal_entrance, "try_go_to_portal_entrance"},
    {plan_open_runed_doors, "open_runed_doors"},
    {plan_transporter_orient_exit, "try_transporter_orient_exit"},
    {plan_go_to_transporter, "try_go_to_transporter"},
    {plan_zig_leave_level, "zig_leave_level"},
    {plan_zig_go_to_stairs, "try_zig_go_to_stairs"},
    {plan_exit_portal, "exit_portal"},
    {plan_go_to_portal_exit, "try_go_to_portal_exit"},
    {plan_exit_pan, "exit_pan"},
    {plan_go_to_pan_exit, "try_go_to_pan_exit"},
    {plan_go_down_pan, "try_go_down_pan"},
    {plan_go_to_pan_downstairs, "try_go_to_pan_downstairs"},
    {plan_go_to_unexplored_stairs, "try_go_to_unexplored_stairs"},
    {plan_take_unexplored_stairs, "try_take_unexplored_stairs"},
    {plan_go_command, "try_go_command"},
    {plan_autoexplore, "try_autoexplore2"},
    {plan_unexplored_stairs_backtrack, "try_unexplored_stairs_backtrack"},
} -- hack

plan_move = cascade {
    {plan_ancestor_identity, "try_ancestor_identity"},
    {plan_join_beogh, "join_beogh"},
    {plan_shop, "shop"},
    {plan_stairdance_up, "stairdance_up"},
    {plan_emergency, "emergency"},
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

------------------
-- Skill selection

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
        if you.race() == "Tengu" and intrinsic_flight() then
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
        return shield_skill_utility()
    elseif sk == "Throwing" then
        local rating
        rating, _ = best_missile()
        return 0.2 * rating
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
        return (at_min_delay() and 0.5 or 1.5)
    end
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
        if DEBUG_MODE then
            dsay("Best skill: " .. best_sk .. ", utility: " .. best_utility,
                "skills")
        end

        table.insert(skills, best_sk)
    end

    -- Choose one MP skill to train.
    mp_skill = "Evocations"
    if god_uses_invocations() then
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

--------------------
-- Utility functions

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

function bool_string(x)
    return x and "true" or "false"
end

function capitalize(str)
    local lower = str:lower()
    return lower:sub(1, 1):upper() .. lower:sub(2)
end

-- Remove leading and trailing whitespace.
function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
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

------------------
-- Debug functions

function set_gameplans(str)
    override_gameplans = str
    initialized = false
    update_coroutine = coroutine.create(turn_update)
    run_update()
end

function restore_gameplans()
    override_gameplans = nil
    initialized = false
    update_coroutine = coroutine.create(turn_update)
    run_update()
end

function toggle_debug()
    DEBUG_MODE = not DEBUG_MODE
end

function toggle_debug_channel(channel)
    if util.contains(DEBUG_CHANNELS, channel) then
        local list = util.copy_table(DEBUG_CHANNELS)
        for i, e in ipairs(DEBUG_CHANNELS) do
            if e == "plans" then
                table.remove(list, i)
            end
        end
        DEBUG_CHANNELS = list
    else
        table.insert(DEBUG_CHANNELS, channel)
    end
end

---------------------------------------------
-- initialization/control/saving

-- Remove the "God:" prefix and return the god's full name.
function gameplan_god(plan)
    if not plan:find("^God:") then
        return
    end

    return god_full_name(plan:sub(5))
end

-- Remove the "Rune:" prefix and return the branch name.
function gameplan_rune_branch(plan)
    if not plan:find("^Rune:") then
        return
    end

    return plan:sub(6)
end

-- Remove any prefix and return the Zig depth we want to reach.
function gameplan_zig_depth(plan)
    if plan == "Zig" or plan:find("^MegaZig") then
        return 27
    end

    if not plan:find("^Zig:") then
        return
    end

    return tonumber(plan:sub(5))
end

function make_initial_gameplans()
    local gameplans = split(gameplan_options(), ",")
    gameplan_list = {}
    for _, pl in ipairs(gameplans) do
        -- Two-part plan specs: God conversion and rune.
        local plan
        pl = trim(pl)
        if pl:lower():find("^god:") then
            local name = gameplan_god(pl)
            if not name then
                error("Unkown god: " .. name)
            end

            plan = "God:" .. full_name
            processed = true
        elseif pl:lower():find("^rune:") then
            local branch = capitalize(gameplan_rune_branch(pl))
            if not branch_data[branch] then
                error("Unknown rune branch: " .. branch)
            elseif not branch_rune(branch) then
                error("Branch has no rune: " .. branch)
            end

            plan = "Rune:" .. branch
            processed = true
        else
            -- Normalize the plan so we're always making accurate comparisons
            -- for special plans like Normal, Shopping, Orb, etc.
            plan = capitalize(pl)
        end

        -- We turn Hells into a sequence of gameplans for each Hell branch rune
        -- in random order.
        if plan == "Hells" then
            -- Save our selection so it can be recreated across saving.
            if not c_persist.hell_branches then
                c_persist.hell_branches = util.random_subset(hell_branches,
                    #hell_branches)
            end

            for _, br in ipairs(c_persist.hell_branches) do
                table.insert(gameplan_list, "Rune:" .. br)
            end
        end

        if plan == "Zig" then
            will_zig = true
        end

        local branch, min_level, max_level = parse_level_range(plan)
        if not (branch
                or plan:find("^Rune:")
                or plan:find("^God:")
                or plan == "Hells"
                or plan == "Normal"
                or plan == "Shopping"
                or plan == "Orb"
                or plan == "Zig") then
            error("Invalid gameplan '" .. tostring(plan) .. "'.")
        end

        table.insert(gameplan_list, plan)
    end
end

function initialize_c_persist()
    if not c_persist.portals then
        c_persist.portals = { }
    end
    if not c_persist.plan_fail_count then
        c_persist.plan_fail_count = { }
    end
    if not c_persist.branches then
        c_persist.branches = { }
    end
    if not c_persist.altars then
        c_persist.altars = { }
    end
    if not c_persist.autoexplore then
        c_persist.autoexplore = { }
    end
    if not c_persist.upstairs then
        c_persist.upstairs = { }
    end
    if not c_persist.downstairs then
        c_persist.downstairs = { }
    end
end

function initialize()
    if you.turns() == 0 then
        initialize_c_persist()
        initialize_branch_data()
        initialize_god_data()
        first_turn_initialize()
    end

    initialize_c_persist()
    initialize_branch_data()
    initialize_god_data()

    initialize_monster_array()

    make_initial_gameplans()
    where = "nowhere"
    where_branch = "nowhere"
    where_depth = nil

    if not level_map then
        level_map = {}
        stair_dists = {}
        map_search = {}
        clear_level_map(1)
        clear_level_map(2)
        waypoint_parity = 1
        previous_where = "nowhere"
    end

    for _, god in ipairs(god_options()) do
        if god == "the Shining One" or god == "Elyvilon" or god == "Zin" then
            might_be_good = true
        end
    end

    set_options()
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

function note_qw_data()
    note("qw: Version: " .. qw_version)
    note("qw: Game counter: " .. c_persist.record.counter)
    note("qw: Always use a shield: " .. bool_string(SHIELD_CRAZY))
    if not util.contains(god_options(), you.god()) then
        note("qw: God list: " .. table.concat(god_options(), ", "))
        note("qw: Allow faded altars: " .. bool_string(FADED_ALTAR))
    end
    note("qw: Do Orc after D:" .. branch_depth("D") .. " "
        .. bool_string(LATE_ORC))
    note("qw: Do second Lair branch before Depths: " ..
        bool_string(EARLY_SECOND_RUNE))
    note("qw: Lair rune preference: " .. RUNE_PREFERENCE)

    local plans = gameplan_options()
    note("qw: Plans: " .. plans)
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

    local god_list = c_persist.next_god_list
    local plans = c_persist.next_gameplans
    for key, _ in pairs(c_persist) do
        if key ~= "record" then
            c_persist[key] = nil
        end
    end

    if not god_list then
        if GOD_LIST and #GOD_LIST > 0 then
            god_list = GOD_LIST
        else
            error("No default god list defined in GOD_LIST.")
        end
    end

    -- Check for and normalize a list with "No God"
    local no_god = false
    for _, god in ipairs(god_list) do
        if god_full_name(god) == "No God" then
            no_god = true
            break
        end
    end
    if no_god then
        if #god_list > 1 then
            error("God list containing 'No God' must have no other entries.")
        else
            god_list = {"No God"}
        end
    end
    c_persist.current_god_list = god_list

    c_persist.current_gameplans = plans
    note_qw_data()

    if COMBO_CYCLE then
        local combo_string_list = split(COMBO_CYCLE_LIST, ",")
        local combo_string = combo_string_list[
            1 + (c_persist.record.counter % (#combo_string_list))]
        combo_string = trim(combo_string)
        local combo_parts = split(combo_string, "^")
        c_persist.options = "combo = " .. combo_parts[1]
        if #combo_parts > 1 then
            local plan_parts = split(combo_parts[2], "!")
            c_persist.next_god_list = { }
            for g in plan_parts[1]:gmatch(".") do
                table.insert(c_persist.next_god_list, god_full_name(g))
            end
            if #plan_parts > 1 then
                if not GAMEPLANS[plan_parts[2]] then
                    error("Unknown plan name '" .. plan_parts[2] .. "'" ..
                    " given in combo spec '" .. combo_string .. "'")
                end
                c_persist.next_gameplans = plan_parts[2]
            end
        end
    end
end

function run_update()
    if update_coroutine == nil then
        update_coroutine = coroutine.create(turn_update)
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

function portal_allowed(portal)
    return util.contains(ALLOWED_PORTALS, portal)
end

function remove_portal(level, portal, silent)
    if not c_persist.portals[level]
            or not c_persist.portals[level][portal]
            or #c_persist.portals[level][portal] == 0 then
        return
    end

    -- This is a list because bazaars can be both permanent and timed and
    -- potentially with both on the same level. We make the list so the timed
    -- portal is at the end, and since we enter timed portals before the
    -- permanent one, we always want to remove from the end.
    table.remove(c_persist.portals[level][portal])
    branch_data[portal].parent = nil
    branch_data[portal].parent_min_depth = nil
    branch_data[portal].parent_max_depth = nil

    if portal_allowed(portal) then
        if not silent then
            say("RIP " .. portal:upper())
        end

        want_gameplan_update = true
    end
end

-- Expire any timed portals for levels we've fully explored or where they're
-- older than their max timeout.
function check_expired_portals()
    for level, portals in pairs(c_persist.portals) do
        local explored = explored_level_range(level)
        for portal, turns_list in pairs(portals) do
            local timeout = portal_timeout(portal)
            for _, turns in ipairs(turns_list) do
                if where_branch ~= portal
                        and turns ~= INF_TURNS
                        and (explored
                            or timeout and you.turns() - turns > timeout) then
                    remove_portal(level, portal)
                end
            end
        end
    end
end

-- We want to call this exactly once each turn.
function turn_update()
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

            if you.where() ~= previous_where or in_branch("Tomb") then
                clear_level_map(waypoint_parity)
                set_waypoint()
                coroutine.yield()
            end

            current_where = you.where()
            previous_where = where
        elseif is_waypointable(you.where())
                and you.where() ~= current_where then
            clear_level_map(waypoint_parity)
            set_waypoint()
            coroutine.yield()
            current_where = you.where()
        end

        where = you.where()
        where_branch = you.branch()
        where_depth = you.depth()
        want_gameplan_update = true

        if backtracked_to ~= where then
            backtracked_to = nil
        end

        clear_ignores()
        target_stair = nil
        base_corrosion = in_branch("Dis") and 2 or 0

        transp_zone = 0
        zone_counts = {}

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = you.turns()
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = you.turns()
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = you.turns()
        end
    end

    stairs_search = nil

    transp_search = nil
    if can_use_transporters() then
        local feat = view.feature_at(0, 0)
        if feat_uses_map_key(">", feat) and map_search_zone then
            if not zone_counts[map_search_zone] then
                zone_counts[map_search_zone] = {}
            end
            zone_counts[map_search_zone][map_search_count] = transp_zone
            map_search_zone = nil
            map_search_count = nil
            if feat == "transporter" then
                transp_search = transp_zone
            end
        elseif feat == "exit_" .. where_branch:lower() then
            transp_zone = 0
            transp_orient = false
        end
    end

    can_waypoint = is_waypointable(where)
    if can_waypoint then
        update_level_map(waypoint_parity)
    end

    if want_gameplan_update then
        check_expired_portals()
        if in_branch("Zig")
                and where_depth == gameplan_zig_depth(gameplan_status) then
            c_persist.zig_completed = true
        end

        update_gameplan()
        update_travel()

        check_future_branches()
        check_future_gods()

        want_gameplan_update = false
    end
    travel_fail_count = 0

    update_monster_array()
    danger = sense_danger(los_radius)
    immediate_danger = sense_immediate_danger()
    sense_sigmund()

    find_good_stairs()
    cloudy = not view.is_safe_square(0, 0) and view.cloud_at(0, 0) ~= nil
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
        elseif you.branch() == "Abyss" then
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
    for i = -los_radius, los_radius do
        for j = -los_radius, los_radius do
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
        return WIZMODE_DEATH
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

function record_portal(level, portal, permanent)
    if not c_persist.portals[level] then
        c_persist.portals[level] = {}
    end

    if not c_persist.portals[level][portal] then
        c_persist.portals[level][portal] = {}
    end

    -- This timed portal has already been recorded for this level.
    local len = #c_persist.portals[level][portal]
    if not permanent
            and len > 0
            and c_persist.portals[level][portal][len] ~= INF_TURNS then
        return
    end

    -- Permanent portals go at the beginning, so they'll always be chosen last.
    -- We can't have multiple timed portals of the same type on the same level,
    -- so this scheme puts portals in the correct order. For timed portals,
    -- record the turns to allow prioritizing among timed portals across
    -- levels.
    dsay("Found " .. portal .. ".", "explore")
    if permanent then
        table.insert(c_persist.portals[level][portal], 1, INF_TURNS)
    else
        table.insert(c_persist.portals[level][portal], you.turns())
    end

    if portal_allowed(portal) then
        want_gameplan_update = true
    end
end

function los_state(x, y)
    if you.see_cell_solid_see(x, y) then
        return FEAT_LOS.REACHABLE
    elseif you.see_cell_no_trans(x, y) then
        return FEAT_LOS.DIGGABLE
    end
    return FEAT_LOS.SEEN
end

-- A hook for incoming game messages. Note that this is executed for every new
-- message regardless of whether turn_update() this turn (e.g during
-- autoexplore or travel)). Hence this function shouldn't depend on any state
-- variables managed by turn_update(). Use the clua interfaces like you.where()
-- directly to get info about game status.
function c_message(text, channel)
    if text:find("Sigmund flickers and vanishes") then
        invis_sigmund = true
    elseif text:find("Your surroundings suddenly seem different") then
        invis_sigmund = false
    elseif text:find("Your pager goes off") then
        have_message = true
    elseif text:find("Done exploring") then
        c_persist.autoexplore[you.where()] = AUTOEXP.FULL
        want_gameplan_update = true
    elseif text:find("Partly explored") then
        if text:find("transporter") then
            c_persist.autoexplore[you.where()] = AUTOEXP.TRANSPORTER
        else
            c_persist.autoexplore[you.where()] = AUTOEXP.PARTIAL
        end
        want_gameplan_update = true
    elseif text:find("Could not explore") then
        c_persist.autoexplore[you.where()] = AUTOEXP.RUNED_DOOR
        want_gameplan_update = true
    -- Track which stairs we've fully explored by watching pairs of messages
    -- corresponding to standing on stairs and then taking them. The climbing
    -- message happens before the level transition.
    elseif text:find("You climb downwards")
            or text:find("You fly downwards")
            or text:find("You climb upwards")
            or text:find("You fly upwards") then
        stairs_travel = view.feature_at(0, 0)
    -- Record the staircase if we had just set stairs_travel.
    elseif text:find("There is a stone staircase") then
        if stairs_travel then
            local feat = view.feature_at(0, 0)
            local dir, num = stone_stair_type(feat)
            local travel_dir, travel_num = stone_stair_type(stairs_travel)
            -- Sanity check to make sure the stairs correspond.
            if travel_dir and dir and travel_dir == -dir
                    and travel_num == num then
                local branch, depth = parse_level_range(you.where())
                record_stairs(branch, depth, feat, FEAT_LOS.EXPLORED)
                record_stairs(branch, depth + dir, stairs_travel,
                    FEAT_LOS.EXPLORED)
            end
        end
        stairs_travel = nil
    elseif text:find("Orb of Zot") then
        c_persist.found_orb = true
        want_gameplan_update = true
    -- Timed portals are recorded by the "Hurry and find it" message handling,
    -- but a permanent bazaar doesn't have this. Check messages for "a gateway
    -- to a bazaar", which happens via autoexplore. Timed bazaars are described
    -- as "a flickering gateway to a bazaar", so by looking for the right
    -- message, we prevent counting timed bazaars twice.
    elseif text:find("Found a gateway to a bazaar") then
        record_portal(you.where(), "Bazaar", true)
    elseif text:find("Hurry and find it")
            or text:find("Find the entrance") then
        for portal, _ in pairs(portal_data) do
            if text:lower():find(portal_description(portal):lower()) then
                record_portal(you.where(), portal)
                break
            end
        end
    elseif text:find("The walls and floor vibrate strangely") then
        local where = you.where()
        -- If there was only one timed portal on the level, we can be sure it's
        -- the one that expired.
        if c_persist.portals[where] then
            local count = 0
            local expired_portal
            for portal, turns_list in pairs(c_persist.portals[where]) do
                for _, turns in ipairs(turns_list) do
                    if turns ~= INF_TURNS then
                        count = count + 1
                        if count > 1 then
                            expired_portal = nil
                            break
                        end

                        expired_portal = portal
                    end
                end
            end
            if expired_portal then
                remove_portal(where, expired_portal)
            end
        end
    elseif text:find("You enter the transporter") then
        transp_zone = transp_zone + 1
        transp_orient = true
    end
end
