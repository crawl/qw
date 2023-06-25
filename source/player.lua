-----------------------------------------
-- Player functions

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
        and (SHIELD_CRAZY
            or sp == "Formicid"
            or sp == "Kobold"
            or skill == "Short Blades"
            or skill == "Unarmed Combat")
end

function want_shield()
    return want_buckler()
        and (SHIELD_CRAZY or you.race() == "Troll" or you.race() == "Formicid")
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
    return you.god() == "Trog"
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
        los_radius = 8
    elseif you.race() == "Kobold" then
        los_radius = 4
    else
        los_radius = 7
    end
end

function unable_to_move()
    return turn_memo("unable_to_move",
        function()
            local form = you.transform()
            return form == "tree" or form == "fungus" and danger
        end)
end

function dangerous_to_move()
    return turn_memo("dangerous_to_move",
        function()
            return you.confused()
                and (count_brothers_in_arms(1) > 0
                    or count_greater_servants(1) > 0
                    or count_divine_warriors(1) > 0
                    or count_beogh_allies(1) > 0)
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
    if you.caught() or you.confused() then
        return false
    end

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
                    and (count_brothers_in_arms(los_radius) > 0
                        or count_greater_servants(los_radius) > 0
                        or count_divine_warriors(los_radius) > 0
                        or count_beogh_allies(los_radius) > 0)
        end)
end

function dangerous_to_melee()
    return turn_memo("dangerous_to_melee",
        function()
            return dangerous_to_attack()
                -- Don't attempt melee with summoned allies adjacent.
                or you.confused()
                    and (count_brothers_in_arms(1) > 0
                        or count_greater_servants(1) > 0
                        or count_divine_warriors(1) > 0
                        or count_beogh_allies(1) > 0)
        end)
end

-- Currently we only use this to disallow attacking when in an exclusion.
function dangerous_to_attack()
    return not map_is_unexcluded_at(global_pos)
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

function get_dig_wand()
    return turn_memo("get_dig_wand",
        function()
            return find_item("wand", "digging")
        end)
end
