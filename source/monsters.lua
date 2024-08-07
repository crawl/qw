-----------------------------------------
-- monster functions and data

const.pan_lord_type = 344

const.attitude = {
    "hostile",
    "neutral",
    "strict_neutral",
    "peaceful",
    "friendly"
}

const.moderate_threat = 5
const.high_threat = 10
const.extreme_threat = 20

function moderate_threat_level()
    return const.moderate_threat - max(0, min(3, 10 - you.xl()))
end

function high_threat_level()
    return const.high_threat - max(0, min(5, 2 * (10 - you.xl())))
end

function extreme_threat_level()
    return const.extreme_threat - max(0, min(10, 2 * (10 - you.xl())))
end

-- functions for use in the monster lists below
function in_desc(lev, str)
    return function (mons)
        return you.xl() < lev and mons:desc():find(str)
    end
end

function pan_lord(lev)
    return function (mons)
        return you.xl() < lev and mons:type() == const.pan_lord_type
    end
end

local player_resist_funcs = {
    rF=you.res_fire,
    rC=you.res_cold,
    rPois=you.res_poison,
    rElec=you.res_shock,
    rN=you.res_draining,
    -- returns a boolean
    rCorr=function() return you.res_corr() and 1 or 0 end,
    Will=you.willpower,
}

function check_resist(lev, resist, value)
    return function (enemy)
        return you.xl() < lev and player_resist_funcs[resist]() < value
    end
end

function slow_berserk(lev)
    return function (enemy)
        return you.xl() < lev and count_enemies(1) > 0
    end
end

function hydra_weapon_value(weap)
    if not weap then
        return 0
    end

    local sk = weap.weap_skill
    if sk == "Ranged Weapons"
            or sk == "Maces & Flails"
            or sk == "Short Blades"
            or sk == "Polearms" and weap.hands == 1 then
        return 0
    elseif weap.ego() == "flaming" then
        return 2
    else
        return -2
    end
end

function hydra_melee_value()
    local total_value = 0
    for weapon in equipped_slot_iter("weapon") do
        total_value = total_value + hydra_weapon_value(weapon)
    end
    return total_value
end

function hydra_is_scary(mons)
    if hydra_melee_value() > 0 then
        return false
    end

    if unable_to_swap_weapons() then
        return true
    end

    local best_weapon = best_hydra_swap_weapon()
    return hydra_weapon_value(best_weapon) <= 0
end

-- The format in monster lists below is that a num is equivalent to checking
-- XL < num, otherwise we want a function. ["*"] should be a table of
-- functions to check for every monster.
local scary_monsters = {
    ["ice beast"] = { xl = 7, resists = { rC = 0.75 } },

    ["fire crab"] = { xl = 14, resists = { rF = 0.65} },
    ["wolf spider"] = { xl = 14 },
    ["ice statue"] = { xl = 14, resists = { rC = 1 } },

    ["white ugly thing"] = { xl = 15, resists = { rC = 0.75 } },
    ["freezing wraith"] = { xl = 15, resists = { rC = 0.75 } },
    ["skeletal warrior"] = { xl = 15 },
    ["fire dragon"] = { xl = 15, resists = {rF = 0.5 } },
    ["ice dragon"] = { xl = 15, resists = {rC = 0.5 } },

    ["hydra"] = { xl = 17, check = hydra_is_scary },
    ["entropy weaver"] = { xl = 17, resists = { rCorr = 0.75 } },
    ["shock serpent"] = { xl = 17, resists = { rElec = 0.75 } },
    ["spark wasp"] = { xl = 17, resists = { rElec = 0.75 } },
    ["sun demon"] = { xl = 17, resists = { rF = 0.75 } },
    ["white very ugly thing"] = { xl = 17, resists = { rC = 0.75 } },
    ["Lodul"] = { xl = 17, resists = { rElec = 0.75 } },

    ["ironbound frostheart"] = { xl = 20, resists = { rC = 0.75 } },
    ["ironbound thunderhulk"] = { xl = 20, resists = { rElec = 0.75 } },

    ["azure jelly"] = { xl = 24, resists = { rC = 0.75 } },
    ["enormous slime creature"] = { xl = 24 },
    ["fire giant"] = { xl = 24, resists = { rF = 0.75 } },
    ["frost giant"] = { xl = 24, resists = { rC = 0.75 } },
    ["hell hog"] = { xl = 24, resists = { rF = 0.75 } },
    ["orange crystal statue"] = { xl = 24 },
    ["shadow dragon"] = { xl = 24, resists = { rN = 0.75 } },
    ["spriggan air mage"] = { xl = 24, resists = { rElec = 0.75 } },
    ["storm dragon"] = { xl = 24, resists = { rElec = 0.75 } },
    ["titan"] = { xl = 24, resists = { rElec = 0.5 } },
    ["Margery"] = { xl = 24, resists = { rF = 0.75 } },
    ["Xtahua"] = { xl = 24, resists = { rF = 0.75 } },

    ["daeva"] = { xl = 30 },
    ["hellion"] = { xl = 30 },
    ["titanic slime creature"] = { xl = 30 },
    ["doom hound"] = { xl = 30,
        check = function(mons) return mons:is("ready_to_howl") end },
    ["electric golem"] = { xl = 30, resists = { rElec = 1 } },
    ["orb of fire"] = { xl = 30, resists = { rF = 1 } },
    ["pandemonium lord"] = { xl = 30 },
    ["player ghost"] = { xl = 30 },

    ["Antaeus"] = { xl = 34 },
    ["Asmodeus"] = { xl = 34 },
    ["Lom Lobon"] = { xl = 34 },
    ["Cerebov"] = { xl = 34 },
}

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
}

