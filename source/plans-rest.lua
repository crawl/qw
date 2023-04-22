------------------
-- The rest plan cascade.

function plan_cure_poison()
    if not you.poisoned() or you.poison_survival() > 1 then
        return false
    end

    if drink_by_name("curing") then
        say("(to cure poison)")
        return true
    end

    if can_trogs_hand() then
        trogs_hand()
        return true
    end

    if can_purification() then
        purification()
        return true
    end

    return false
end

function should_rest()
    if you.confused() or you.berserk() or transformed() then
        return true
    end

    if dangerous_to_rest() then
        return false
    end

    if you.turns() < hiding_turn_count + 10 then
        dsay("Waiting for ranged monster.")
        return true
    end

    return reason_to_rest(99.9)
        or you.god() == "Makhleb"
            and you.turns() <= greater_servant_timer + 100
        or should_ally_rest()
end

-- Check statuses to see whether there is something to rest off, does not
-- include some things in should_rest() because they are not clearly good to
-- wait out with monsters around.
function reason_to_rest(percentage)
    if not no_spells and starting_spell() then
        local mp, mmp = you.mp()
        if mp < mmp then
            return true
        end
    end

    if you.god() == "Elyvilon" and you.piety_rank() >= 4 then
        local mp, mmp = you.mp()
        if mp < mmp and mp < 10 then
            return true
        end
    end

    return you.confused()
        or transformed()
        or hp_is_low(percentage)
            and (you.god() ~= "the Shining One"
                or hp_is_low(75)
                or count_divine_warriors(2) == 0)
        or you.slowed()
        or you.exhausted()
        or you.teleporting()
        or you.status("on berserk cooldown")
        or you.status("marked")
        or you.status("spiked")
        or you.status("weakened")
        or you.silencing()
        or you.corrosion() > base_corrosion
end

function should_ally_rest()
    if (you.god() ~= "Yredelemnul" and you.god() ~= "Beogh")
            or dangerous_to_rest() then
        return false
    end

    for pos in square_iter(origin, 3) do
        local mons = monster_map[pos.x][pos.y]
        if mons and mons:is_friendly() and mons:damage_level() > 0 then
            return true
        end
    end

    return false
end

function wait_one_turn(short_delay)
    magic("s")
    if short_delay then
        next_delay = 5
    end
end

function long_rest()
    magic("5")
end

function plan_long_rest()
    if should_rest() then
        long_rest()
        return true
    end
    return false
end

function plan_rest_one_turn()
    if should_rest() then
        wait_one_turn(true)
        return true
    end
    return false
end

function set_plan_rest()
    plan_rest = cascade {
        {plan_cure_poison, "cure_poison"},
        {plan_long_rest, "try_long_rest"},
        {plan_rest_one_turn, "rest_one_turn"},
    }
end
