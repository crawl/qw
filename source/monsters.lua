-----------------------------------------
-- monster functions and data

util.defclass("Monster")

-- Return a function that calls a lookup function in a clua moninfo userdata
-- object, caching the result.
function Monster:prop_func(name, func)
    return function()
        if self.props[name] == nil then
            if filter then
                self.props[name] = func()
            else
                self.props[name] = self.minfo[name]()
            end
        end

        return self.props[name]
    end
end

function Monster:set_props()
    self.props = {}
    self.x_pos = self.prop_func("x_pos")
    self.y_pos = self.prop_func("y_pos")
    self.pos = self.prop_func("pos",
        function()
            return { x = self:x_pos(), y = self:y_pos() }
        end)
    self.distance = self.prop_func("distance",
        function() return supdist(self:x_pos(), self:y_pos()) end)

    self.name = self.prop_func("name")
    self.desc = self.prop_func("desc")

    self.speed_description = self.prop_func("speed_description")
    self.speed = self.prop_func("speed",
        function()
            return mons_speed(self)
        end)
    self.is_fast = self.prop_func("is_fast",
        function()
            return self:speed() > player_speed()
        end)

    self.type = self.prop_func("type")
    self.attitude = self.prop_func("attitude")
    self.holiness = self.prop_func("holiness")
    self.is_holy_vulnerable = self.prop_func("is_holy_vulnerable",
        function()
            local holiness = self:holiness()
            return holiness == "undead" or holiness == "demonic"
        end)

    self.is_firewood = self.prop_func("is_firewood")
    self.is_safe = self.prop_func("is_safe")
    self.threat = self.prop_func("threat")

    self.is_stationary = self.prop_func("is_stationary")
    -- Adding some clua for this would be better.
    self.can_use_stairs = self.prop_func("can_use_stairs",
        function()
            local name = self:name()
            return not (self:is_stationary()
                    or self:is_liquid_bound()
                    or name:find("zombie")
                    or name:find("skeleton")
                    or name:find("spectral")
                    or name:find("simulacrum")
                    or name:find("tentacle")
                    or name:find("vortex")
                    or name == "silent spectre"
                    or name == "Geryon"
                    or name == "Royal Jelly"
                    or name == "bat"
                    or name == "unseen horror")
        end)

    self.is_liquid_bound = self.prop_func("is_liquid_bound",
        function()
            local name = self:name()
            return name == "electric eel"
                or name == "kraken"
                or name == "elemental wellspring"
                or name == "lava snake"
        end)

    self.damage_level = self.prop_func("damage_level")
    self.is_caught = self.prop_func("is_caught")
    self.is_summoned = self.propf_func("is_summoned",
        function() return self.minfo.is("summoned") end)

    self.reach_range = self.prop_func("reach_range")
    self.constricting_you = self.prop_func("constricting_you")
    self.stabbability = self.prop_func("stabbability")
    self.has_known_ranged_attack = self.prop_func("has_known_ranged_attack")
    self.is_ranged = self.prop_func("is_ranged",
        function()
            return self:has_known_ranged_attack()
                    and not self.name():find("kraken")
                or self:name() == "lost soul"
        end)

    -- Whether we'd ever want to attack this monster, and hence whether it's in
    -- the enemy_list.
    self.is_enemy = self.prop_func("is_enemy",
        function()
            return self:is_safe()
                and self:attitude() < enum_att_neutral
                and self:name() ~= "orb of destruction"
        end)

    self.is_orc_priest_wizard = self.prop_func("is_orc_priest_wizard",
        function()
            return self:name() == "orc priest" or self:name() == "orc wizard"
        end)

    self.player_can_melee = self.prop_func("player_can_melee",
        function() player_can_melee_mons(self) end)
    self.can_melee_player = self.prop_func("can_melee_player",
        function() mons_can_melee_player(self) end)
end

function Monster:new(mons)
    local monster = {}
    setmetatable(monster, self)
    monster.minfo = mons
    monster:set_props()
    return monster
end

