function plan_find_altar()
    if not want_altar() then
        return false
    end

    str = "altar&&<<of " .. table.concat(god_options(), "||of ")
    if FADED_ALTAR then
        str = str .. "||of an unknown god"
    end
    str = str .. ">>"
    magicfind(str)
    return true
end

function plan_find_conversion_altar()
    if not gameplan_status:find("^God:") then
        return false
    end

    local god = gameplan_god(gameplan_status)
    if you.god() == god then
        return false
    end

    magicfind("altar&&<<of " .. god .. ">>")
    return true
end

function plan_abandon_god()
    local want_god = gameplan_god(gameplan_status)
    if want_god == "No God"
            or you.class() == "Chaos Knight"
                and you.god() == "Xom"
                and CK_ABANDON_XOM then
        magic("aXYY")
        want_gameplan_update = true
        return true
    end

    return false
end

function plan_join_beogh()
    if you.race() ~= "Hill Orc" or not want_altar() or you.confused() then
        return false
    end
    for _, god in ipairs(god_options()) do
        if god == "Beogh" and use_ability("Convert to Beogh", "YY") then
            want_gameplan_update = true
            return true
        end
    end
    return false
end

function plan_convert()
    if not gameplan_status:find("^God:") then
        return false
    end

    local god = gameplan_god(gameplan_status)
    if you.god() == god then
        return false
    end

    if view.feature_at(0, 0) ~= god_altar(god) then
        return false
    end

    if you.silenced() then
        rest()
    else
        magic("<JY")
        want_gameplan_update = true
    end

    return true
end

function plan_join_god()
    if not want_altar() then
        return false
    end

    feat = view.feature_at(0, 0)
    for _, god in ipairs(god_options()) do
        if feat == god_altar(god) then
            if you.silenced() then
                rest()
            else
                magic("<J")
            end
            want_gameplan_update = true
            return true
        end
    end

    if FADED_ALTAR and feat == "altar_ecumenical" then
        if you.silenced() then
            rest()
        else
            magic("<J")
        end
        want_gameplan_update = true
        return true
    end

    return false
end

function plan_sacrifice()
    if you.god() ~= "Ru" or not can_invoke() then
        return false
    end

    -- Sacrifices that we won't do for now: words, drink, courage, durability,
    -- hand, resistance, purity, health
    good_sacrifices = {
        "Sacrifice Artifice", -- 55
        "Sacrifice Love", -- 40
        "Sacrifice Experience", -- 40
        "Sacrifice Nimbleness", -- 30
        "Sacrifice Skill", -- 30
        "Sacrifice Arcana", -- 25
        "Sacrifice an Eye", -- 20
        "Sacrifice Stealth", -- 15
        "Sacrifice Essence", -- variable
        "Reject Sacrifices",
    }
    for _, sacrifice in ipairs(good_sacrifices) do
        if sacrifice == "Sacrifice Nimbleness" then
            for letter, abil in pairs(you.ability_table()) do
                if abil == sacrifice then
                    you.train_skill("Fighting", 1)
                    say("INVOKING " .. sacrifice .. ".")
                    magic("a" .. letter .. "YY")
                    return true
                end
            end
        elseif use_ability(sacrifice, "YY") then
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