-- Potion of resistance these.
local fire_resistance_monsters = {
    ["*"] = {},

    ["fire crab"] = check_resist(14, "rF", 1),

    ["hellephant"] = check_resist(100, "rF", 2),
    ["orb of fire"] = 100,

    ["Asmodeus"] = check_resist(100, "rF", 2),
    ["Cerebov"] = 100,
    ["Margery"] = check_resist(100, "rF", 2),
    ["Xtahua"] = check_resist(100, "rF", 2),
    ["Vv"] = check_resist(100, "rF", 2),
}

local cold_resistance_monsters = {
    ["*"] = {},

    ["ice beast"] = check_resist(5, "rC", 1),

    ["white ugly thing"] = check_resist(13, "rC", 1),
    ["freezing wraith"] = check_resist(13, "rC", 1),

    ["Ice Fiend"] = 100,
    ["Vv"] = 100,
}

local elec_resistance_monsters = {
    ["*"] = {
        in_desc(20, "black draconian"),
    },
    ["ironbound thunderhulk"] = 20,
    ["storm dragon"] = 20,
    ["electric golem"] = 100,
    ["spark wasp"] = 100,
    ["Antaeus"] = 100,
}

local pois_resistance_monsters = {
    ["*"] = {},
    ["swamp drake"] = 100,
}

local acid_resistance_monsters = {
    ["*"] = {},
    ["acid blob"] = 100,
}

function update_invis_monsters(closest_invis_pos)
    if you.see_invisible() then
        invis_monster = false
        invis_monster_turns = 0
        invis_monster_pos = nil
        nasty_invis_caster = false
        return
    end

    -- A visible nasty monster that can go invisible and whose position we
    -- prioritize tracking over any currently invisible monster.
    if you.xl() < 10 then
        for _, enemy in ipairs(qw.enemy_list) do
            if enemy:name() == "Sigmund" then
                invis_monster = false
                nasty_invis_caster = true
                invis_monster_turns = 0
                invis_monster_pos = enemy:pos()
                return
            end
        end
    end

    if closest_invis_pos then
        invis_monster = true
        if not invis_monster_turns then
            invis_monster_turns = 0
        end
        invis_monster_pos = closest_invis_pos
    end

    if not qw.position_is_safe or options.autopick_on then
        invis_monster = false
        nasty_invis_caster = false
    end

    if invis_monster and invis_monster_turns > 100 then
        say("Invisibility monster not found???")
        invis_monster = false
    end

    if not invis_monster then
        if not options.autopick_on then
            magic(control('a'))
            qw.do_dummy_action = false
            coroutine.yield()
        end

        invis_monster_turns = 0
        invis_monster_pos = nil
        return
    end

    invis_monster_turns = invis_monster_turns + 1
