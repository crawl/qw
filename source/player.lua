-----------------------------------------
-- Player functions and data

const.duration = {
    -- Ignore this duration.
    "ignore",
    -- Ignore this duration if it's a buff.
    "ignore_buffs",
    -- We can get this duration, but it's not currently active.
    "usable",
    -- The duration is currently active.
    "active",
    -- We can get this duration or it's currently active.
    "available",
}

function initialize_player_durations()
    const.player_durations = {
        ["heroism"] = { status = "heroic", can_use_func = can_heroism },
        ["finesse"] = { status = "finesse-ful", can_use_func = can_finesse },
        ["berserk"] = { check_func = you.berserk, can_use_func = can_berserk },
        ["haste"] = { check_func = you.hasted, can_use_func = can_haste },
        ["slow"] = { check_func = you.slowed },
        ["might"] = { check_func = you.mighty, can_use_func = can_might },
        ["weak"] = { status = "weakened" },
    }
end

function can_use_buff(name)
    buff = const.player_durations[name]
    return buff and buff.can_use_func and buff.can_use_func()
end

function duration_active(name)
    duration = const.player_durations[name]
    if not duration then
        return false
    end

    if duration.status then
        return you.status(duration.status)
    else
        return duration.check_func()
    end
end

function have_duration(name, level)
    if level == const.duration.ignore
            or level == const.duration.ignore_buffs
                and const.player_durations[name].can_use_func then
        return false
    elseif level == const.duration.usable then
        return can_use_buff(name)
    elseif level == const.duration.active then
        return duration_active(name)
    else
        return can_use_buff(name) or duration_active(name)
    end
end

function intrinsic_rpois()
    local sp = you.race()
    return sp == "Gargoyle" or sp == "Naga" or sp == "Ghoul" or sp == "Mummy"
end

function intrinsic_relec()
    return sp == "Gargoyle"
end

function intrinsic_sinv()
    local sp = you.race()
    if sp == "Naga"
            or sp == "Felid"
            or sp == "Formicid"
            or sp == "Vampire" then
        return true
    end

    -- We assume that we won't change gods away from TSO.
    if you.god() == "the Shining One" and you.piety_rank() >= 2 then
        return true
    end

    return false
end

function intrinsic_flight()
    local sp = you.race()
    return (sp == "Gargoyle"
        or sp == "Black Draconian") and you.xl() >= 14
        or sp == "Tengu" and you.xl() >= 5
end

function intrinsic_amphibious()
    local sp = you.race()
    return sp == "Merfolk" or sp == "Octopode" or sp == "Barachi"
end

function intrinsic_fumble()
    if intrinsic_amphibious() or intrinsic_flight() then
        return false
    end

    local sp = you.race()
    return not (sp == "Grey Draconian"
        or sp == "Armataur"
        or sp == "Naga"
        or sp == "Troll"
        or sp == "Oni")
end

function intrinsic_evil()
    local sp = you.race()
    return sp == "Demonspawn"
        or sp == "Mummy"
        or sp == "Ghoul"
        or sp == "Vampire"
end

function intrinsic_undead()
    return you.race() == "Ghoul" or you.race() == "Mummy"
end

-- Returns the player's intrinsic level of an artprop string.
function intrinsic_property(prop)
    if prop == "rF" then
        return you.mutation("fire resistance")
    elseif prop == "rC" then
        return you.mutation("cold resistance")
    elseif prop == "rElec" then
        return you.mutation("electricity resistance")
    elseif prop == "rPois" then
        if intrinsic_rpois() or you.mutation("poison resistance") > 0 then
            return 1
        else
            return 0
        end
    elseif prop == "rN" then
        local val = you.mutation("negative energy resistance")
        if you.god() == "the Shining One" then
            val = val + math.floor(you.piety_rank() / 3)
        end
        return val
    elseif prop == "Will" then
        return you.mutation("strong-willed") + (you.god() == "Trog" and 1 or 0)
    elseif prop == "rCorr" then
        return 0
    elseif prop == "SInv" then
        if intrinsic_sinv() or you.mutation("see invisible") > 0 then
            return 1
        else
            return 0
        end
    elseif prop == "Fly" then
        return intrinsic_flight() and 1 or 0
    elseif prop == "Spirit" then
        return you.race() == "Vine Stalker" and 1 or 0
    end

    return 0
end

--[[
Returns the current level of player property by artprop string. If an item is
provided, assume the item is equipped and try to pretend that it is unequipped.
Does not include some temporary effects.
]]--
function player_property(prop, ignore_equip)
    local value
    local prop_is_stat = false
    if prop == "Str" then
        value = you.strength()
        prop_is_stat = true
    elseif prop == "Dex" then
        value = you.dexterity()
        prop_is_stat = true
    elseif prop == "Int" then
        value = you.intelligence()
        prop_is_stat = true
    else
        value = intrinsic_property(prop)
    end

    for slot, item in equipped_slots_iter() do
        local is_ignored = item_in_equip_set(item, ignore_equip)
        -- For stats, we must remove the value contributed by an ignored
        -- item.
        if is_ignored and prop_is_stat then
            value = value - item_property(prop, item)
        elseif not is_ignored and not prop_is_stat then
            value = value + item_property(prop, item)
        end
    end

    local max_level = const.property_max_levels[prop]
    if max_level and value > max_level then
        value = max_level
    end

    return value
