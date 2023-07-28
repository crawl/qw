------------------
-- Plans related to the Ziggurat portal.

function plan_zig_fog()
    if not in_branch("Zig")
            or you.berserk()
            or you.teleporting()
            or you.confused()
            or not danger
            or not hp_is_low(70)
            or count_enemies(qw.los_radius) - count_enemies(2) < 15
            or view.cloud_at(0, 0) ~= nil then
        return false
    end
    return read_by_name("fog")
end

function plan_move_to_zigfig_location()
    if unable_to_travel()
            or goal_branch ~= "Zig"
            or branch_is_temporary(where_branch)
            or not find_item("misc", "figurine of a ziggurat")
            or not feature_is_critical(view.feature_at(0, 0)) then
        return false
    end

    for pos in adjacent_iter(const.origin) do
        if is_traversable_at(pos)
                and not is_solid_at(pos)
                and not monster_in_way(pos)
                and is_safe_at(pos)
                and not feature_is_critical(view.feature_at(pos.x, pos.y)) then
            return move_to(pos)
        end
    end

    return false
end

function plan_use_zigfig()
    if goal_branch ~= "Zig"
            or branch_is_temporary(where_branch)
            or position_is_cloudy
            or danger
            or you.berserk()
            or you.confused()
            or feature_is_critical(view.feature_at(0, 0)) then
        return false
    end

    local c = find_item("misc", "figurine of a ziggurat")
    if c then
        say("MAKING ZIG")
        magic("V" .. letter(c))
        return true
    end

    return false
end

function plan_go_to_zig_dig()
    if unable_to_travel()
            or goal_branch ~= "Zig"
            or not branch_found("Zig")
            or view.feature_at(0, 0) == branch_entrance("Zig")
            or view.feature_at(3, 1) == branch_entrance("Zig")
            or count_charges("digging") == 0 then
        return false
    end

    magic(control('f') .. portal_entrance_description("Zig") .. "\rayby\r")
    return true
end

function plan_zig_dig()
    if not in_branch("Depths")
            or goal_branch ~= "Zig"
            or view.feature_at(3, 1) ~= branch_entrance("Zig") then
        return false
    else
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "L")
            return true
        end
    end

    return false
end

function plan_zig_go_to_stairs()
    if unable_to_travel() or not in_branch("Zig") then
        return false
    end

    if c_persist.zig_completed then
        magic("X<\r")
    else
        magic("X>\r")
    end
    return true
end

function plan_zig_leave_level()
    if not in_branch("Zig") or unable_to_use_stairs() then
        return false
    end

    if c_persist.zig_completed
            and view.feature_at(0, 0) == branch_exit("Zig") then
        local parent, depth = parent_branch(where_branch)
        remove_portal(make_level(parent, depth), where_branch, true)
        go_upstairs(true)
        return true
    elseif feature_is_downstairs(view.feature_at(0, 0)) then
        go_downstairs()
        return true
    end

    return false
end
