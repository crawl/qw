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
    const.mp_using_gods = {}

    for _, entry in ipairs(god_data_values) do
        local god = entry[1]
        god_data[god] = {}
        god_data[god]["uses_invocations"] = entry[2]
        god_data[god]["uses_mp"] = entry[3]
        if entry[3] then
            table.insert(const.mp_using_gods, god)
        end

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
    if you.race() == "Djinni" then
        return false
    end

    if not god then
        god = you.god()
    end

    if not god_data[god] then
        return false
    end

    return god_data[god].uses_mp
end

function enough_max_mp_for_god(max_mp, god)
    if you.race() == "Djinni" then
        return true
    end

    -- Hero costs 2 and Finesse costs 5, so we want at least 7mmp
    if god == "Okawaru" then
        return max_mp >= 7
    end

    -- These gods want to spam MP-using abilities .
    if god == "Cheibriados" or god == "the Shining One" then
        return max_mp >= 30
    end

    return true
end

function future_gods_enough_max_mp(max_mp)
    if you.race() == "Djinni" then
        return true
    end

    for _, god in ipairs(qw.future_gods) do
        if not enough_max_mp_for_god(max_mp, god) then
            return false
        end
    end

    return true
end

function item_is_evil(it)
    local subtype = it.subtype()
    if subtype and subtype:find("^demon") then
        return true
    end

    local ego = it.ego()
    if ego == "pain"
            or ego == "vampirism"
            or ego == "draining"
            or ego == "chaos"
            or ego == "reaping"
            or ego == "distortion" then
        return true
    end

    if not subtype then
        return false
    end

    local name = it.name()
    return name:find("Vitality") and subtype:find("^amulet")
        or name:find("{damnation}")
        or name:find("Cerebov") and subtype == "great sword"
        or name:find("Asmodeus") and subtype == "eveningstar"
        or name:find("Cigotuvi's embrace")
        or name:find("Black Knight's barding")
end

function current_god_hates_item(it)
    -- We don't want to be wearing hated items when we convert to a new god,
    -- since we might incur penance while taking them off.
    local new_god
    if goal_status then
        new_god = goal_god(goal_status)
        if new_god and view.feature_at(0, 0) ~= god_altar(new_god) then
            new_god = nil
        end
    end

    return god_hates_item(you.god(), it)
        or new_god and god_hates_item(new_god, it)
end

function god_hates_item(god, it)
    if is_good_god(god) and item_is_evil(it) then
        return true
    end

    local ego = it.ego()
    if god == "Cheibriados" then
        return ego == "speed" or ego == "chaos"
    end

    if god == "Yredelemnul" then
        return ego == "holy wrath"
    end

    if god == "Trog" then
        return ego == "pain"
    end

    return false
end

function future_gods_hate_item(it)
    for _, god in ipairs(qw.future_gods) do
        if god_hates_item(god, it) then
            return true
        end
    end

    return false
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

function altar_found(god, feat_state)
    if not feat_state then
        feat_state = const.explore.reachable
    end

    if not c_persist.altars[god] then
        return
    end

    for level, entries in pairs(c_persist.altars[god]) do
        for _, state in pairs(entries) do
            if state.feat >= feat_state then
                return level
            end
        end
    end
end

function can_trogs_hand()
    return you.god() == "Trog"
        and you.piety_rank() >= 2
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
        and can_use_mp(2)
        and can_invoke()
end

function can_finesse()
    return you.god() == "Okawaru"
        and you.piety_rank() >= 4
        and can_use_mp(5)
        and can_invoke()
end

function can_recall()
    return you.god() == "Yredelemnul"
            or you.god() == "Beogh" and you.piety_rank() >= 4
        and not you.status("recalling")
        and can_use_mp(2)
        and can_invoke()
end

function can_drain_life()
    return you.god() == "Yredelemnul"
        and you.piety_rank() >= 4
        and can_use_mp(6)
        and can_invoke()
end

function can_recall_ancestor()
    return you.god() == "Hepliaklqana"
        and can_use_mp(2)
        and can_invoke()
end

function can_slouch()
    return you.god() == "Cheibriados"
        and you.piety_rank() >= 4
        and can_use_mp(5)
        and can_invoke()
end

function can_ely_healing()
    return you.god() == "Elyvilon"
        and you.piety_rank() >= 4
        and can_use_mp(2)
        and can_invoke()
end