end

function player_resist_percentage(resist, level)
    if level < 0 then
        return 1.5
    elseif level == 0 then
        return 1
    end

    if resist == "rF" or resist == "rC" then
        return level == 1 and 0.5 or (level == 2 and 1 / 3 or 0.2)
    elseif resist == "rElec" then
        return 2 / 3
    elseif resist == "rPois" then
        return 1 / 3
    elseif resist == "rCorr" then
        return 0.5
    elseif resist == "rN" then
        return level == 1 and 0.5 or (level == 2 and 0.25 or 0)
    end
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
    if sp == "Oni" or sp == "Troll" then
        return "large"
    elseif sp == "Deep Elf" or sp == "Kobold" or sp == "Merfolk" then
        return "dodgy"
    elseif weapon_skill() == "Ranged Weapons"
            or sp:find("Draconian")
            or sp == "Felid"
            or sp == "Octopode"
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
    return armour_plan() == "large" or sp == "Armataur" or sp == "Naga"
end

-- Used for backgrounds who don't get to choose a weapon.
function weapon_skill_choice()
    local sp = you.race()
    if sp == "Felid" or sp == "Troll" then
        return "Unarmed Combat"
    end

    local class = you.class()
    if class == "Hunter" or class == "Hexslinger" then
        return "Ranged Weapons"
    end

    if sp == "Kobold" then
        return "Maces & Flails"
    elseif sp == "Merfolk" then
        return "Polearms"
    elseif sp == "Spriggan" then
        return "Short Blades"
    else
        return "Axes"
    end
end

-- other player functions

function hp_is_low(percentage)
    local hp, mhp = you.hp()
    return 100 * hp <= percentage * mhp
end

function hp_is_full()
    local hp, mhp = you.hp()
    return hp == mhp
end

function meph_immune()
    -- should also check clarity and unbreathing
    return you.res_poison() >= 1
end

function miasma_immune()
    -- this isn't all the cases, I know
    return you.race() == "Gargoyle"
        or you.race() == "Vine Stalker"
        or you.race() == "Ghoul"
        or you.race() == "Mummy"
end

function in_bad_form(include_tree)
    local form = you.transform()
    return form == "bat"
        or form == "pig"
        or form == "wisp"
        or form == "fungus"
        or include_tree and form == "tree"
end

function transformed()
    return you.transform() ~= ""
end

function unable_to_wield_weapon()
    if you.berserk() or you.race() == "Felid" then
        return true
    end

    local form = you.transform()
    return not (form == ""
        or form == "tree"
        or form == "statue"
        or form == "maw"
        or form == "death")
end

function unable_to_swap_weapons()
    if unable_to_wield_weapon() then
        return true
    end

    -- XXX: If we haven't initialized this yet, assume it's unsafe for coglins
    -- to swap weapons.
    if qw.danger_in_los == nil then
        return you.race() == "Coglin"
    end

    return (qw.danger_in_los or not qw.position_is_safe)
        and you.race() == "Coglin"
end

function can_read()
    return not (you.berserk()
        or you.confused()
        or you.silenced()
        or you.status("engulfed (cannot breathe)")
        or you.status("unable to read"))
end

function can_drink()
    return not (you.berserk()
        or you.race() == "Mummy"
        or you.transform() == "lich"
        or you.status("unable to drink"))
end

function can_evoke()
    return not (you.berserk()
        or you.confused()
        or transformed()
        or you.mutation("inability to use devices") > 0)
end

function can_teleport()
    return can_read()
        and not (you.teleporting()
            or you.anchored()
            or you.transform() == "tree"
            or you.race() == "Formicid"
            or in_branch("Gauntlet"))
        and find_item("scroll", "teleportation")
end

function can_use_altars()
    return not (you.berserk()
        or you.silenced()
        or you.status("engulfed (cannot breathe)"))
end

function can_invoke()
    return not (you.berserk()
        or you.confused()
        or you.silenced()
        or you.under_penance(you.god())
        or you.status("engulfed (cannot breathe)"))
end

function can_berserk()
    return not using_ranged_weapon()
        and not intrinsic_undead()
        and you.race() ~= "Formicid"
        and not you.mesmerised()
        and not you.status("afraid")
        and not you.transform() == "lich"
        and not you.status("on berserk cooldown")
        and you.god() == "Trog"
        and you.piety_rank() >= 1
        and can_invoke()
end

function can_use_mp(mp)
    if you.race() == "Djinni" then
        return you.hp() > mp
    else
        return you.mp() >= mp
    end
