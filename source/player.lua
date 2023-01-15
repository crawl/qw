-----------------------------------------
-- Player functions

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

    -- We assume TSO piety won't drop below 2* and that we won't change gods
    -- away from TSO.
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

function intrinsic_fumble()
    if intrinsic_amphibious() or intrinsic_flight() then
        return false
    end

    local sp = you.race()
    return not (sp == "Grey Draconian"
        or sp == "Palentonga"
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
    if sp == "Felid" or sp == "Troll" then
        return "Unarmed Combat"
    elseif sp == "Kobold" then
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

function meph_immune()
    -- should also check clarity and unbreathing
    return (you.res_poison() >= 1)
end

function miasma_immune()
    -- this isn't all the cases, I know
    return (you.race() == "Gargoyle" or you.race() == "Vine Stalker"
                    or you.race() == "Ghoul" or you.race() == "Mummy")
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
            or in_branch("Gauntlet"))
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

function dangerous_to_rest()
    if danger then
        return true
    end

    for pos in adjacent_iter(origin) do
        if view.feature_at(pos.x, pos.y) == "slimy_wall" then
            return true
        end
    end

    return false
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
            or you.race() == "Palentonga" then
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

function can_move()
    return not (you.transform() == "tree"
        or you.transform() == "fungus" and danger)
end

function player_can_melee_mons(mons)
    local range = reach_range()
    local dist = mons:distance()
    if you.caught() or you.confused() then
        return false
    elseif range == 2 then
        return dist <= range and view.can_reach(mons:x_pos(), mons:y_pos())
    else
        return dist <= range
    end

    return
end
