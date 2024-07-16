------------------
-- Skill selection

const.skill_list = {
    "Fighting", "Maces & Flails", "Axes", "Polearms", "Staves",
    "Unarmed Combat", "Throwing", "Short Blades", "Long Blades",
    "Ranged Weapons", "Armour", "Dodging", "Shields", "Stealth",
    "Spellcasting", "Conjurations", "Hexes", "Summonings", "Necromancy",
    "Translocations", "Alchemy", "Fire Magic", "Ice Magic", "Air Magic",
    "Earth Magic", "Invocations", "Evocations", "Shapeshifting",
}

const.ev_value = 0.8
const.ac_value = 1.0
const.sh_value = 0.75
const.delay_value = 2.4

function weapon_skill()
    -- Cache in case we unwield a weapon somehow.
    if c_persist.weapon_skill then
        return c_persist.weapon_skill
    end

    if you.class() ~= "Wanderer" then
        for weapon in equipped_slot_iter("weapon") do
            if weapon.weap_skill ~= "Short Blades" then
                c_persist.weapon_skill = weapon.weap_skill
                return c_persist.weapon_skill
            end
        end
    end

    c_persist.weapon_skill = weapon_skill_choice()
    return c_persist.weapon_skill
end

function choose_single_skill(chosen_sk)
    you.train_skill(chosen_sk, 1)
    for _, sk in ipairs(const.skill_list) do
        if sk ~= chosen_sk then
            you.train_skill(sk, 0)
        end
    end
end

function shield_skill_utility()
    local shield = get_shield()
    if not shield or shield.encumbrance == 0 then
        return 0
    end
    local sh_gain = 0.19 + shield.ac/40
    local delay_reduction = 2 * shield.encumbrance * shield.encumbrance
        / (25 + 5 * max_strength()) / 27
    local ev_gain = delay_reduction
    return const.sh_value * sh_gain + const.ev_value * ev_gain
        + const.delay_value * delay_reduction
end

function skill_value(sk)
    if sk == "Dodging" then
        local str = max_strength()
        if str < 1 then
            str = 1
        end

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
        local ev_gain = 0.8 * max(you.dexterity(), 1)
            / (20 + 2 * body_size()) * penalty_factor
        return const.ev_value * ev_gain
    elseif sk == "Armour" then
        local str = max_strength()
        if str < 0 then
            str = 0
        end
        local ac_gain = base_ac() / 22
        local ev_gain = 2 / 225 * armour_evp() ^ 2 / (3 + str)
        return const.ac_value * ac_gain + const.ev_value * ev_gain
    elseif sk == "Fighting" then
        return 0.75
    elseif sk == "Shields" then
        return shield_skill_utility()
    elseif sk == "Throwing" then
        local missile = best_missile(missile_damage)
        if missile then
            return missile_damage(missile) / 25
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
        return at_min_delay() and 0.3 or 1.5
    end
end

function choose_skills()
    -- Choose one martial skill to train.
    local martial_skills = { weapon_skill(), "Fighting", "Shields", "Armour",
        "Dodging", "Invocations", "Throwing" }

    local best_sk, best_val
    for _, sk in ipairs(martial_skills) do
        if you.skill_cost(sk) then
            local val = skill_value(sk) / you.skill_cost(sk)
            if val and (not best_val or val > best_val) then
                best_val = val
                best_sk = sk
            end
        end
    end

    local skills = {}
    if best_val then
        if debug_channel("skills") then
            dsay("Best skill: " .. best_sk .. ", value: " .. best_val)
        end

        table.insert(skills, best_sk)
    end

    -- Choose one MP skill to train.
    local mp_skill = "Evocations"
    if god_uses_invocations() then
        mp_skill = "Invocations"
    elseif you.god() == "Ru" or you.god() == "Xom" then
        mp_skill = "Spellcasting"
    end
    local mp_skill_level = you.base_skill(mp_skill)

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

    local trainable_skills = {}
    local safe_count = 0
    for _, sk in ipairs(skills) do
        if you.can_train_skill(sk) and you.base_skill(sk) < 27 then
            table.insert(trainable_skills, sk)
            if you.base_skill(sk) < 26.5 then
                safe_count = safe_count + 1
            end
        end
    end

    -- Try to avoid getting stuck in the skill screen.
    if safe_count == 0 then
        if you.base_skill("Fighting") < 26.5 then
            table.insert(trainable_skills, "Fighting")
        elseif you.base_skill(mp_skill) < 26.5 then
            table.insert(trainable_skills, mp_skill)
        else
            for _, sk in ipairs(const.skill_list) do
                if you.can_train_skill(sk) and you.base_skill(sk) < 26.5 then
                    table.insert(trainable_skills, sk)
                    return trainable_skills
                end
            end
        end
    end
    return trainable_skills
end

function handle_skills()
    skills = choose_skills()
    choose_single_skill(skills[1])
    for _, sk in ipairs(skills) do
        you.train_skill(sk, 1)
    end
end

function update_skill_tracking()
    if not qw.base_skills then
        qw.base_skills = {}
    end

    for _, sk in ipairs(const.skill_list) do
        local base_skill = you.base_skill(sk)
        if base_skill > 0
                and (not qw.base_skills[sk]
                    or base_skill - qw.base_skills[sk] >= 1) then
            reset_best_equip()
            qw.base_skills[sk] = base_skill
        end
    end
end

function choose_stat_gain()
    local ap = armour_plan()
    if ap == "heavy" or ap == "large" then
        return "s"
    elseif ap == "light" then
        return "d"
    else
        if 3 * max_strength() < 2 * max_dexterity() then
            return "s"
        else
            return "d"
        end
    end
end

-- clua hook for experience menu after quaffing !experience. Simply accepts the
-- default skill allocations.
function auto_experience()
    return true
end
