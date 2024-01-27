------------------
-- Plans specific to the Orb run.

function want_to_orbrun_heal_wounds()
    if not qw.have_orb then
        return false
    end

    if qw.danger_in_los then
        return hp_is_low(25) or hp_is_low(50) and you.teleporting()
    else
        return hp_is_low(50)
    end
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