end

-- This returns a value for monster movement energy that's on the aut scale,
-- so that reasoning about the difference between player and monster move
-- delay is easier.
function monster_move_delay(mons)
    local desc = mons.minfo:speed_description()
    local delay = 10
    if desc:find("travel:") then
        -- We only want to pass the first return value of gsub() to
        -- tonumber().
        delay = desc:gsub(".*travel: (%d+)%%.*", "%1")
        -- We're converting a percentage that's based on monsters delay/energy
        -- to aut, since this is easier to compare to player actions.
        delay = 10 * 100 / tonumber(delay)
    elseif desc:find("Speed:") then
        delay = desc:gsub(".*Speed: (%d+)%%.*", "%1")
        delay = 10 * 100 / tonumber(delay)
    end

    -- Assume these move at their roll delay so we won't try to kite.
    if mons:name():find("boulder beetle") then
        delay = delay - 5
    end

    local feat = view.feature_at(mons:x_pos(), mons:y_pos())
    if (feat == "shallow_water" or feat == "deep_water" or feat == "lava")
            and not mons:is("airborne") then
        if desc:find("swim:") then
            delay = desc:gsub(".*swim: (%d+)%%.*", "%1")
            delay = 10 * 100 / tonumber(delay)
        else
            delay = 1.6 * delay
        end
    end

    if mons:is("hasted") or mons:is("berserk") then
        delay = 2 / 3 * delay
    end

    if mons:is("slowed") then
        delay = 1.5 * delay
    end

    return delay
end

function initialize_monster_map()
    qw.monster_map = {}
    for x = -qw.los_radius, qw.los_radius do
        qw.monster_map[x] = {}
    end
end

function update_monsters()
    qw.enemy_list = {}
    qw.slow_aura = false
    qw.all_enemies_safe = true

    local closest_invis_pos
    local sinv = you.see_invisible()

    for pos in radius_iter(const.origin) do
        if you.see_cell_no_trans(pos.x, pos.y) then
            local mon_info = monster.get_monster_at(pos.x, pos.y)
            if mon_info then
                local mons = Monster:new(mon_info)
                qw.monster_map[pos.x][pos.y] = mons
                if mons:is_enemy() then
                    if not mons:is_safe() then
                        qw.all_enemies_safe = false
                    end

                    if mons:name() == "torpor snail" then
                        qw.slow_aura = true
                    end

                    table.insert(qw.enemy_list, mons)
                end
            else
                qw.monster_map[pos.x][pos.y] = nil
            end

            if not sinv
                    and not closest_invis_pos
                    and view.invisible_monster(pos.x, pos.y)
                    and you.see_cell_solid_see(pos.x, pos.y) then
                closest_invis_pos = pos
            end
        else
            qw.monster_map[pos.x][pos.y] = nil
        end
    end

    update_invis_monsters(closest_invis_pos)
end

function get_monster_at(pos)
    if supdist(pos) <= qw.los_radius then
        return qw.monster_map[pos.x][pos.y]
    end
end

function get_closest_enemy()
    if #qw.enemy_list > 0 then
        return qw.enemy_list[1]
    end
end

function monster_in_list(mons, mons_list)
    local entry = mons_list[mons:name()]
    if type(entry) == "number" and you.xl() < entry then
        return true
    elseif type(entry) == "function" and entry(mons) then
        return true
    end

    for _, entry in ipairs(mons_list["*"]) do
        if entry(mons) then
            return true
        end
    end

    return false
end

