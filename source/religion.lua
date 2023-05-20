------------------
-- Functions and data related to god worship.

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
}

good_gods = { "Elyvilon", "the Shining One", "Zin" }
function is_good_god(god)
    if not god then
        god = you.god()
    end

    return util.contains(good_gods, god)
end

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

function altar_god(feat)
    return god_full_name(feat:gsub("^altar_", ""):gsub("_", " "))
end

function god_altar(god)
    if not god then
        god = you.god()
    end

    return "altar_" .. god:lower():gsub(" ", "_")
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

    for level, entries in pairs(c_persist.altars[god]) do
        for _, state in pairs(entries) do
            if state.los >= los_state then
                return level
            end
        end
    end
end

function can_trogs_hand()
    return you.god() == "Trog"
                 and you.piety_rank() >= 2
                 and not you.regenerating()
                 and can_invoke()
end

function can_brothers_in_arms()
    return you.god() == "Trog"
                 and you.piety_rank() >= 4
                 and can_invoke()
end


function can_heroism()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 1
                 and you.mp() >= 2
                 and not you.status("heroic")
                 and can_invoke()
end

function can_finesse()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 5
                 and you.mp() >= 5
                 and not you.status("finesse-ful")
                 and can_invoke()
end

function can_recall()
    return you.god() == "Yredelemnul"
            or you.god() == "Beogh" and you.piety_rank() >= 4
        and not you.status("recalling")
        and you.mp() >= 2
        and can_invoke()
end

function can_drain_life()
    return you.god() == "Yredelemnul"
                 and you.piety_rank() >= 4
                 and you.mp() >= 6
                 and can_invoke()
end

function can_recall_ancestor()
    return you.god() == "Hepliaklqana"
                 and you.mp() >= 2
                 and can_invoke()
end

function can_slouch()
    return you.god() == "Cheibriados"
                 and you.piety_rank() >= 4
                 and you.mp() >= 5
                 and can_invoke()
end

function can_ely_healing()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 4
                 and you.mp() >= 2
                 and can_invoke()
end

function can_purification()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 3
                 and you.mp() >= 3
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
                 and you.mp() >= 8
                 and not you.exhausted()
                 and can_invoke()
end

function can_grand_finale()
    return you.god() == "Uskayaw"
                 and you.piety_rank() >= 5
                 and you.mp() >= 8
                 and can_invoke()
end

function can_greater_servant()
    return you.god() == "Makhleb"
                 and you.piety_rank() >= 5
                 and you.hp() > 10
                 and can_invoke()
end

function can_cleansing_flame(ignore_mp)
    return you.god() == "the Shining One"
        and you.piety_rank() >= 3
        and (ignore_mp or you.mp() >= 5)
        and can_invoke()
end

function can_divine_warrior(ignore_mp)
    return you.god() == "the Shining One"
                 and you.piety_rank() >= 5
                 and (ignore_mp or you.mp() >= 8)
                 and can_invoke()
end

function can_destruction()
    return you.god() == "Makhleb"
                 and you.hp() > 6
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

function count_brothers_in_arms(radius)
    if you.god() ~= "Trog" then
        return 0
    end

    local i = 0
    for pos in square_iter(origin, radius) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_safe()
                and mons:is("berserk")
                and contains_string_in(mons:name(),
                    { "ogre", "giant", "bear", "troll" }) then
            i = i + 1
        end
    end
    return i
end

function count_elliptic(radius)
    if you.god() ~= "Hepliaklqana" then
        return 0
    end

    local i = 0
    for pos in square_iter(origin, radius) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_safe()
                and contains_string_in(mons:name(), {"elliptic"}) then
            i = i + 1
        end
    end
    return i
end

function monster_is_greater_servant(mons)
    return contains_string_in(mons:name(), { "Executioner", "green death",
        "blizzard demon", "balrug", "cacodemon" })
end

function count_greater_servants(radius)
    if you.god() ~= "Makhleb" then
        return 0
    end

    local i = 0
    for pos in square_iter(origin, radius) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_safe()
                and mons:is("summoned")
                and monster_is_greater_servant(m) then
            i = i + 1
        end
    end
    return i
end

function count_divine_warriors(radius)
    if you.god() ~= "the Shining One" then
        return 0
    end

    local i = 0
    for pos in square_iter(origin, radius) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_safe()
                and contains_string_in(mons:name(), {"angel", "daeva"}) then
            i = i + 1
        end
    end
    return i
end

function count_beogh_allies(radius)
    if you.god() ~= "Beogh" then
        return 0
    end

    local i = 0
    for pos in square_iter(origin, radius) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_safe()
                and contains_string_in(mons:name(), {"orc "}) then
            i = i + 1
        end
    end
    return i
end

function update_altar(god, level, hash, state, force)
    if state.safe == nil and not state.los then
        error("Undefined altar state.")
    end

    if not c_persist.altars[god] then
        c_persist.altars[god] = {}
    end

    if not c_persist.altars[god][level] then
        c_persist.altars[god][level] = {}
    end

    if not c_persist.altars[god][level][hash] then
        c_persist.altars[god][level][hash] = {}
    end

    local current = c_persist.altars[god][level][hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            local pos = position_difference(unhash_position(hash), global_pos)
            dsay("Updating " .. god .. " altar on " .. level .. " at "
                .. pos_string(pos) .. " from " .. stairs_state_string(current)
                .. " to " .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed then
            current.los = state.los
            want_gameplan_update = true
        end
        return true
    end

    return false
end

function estimate_slouch_damage()
    local count = 0
    for _, enemy in ipairs(enemy_list) do
        local speed = enemy:speed()
        local val = 0
        if speed >= 6 then
            val = 3
        elseif speed == 5 then
            val = 2.5
        elseif speed == 4 then
            val = 1.5
        elseif speed == 3 then
            val = 1
        end
        if enemy:name() == "orb of fire" then
            val = val + 1
        elseif v > 0 and enemy:threat() <= 1 then
            val = 0.5
        end
        count = count + val
    end
    return count
end

function update_permanent_flight()
    if not gained_permanent_flight then
        return
    end

    for god, levels in pairs(c_persist.altars) do
        for level, altars in pairs(levels) do
            for hash, state in pairs(altars) do
                if state.los >= FEAT_LOS.SEEN
                        and state.los < FEAT_LOS.REACHABLE then
                    update_altar(god, level, hash, { los = FEAT_LOS.REACHABLE })
                end
            end
        end
    end
end
