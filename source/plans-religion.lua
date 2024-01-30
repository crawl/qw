------------------
-- General plans related to religion

function plan_go_to_altar()
    local god = goal_god(goal_status)
    if unable_to_travel() or not god then
        return false
    end

    magicfind("altar&&<<of " .. god .. ">>")
    return true
end

function plan_abandon_god()
    if goal_god(goal_status) == "No God"
            or you.class() == "Chaos Knight"
                and you.god() == "Xom"
                and qw.ck_abandon_xom then
        magic("aXYY")
        return true
    end

    return false
end

function plan_join_beogh()
    if you.race() ~= "Hill Orc"
            or goal_status ~= "God:Beogh"
            or you.confused()
            or you.silenced() then
        return false
    end

    if use_ability("Convert to Beogh", "YY") then
        return true
    end

    return false
end

function plan_use_altar()
    local god = goal_god(goal_status)
    if not god
            or view.feature_at(0, 0) ~= god_altar(god)
            or not can_use_altars() then
        return false
    end

    magic("<JY")
    return true
end

function plan_sacrifice()
    if you.god() ~= "Ru" or not can_invoke() then
        return false
    end

    -- Sacrifices that we won't do for now: words, drink, courage, durability,
    -- hand, resistance, purity, health.
    good_sacrifices = {
        "Sacrifice Artifice",   -- 55
        "Sacrifice Love",       -- 40
        "Sacrifice Experience", -- 40
        "Sacrifice Nimbleness", -- 30
        "Sacrifice Skill",      -- 30
        "Sacrifice Arcana",     -- 25
        "Sacrifice an Eye",     -- 20
        "Sacrifice Stealth",    -- 15
        "Sacrifice Essence",    -- variable
        "Reject Sacrifices",
    }
    for _, sacrifice in ipairs(good_sacrifices) do
        if use_ability(sacrifice, "YY") then
            return true
        end
    end
    return false
end

local did_ancestor_identity = false
function plan_ancestor_identity()
    if you.god() ~= "Hepliaklqana" or not can_invoke() then
        return false
    end

    if not did_ancestor_identity then
        use_ability("Ancestor Identity",
            "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\belliptic\ra")
        did_ancestor_identity = true
        return true
    end
    return false
end

function plan_ancestor_life()
    if you.god() ~= "Hepliaklqana" or not can_invoke() then
        return false
    end

    local ancestor_options = {"Knight", "Battlemage", "Hexer"}
    if use_ability("Ancestor Life: " ..
            ancestor_options[crawl.roll_dice(1, 3)], "Y") then
        return true
    end

    return false
end