function assess_enemies_func(duration_level, radius, filter)
    if not radius then
        radius = qw.los_radius
    end

    local result = { count = 0, threat = 0, ranged_threat = 0, move_delay = 0 }
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:distance() > radius then
            break
        end

        local ranged = enemy:is_ranged(true)
        if (not filter or filter(enemy))
                and (ranged or enemy:has_path_to_melee_player()) then
            local threat = enemy:threat(duration_level)
            result.threat = result.threat + threat
            if ranged then
                result.ranged_threat = result.ranged_threat + threat
            end

            if not result.scary_enemy and threat >= 3 then
                result.scary_enemy = enemy
            end

            result.move_delay = result.move_delay + enemy:move_delay() * threat
            result.count = result.count + 1
        end
    end
    result.move_delay = result.move_delay / result.threat

    return result
end

function assess_enemies(duration_level, radius, filter)
    return turn_memo_args("assess_enemies",
        function()
            return assess_enemies_func(duration_level, radius, filter)
        end, duration_level, radius, filter)
end

function have_moderate_threat(duration_level)
    local enemies = assess_enemies(duration_level)
    return enemies.threat >= moderate_threat_level()
end

function have_high_threat(duration_level)
    local enemies = assess_enemies(duration_level)
    return enemies.threat >= high_threat_level()
end

function have_extreme_threat(duration_level)
    local enemies = assess_enemies(duration_level)
    return enemies.threat >= extreme_threat_level()
end

function get_scary_enemy(duration_level)
    local enemies = assess_enemies(duration_level)
    return enemies.scary_enemy
end

function mons_res_holy_check(mons)
    return mons:res_holy() <= 0
end

function mons_tso_heal_check(mons)
    return mons:res_holy() <= 0 and not mons:is_summoned()
end

function assess_hell_enemies(radius)
    if not in_hell_branch() then
        return { threat = 0, ranged_threat, count = 0 }
    end

    -- We're most concerned with hell monsters that aren't vulnerable to any
    -- holy wrath we might have (either from TSO Cleansing Flame or the weapon
    -- brand).
    local have_holy_wrath = you.god() == "the Shining One"
    for weapon in equipped_slot_iter("weapon") do
        if weapon.ego() == "holy wrath" then
            have_holy_wrath = true
        end
    end

    local filter = function(mons)
        return not have_holy_wrath or mons:res_holy() > 0
    end
    return assess_enemies(radius, const.duration.active, filter)
end

function check_enemies_func(radius, filter)
    local i = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:distance() <= radius and (not filter or filter(enemy)) then
            return true
        end
    end

    return false
end

function check_enemies(radius, filter)
    return turn_memo_args("check_enemies",
        function()
            return check_enemies_func(radius, filter)
        end, radius, filter)
end

function check_enemies_in_list(radius, mons_list)
    local filter = function(enemy)
        return monster_in_list(enemy, mons_list)
    end
    return check_enemies(radius, filter)
end

function check_immediate_danger()
    local filter = function(enemy)
        local dist = enemy:distance()
        if dist <= 2 then
            return true
        elseif dist == 3 and enemy:reach_range() >= 2 then
            return true
        elseif enemy:is_ranged(true) then
            return true
        end

        return false
    end
    return check_enemies(qw.los_radius, filter)
end

function count_enemies_func(radius, filter)
    local i = 0
    for _, enemy in ipairs(qw.enemy_list) do
        if enemy:distance() <= radius and (not filter or filter(enemy)) then
            i = i + 1
        end
    end
    return i
end

function count_enemies(radius, filter)
    return turn_memo_args("count_enemies",
        function()
            return count_enemies_func(radius, filter)
        end, radius, filter)
end

function count_enemies_by_name(radius, name)
    return count_enemies(radius,
        function(enemy) return enemy:name() == name end)
end

function count_hostile_summons(radius)
    if you.god() ~= "Makhleb" then
        return 0
    end

    return count_enemies(radius,
        function(enemy) return enemy:is_summoned()
            and monster_is_greater_servant(enemy) end)
end

function count_pan_lords(radius)
    return count_enemies(radius,
        function(mons) return mons:type() == const.pan_lord_type end)
end

function should_dig_unreachable_monster(mons)
    if not find_item("wand", "digging") then
        return false
    end

    local grate_mon_list
    if in_branch("Zot") or in_branch("Depths") and at_branch_end() then
        grate_mon_list = {"draconian stormcaller", "draconian scorcher"}
    elseif in_branch("Pan") then
        grate_mon_list = {"smoke demon", "ghost moth"}
    elseif at_branch_end("Geh") then
        grate_mon_list = {"smoke demon"}
    elseif in_branch("Zig") then
        grate_mon_list = {""}
    else
        return false
    end

    return contains_string_in(mons:name(), grate_mon_list)
        and can_dig_to(mons:pos())
