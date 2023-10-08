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

function hydra_weapon_value(weap)
    if not weap then
        return 0
    end

    local sk = weap.weap_skill
    if sk == "Ranged Weapons"
            or sk == "Maces & Flails"
            or sk == "Short Blades"
            or sk == "Polearms" and weap.hands == 1 then
        return sk == weapon_skill() and 1 or 0
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
            and not contains_string_in(mons:name(),
                { "skeleton", "zombie", "simulacrum", "spectral" })
            and hydra_weapon_value(get_weapon()) ~= 1
    end
end

-- The format in monster lists below is that a num is equivalent to checking
-- XL < num, otherwise we want a function. ["*"] should be a table of
-- functions to check for every monster.
local scary_monsters = {
    ["*"] = {
        hydra_check_flaming(17),
        in_desc(100, "berserk[^e]"),
        in_desc(100, "statue"),
        in_desc(100, "'s? ghost"),
        in_desc(100, "'s? illusion"),
        pan_lord(100),
    },

    ["worm"] = slow_berserk(4),

    ["ice beast"] = check_resist(7, "rC", 1),

    ["white ugly thing"] = check_resist(15, "rC", 1),
    ["freezing wraith"] = check_resist(15, "rC", 1),

    ["shock serpent"] = check_resist(17, "rElec", 1),
    ["sun demon"] = check_resist(17, "rF", 1),
    ["white very ugly thing"] = check_resist(17, "rC", 1),
    ["Lodul"] = check_resist(17, "rElec", 1),

    ["ironbound frostheart"] = check_resist(20, "rC", 1),
    ["ironbound thunderhulk"] = check_resist(20, "rElec", 1),

    ["azure jelly"] = check_resist(24, "rC", 1),
    ["fire giant"] = check_resist(24, "rF", 1),
    ["frost giant"] = check_resist(24, "rC", 1),
    ["hell hog"] = check_resist(24, "rF", 1),
    ["shadow dragon"] = check_resist(24, "rN", 1),
    ["storm dragon"] = check_resist(24, "rElec", 1),
    ["titan"] = check_resist(24, "rElec", 1),
    ["Margery"] = check_resist(24, "rF", 2),
    ["Xtahua"] = check_resist(24, "rF", 2),

    ["electric golem"] = check_resist(100, "rElec", 1),
    ["entropy weaver"] = check_resist(100, "rCorr", 1),
    ["spark wasp"] = check_resist(100, "rElec", 1),
    ["spriggan air mage"] = check_resist(100, "rElec", 1),
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
        -- The enemy list is in order of increasing distance, so once we've
        -- seen a monster with distance above our radius, we're done.
        if enemy:distance() > radius then
            return
        end

        if not moveable
                or you.see_cell_solid_see(enemy:x_pos(), enemy:y_pos()) then
            return true
        end
    end

    return false
end

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
        for _, enemy in ipairs(enemy_list) do
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

    if not position_is_safe or options.autopick_on then
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

function monster_speed_number(mons)
    local desc = mons:speed_description()
    local num
    if desc == "extremely fast" then
        num = 6
    elseif desc == "very fast" then
        num = 5
    elseif desc == "fast" then
        num = 4
    elseif desc == "normal" then
        num = 3
    elseif desc == "slow" then
        num = 2
    elseif desc == "very slow" then
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

function initialize_monster_map()
    monster_map = {}
    for x = -qw.los_radius, qw.los_radius do
        monster_map[x] = {}
    end
end

function update_monsters()
    enemy_list = {}
    local closest_invis_pos
    local sinv = you.see_invisible()
    for pos in radius_iter(const.origin) do
        if you.see_cell_no_trans(pos.x, pos.y) then
            local mon_info = monster.get_monster_at(pos.x, pos.y)
            if mon_info then
                local mons = Monster:new(mon_info)
                monster_map[pos.x][pos.y] = mons
                if mons:is_enemy() and not mons:is_safe() then
                    table.insert(enemy_list, mons)
                end
            else
                monster_map[pos.x][pos.y] = nil
            end

            if not sinv
                    and not closest_invis_pos
                    and view.invisible_monster(pos.x, pos.y) then
                closest_invis_pos = pos
            end
        else
            monster_map[pos.x][pos.y] = nil
        end
    end

    update_invis_monsters(closest_invis_pos)
end

function get_monster_at(pos)
    if supdist(pos) <= qw.los_radius then
        return monster_map[pos.x][pos.y]
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

function check_scary_monsters(radius, filter)
    local score = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius
                and (not filter or filter(enemy))
                and (enemy:is_ranged(true)
                    or enemy:has_path_to_melee_player()) then
            if enemy:threat() >= 3
                    or monster_in_list(enemy, scary_monsters) then
                return true
            end

            score = score + enemy:threat()

            if score >= 10 then
                return true
            end
        end
    end

    return false
end

function total_monster_score(radius, filter)
    local score = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius
                and (not filter or filter(enemy))
                and (enemy:is_ranged(true)
                    or enemy:has_path_to_melee_player(true)) then
            score = score + enemy:threat()
        end
    end

    return score
end

function check_enemies_in_list(radius, mons_list, filter)
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius
                and (not filter or filter(enemy))
                and monster_in_list(enemy, mons_list) then
            return true
        end
    end

    return false
end

function count_enemies(radius, filter)
    local i = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius and (not filter or filter(enemy)) then
            i = i + 1
        end
    end
    return i
end

function count_enemies_in_list(radius, mons_list, filter)
    local i = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() <= radius
                and (not filter or filter(enemy))
                and monster_in_list(enemy, mons_list) then
            i = i + 1
        end
    end
    return i
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

function count_big_slimes(radius)
    return count_enemies(radius,
        function(mons)
            return contains_string_in(mons:name(),
                { "enormous slime creature", "titanic slime creature" })
        end)
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
