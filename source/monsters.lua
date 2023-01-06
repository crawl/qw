-----------------------------------------
-- monster functions and data

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
}

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
}

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
}

-- BiA these even at low piety.
local brothers_in_arms_necessary_monsters = {
    ["*"] = {
        hydra_check_flaming(15),
        in_desc(100, "statue"),
    },

    ["orb spider"] = 20,
}

-- Use haste/might on these few.
local ridiculous_uniques = {
    ["*"] = {},
    ["Antaeus"] = 100,
    ["Asmodeus"] = 100,
    ["Lom Lobon"] = 100,
    ["Cerebov"] = 100,
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

    ["Margery"] = check_resist(100, "rF", 2),
    ["orb of fire"] = 100,
    ["hellephant"] = check_resist(100, "rF", 2),
    ["Xtahua"] = check_resist(100, "rF", 2),
    ["Cerebov"] = 100,
    ["Asmodeus"] = check_resist(100, "rF", 2),
    ["Vv"] = 100,
}

local cold_resistance_monsters = {
    ["*"] = {},
    ["Ice Fiend"] = 100,
    ["Antaeus"] = 100,
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

function mon_speed_num(mons)
    local sdesc = mons:speed_description()
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
    if mons:status("fast") then
        num = num + 1
    end
    if mons:status("slow") then
        num = num - 1
    end
    if mons:name():find("boulder beetle") then
        num = num + 3
    end
    if mons:name():find("spriggan") or mons:name() == "the Enchantress" then
        num = num + 1
    elseif mons:name():find("naga") or mons:name() == "Vashnia" then
        num = num - 1
    end
    return num
end

function is_fast(mons)
    return (mon_speed_num(mons) > player_speed_num())
end

function is_ranged(mons)
    local name = mons:name()
    if name:find("kraken") then
        return false
    end
    if mons:has_known_ranged_attack() then
        return true
    end
    if name == "Maurice" or name == "Ijyb" or name == "crimson imp"
         or name == "lost soul" then
        return true
    end
    return false
end

function sense_immediate_danger()
    for _, enemy in ipairs(enemy_list) do
        local dist = supdist(enemy.pos.x, enemy.pos.y)
        if dist <= 2 then
            return true
        elseif dist == 3 and enemy.mons:reach_range() >= 2 then
            return true
        elseif is_ranged(enemy.mons) then
            return true
        end
    end

    return false
end

function sense_danger(r, moveable)
    for _, e in ipairs(enemy_list) do
        if (moveable and you.see_cell_solid_see(e.pos.x, e.pos.y) or not moveable)
                and supdist(e.pos.x, e.pos.y) <= r then
            return true
        end
    end

    return false
end

function sense_sigmund()
    for _, enemy in ipairs(enemy_list) do
        if enemy.mons:name() == "Sigmund" then
            sigmund_dx = enemy.pos.x
            sigmund_dy = enemy.pos.y
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
    for x, y in radius_iter(0, 0) do
        if you.see_cell_no_trans(x, y) then
            monster_array[x][y] = monster.get_monster_at(x, y)
            if is_enemy_at(x, y) then
                table.insert(enemy_list,
                    { pos = { x = x, y = y }, mons = monster_array[x][y] })
            end
        else
            monster_array[x][y] = nil
        end
    end
end

function get_monster_distance_map(mons)
    local dist_map = get_distance_map(mons_pos, los_radius)
    local wx, wy = travel.waypoint_delta(waypoint_parity)
    local mons_pos = { x = mons:x_pos() - wx, y = mons:y_pos() - wy }
    update_distance_map(dist_map, { pos }, traversal_func)
end

function can_path_monster(mons)
    local dist_map = mons_distance_maps[waypoint_parity]
    for x, y in adjacent_iter(mons:x_pos(), mons:y_pos()) do
        if dist_map[x][y] then
            return true
        end
    end
end

function enemy_can_move_melee(enemy)
    if enemy.can_move_melee ~= nil then
        return enemy.can_move_melee
    end

    if enemy.mons:name() == "wandering mushroom"
            or e.mons:name():find("vortex")
            or e.mons:desc():find("fleeing")
            or e.mons:status("paralysed")
            or e.mons:status("confused")
            or e.mons:status("petrified") then
        enemy.can_move_melee = false
        return false
    end

    local tab_func = function(x, y)
        return enemy.mons:can_traverse(x, y)
    end
    local melee_range = enemy.mons:reach_range()
    enemy.can_move_melee = will_tab(enemy.pos.x, enemy.pos.y, 0, 0, tab_func,
            melee_range)
        -- If the monster can reach attack and we can't, be sure we can
        -- close the final 1-square gap.
        and (melee_range < 2
            or attack_range() > 1
            or can_move_closer(enemy.pos.x, enemy.pos.y))
    return enemy.can_move_melee
end

function update_melee_enemy()
    if melee_enemy then
        local name = melee_enemy.mons:name()
        for _, enemy in ipairs(enemy_list) do
            if enemy.mons:name() == name
                    and enemy_can_move_melee(enemy) then
                return
            end
        end
    end

    melee_enemy = nil
    for _, enemy in ipairs(enemy_list) do
        if enemy_can_move_melee(enemy) then
            melee_enemy = enemy
            break
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
    for _, enemy in ipairs(enemy_list) do
        if you.see_cell_no_trans(enemy.pos.x, enemy.pos.y)
                and supdist(enemy.pos.x, enemy.pos.y) <= r
                and (not filter or filter(enemy.mons))
                and mons_in_list(enemy.mons, mlist) then
            return true
        end
    end

    return false
end

function count_monsters_near(cx, cy, r, filter)
    local i = 0
    for _, e in ipairs(enemy_list) do
        if supdist(cx - e.pos.x, cy - e.pos.y) <= r
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

function count_hostile_greater_servants(r)
    if you.god() ~= "Makhleb" then
        return 0
    end

    return count_monsters(r,
        function(m) return m:is("summoned") and mons_is_greater_servant(m) end)
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
            and (m:is_constricted()
                or m:is_caught()
                or m:status("petrified")
                or m:status("paralysed")
                or m:status("constricted by roots")
                or m:desc():find("sleeping")
                or feature_is_deep_water_or_lava(feat)
                or feat  == "trap_zot"))