end

function monster_short_name(mons)
    local desc = mons:desc()
    if desc:find("hydra") then
        local undead = { "skeleton", "zombie", "simulacrum", "spectral" }
        for _, name in ipairs(undead) do
            if desc:find(name) then
                if name == "spectral" then
                    return "spectral hydra"
                else
                    return "hydra " .. name
                end
            end
        end

        return "hydra"
    end

    if mons:desc():find("'s? ghost") then
        return "player ghost"
    end

    if mons:desc():find("'s? illusion") then
        return "player illusion"
    end

    if mons:type() == const.pan_lord_type then
        return "pandemonium lord"
    end

    return mons:name()
end

function monster_percent_unresisted(resist, level, ego)
    if level < 0 then
        return 1.5
    elseif level == 0 then
        return 1
    end

    if resist == "rF" or resist == "rC" or resist == "rN" or resist == "rCorr" then
        if ego then
            return level > 0 and 0 or 1
        end

        return level == 1 and 0.5 or (level == 2 and 0.2 or 0)
    elseif resist == "rElec" or resist == "rPois" then
        if ego then
            return level > 0 and 0 or 1
        end

        return level == 1 and 0.5 or (level == 2 and 0.25 or 0)
    else
        return 1
    end
end

const.monster_resist_props = {
    ["rF"] = "res_fire",
    ["rC"] = "res_cold",
    ["rElec"] = "res_shock",
    ["rPois"] = "res_poison",
    ["rN"] = "res_draining",
    ["rCorr"] = "res_corr",
    ["rHoly"] = "res_holy",
}

function monster_threat(mons, duration_level)
    if not duration_level then
        duration_level = const.duration.active
    end

    local threat = mons.minfo:threat()
    local entry = scary_monsters[mons:short_name()]
    local player_xl = you.xl()
    if entry and player_xl < entry.xl
            and (not entry.check or entry.check(mons)) then
        threat = threat + entry.xl - player_xl

        local resist_factor = 1
        if entry.resists then
            for resist, factor in pairs(entry.resists) do
                local perc = player_resist_percentage(resist,
                    player_property(resist))
                resist_factor = resist_factor + factor * (perc - 1)
            end
        end
        threat = threat * resist_factor
    end

    if duration_level >= const.duration.active then
        local mons_berserk = mons:is("berserk")
        threat = threat
            -- (3/2)^3 for +50% speed & +50% damage & +50% HP.
            * (mons_berserk and 3.375 or 1)
            * (not mons_berserk and mons:is("strong") and 1.5 or 1)
            * (not mons_berserk and mons:is("hasted") and 1.5 or 1)
            * (mons:is("slowed") and 2 / 3 or 1)
    end

    local attack = get_attack(1)
    -- An optimization: we can avoid weapon delay calculations and use simple
    -- multipliers if we're not incorporating heroism.
    if have_duration("heroism", duration_level) then
        threat = threat * player_attack_delay(1, duration_level)
            / player_attack_delay(1, const.duration.ignore)
    else
        if have_duration("slow", duration_level) then
            threat = threat * 1.5
        end

        if have_duration("finesse", duration_level) then
            threat = threat / 2
        elseif attack.uses_berserk
                and have_duration("berserk", duration_level) then
            threat = 2 * threat / 3
        elseif have_duration("haste", duration_level) then
            threat = 2 * threat / 3
        end
    end

    -- Another optimization: don't bother with this set of damage calculations
    -- if the durations don't apply.
    if get_attack(1).uses_might
            and (have_duration("berserk", duration_level)
                or have_duration("might", duration_level)
                or have_duration("weak", duration_level)) then
        threat = threat * player_attack_damage(mons, 1, const.duration.ignore)
            / player_attack_damage(mons, 1, duration_level)
    end

    return threat
end
