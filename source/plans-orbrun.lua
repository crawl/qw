------------------
-- Plans specific to the Orb run.

function want_to_orbrun_teleport()
    return have_orb and hp_is_low(33) and sense_danger(2)
end

function want_to_orbrun_heal_wounds()
    if danger then
        return hp_is_low(25) or hp_is_low(50) and you.teleporting()
    else
        return hp_is_low(50)
    end
end

function want_to_orbrun_buff()
    return count_pan_lords(qw.los_radius) > 0
        or check_enemies_in_list(qw.los_radius, scary_monsters)
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
    if can_heroism() and want_to_orbrun_buff() then
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