end

function tabbable_square(x, y)
    if view.feature_at(x, y) ~= "unseen" and view.is_safe_square(x, y) then
        if not monster_array[x][y]
                or not monster_array[x][y]:is_firewood() then
            return true
        end
    end
    return false
end

function get_monster_info(dx, dy)
    local mons = monster_array[dx][dy]
    if not mons then
        return nil
    end

    local name = mons:name()
    local info = {}
    info.distance = -supdist(dx, dy)

    local range = reach_range()
    if you.caught() or you.confused() then
        info.attack_range = 0
    elseif range > 1 then
        info.attack_range = view.can_reach(dx, dy) and range or 0
    else
        info.attack_range = -info.distance < 2 and 1 or 0
    end
    info.can_attack = info.attack_range > 0 and 1 or 0

    info.safe = mons:is_safe() and -1 or 0
    info.constricting_you = mons:is_constricting_you() and 1 or 0
    info.very_stabbable = mons:stabbability() >= 1 and 1 or 0
    info.injury = mons:damage_level()
    info.threat = mons:threat()
    info.orc_priest_wizard =
        (name == "orc priest" or name == "orc wizard") and 1 or 0
    return info
end

function compare_monster_info(m1, m2, flag_order, flag_reversed)
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
        if m1[flag] > m2[flag] then
            return if_greater_val
        elseif m1[flag] < m2[flag] then
            return not if_greater_val
        end
    end
    return false
end

function has_dangerous_monster(x, y)
    return not monster_is_safe(monster.get_monster_at(x, y))
end

function monster_is_safe(mons)
    return not mons
        or mons:attitude() > enum_att_neutral
        or mons:is_firewood()
        or mons:name() == "butterfly"
        or mons:name() == "orb of destruction"
end

function is_enemy_at(x, y)
    if supdist(x, y) > los_radius then
        return false
    end

    if monster_is_safe(monster_array[x][y]) then
        return false
    end

    return true
end

function can_melee_enemy(enemy, handle_ignore)
    if will_tab(0, 0, enemy.pos.x, enemy.pos.y, tabbable_square) then
        if handle_ignore then
            remove_ignore(enemy.pos.x, enemy.pos.y)
        end
        return true
    else
        if handle_ignore then
            add_ignore(enemy.pos.x, enemy.pos.y)
        end
        return false
    end
end


