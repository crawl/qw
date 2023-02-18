------------------------------
-- Branch data and logic

-- Some tables with hardcoded data about branches/gods/portals/monsters:

-- Branch data: branch abbreviation, interlevel travel code, max depth,
-- entrance description, parent branch, min parent branch depth, max parent
-- branch depth, rune name(s).
--
-- This gets loaded into the branch_data table, which is keyed by the branch
-- name. Use the helper functions to access this data: branch_travel(),
-- branch_depth(), parent_branch(), and have_branch_runes().
local branch_data_values = {
    { "D", "D", 15 },
    { "Ossuary", nil, 1, "enter_ossuary" },
    { "Sewer", nil, 1, "enter_sewer" },
    { "Bailey", nil, 1, "enter_bailey" },
    { "IceCv", nil, 1, "enter_ice_cave" },
    { "Volcano", nil, 1, "enter_volcano" },
    { "Bailey", nil, 1, "enter_bailey" },
    { "Gauntlet", nil, 1, "enter_gauntlet" },
    { "Bazaar", nil, 1, "enter_bazaar" },
    { "WizLab", nil, 1, "enter_wizlab" },
    { "Desolation", nil, 1, "enter_desolation" },
    { "Temple", "T", 1, "enter_temple", "D", 4, 7 },
    { "Orc", "O", 2, "enter_orcish_mines", "D", 9, 12 },
    { "Elf", "E", 3, "enter_elven_halls", "Orc", 2, 2 },
    { "Lair", "L", 5, "enter_lair", "D", 8, 11 },
    { "Swamp", "S", 4, "enter_swamp", "Lair", 2, 4, "decaying" },
    { "Shoals", "A", 4, "enter_shoals", "Lair", 2, 4, "barnacled" },
    { "Snake", "P", 4, "enter_snake_pit", "Lair", 2, 4, "serpentine" },
    { "Spider", "N", 4, "enter_spider_nest", "Lair", 2, 4, "gossamer" },
    { "Slime", "M", 5, "enter_slime_pits", "Lair", 5, 6, "slimy" },
    { "Vaults", "V", 5, "enter_vaults", "D", 13, 14, "silver" },
    { "Crypt", "C", 3, "enter_crypt", "Vaults", 3, 4 },
    { "Tomb", "W", 3, "enter_tomb", "Crypt", 3, 3, "golden" },
    { "Depths", "U", 4, "enter_depths", "D", 15, 15 },
    { "Zig", nil, 27, "enter_ziggurat", "Depths", 1, 4 },
    { "Zot", "Z", 5, "enter_zot", "Depths", 4, 4 },
    { "Pan", nil, 1, "enter_pandemonium", "Depths", 2, 2,
        { "dark", "demonic", "fiery", "glowing", "magical" } },
    { "Abyss", nil, 7, "enter_abyss", "Depths", 4, 4, "abyssal" },
    { "Hell", "H", 1, "enter_hell", "Depths", 1, 4 },
    { "Dis", "I", 7, "enter_dis", "Hell", 1, 1, "iron" },
    { "Geh", "G", 7, "enter_gehenna", "Hell", 1, 1, "obsidian" },
    { "Coc", "X", 7, "enter_cocytus", "Hell", 1, 1, "icy" },
    { "Tar", "Y", 7, "enter_tartarus", "Hell", 1, 1, "bone" },
}

hell_branches = { "Coc", "Dis", "Geh", "Tar" }

-- Portal branch, entry description, max timeout in turns, description.
local portal_data_values = {
    { "Ossuary", "sand-covered staircase", 800 },
    { "Sewer", "glowing drain", 800 },
    { "Bailey", "flagged portal", 800 },
    { "Volcano", "dark tunnel", 800 },
    { "IceCv", "frozen_archway", 800, "ice cave" },
    { "Gauntlet", "gate leading to a gauntlet", 800 },
    { "Bazaar", "gateway to a bazaar", 1300 },
    { "WizLab", "magical portal", 800, "wizard's laboratory" },
    { "Desolation", "crumbling gateway", 800 },
    { "Zig", "one-way gateway to a ziggurat", },
}