function can_purification()
    return you.god() == "Elyvilon"
        and you.piety_rank() >= 3
        and can_use_mp(3)
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
        and can_use_mp(8)
        and not you.exhausted()
        and can_invoke()
end

function can_grand_finale()
    return you.god() == "Uskayaw"
        and you.piety_rank() >= 5
        and can_use_mp(8)
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
        and (ignore_mp or can_use_mp(5))
        and can_invoke()
end

function can_divine_warrior(ignore_mp)
    return you.god() == "the Shining One"
        and you.piety_rank() >= 5
        and (ignore_mp or can_use_mp(8))
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
        and can_invoke()
end

function can_foxfire_swarm()
    return you.god() == "Ignis"
        and you.piety_rank() >= 1
        and can_invoke()
end

function check_allies_func(radius, filter)
    for pos in square_iter(const.origin, radius) do
        local mons = get_monster_at(pos)
        if mons and mons:is_friendly()
                and (not filter or filter(mons)) then
            return true
        end
    end
    return false
end

function check_allies(radius, filter)
    return turn_memo_args("check_allies",
        function()
            return check_allies_func(radius, filter)
        end, radius, filter)
end

function check_brothers_in_arms(radius)
    if you.god() ~= "Trog" then
        return false
    end

    local filter = function (mons)
        return mons:is("summoned")
            and mons:is("berserk")
            and contains_string_in(mons:name(),
                { "ogre", "giant", "bear", "troll" })
    end
    return check_allies(radius, filter)
end

function check_elliptic(radius)
    if you.god() ~= "Hepliaklqana" then
        return false
    end

    local filter = function (mons)
        return mons:is("summoned")
            and contains_string_in(mons:name(), { "elliptic" })
    end
    return check_allies(radius, filter)
end

function check_greater_servants(radius)
    if you.god() ~= "Makhleb" then
        return false
    end

    local filter = function (mons)
        return mons:is("summoned")
            and contains_string_in(mons:name(), { "Executioner", "green death",
                "blizzard demon", "balrug", "cacodemon" })
    end
    return check_allies(radius, filter)
end

function check_divine_warriors(radius)
    if you.god() ~= "the Shining One" then
        return false
    end

    local filter = function (mons)
        return mons:is_summoned()
            and contains_string_in(mons:name(), { "angel", "daeva" })
    end
    return check_allies(radius, filter)
end

function check_beogh_allies(radius)
    if you.god() ~= "Beogh" then
        return false
    end

    local filter = function (mons)
        -- Beogh allies are permanent.
        return not mons:is_summoned()
            and contains_string_in(mons:name(), { "orc" })
    end
    return check_allies(radius, filter)
end

function update_altar(god, level, hash, state, force)
    if state.safe == nil and not state.feat and not state.threat then
        error("Undefined altar state.")
    end

    if not c_persist.altars[god] then
        c_persist.altars[god] = {}
    end

    if not c_persist.altars[god][level] then
        c_persist.altars[god][level] = {}
    end

    local current = c_persist.altars[god][level][hash]
    if not current then
        current = {}
        cleanup_feature_state(current)
        c_persist.altars[god][level][hash] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.feat == nil then
        state.feat = current.feat
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe == current.safe
            and not feat_state_changed
            and state.threat == current.threat then
        return false
    end

    if debug_channel("map") then
        dsay("Updating altar on " .. level .. " at "
            .. cell_string_from_map_position(unhash_position(hash))
            .. " from " .. stairs_state_string(current)
            .. " to " .. stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat
    if feat_state_changed then
        current.feat = state.feat
        qw.want_goal_update = true
    end

    return true
end

function estimate_slouch_damage()
    local total = 0
    for _, enemy in ipairs(qw.enemy_list) do
        local delay = enemy:move_delay()
        local val = 0
        if delay < 5 then
            val = 3
        elseif delay < 8 then
            val = 2.5
        elseif delay < 10 then
            val = 1.5
        elseif delay == 10 then
            val = 1
        end

        if val > 0 and enemy:threat() <= 1 then
            val = 0.5
        end

        total = total + val
    end
    return total
end

function update_permanent_flight()
    if not gained_permanent_flight then
        return
    end

    for god, levels in pairs(c_persist.altars) do
        for level, altars in pairs(levels) do
            for hash, state in pairs(altars) do
                if state.feat >= const.explore.seen
                        and state.feat < const.explore.reachable then
                    update_altar(god, level, hash,
                        { feat = const.explore.reachable })
                end
            end
        end
    end
end
