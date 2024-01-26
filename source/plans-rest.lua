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
    if qw.danger_in_los and not qw.all_enemies_safe then
        return false
    end

    if qw.have_orb then
        return you.confused()
            or transformed()
            or you.slowed() and not qw.slow_aura
            or you.berserk()
            or you.teleporting()
            or you.status("spiked")
    end

    if want_to_move_to_abyss_objective() then
        return false
    end

    return you.berserk()
        or you.turns() < hiding_turn_count + 10
        or you.god() == "Makhleb"
            and you.turns() <= hostile_servants_timer + 100
        or reason_to_rest(99.9)
end

-- Check statuses to see whether there is something to rest off, does not
-- include some things in should_rest() because they are not clearly good to
-- wait out with monsters around.
function reason_to_rest(percentage)
    if starting_spell or god_uses_mp() then
        local mp, mmp = you.mp()
        if mp < mmp then
            return true
        end
    end

    if you.race() ~= "Djinni"
            and you.god() == "Elyvilon"
            and you.piety_rank() >= 4 then
        local mp, mmp = you.mp()
        if mp < mmp and mp < 10 then
            return true
        end
    end

    return you.confused()
        or transformed()
        or you.slowed() and not qw.slow_aura
        or you.exhausted()
        or you.teleporting()
            and not teleporting_before_dangerous_stairs()
        or you.status("on berserk cooldown")
        or you.status("marked")
        or you.status("spiked")
        or you.status("weak-willed") and not in_branch("Tar")
        or you.status("fragile (+50% incoming damage)")
        or you.silencing()
        or you.corrosion() > base_corrosion
        or hp_is_low(percentage)
            -- Don't rest if we're in good shape and have divine warriors nearby.
            and not (you.god() == "the Shining One"
                and check_divine_warriors(2)
                and not hp_is_low(75))
end

function should_ally_rest()
    if qw.danger_in_los
            or you.god() ~= "Yredelemnul" and you.god() ~= "Beogh" then
        return false
    end

    for pos in square_iter(const.origin, 3) do
        local mons = get_monster_at(pos)
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
    plans.rest = cascade {
        {plan_cure_poison, "cure_poison"},
        {plan_long_rest, "try_long_rest"},
        {plan_rest_one_turn, "rest_one_turn"},
    }
end
