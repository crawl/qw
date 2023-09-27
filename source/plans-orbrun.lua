------------------
-- Plans specific to the Orb run.

function want_to_orbrun_teleport()
    return have_orb and hp_is_low(33) and sense_danger(2)
end

function want_to_orbrun_heal_wounds()
    if not have_orb then
        return false
    end

    if danger then
        return hp_is_low(25) or hp_is_low(50) and you.teleporting()
    else
        return hp_is_low(50)
    end
end

function want_to_orbrun_buff()
    return have_orb and check_scary_monsters(qw.los_radius)
end

function plan_go_to_orb()
    if unable_to_travel()
            or goal_status ~= "Orb"
            or not c_persist.found_orb then
        return false
    end

    magicfind("orb of zot")
    return true
end

function plan_orbrun_haste()
    if want_to_orbrun_buff() and not you.status("finesse-ful") then
        return haste()
    end

    return false
end

function plan_orbrun_might()
    if want_to_orbrun_buff() then
        return might()
    end

    return false
end

function plan_orbrun_heroism()
    if not can_finesse() and can_heroism() and want_to_orbrun_buff() then
        return heroism()
    end

    return false
end

function plan_orbrun_finesse()
    if can_finesse() and want_to_orbrun_buff() then
        return finesse()
    end

    return false
end