function Monster:is(flag)
    if not self.props.flags then
        self.props.flags = { }
    end

    if self.props.flags[flag] == nil then
        self.props.flags[flag] = self.minfo:is(flag)
    end

    return self.props.flags[flag]
end

function Monster:status(status)
    if not self.props.status then
        self.props.status = { }
    end

    if self.props.status[status] == nil then
        self.props.status[status] = self.minfo:status(status)
    end

    return self.props.status[status]
end

function Monster:player_can_move_to_melee(handle_ignore)
end

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
        return (you.xl() < lev and res_func_table[resist]() < value)
    end
end

function slow_berserk(lev)
    return function (enemy)
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
        elseif is_ranged_mons(enemy) then
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
                and supdist(pos.x, pos.y) <= radius then
            return true
        end
    end

    return false
end

function sense_sigmund()
    for _, enemy in ipairs(enemy_list) do
        if enemy:name() == "Sigmund" then
            sigmund_pos = enemy:pos()
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
    for pos in radius_iter(origin) do
        if you.see_cell_no_trans(pos.x, pos.y) then
            monster_array[pos.x][pos.y] =
                Monster(monster.get_monster_at(pos.x, pos.y))
            if monster_array[pos.x][pos.y]:is_enemy() then
                table.insert(enemy_list, monster_array[pos.x][pos.y])
            end
        else
            monster_array[pos.x][pos.y] = nil
        end
    end
end

function get_monster_distance_map(mons)
    local dist_map = get_distance_map(mons_pos, los_radius)
    local mons_pos = { x = mons:x_pos() - waypoint.x,
        y = mons:y_pos() - waypoint.y }
    update_distance_map(dist_map, { pos }, traversal_func)
end

function can_path_monster(mons)
    local dist_map = mons_distance_maps[waypoint_parity]
    for pos in adjacent_iter(mons:pos()) do
        if dist_map[pos.x][pos.y] then
            return true
        end
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

function check_mons_list(radius, mons_list, filter)
    for _, enemy in ipairs(enemy_list) do
        if supdist(enemy:x_pos(), enemy:y_pos()) <= radius
                and (not filter or filter(enemy))
                and mons_in_list(enemy, mons_list) then
            return true
        end
    end

    return false
end

function count_enemies_near(cx, cy, radius, filter)
    local i = 0
    for _, enemy in ipairs(enemy_list) do
        if supdist(cx - enemy:x_pos(), cy - enemy:y_pos()) <= radius
                and (not filter or filter(enemy)) then
            i = i + 1
        end
    end
    return i
end

function count_enemies_near_by_name(cx, cy, radius, name)
    return count_enemies_near(cx, cy, radius,
        function(enemy) return enemy:name() == name end)
end

function count_enemies(radius, filter)
    return count_enemies_near(0, 0, radius, filter)
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
    return count_monsters(radius,
        function(mons)
            return contains_string_in(mons:name(),
                { "enormous slime creature", "titanic slime creature" })
        end)
end

function count_pan_lords(radius)
    return count_monsters(radius,
        function(mons) return mons:type() == enum_mons_pan_lord end)
end

-- Should only be called for adjacent squares.
function monster_in_way(pos)
    local mons = monster_array[pos.x][pos.y]
    local feat = view.feature_at(0, 0)
    return mons and (mons:attitude() <= enum_att_neutral
            and not branch_step_mode
        or mons:attitude() > enum_att_neutral
            and (mons:is_constricted()
                or mons:is_caught()
                or mons:status("petrified")
                or mons:status("paralysed")
                or mons:status("constricted by roots")
                or mons:desc():find("sleeping")
                or feature_is_deep_water_or_lava(feat)
                or feat  == "trap_zot"))
end

function tabbable_square(pos)
    if view.feature_at(pos.x, pos.y) ~= "unseen"
            and view.is_safe_square(pos.x, pos.y) then
        if not monster_array[pos.x][pos.y]
                or not monster_array[pos.x][pos.y]:is_firewood() then
            return true
        end
    end
    return false
end