function initialize_branch_data()
    for _, entry in ipairs(branch_data_values) do
        local br = entry[1]
        local data = {}
        data["travel"] = entry[2]
        data["depth"] = entry[3]
        data["entrance"] = entry[4]
        data["parent"] = entry[5]
        data["parent_min_depth"] = entry[6]
        data["parent_max_depth"] = entry[7]
        data["rune"] = entry[8]

        -- Update the parent entry depth with that of an entry found in the
        -- parent either if the entry depth is unconfirmed our the found entry
        -- is at a lower depth.
        if c_persist.branches[br] then
            for level, _ in pairs(c_persist.branches[br]) do
                local parent, depth = parse_level_range(level)
                if parent == data.parent
                        and (not data.parent_min_depth
                            or data.parent_min_depth ~= data.parent_max_depth
                            or depth < data.parent_min_depth) then
                    data.parent_min_depth = depth
                    data.parent_max_depth = depth
                    break
                end
            end
        end

        branch_data[br] = data
    end

    for _, entry in ipairs(portal_data_values) do
        local br = entry[1]
        local data = {}
        data["entrance_description"] = entry[2]
        data["timeout"] = entry[3]
        data["description"] = entry[4]
        if not data["description"] then
            data["description"] = br:lower()
        end
        portal_data[br] = data
    end

    early_vaults = make_level_range("Vaults", 1, -1)
    vaults_end = branch_end("Vaults")

    early_zot = make_level_range("Zot", 1, -1)
    zot_end = branch_end("Zot")
end

function branch_travel(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].travel
end

function branch_depth(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].depth
end

function branch_entrance(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].entrance
end

