-----------------------------------------
-- Player functions and data

const.duration = {
    -- Ignore this duration.
    "ignore",
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
    if level == const.duration.ignore then
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
        or sp == "Ogre")
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
function intrinsic_property(str)
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


--[[
Returns the current level of player property by artprop string. If an item is
provided, assume the item is equipped and try to pretend that it is unequipped.
Does not include some temporary effects.
]]--
function player_property(str, it)
    local it_res = it and it.equipped and item_property(str, it) or 0
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

    local other_res = intrinsic_property(str)
    for it2 in inventory() do
        if it2.equipped and (not it or it2.slot ~= it.slot) then
            other_res = other_res + item_property(str, it2)
        end
    end

    if str == "rF" or str == "rC" or str == "rN" or str == "Will" then
        return other_res
    else
        return other_res > 0 and 1 or 0
    end
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
    if sp == "Ogre" or sp == "Troll" then
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

function want_buckler()
    local sp = you.race()
    local skill = weapon_skill()
    return sp ~= "Felid"
        and (skill ~= "Ranged Weapons" or sp == "Formicid")
        and (qw.shield_crazy
            or sp == "Formicid"
            or sp == "Kobold"
            or skill == "Short Blades"
            or skill == "Unarmed Combat")
end

function want_shield()
    return want_buckler()
        and (qw.shield_crazy or you.race() == "Troll" or you.race() == "Formicid")
end

-- used for backgrounds who don't get to choose a weapon
function weapon_choice()
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

function weapon_skill()
    -- Cache in case we unwield a weapon somehow.
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

function can_zap()
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
    return not have_ranged_weapon()
        and you.god() == "Trog"
        and you.piety_rank() >= 1
        and you.race() ~= "Mummy"
        and you.race() ~= "Ghoul"
        and you.race() ~= "Formicid"
        and not (you.status("on berserk cooldown")
            or you.mesmerised()
            or you.transform() == "lich"
            or you.status("afraid"))
        and can_invoke()
end

function can_use_mp(mp)
    if you.race() == "Djinni" then
        return you.hp() > mp
    else
        return you.mp() >= mp
    end
end

function player_speed()
    local num = 3
    local form = you.transform()
    if you.god() == "Cheibriados" then
        num = 1
    elseif form ~= "" then
        if form == "bat" or form == "pig" then
            num = 4
        elseif form == "statue" then
            num = 2
        end
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
            or you.race() == "Ogre"
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
    local range = reach_range()
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

function have_ranged_target()
    return turn_memo("have_ranged_target",
        function()
            if have_ranged_weapon() then
                return get_launcher_target()
            else
                return get_throwing_target()
            end
        end)
end

function want_to_be_surrounded()
    return turn_memo("want_to_be_surrounded",
        function()
            local weapon = get_weapon()
            if not weapon
                    or weapon.weap_skill ~= "Axes"
                    or weapon:ego() ~= "vampirism" then
                return false
            end

            local vamp_check = function(mons)
                    return not mons:is_immune_vampirism()
                end
            return count_enemies(qw.los_radius, vamp_check) >= 4
        end)
end
