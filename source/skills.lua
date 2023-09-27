------------------
-- Skill selection

local skill_list = {
    "Fighting", "Short Blades", "Long Blades", "Axes", "Maces & Flails",
    "Polearms", "Staves", "Unarmed Combat", "Ranged Weapons", "Throwing",
    "Armour", "Dodging", "Shields", "Invocations", "Evocations", "Stealth",
    "Spellcasting", "Conjurations", "Hexes", "Summonings",
    "Necromancy", "Translocations", "Transmutations", "Fire Magic",
    "Ice Magic", "Air Magic", "Earth Magic", "Poison Magic"
}

function choose_single_skill(sk)
    you.train_skill(sk, 1)
    for _, sk2 in ipairs(skill_list) do
        if sk ~= sk2 then
            you.train_skill(sk2, 0)
        end
    end
end

function skill_value(sk)
    if sk == "Dodging" then
        local str, _ = you.strength()
        if str < 1 then
            str = 1
        end
        local dex, _ = you.dexterity()
        local evp_adj = max(armour_evp() - 3, 0)
        local penalty_factor
        if evp_adj >= str then
            penalty_factor = str / (2 * evp_adj)
        else
            penalty_factor = 1 - evp_adj / (2 * str)
        end
        if you.race() == "Tengu" and intrinsic_flight() then
            penalty_factor = penalty_factor * 1.2 -- flying EV mult
        end
        return 18 * math.log(1 + dex / 18)
            / (20 + 2 * body_size()) * penalty_factor
    elseif sk == "Armour" then
        local str, _ = you.strength()
        if str < 0 then
            str = 0
        end
        local val1 = 2 / 225 * armour_evp() ^ 2 / (3 + str)
        local val2 = base_ac() / 22
        return val1 + val2
    elseif sk == "Fighting" then
        return 0.75
    elseif sk == "Shields" then
        return shield_skill_utility()
    elseif sk == "Throwing" then
        local missile = best_missile()
        if missile then
            return 0.2 * missile_rating(missile)
        else
            return 0
        end
    elseif sk == "Invocations" then
        if you.god() == "the Shining One" then
            return undead_or_demon_branch_soon() and 1.5 or 0.5
        elseif you.god() == "Uskayaw" or you.god() == "Zin" then
            return 0.75
        elseif you.god() == "Elyvilon" then
            return 0.5
        else
            return 0
        end
    elseif sk == weapon_skill() then
        return at_min_delay() and 0.5 or 1.5
    end
end

function choose_skills()
    local skills = {}
    -- Choose one martial skill to train.
    local martial_skills = {
        weapon_skill(), "Fighting", "Shields", "Armour", "Dodging",
        "Invocations", "Throwing"
    }

    local best_sk
    local best_utility = 0
    local utility
    for _, sk in ipairs(martial_skills) do
        if you.skill_cost(sk) then
            utility = skill_value(sk) / you.skill_cost(sk)
            if utility > best_utility then
                best_utility = utility
                best_sk = sk
            end
        end
    end
    if best_utility > 0 then
        if debug_channel("skills") then
            dsay("Best skill: " .. best_sk .. ", utility: " .. best_utility)
        end

        table.insert(skills, best_sk)
    end

    -- Choose one MP skill to train.
    mp_skill = "Evocations"
    if god_uses_invocations() then
        mp_skill = "Invocations"
    elseif you.god() == "Ru" or you.god() == "Xom" then
        mp_skill = "Spellcasting"
    end
    mp_skill_level = you.base_skill(mp_skill)
    bmp = you.base_mp()
    if you.god() == "Makhleb"
            and you.piety_rank() >= 2
            and mp_skill_level < 15 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Okawaru"
            and you.piety_rank() >= 1
            and mp_skill_level < 4 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Okawaru"
            and you.piety_rank() >= 4
            and mp_skill_level < 10 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Cheibriados"
            and you.piety_rank() >= 5
            and mp_skill_level < 8 then
        table.insert(skills, mp_skill)
    elseif you.god() == "Yredelemnul"
            and you.piety_rank() >= 4
            and mp_skill_level < 8 then
        table.insert(skills, mp_skill)
    elseif you.race() == "Vine Stalker"
            and you.god() ~= "No God"
            and mp_skill_level < 12
            and (at_min_delay()
                 or you.base_skill(weapon_skill()) >= 3 * mp_skill_level) then
        table.insert(skills, mp_skill)
    end

    skills2 = {}
    safe_count = 0
    for _, sk in ipairs(skills) do
        if you.can_train_skill(sk) and you.base_skill(sk) < 27 then
            table.insert(skills2, sk)
            if you.base_skill(sk) < 26.5 then
                safe_count = safe_count + 1
            end
        end
    end
    -- Try to avoid getting stuck in the skill screen.
    if safe_count == 0 then
        if you.base_skill("Fighting") < 26.5 then
            table.insert(skills2, "Fighting")
        elseif you.base_skill(mp_skill) < 26.5 then
            table.insert(skills2, mp_skill)
        else
            for _, sk in ipairs(skill_list) do
                if you.can_train_skill(sk) and you.base_skill(sk) < 26.5 then
                    table.insert(skills2, sk)
                    return skills2
                end
            end
        end
    end
    return skills2
end

function handle_skills()
    skills = choose_skills()
    choose_single_skill(skills[1])
    for _, sk in ipairs(skills) do
        you.train_skill(sk, 1)
    end
end

function choose_stat_gain()
    local ap = armour_plan()
    if ap == "heavy" or ap == "large" then
        return "s"
    elseif ap == "light" then
        return "d"
    else
        local str, _ = you.strength()
        local dex, _ = you.dexterity()
        if 3 * str < 2 * dex then
            return "s"
        else
            return "d"
        end
    end
end

function auto_experience()
    return true
end
