function gameplan_normal_next(final)
    local gameplan

    -- Don't try to convert from Ignis too early.
    if explored_level_range("D:1-8")
            and you.god() == "Ignis"
            and you.piety_rank() == 0 then
        local found = {}
        local gods = god_options()
        local keep_ignis = false
        for _, g in ipairs(gods) do
            if g == "Ignis" then
                keep_ignis = true
                break
            elseif altar_found(g) then
                table.insert(found, g)
            end
        end

        if not keep_ignis then
            if #found ~= #gods
                    and branch_found("Temple")
                    and not explored_level_range("Temple") then
                return "Temple"
            end

            if #found > 0 then
                if not c_persist.chosen_god then
                    c_persist.chosen_god = found[crawl.roll_dice(1, #found)]
                end

                return "God:" .. c_persist.chosen_god
            end
        end
    end

    if not explored_level_range("D:1-11") then
        -- We head to Lair early, before having explored through D:11, if we
        -- feel we're ready.
        if branch_found("Lair")
                and not explored_level_range("Lair")
                and ready_for_lair() then
            gameplan = "Lair"
        else
            gameplan = "D:1-11"
        end
    -- D:1-11 explored, but not Lair.
    elseif not explored_level_range("Lair") then
        gameplan = "Lair"
    -- D:1-11 and Lair explored, but not D:12.
    elseif not explored_level_range("D:12") then
        if LATE_ORC then
            gameplan = "D"
        else
            gameplan = "D:12"
        end
    -- D:1-12 and Lair explored, but not all of D.
    elseif not explored_level_range("D") then
        if not LATE_ORC
                and branch_found("Orc")
                and not explored_level_range("Orc") then
            gameplan = "Orc"
        else
            gameplan = "D"
        end
    -- D and Lair explored, but not Orc.
    elseif not explored_level_range("Orc") then
        gameplan = "Orc"
    end

    if gameplan then
        return gameplan
    end

    -- At this point we're sure we've found Lair branches.
    if not early_first_lair_branch then
        local first_br = next_branch(lair_branch_order())
        early_first_lair_branch = make_level_range(first_br, 1, -1)
        first_lair_branch_end = branch_end(first_br)

        local second_br = next_branch(lair_branch_order(), 1)
        early_second_lair_branch = make_level_range(second_br, 1, -1)
        second_lair_branch_end = branch_end(second_br)
    end

    -- D, Lair, and Orc explored, but no Lair branch.
    if not explored_level_range(early_first_lair_branch) then
        gameplan = early_first_lair_branch
    -- D, Lair, and Orc explored, levels 1-3 of the first Lair branch.
    elseif not explored_level_range(early_second_lair_branch) then
        gameplan = early_second_lair_branch
    -- D, Lair, and Orc explored, levels 1-3 of both Lair branches.
    elseif not explored_level_range(first_lair_branch_end) then
        gameplan = first_lair_branch_end
    -- D, Lair, Orc, and at least one Lair branch explored, but not early
    -- Vaults.
    elseif not explored_level_range(early_vaults) then
        gameplan = early_vaults
    -- D, Lair, Orc, one Lair branch, and early Vaults explored, but the
    -- second Lair branch not fully explored.
    elseif not explored_level_range(second_lair_branch_end) then
        if not explored_level_range("Depths")
                and not EARLY_SECOND_RUNE then
            gameplan = "Depths"
        else
            gameplan = second_lair_branch_end
        end
    -- D, Lair, Orc, both Lair branches, and early Vaults explored, but not
    -- Depths.
    elseif not explored_level_range("Depths") then
        gameplan = "Depths"
    -- D, Lair, Orc, both Lair branches, early Vaults, and Depths explored,
    -- but no Vaults rune.
    elseif not explored_level_range(vaults_end) then
        gameplan = vaults_end
    -- D, Lair, Orc, both Lair branches, Vaults, and Depths explored, and it's
    -- time to shop.
    elseif not c_persist.done_shopping then
        gameplan = "Shopping"
    -- If we have other gameplan entries, the Normal plan stops here, otherwise
    -- early Zot.
    elseif final and not explored_level_range(early_zot) then
        gameplan = early_zot
    -- Time to win.
    elseif final then
        gameplan = "Orb"
    end

    return gameplan
end

function gameplan_complete(plan, final)
    if plan:find("^God:") then
        return you.god() == gameplan_god(plan)
    elseif plan:find("^Rune:") then
        local branch = gameplan_rune_branch(plan)
        return not branch_exists(branch) or have_branch_runes(branch)
    end

    local branch = parse_level_range(plan)
    return plan == "Normal" and not gameplan_normal_next(final)
        or branch and not branch_exists(branch)
        or branch and explored_level_range(plan)
        or plan == "Shopping" and c_persist.done_shopping
        or plan == "Abyss"
            and have_branch_runes("Abyss")
        or plan == "Pan" and have_branch_runes("Pan")
        or plan == "Zig" and c_persist.zig_completed
end

function choose_gameplan()
    local next_gameplan, chosen_gameplan, normal_gameplan
    while not chosen_gameplan and which_gameplan <= #gameplan_list do
        chosen_gameplan = gameplan_list[which_gameplan]
        next_gameplan = gameplan_list[which_gameplan + 1]
        local chosen_final = not next_gameplan
        local next_final = not gameplan_list[which_gameplan + 2]

        if chosen_gameplan == "Normal" then
            normal_gameplan = gameplan_normal_next(chosen_final)
            if not normal_gameplan then
                chosen_gameplan = nil
            end
        -- For God conversions, we don't perform them if we see that the next
        -- plan is complete. This way if a gameplan list has god conversions,
        -- past ones won't be re-attempted when we save and reload.
        elseif chosen_gameplan:find("^God:")
                and (gameplan_complete(chosen_gameplan, chosen_final)
                    or next_gameplan
                        and gameplan_complete(next_gameplan, next_final)) then
            chosen_gameplan = nil
        elseif gameplan_complete(chosen_gameplan, chosen_final) then
            chosen_gameplan = nil
        end

        if not chosen_gameplan then
            which_gameplan = which_gameplan + 1
        end
    end

    -- We're out of gameplans, so we make our final task be getting the ORB.
    if not chosen_gameplan then
        which_gameplan = nil
        chosen_gameplan = "Orb"
    end

    return chosen_gameplan, normal_gameplan
end

-- Choose an active portal on this level. We only consider allowed portals, and
-- choose the oldest one. Permanent bazaars get chosen last.
function choose_level_portal(level)
    local oldest_portal
    local oldest_turns
    for portal, turns_list in pairs(c_persist.portals[level]) do
        if portal_allowed(portal) then
            if #turns_list > 0
                    and (not oldest_turns
                        or turns_list[#turns_list] < oldest_turns) then
                oldest_portal = portal
                oldest_turns = turns_list[#turns_list]
            end
        end
    end

    return oldest_portal, oldest_turns
end

-- If we found a viable portal on the current level, that becomes our gameplan.
function check_portal_gameplan()
    local chosen_portal, chosen_level, chosen_turns
    for level, portals in pairs(c_persist.portals) do
        local portal, turns = choose_level_portal(level)
        if portal and (not chosen_turns or turns < chosen_turns) then
            chosen_portal = portal
            chosen_level = level
            chosen_turns = turns
        end
    end

    -- We only load a portal's parent branch info when it's actually chosen,
    -- and the parent info will be removed once the portal expires or is
    -- completed.
    if chosen_portal then
        local branch, depth = parse_level_range(chosen_level)
        branch_data[chosen_portal].parent = branch
        branch_data[chosen_portal].parent_min_depth = depth
        branch_data[chosen_portal].parent_max_depth = depth
    end

    return chosen_portal, chosen_turns == INF_TURNS
end

function want_altar()
    return you.race() ~= "Demigod"
        and you.god() == "No God"
        and god_options()[1] ~= "No God"
end

function determine_gameplan()
    permanent_bazaar = nil
    local chosen_gameplan, normal_gameplan = choose_gameplan()
    local old_status = gameplan_status
    local status = chosen_gameplan
    local gameplan = status
    local desc

    if status == "Normal" then
        status = normal_gameplan
        gameplan = normal_gameplan
    end

    -- Once we have the rune for this branch, this gameplan will be complete.
    -- Until then, we're diving to and exploring the branch end.
    if status:find("^Rune:") then
        local branch = gameplan_rune_branch(status)
        gameplan = branch_end(branch)
        desc = status .. " rune"
    end

    -- If we're configured to join a god, prioritize finding one from our god
    -- list, possibly exploring Temple once it's found.
    if want_altar() then
        local found = {}
        local gods = god_options()
        for _, g in ipairs(gods) do
            if altar_found(g) then
                table.insert(found, g)
            end
        end

        if #found ~= #gods
                and branch_found("Temple")
                and not explored_level_range("Temple") then
            status = "Temple"
            gameplan = "Temple"
        elseif #found > 0 then
            if not c_persist.chosen_god then
                c_persist.chosen_god = found[crawl.roll_dice(1, #found)]
            end

            status = "God:" .. c_persist.chosen_god
        end
    end

    if status:find("^God:") then
        local god = gameplan_god(status)
        desc = god .. " worship"
        local altar_lev = altar_found(god)
        if altar_lev then
            gameplan = altar_lev
        elseif branch_found("Temple")
                and not explored_level_range("Temple") then
            gameplan = "Temple"
        end
    end

    local portal
    portal, permanent_bazaar = check_portal_gameplan()
    if portal then
        status = portal
        gameplan = portal
    end

    -- Dive to and explore the end of Zot. We'll start trying to pick up the
    -- ORB via stash search travel as soon as it's found.
    if status == "Orb" then
        gameplan = zot_end
    end

    -- Portals remain our gameplan while we're there.
    if in_portal() then
        status = where_branch
        gameplan = where_branch
    end

    local branch = parse_level_range(gameplan)
    if branch == "Vaults" and you.num_runes() < 1 then
        error("Couldn't get a rune to enter Vaults!")
    elseif branch == "Zot" and you.num_runes() < 3 then
        error("Couldn't get three runes to enter Zot!")
    end

    if old_status ~= status then
        if not desc then
            if status == "Shopping" then
                desc = "shopping spree"
            else
                desc = status
            end
        end
        say("PLANNING " .. desc:upper())
    end

    set_gameplan(status, gameplan)
end

function branch_soon(branch)
    return branch == gameplan_branch
end

function in_extended()
    return gameplan_branch == "Pan"
        or gameplan_branch == "Coc"
        or gameplan_branch == "Dis"
        or gameplan_branch == "Geh"
        or gameplan_branch == "Tar"
        or gameplan_branch == "Tomb"
end

function gameplans_visit_branch(branch)
    if branch == "Zot" then
        return true
    elseif not which_gameplan then
        return false
    end

    for i = which_gameplan, #gameplan_list do
        local plan = gameplan_list[i]
        local plan_branch
        if plan:find("^Rune:") then
            plan_branch = gameplan_rune_branch(plan)
        else
            plan_branch = parse_level_range(plan)
        end

        if plan_branch
                and plan_branch == branch
                and not gameplan_complete(plan, i == #gameplan_list) then
            return true
        end
    end
end

function check_future_branches()
    planning_zig = gameplans_visit_branch("Zig")

    planning_undead_demon_branches = false

    for _, br in ipairs(hell_branches) do
        if gameplans_visit_branch(br) then
            planning_undead_demon_branches = true
            break
        end
    end

    planning_undead_demon_branches = planning_undead_demon_branches
        or gameplans_visit_branch("Crypt")
        or gameplans_visit_branch("Pan")
        or gameplans_visit_branch("Tomb")
        or planning_zig

    planning_vaults = gameplans_visit_branch("Vaults")
    planning_slime = gameplans_visit_branch("Slime")
    planning_pan = gameplans_visit_branch("Pan")
    planning_cocytus = gameplans_visit_branch("Coc")
    planning_gehenna = gameplans_visit_branch("Geh")
end

function check_future_gods()
    planning_god_uses_mp = false
    planning_tso = false

    if god_uses_mp() then
        planning_god_uses_mp = true
        return
    end

    if not which_gameplan then
        return
    end

    for i = which_gameplan, #gameplan_list do
        local plan = gameplan_list[i]
        local next_plan = gameplan_list[i + 1]
        local plan_final = not next_plan
        local next_final = not gameplan_list[i + 2]

        if plan:find("^God:") then
            local god = gameplan_god(plan)
            if not gameplan_complete(plan, plan_final)
                    and not (next_plan
                        and not gameplan_complete(next_plan, next_final)) then
                if god_uses_mp(god) then
                    planning_god_uses_mp = true
                elseif god == "the Shining One" then
                    planning_tso = true
                end
            end
        end
    end
end

-- Make a level range for the given branch and ranges, e.g. D:1-11. The
-- returned string is normalized so it's as simple as possible. Invalid level
-- ranges raise an error.
-- @string      branch The branch.
-- @number      first  The first level in the range.
-- @number[opt] last   The last level in the range, defaulting to the branch end.
--                     If negative, the range stops that many levels from the
--                     end of the end of the branch
-- @treturn string The level range.
function make_level_range(branch, first, last)
    local max_depth = branch_depth(branch)
    if not last then
        last = max_depth
    elseif last < 0 then
        last = max_depth + last
    end

    if first < 1
            or first > max_depth
            or last < 1
            or last > max_depth
            or first > last then
        error("Invalid level level range for " .. tostring(branch)
            ..": " .. tostring(first) .. ", " .. tostring(last))
    end

    if first == 1 and last == max_depth then
        return branch
    elseif first == last then
        return branch .. ":" .. first
    else
        return branch .. ":" .. first .. "-" .. last
    end
end

-- Make a level range for a single level, e.g. D:1.
-- @string branch The branch.
-- @int    first  The level.
-- @treturn string The level range.
function make_level(branch, depth)
    return make_level_range(branch, depth, depth)
end

-- Parse components of a level range.
-- @string      range The level range.
-- @treturn string The branch. Will be nil if the level is invalid.
-- @treturn int    The starting level.
-- @treturn int    The ending level.
function parse_level_range(range)
    local terms = split(range, ":")
    local br = terms[1]

    if not branch_data[br] then
        return
    end

    local br_depth = branch_depth(br)
    -- A branch name with no level range.
    if #terms == 1 then
        return br, 1, br_depth
    end

    local min_level, max_level
    local level_terms = split(terms[2], "-")
    min_level = tonumber(level_terms[1])
    if not min_level
            or math.floor(min_level) ~= min_level
            or min_level < 1
            or min_level > br_depth then
        return
    end

    if #level_terms == 1 then
        max_level = min_level
    else
        max_level = tonumber(level_terms[2])
        if not max_level
                or math.floor(max_level) ~= max_level
                or max_level < min_level
                or max_level > br_depth then
            return
        end
    end

    return br, min_level, max_level
end

function autoexplored_level(branch, depth)
    local state = c_persist.autoexplore[make_level(branch, depth)]
    return state and state > AUTOEXP.NEEDED
end

function explored_level(branch, depth)
    if branch == "Abyss" or branch == "Pan" then
        return have_branch_runes(branch)
    end

    return autoexplored_level(branch, depth)
        and have_all_stairs(branch, depth, DIR.DOWN, FEAT_LOS.REACHABLE)
        and have_all_stairs(branch, depth, DIR.UP, FEAT_LOS.REACHABLE)
        and (have_branch_runes(branch) or depth < branch_rune_depth(branch))
end

function explored_level_range(range)
    local br, min_level, max_level
    br, min_level, max_level = parse_level_range(range)
    if not br then
        return false
    end

    for l = min_level, max_level do
        if not explored_level(br, l) then
            return false
        end
    end

    return true
end

function ready_for_lair()
    if want_altar()
            or gameplan_branch
                and gameplan_branch == "D"
                and gameplan_depth <= 11
                and not explored_level(gameplan_branch, gameplan_depth) then
        return false
    end

    return you.god() == "Trog"
        or you.god() == "Cheibriados"
        or you.god() == "Okawaru"
        or you.god() == "Ignis"
        or you.god() == "Qazlal"
        or you.god() == "the Shining One"
        or you.god() == "Lugonu"
        or you.god() == "Uskayaw"
        or you.god() == "Xom"
        or you.god() == "Zin"
        or (you.god() == "Beogh"
            or you.god() == "Makhleb"
            or you.god() == "Yredelemnul") and you.piety_rank() >= 4
        or (you.god() == "Ru" or you.god() == "Elyvilon")
            and you.piety_rank() >= 3
        or you.god() == "Hepliaklqana" and you.piety_rank() >= 2
end

-- Return the next existing level range in a list.
-- @param[opt=0] skip A number giving how many valid level ranges to skip.
-- @tparam options A list of level ranges.
-- @treturn string The next level range.
function next_branch(options, skip)
    if not skip then
        skip = 0
    end

    local skipped = 0
    for _, level in ipairs(options) do
        local branch = parse_level_range(level)
        -- Reject any levels in branches that couldn't exist given the branches
        -- we've found already.
        if branch and branch_exists(branch) then
            if skipped < skip then
                skipped = skipped + 1
            else
                return branch
            end
        end
    end
end

function lair_branch_order()
    if c_persist.lair_branch_order then
        return c_persist.lair_branch_order
    end

    local branch_options
    if RUNE_PREFERENCE == "smart" then
        if crawl.random2(2) == 0 then
            branch_options = { "Spider", "Snake", "Swamp", "Shoals" }
        else
            branch_options = { "Spider", "Swamp", "Snake", "Shoals" }
        end
    elseif RUNE_PREFERENCE == "dsmart" then
        if crawl.random2(2) == 0 then
            branch_options = { "Spider", "Swamp", "Snake", "Shoals" }
        else
            branch_options = { "Swamp", "Spider", "Snake", "Shoals" }
        end
    elseif RUNE_PREFERENCE == "nowater" then
        branch_options = { "Snake", "Spider", "Swamp", "Shoals" }
    -- "random"
    else
        if crawl.random2(2) == 0 then
            branch_options = { "Snake", "Spider", "Swamp", "Shoals" }
        else
            branch_options = { "Swamp", "Shoals", "Snake", "Spider" }
        end
    end

    c_persist.lair_branch_order = branch_options
    return branch_options
end

-- Remove the "God:" prefix and return the god's full name.
function gameplan_god(plan)
    if not plan:find("^God:") then
        return
    end

    return god_full_name(plan:sub(5))
end

-- Remove the "Rune:" prefix and return the branch name.
function gameplan_rune_branch(plan)
    if not plan:find("^Rune:") then
        return
    end

    return plan:sub(6)
end

-- Remove any prefix and return the Zig depth we want to reach.
function gameplan_zig_depth(plan)
    if plan == "Zig" or plan:find("^MegaZig") then
        return 27
    end

    if not plan:find("^Zig:") then
        return
    end

    return tonumber(plan:sub(5))
end

function make_initial_gameplans()
    local gameplans = split(gameplan_options(), ",")
    gameplan_list = {}
    for _, pl in ipairs(gameplans) do
        -- Two-part plan specs: God conversion and rune.
        local plan
        pl = trim(pl)
        if pl:lower():find("^god:") then
            local name = gameplan_god(pl)
            if not name then
                error("Unkown god: " .. name)
            end

            plan = "God:" .. name
            processed = true
        elseif pl:lower():find("^rune:") then
            local branch = capitalize(gameplan_rune_branch(pl))
            if not branch_data[branch] then
                error("Unknown rune branch: " .. branch)
            elseif not branch_rune(branch) then
                error("Branch has no rune: " .. branch)
            end

            plan = "Rune:" .. branch
            processed = true
        else
            -- Normalize the plan so we're always making accurate comparisons
            -- for special plans like Normal, Shopping, Orb, etc.
            plan = capitalize(pl)
        end

        -- We turn Hells into a sequence of gameplans for each Hell branch rune
        -- in random order.
        if plan == "Hells" then
            -- Save our selection so it can be recreated across saving.
            if not c_persist.hell_branches then
                c_persist.hell_branches = util.random_subset(hell_branches,
                    #hell_branches)
            end

            for _, br in ipairs(c_persist.hell_branches) do
                table.insert(gameplan_list, "Rune:" .. br)
            end
        end

        if plan == "Zig" then
            will_zig = true
        end

        local branch, min_level, max_level = parse_level_range(plan)
        if not (branch
                or plan:find("^Rune:")
                or plan:find("^God:")
                or plan == "Hells"
                or plan == "Normal"
                or plan == "Shopping"
                or plan == "Orb"
                or plan == "Zig") then
            error("Invalid gameplan '" .. tostring(plan) .. "'.")
        end

        table.insert(gameplan_list, plan)
    end
end

function update_gameplan()
    check_expired_portals()
    determine_gameplan()
    check_future_branches()
    check_future_gods()

    update_gameplan_travel()

    want_gameplan_update = false
end

function god_options()
    return c_persist.current_god_list
end

function gameplan_options()
    if override_gameplans then
        return override_gameplans
    end

    local plan = c_persist.current_gameplans or DEFAULT_GAMEPLAN
    return GAMEPLANS[plan]
end

function next_exploration_depth(branch, min_depth, max_depth)
    -- The earliest depth that either lacks autoexplore or doesn't have all
    -- stairs reachable.
    local branch_max = branch_depth(branch)
    for d = min_depth, max_depth do
        if not autoexplored_level(branch, d) then
            return d
        elseif not have_all_stairs(branch, d, DIR.UP, FEAT_LOS.REACHABLE)
                or not have_all_stairs(branch, d, DIR.DOWN,
                    FEAT_LOS.REACHABLE) then
            return d
        end
    end

    if max_depth == branch_depth(branch) and not have_branch_runes(branch) then
        return max_depth
    end
end

function set_gameplan(status, gameplan)
    gameplan_status = status

    gameplan_branch = nil
    gameplan_depth = nil
    local min_depth, max_depth
    gameplan_branch, min_depth, max_depth = parse_level_range(gameplan)

    -- God gameplans always set the gameplan branch/depth to the known location
    -- of an altar, so we don't need further exploration.
    if status:find("^God") then
        gameplan_depth = min_depth
    elseif in_portal() then
        gameplan_depth = where_depth
    elseif gameplan_branch then
        gameplan_depth
            = next_exploration_depth(gameplan_branch, min_depth, max_depth)

        if gameplan == zot_end and not gameplan_depth then
            gameplan_depth = branch_depth("Zot")
            if where == zot_end then
                ignore_traps = true
                c_persist.autoexplore[zot_end] = AUTOEXP.NEEDED
            end
        end
    end

    if DEBUG_MODE then
        dsay("Gameplan status: " .. gameplan_status, "explore")
        dsay("Gameplan branch: " .. tostring(gameplan_branch), "explore")
        dsay("Gameplan depth: " .. tostring(gameplan_depth), "explore")
    end
end

function want_to_stay_in_abyss()
    return gameplan_branch == "Abyss"
        and not have_branch_runes("Abyss")
        and not hp_is_low(50)
end
