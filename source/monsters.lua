-----------------------------------------
-- monster functions and data


-- functions for use in the monster lists below
function in_desc(lev, str)
    return function (mons)
        return you.xl() < lev and mons:desc():find(str)
    end
end

function pan_lord(lev)
    return function (mons)
        return you.xl() < lev and mons:type() == enum_mons_pan_lord
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
    return function (enemy)
        return you.xl() < lev and res_func_table[resist]() < value
    end
end

function slow_berserk(lev)
    return function (enemy)
        return you.xl() < lev and count_enemies(1) > 0
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
    return function (mons)
        return you.xl() < lev
            and mons:desc():find("hydra")
            and not contains_string_in(enemy:name(),
                { "skeleton", "zombie", "simulacrum", "spectral" })
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

function mons_speed_num(mons)
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

    local name = mons:name()
    if name:find("boulder beetle") then
        num = num + 3
    end
    if name:find("spriggan") or name == "the Enchantress" then
        num = num + 1
    elseif name:find("naga") or name == "Vashnia" then
        num = num - 1
    end

    return num
end

function sense_immediate_danger()
    for _, enemy in ipairs(enemy_list) do
        local dist = enemy:distance()
        if dist <= 2 then
            return true
        elseif dist == 3 and enemy:reach_range() >= 2 then
            return true
        elseif enemy:is_ranged() then
            return true
        end
    end

    return false
end

function sense_danger(radius, moveable)
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        if (moveable and you.see_cell_solid_see(pos.x, pos.y)
                    or not moveable)
                and supdist(pos) <= radius then
            return true
        end
    end

    return false
end

function sense_sigmund()
    local see_sigmund = false
    for _, enemy in ipairs(enemy_list) do
        if enemy:name() == "Sigmund" then
            sigmund_pos = enemy:pos()
            see_sigmund = true
            break
        end
    end

    if invis_sigmund and invis_sigmund_count > 100 then
        say("Invisible monster not found???")
        if not options.autopick_on then
            magic(control('a'))
            coroutine.yield()
        end
    end

    if see_sigmund or options.autopick_on then
        invis_sigmund_count = 0
        invis_sigmund = false
    end
end

function initialize_monster_map()
    monster_map = {}
    for x = -los_radius, los_radius do
        monster_map[x] = {}
    end
end

function update_monster_map()
    enemy_list = {}
    for pos in radius_iter(origin) do
        if you.see_cell_no_trans(pos.x, pos.y) then
            local mons = monster.get_monster_at(pos.x, pos.y)
            if mons then
                monster_map[pos.x][pos.y] = Monster:new(mons)
                if monster_map[pos.x][pos.y]:is_enemy() then
                    table.insert(enemy_list, monster_map[pos.x][pos.y])
                end
            end
        else
            monster_map[pos.x][pos.y] = nil
        end
    end

    if #enemy_list > 0 and move_reason == "monster" then
        move_target = nil
        move_reason = nil
    end
end

function mons_in_list(mons, mlist)
    local entry = mlist[mons:name()]
    if type(entry) == "number" and you.xl() < entry then
        return true
    elseif type(entry) == "function" and entry(mons) then
        return true
    end

    for _, entry in ipairs(mlist["*"]) do
        if entry(m) then
            return true
        end
    end

    return false
end

function check_monster_list(radius, mons_list, filter)
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius
                and (not filter or filter(enemy))
                and mons_in_list(enemy, mons_list) then
            return true
        end
    end

    return false
end

function count_enemies_near(pos, radius, filter)
    local i = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius and (not filter or filter(enemy)) then
            i = i + 1
        end
    end
    return i
end

function count_enemies_near_by_name(pos, radius, name)
    return count_enemies_near(pos, radius,
        function(enemy) return enemy:name() == name end)
end

function count_enemies(radius, filter)
    return count_enemies_near(origin, radius, filter)
end

function count_enemies_in_mons_list(radius, mons_list, filter)
    return count_enemies(radius,
        function(enemy)
            return (not filter or filter(enemy))
                and mons_in_list(enemy, mons_list)
        end)
end

function count_enemies_by_name(radius, name)
    return count_enemies(radius,
        function(enemy) return enemy:name() == name end)
end

function count_hostile_greater_servants(radius)
    if you.god() ~= "Makhleb" then
        return 0
    end

    return count_enemies(radius,
        function(enemy) return enemy:is_summoned()
            and mons_is_greater_servant(enemy) end)
end

function count_big_slimes(radius)
    return count_enemies(radius,
        function(mons)
            return contains_string_in(mons:name(),
                { "enormous slime creature", "titanic slime creature" })
        end)
end

function count_pan_lords(radius)
    return count_enemies(radius,
        function(mons) return mons:type() == enum_mons_pan_lord end)
end