function update_ranged_target_info(enemy, ranged_items)
    if enemy.have_ranged_target_info then
        return
    end

    local weapon = items.fired_item()
    local test_spell = weapon_test_spell(weapon)
    local penetrating = is_penetrating_weapon(weapon)
    local positions = spells.path(test_spell, enemy.pos.x, enemy.pos.y, false)
    for _, pos in ipairs(positions) do
    end


    enemy.player_can_ranged_attack = enemy.player_melee_range > 0

    enemy.have_ranged_target_info = true
end

function is_enemy_at(pos)
    return monster_array[pos.x][pos.y]
        and monster_array[pos.x][pos.y].is_enemy()
end

function player_can_move_to_melee_mons(mons)
    local pos = mons:pos()
    if will_tab(origin, pos, tabbable_square) then
        return true
    else
        return false
    end
end

function can_ranged_attack_enemy(enemy, weapon)
    local hit = false
    for _, pos in ipairs(positions) do
        if pos.x == enemy.pos.x and pos.y == enemy.pos.y then
            hit = true
        elseif not penetrating then
            return false
        end
    end
end

function will_tab(center, target, square_func, tab_dist)
    if not tab_dist then
        tab_dist = 1
    end

    local dpos = { x = target.x - center.x, y = target.y - center.y }
    if supdist(dpos.x, dpos.y) <= tab_dist then
        return true
    end

    local function attempt_move(pos)
        if pos.x == 0 and pos.y == 0 then
            return
        end

        local new_pos = { x = center.x + pos.x, y = center.y + pos.y }
        if supdist(newpos.x, newpos.y) > los_radius then
            return
        end

        if square_func(newpos) then
            return will_tab(newpos, target, square_func, tab_dist)
        end
    end

    local move
    if abs(dpos.x) > abs(dpos.y) then
        if abs(dpos.y) == 1 then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move and abs(dpos.x) > abs(dpos.y) + 1 then
             move = attempt_move({ x = sign(dpos.x), y = 1 })
        end
        if not move and abs(dpos.x) > abs(dpos.y) + 1 then
             move = attempt_move({ x = sign(dpos.x), y = -1 })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
    elseif abs(dpos.x) == abs(dpos.y) then
        move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
    else
        if abs(dpos.x) == 1 then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
        if not move and abs(dpos.y) > abs(dpos.x) + 1 then
             move = attempt_move({ x = 1, y = sign(dpos.y) })
        end
        if not move and abs(dpos.y) > abs(dpos.x) + 1 then
             move = attempt_move({ x = -1, y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
    end
    return move
end

function estimate_slouch_damage()
    local count = 0
    local s, v
    for _, enemy in ipairs(enemy_list) do
        s = mons_speed_num(enemy.mons)
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
        if e.name == "orb of fire" then
            v = v + 1
        elseif v > 0 and e.threat <= 1 then
            v = 0.5
        end
        count = count + v
    end
    return count
end

function assess_square_enemies(a, cx, cy)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers_to_land = false
    a.adjacent = 0
    a.slow_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        local dist = enemy:distance()
        local see_cell = view.cell_see_cell(cx, cy, pos.x, pos.y)
        local ranged = enemy:is_ranged()
        local liquid_bound = enemy:is_liquid_bound()

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound
                    and not ranged
                    and enemy:reach_range() < 2 then
                a.followers_to_land = true
            end

            if have_reaching()
                    and not ranged
                    and enemy:reach_range() < 2
                    and enemy:speed() < player_speed() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (dist == 2
                        and (enemy:is_fast() or enemy:reach_range() >= 2)
                    or ranged) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (enemy:desc():find("wandering")
                        and not enemy:desc():find("mushroom")
                    or enemy:desc():find("sleeping")
                    or enemy:desc():find("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (enemy:desc():find("wandering")
                    or enemy:desc():find("sleeping")
                    or enemy:desc():find("dormant")
                    or enemy:desc():find("stupefied")
                    or liquid_bound
                    or enemy:is_stationary())
                and enemy:can_move_to_melee_player() then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function distance_to_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end

function distance_to_tabbable_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist
                and enemy:can_move_to_melee_player() then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end