end

function player_move_delay_func()
    local delay = 10

    local form = you.transform()
    if form == "tree" then
        return const.inf_turns
    elseif form == "bat" then
        delay = 6
    elseif form == "pig" then
        delay = 7
    elseif you.race() == "Spriggan" then
        delay = 6
    elseif you.race() == "Barachi" then
        delay = 12
    elseif you.race() == "Naga" then
        delay = 14
    end

    if you.god() == "Cheibriados" then
        delay = delay + 10
    end

    if form == "statue" then
        delay = 1.5 * delay
    end

    if you.hasted() or you.berserk() then
        delay = 2 / 3 * delay
    end

    if you.slowed() then
        delay = 1.5 * delay
    end

    if view.feature_at(0, 0) == "shallow_water"
            and not (you.flying()
                or you.god() == "Beogh"
                    and you.piety_rank() >= 5)
            and not intrinsic_amphibious() then
        delay = 8 / 5 * delay
    end

    return delay
end

function player_move_delay()
    return turn_memo("player_move_delay", player_move_delay_func)
end

function base_mutation(str)
    return you.mutation(str) - you.temp_mutation(str)
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

function body_size()
    if you.race() == "Kobold" then
        return -1
    elseif you.race() == "Spriggan" or you.race() == "Felid" then
        return -2
    elseif you.race() == "Troll"
            or you.race() == "Oni"
            or you.race() == "Naga"
            or you.race() == "Armataur" then
        return 1
    else
        return 0
    end
end

function calc_los_radius()
    if you.race() == "Barachi" then
        qw.los_radius = 8
    elseif you.race() == "Kobold" then
        qw.los_radius = 4
    else
        qw.los_radius = 7
    end
end

function unable_to_move()
    return turn_memo("unable_to_move",
        function()
            local form = you.transform()
            return form == "tree" or form == "fungus" and qw.danger_in_los
        end)
end

function dangerous_to_move(allow_spiked)
    return turn_memo_args("dangerous_to_move",
        function()
            return not allow_spiked and you.status("spiked")
                or you.confused()
                    and (check_brothers_in_arms(1)
                        or check_greater_servants(1)
                        or check_divine_warriors(1)
                        or check_beogh_allies(1))
        end, allow_spiked)
end

function unable_to_melee()
    return turn_memo("unable_to_melee",
        function()
            return you.caught()
        end)
end

function unable_to_shoot()
    return turn_memo("unable_to_shoot",
        function()
            if you.berserk() or you.caught() then
                return true
            end

            local form = you.transform()
            return not (form == ""
                or form == "tree"
                or form == "statue"
                or form == "lich")
        end)
end

function unable_to_throw()
    if you.berserk() or you.confused() or you.caught() then
        return true
    end

    local form = you.transform()
    return not (form == ""
        or form == "tree"
        or form == "statue"
        or form == "lich")
end

function player_can_melee_mons(mons)
    if mons:name() == "orb of destruction"
            or mons:attacking_causes_penance()
            or unable_to_melee() then
        return false
    end

    local range = player_reach_range()
    local dist = mons:distance()
    if range == 2 then
        return dist <= range and view.can_reach(mons:x_pos(), mons:y_pos())
    else
        return dist <= range
    end
end

function dangerous_to_shoot()
    return turn_memo("dangerous_to_shoot",
        function()
            return dangerous_to_attack()
                -- Don't attempt to shoot with summoned allies adjacent.
                or you.confused()
                    and (check_brothers_in_arms(qw.los_radius)
                        or check_greater_servants(qw.los_radius)
                        or check_divine_warriors(qw.los_radius)
                        or check_beogh_allies(qw.los_radius))
        end)
end

function dangerous_to_melee()
    return turn_memo("dangerous_to_melee",
        function()
            return dangerous_to_attack()
                -- Don't attempt melee with summoned allies adjacent.
                or you.confused()
                    and (check_brothers_in_arms(1)
                        or check_greater_servants(1)
                        or check_divine_warriors(1)
                        or check_beogh_allies(1))
        end)
end

-- Currently we only use this to disallow attacking when in an exclusion.
function dangerous_to_attack()
    return not map_is_unexcluded_at(qw.map_pos)
end

function want_to_be_surrounded()
    return turn_memo("want_to_be_surrounded",
        function()
            local have_vamp_cleave = false
            for weapon in equipped_slot_iter("weapon") do
                if weapon.weap_skill == "Axes"
                        and weapon:ego() == "vampirism" then
                    have_vamp_cleave = true
                    break
                end
            end
            if not have_vamp_cleave then
                return false
            end

            local vamp_check = function(mons)
                    return not mons:is_immune_vampirism()
                end
            return count_enemies(qw.los_radius, vamp_check) >= 4
        end)
end

function max_strength()
    return select(2, you.strength())
end

function max_dexterity()
    return select(2, you.dexterity())
end