function can_ranged_attack_enemy(enemy, weapon)
    local test_spell = ranged_weapon_test_spell(weapon)
    local penetrating = is_penetrating_weapon(weapon)
    local positions = spells.path(test_spell, enemy.pos.x, enemy.pos.y, false)
    for _, pos in ipairs(positions) do
        if pos.x == enemy.pos.x and pos.y == enemy.pos.y then
            return true
        elseif not penetrating then
            return false
        end
    end
    return false
end

function count_ranged(cx, cy, radius)
    local i = 0
    for _, enemy in ipairs(enemy_list) do
        local dist = supdist(cx - enemy.pos.x, cy - enemy.pos.y)
        if dist > 1 and dist <= radius then
            if dist == 2 and is_fast(enemy.mons)
                 or (is_ranged(enemy.mons)
                 or dist == 2
                     and enemy.mons:reach_range() >= 2)
                     and view.cell_see_cell(cx, cy, enemy.pos.x, enemy.pos.y) then
                i = i + 1
            end
        end
    end
    return i
end

function count_shortranged(cx, cy, r)
    local i = 0
    for _, e in ipairs(enemy_list) do
        if supdist(cx - e.pos.x, cy - e.pos.y) <= r and is_ranged(e.m) then
            i = i + 1
        end
    end
    return i
end

-- adding some clua for this would be better
function mons_can_use_stairs(mons)
    local mname = mons:name()
    if mons:is_stationary()
            or mons_liquid_bound(mons)
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

function mons_tabbable_square(x, y)
    return not deep_water_or_lava(x, y) and not is_solid(x, y)
end

function will_tab(cx, cy, ex, ey, square_func, tab_dist)
    if not tab_dist then
        tab_dist = 1
    end

    local dx = ex - cx
    local dy = ey - cy
    if supdist(dx, dy) <= tab_dist then
        return true
    end

    local function attempt_move(fx, fy)
        if fx == 0 and fy == 0 then return end
        if supdist(cx + fx, cy + fy) > los_radius then return end
        if square_func(cx + fx, cy + fy) then
            return will_tab(cx + fx, cy + fy, ex, ey, square_func, tab_dist)
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
        if e.mons:name() == "orb of fire" then
            v = v + 1
        elseif v > 0 and e.mons:threat() <= 1 then
            v = 0.5
        end
        count = count + v
    end
    return count
end

function mons_is_holy_vulnerable(mons)
    local holiness = mons:holiness()
    return holiness == "undead" or holiness == "demonic"
end

function mons_liquid_bound(mons)
    return mons:name() == "electric eel"
        or mons:name() == "kraken"
        or mons:name() == "elemental wellspring"
        or mons:name() == "lava snake"
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
        local dist = supdist(cx - enemy.pos.x, cy - enemy.pos.y)
        local see_cell = view.cell_see_cell(cx, cy, enemy.pos.x, enemy.pos.y)
        local ranged = is_ranged(enemy.m)
        local liquid_bound = mons_liquid_bound(enemy.m, true)

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound and not ranged and enemy.mons:reach_range() < 2 then
                a.followers_to_land = true
            end

            if have_reaching()
                    and not ranged
                    and enemy.mons:reach_range() < 2
                    and mon_speed_num(enemy.mons) < player_speed_num() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (dist == 2
                        and (is_fast(enemy.mons)
                            or enemy.mons:reach_range() >= 2)
                    or ranged) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (enemy.mons:desc():find("wandering")
                        and not enemy.mons:desc():find("mushroom")
                    or enemy.mons:desc():find("sleeping")
                    or enemy.mons:desc():find("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (enemy.mons:desc():find("wandering")
                    or enemy.mons:desc():find("sleeping")
                    or enemy.mons:desc():find("dormant")
                    or enemy.mons:desc():find("stupefied")
                    or liquid_bound
                    or enemy.mons:is_stationary())
                and enemy_can_move_melee(e) then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function distance_to_enemy(cx, cy)
    local best_dist = 10
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.pos.x, cy - e.pos.y)
        if dist < best_dist then
            best_dist = dist
        end
    end
    return best_dist
end

function distance_to_tabbable_enemy(cx, cy)
    local best_dist = 10
    for _, e in ipairs(enemy_list) do
        local dist = supdist(cx - e.pos.x, cy - e.pos.y)
        if dist < best_dist then
            if will_tab(e.pos.x, e.pos.y, 0,  0, mons_tabbable_square) then
                best_dist = dist
            end
        end
    end
    return best_dist
end