function branch_exit(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    if branch_data[branch].entrance then
        return branch_data[branch].entrance:gsub("enter", "exit", 1)
    else
        return "exit_dungeon"
    end
end

function portal_entrance_description(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].entrance_description
end

function portal_timeout(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].timeout
end

function portal_description(portal)
    if not portal_data[portal] then
        error("Unknown portal: " .. tostring(portal))
    end

    return portal_data[portal].description
end

function parent_branch(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].parent,
        branch_data[branch].parent_min_depth,
        branch_data[branch].parent_max_depth

end

function branch_rune(branch)
    if not branch_data[branch] then
        error("Unknown branch: " .. tostring(branch))
    end

    return branch_data[branch].rune
end

function branch_exists(branch)
    return not (branch == "Snake" and branch_found("Spider")
        or branch == "Spider" and branch_found("Snake")
        or branch == "Shoals" and branch_found("Swamp")
        or branch == "Swamp" and branch_found("Shoals")
        or not branch_data[branch])
end

function branch_found(branch, los_state)
    if branch == "D" then
        return {"D:0"}
    end

    if not los_state then
        -- Hack. Temple entries sometimes restrict access when they reveal the
        -- branch, requiring entry via stairs inside the vault. Requiring
        -- reachable means we won't try to access temple until we've explored
        -- these stairs and can therefore successfully travel to it. Other
        -- branches tend to not cause travel problems yet are sometimes
        -- initially spotted behind e.g. statues, so we allow only seeing them
        -- to consider them found.
        if branch == "Temple" then
            los_state = FEAT_LOS.REACHABLE
        else
            los_state = FEAT_LOS.SEEN
        end
    end

    if not c_persist.branches[branch] then
        return
    end

    for w, s in pairs(c_persist.branches[branch]) do
        if s >= los_state then
            return w
        end
    end
end

function in_branch(branch)
    return where_branch == branch
end

function branch_end(branch)
    return make_level(branch, branch_depth(branch))
end

function at_branch_end(branch)
    if not branch then
        branch = where_branch
    end

    return where_branch == branch and where_depth == branch_depth(branch)
end

function is_hell_branch(branch)
    return util.contains(hell_branches, branch)
end

function in_hell_branch()
    return is_hell_branch(where_branch)
end

function branch_rune_depth(branch)
    if not branch_rune(branch) then
        return
    end

    if branch == "Abyss" then
        return 3
    else
        return branch_depth(branch)
    end
end

function have_branch_runes(branch)
    local rune = branch_rune(branch)
    if not rune then
        return true
    elseif type(rune) == "table" then
        for _, r in ipairs(rune) do
            if not you.have_rune(r) then
                return false
            end
        end

        return true
    end

    return you.have_rune(rune)
end

function is_portal_branch(branch)
    return portal_data[branch] ~= nil
end

function in_portal()
    return is_portal_branch(where_branch)
end

function portal_allowed(portal)
    return util.contains(ALLOWED_PORTALS, portal)
end

function record_branch(pos)
    local feat = view.feature_at(pos.x, pos.y)
    for br, entry in pairs(branch_data) do
        if entry.entrance == feat then
            record_feature_position(pos)

            if not c_persist.branches[br] then
                c_persist.branches[br] = {}
            end
            local state = los_state(pos)
            -- We already have a suitable entry recorded.
            if c_persist.branches[br][where]
                    and c_persist.branches[br][where] >= state then
                return
            end

            c_persist.branches[br][where] = state

            -- Update the entry depth in the branch data with the depth where
            -- we found this entry if the entry depth is currently unconfirmed
            -- or if the found depth is higher.
            local cur_br, cur_depth = parse_level_range(where)
            local parent_br, parent_min, parent_max = parent_branch(br)
            if cur_br == parent_br
                    and (parent_min ~= parent_max
                        or cur_depth < parent_min) then
                branch_data[br].parent_min_depth = cur_depth
                branch_data[br].parent_max_depth = cur_depth
            end

            want_gameplan_update = true
            return
        end
    end
end

function record_portal(level, portal, permanent)
    if not c_persist.portals[level] then
        c_persist.portals[level] = {}
    end

    if not c_persist.portals[level][portal] then
        c_persist.portals[level][portal] = {}
    end

    -- This timed portal has already been recorded for this level.
    local len = #c_persist.portals[level][portal]
    if not permanent
            and len > 0
            and c_persist.portals[level][portal][len] ~= INF_TURNS then
        return
    end

    -- Permanent portals go at the beginning, so they'll always be chosen last.
    -- We can't have multiple timed portals of the same type on the same level,
    -- so this scheme puts portals in the correct order. For timed portals,
    -- record the turns to allow prioritizing among timed portals across
    -- levels.
    dsay("Found " .. portal .. ".", "explore")
    if permanent then
        table.insert(c_persist.portals[level][portal], 1, INF_TURNS)
    else
        table.insert(c_persist.portals[level][portal], you.turns())
    end

    if portal_allowed(portal) then
        want_gameplan_update = true
    end
end

function remove_portal(level, portal, silent)
    if not c_persist.portals[level]
            or not c_persist.portals[level][portal]
            or #c_persist.portals[level][portal] == 0 then
        return
    end

    -- This is a list because bazaars can be both permanent and timed and
    -- potentially with both on the same level. We make the list so the timed
    -- portal is at the end, and since we enter timed portals before the
    -- permanent one, we always want to remove from the end.
    table.remove(c_persist.portals[level][portal])
    branch_data[portal].parent = nil
    branch_data[portal].parent_min_depth = nil
    branch_data[portal].parent_max_depth = nil

    if portal_allowed(portal) then
        if not silent then
            say("RIP " .. portal:upper())
        end

        want_gameplan_update = true
    end
end

-- Expire any timed portals for levels we've fully explored or where they're
-- older than their max timeout.
function check_expired_portals()
    for level, portals in pairs(c_persist.portals) do
        local explored = explored_level_range(level)
        for portal, turns_list in pairs(portals) do
            local timeout = portal_timeout(portal)
            for _, turns in ipairs(turns_list) do
                if where_branch ~= portal
                        and turns ~= INF_TURNS
                        and (explored
                            or timeout and you.turns() - turns > timeout) then
                    remove_portal(level, portal)
                end
            end
        end
    end
end

function level_is_temporary()
    return in_portal() or in_branch("Pan") or in_branch("Abyss")
end

function easy_runes()
    local branches = {"Swamp", "Snake", "Shoals", "Spider"}
    local count = 0
    for _, br in ipairs(branches) do
        if have_branch_runes(br) then
            count = count + 1
        end
    end
    return count
end
