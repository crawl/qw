--
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

function god_altar(god)
    if not god then
        god = you.god()
    end

    return "altar_" .. string.gsub(string.lower(god), " ", "_")
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

    for w, s in pairs(c_persist.altars[god]) do
        if s >= los_state then
            return w
        end
    end
end

function can_hand()
    return you.god() == "Trog"
                 and you.piety_rank() >= 2
                 and not you.regenerating()
                 and can_invoke()
end

function can_bia()
    return you.god() == "Trog"
                 and you.piety_rank() >= 4
                 and can_invoke()
end


function can_heroism()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 1
                 and cmp() >= 2
                 and not you.status("heroic")
                 and can_invoke()
end

function can_finesse()
    return you.god() == "Okawaru"
                 and you.piety_rank() >= 5
                 and cmp() >= 5
                 and not you.status("finesse-ful")
                 and can_invoke()
end

function can_recall()
    return (you.god() == "Yredelemnul" and you.piety_rank() >= 2)
                    or (you.god() == "Beogh" and you.piety_rank() >= 4)
                 and not you.status("recalling")
                 and cmp() >= 2
                 and can_invoke()
end

function can_drain_life()
    return you.god() == "Yredelemnul"
                 and you.piety_rank() >= 4
                 and cmp() >= 6
                 and can_invoke()
end

function can_recall_ancestor()
    return you.god() == "Hepliaklqana"
                 and cmp() >= 2
                 and can_invoke()
end

function can_slouch()
    return you.god() == "Cheibriados"
                 and you.piety_rank() >= 4
                 and cmp() >= 5
                 and can_invoke()
end

function can_ely_healing()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 4
                 and cmp() >= 2
                 and can_invoke()
end

function can_purification()
    return you.god() == "Elyvilon"
                 and you.piety_rank() >= 3
                 and cmp() >= 3
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
                 and cmp() >= 8
                 and not you.exhausted()
                 and can_invoke()
end

function can_grand_finale()
    return you.god() == "Uskayaw"
                 and you.piety_rank() >= 5
                 and cmp() >= 8
                 and can_invoke()
end

function can_sgd()
    return you.god() == "Makhleb"
                 and you.piety_rank() >= 5
                 and chp() > 10
                 and can_invoke()
end

function can_cleansing_flame(ignore_mp)
    return you.god() == "the Shining One"
        and you.piety_rank() >= 3
        and (ignore_mp or cmp() >= 5)
        and can_invoke()
end

function can_divine_warrior(ignore_mp)
    return you.god() == "the Shining One"
                 and you.piety_rank() >= 5
                 and (ignore_mp or cmp() >= 8)
                 and can_invoke()
end

function can_destruction()
    return you.god() == "Makhleb"
                 and chp() > 6
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

function count_bia(r)
    if you.god() ~= "Trog" then
        return 0
    end

    local i = 0
    for x, y in square_iter(0, 0, r) do
        m = monster_array[x][y]
        if m and m:is_safe()
                and m:is("berserk")
                and contains_string_in(m:name(),
                    {"ogre", "giant", "bear", "troll"}) then
            i = i + 1
        end
    end
    return i
end

function count_elliptic(r)
    if you.god() ~= "Hepliaklqana" then
        return 0
    end

    local x, y
    local i = 0
    for x, y in square_iter(0, 0, r) do
        m = monster_array[x][y]
        if m and m:is_safe()
                and contains_string_in(m:name(), {"elliptic"}) then
            i = i + 1
        end
    end
    return i
end

function mons_is_greater_demon(m)
    return contains_string_in(m:name(), {"Executioner", "green death",
        "blizzard demon", "balrug", "cacodemon"})
end

function count_sgd(r)
    if you.god() ~= "Makhleb" then
        return 0
    end

    local i = 0
    for x, y in square_iter(0, 0, r) do
        local m = monster_array[x][y]
        if m and m:is_safe()
                and m:is("summoned")
                and mons_is_greater_demon(m) then
            i = i + 1
        end
    end
    return i
end

function count_divine_warrior(r)
    if you.god() ~= "the Shining One" then
        return 0
    end

    local i = 0
    for x, y in square_iter(0, 0, r) do
        local m = monster_array[x][y]
        if m and m:is_safe()
                and contains_string_in(m:name(), {"angel", "daeva"}) then
            i = i + 1
        end
    end
    return i
end

function record_altar(x, y)
    record_feature_position(x, y)
    local feat = view.feature_at(x, y)
    local god = god_full_name(feat:gsub("altar_", ""):gsub("_", " "))

    local state = los_state(x, y)
    if not c_persist.altars[god] then
        c_persist.altars[god] = {}
    end

    if c_persist.altars[god][where]
            and c_persist.altars[god][where] >= state then
        return
    end

    c_persist.altars[god][where] = state
    want_gameplan_update = true
end
